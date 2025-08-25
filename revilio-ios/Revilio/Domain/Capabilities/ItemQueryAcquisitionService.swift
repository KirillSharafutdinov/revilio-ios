//
//  ItemQueryAcquisitionService.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Abstraction responsible for acquiring the user's spoken query and returning the raw recognised text.
public protocol ItemQueryAcquiring {
    func acquireQuery(timeout: TimeInterval) async throws -> String
    func cancel()
    /// Allows clients (eg. two-click flows) to manually request finalisation so the recogniser returns a result immediately.
    func forceFinalization()
}

/// Concrete implementation that leverages *partial* speech recognition results to resolve
/// ambiguities between item names that are prefixes of other names
/// The algorithm iintegrated directly into the `ItemQueryAcquisitionService`
/// so that a single type covers all item‐search scenarios.
final class SpeechItemQueryAcquisitionService: ItemQueryAcquiring {

    // MARK: – Private Properties

    private let speechRecognizer: SpeechRecognizerRepository
    private let feedbackPresenter: FeedbackRepository
    private let registry: ItemsForSearchRegistryService = .shared
    
    private var allItemNames: [String] = []
    
    private var cancellable: AnyCancellable?

    /// Stores the most specific (longest) ambiguous match seen so far so that, if the
    /// speech session ends without an unambiguous resolution, we can still return something
    /// meaningful.
    private var provisionalCandidate: String? = nil
    
    // MARK: – Initialization
    
    init(speechRecognizer: SpeechRecognizerRepository,
         feedbackPresenter: FeedbackRepository) {
        self.speechRecognizer = speechRecognizer
        self.feedbackPresenter = feedbackPresenter
    }
    
    // MARK: – Public interface
    
    func acquireQuery(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var finished = false
            
            self.allItemNames = registry.getAllAvailableItemsForDisplay()
                .flatMap { info -> [String] in
                    var names = [info.displayName]
                    names.append(contentsOf: info.alternativeNames)
                    return names
                }
                .map { $0.lowercased() }
            
            // Local helper to finish once.
            func finish(_ text: String) {
                guard !finished else { return }
                finished = true
                continuation.resume(returning: text)
            }
            
            // Subscribe to recognition fragments.
            self.cancellable = self.speechRecognizer.transcriptPublisher()
                .sink { [weak self] text in
                    guard let self else { return }
                    guard !finished else { return }
                    
                    let lowerText = text.lowercased()
                    
                    // 1. Determine which known items are already present in the recognised phrase.
                    let currentMatches = self.allItemNames.filter { lowerText.contains($0) }
                    
                    if currentMatches.isEmpty {
                        return // Wait for more speech.
                    }
                    
                    // 2. Sort by length (longest first) to prefer more specific items.
                    let sortedMatches = currentMatches.sorted { $0.count > $1.count }

                    // 3. Check each match for ambiguity.
                    var definitiveMatch: String? = nil
                    for candidate in sortedMatches {
                        // Does any longer yet-unspoken item exist?
                        let longerYetUnspokenExists = self.allItemNames.contains(where: { other in
                            other != candidate && other.contains(candidate) && !lowerText.contains(other)
                        })
                        if !longerYetUnspokenExists {
                            definitiveMatch = candidate
                            break
                        }
                    }

                    if let match = definitiveMatch {
                        // Unambiguous winner – finalise immediately.
                        self.speechRecognizer.forceFinalization()
                        // Slight grace period to allow recogniser to settle.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            finish(match)
                        }
                    } else {
                        // Ambiguous – remember the best current candidate.
                        self.provisionalCandidate = sortedMatches.first
                    }
                }

            // Start recognition with partial results.
            speechRecognizer.startRecognition(usePartialResults: true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.feedbackPresenter.announce(Constants.SearchItem.awaitObjectName)
            }
            
            // Safety timeout – if nothing definitive after `timeout`, finalise with provisional.
            if timeout > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self, !finished else { return }
                    self.speechRecognizer.forceFinalization()
                    finish(self.provisionalCandidate ?? "")
                }
            }
        }
    }

    func cancel() {
        cancellable?.cancel()
        speechRecognizer.stopRecognition()
    }

    func forceFinalization() {
        speechRecognizer.forceFinalization()
    }
}
