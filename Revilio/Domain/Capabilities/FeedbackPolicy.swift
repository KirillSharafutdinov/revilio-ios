//
//  FeedbackPolicy.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import CoreGraphics

/// Describes the feedback (haptic + optional speech) that should be delivered for a given point.
public struct FeedbackDirective {
    public let pattern: HapticPattern
    public let intensity: Float
    public let phrase: String?
}

public enum searchType {
    case searchObject
    case searchText
}

/// Strategy that converts a CGPoint (smoothed/predicted position) into tangible feedback.
protocol FeedbackPolicy {
    func feedback(for point: CGPoint,
                  feedback: FeedbackRepository) -> FeedbackDirective
}

/// Default implementation backed by `CentreAlignmentEvaluator`.
final class CentreAlignmentFeedbackPolicy: FeedbackPolicy {
    private let evaluator: CentreAlignmentEvaluator
    private let searchType: searchType

    init(evaluator: CentreAlignmentEvaluator = CentreAlignmentEvaluator(),
         searchType: searchType) {
        self.evaluator = evaluator
        self.searchType = searchType
    }

    func feedback(for point: CGPoint,
                  feedback: FeedbackRepository) -> FeedbackDirective {
        let (pattern, intensity) = evaluator.calculateHapticFeedback(for: point)
        // Build speech phrase only if TTS is idle to avoid overlapping audio.
        let phrase: String? = {
            guard !feedback.isSpeaking else { return nil }
            let text = evaluator.buildSpeechGuidance(for: point, searchType: searchType)
            return text.isEmpty ? nil : text
        }()
        return FeedbackDirective(pattern: pattern, intensity: intensity, phrase: phrase)
    }
}

/// A lightweight, domain-level helper that encapsulates the maths required to translate a point
/// in normalised camera coordinates (0…1) into user feedback (haptics & speech) that guides the
/// user towards perfectly centring the target.
///
/// The implementation is a pure-Swift utility – no platform frameworks leak outside Infrastructure.
/// It can therefore be unit-tested in isolation and reused by any future search mode.
struct CentreAlignmentEvaluator {
    private let parameters: PredictionParameters

    init(predictionParameters: PredictionParameters = .default) {
        self.parameters = predictionParameters
    }

    // MARK: – Public helpers
    /// Calculates the most suitable haptic pattern together with its intensity for the supplied point.
    /// - Parameter point: The current (smoothed) position of the recognised target in normalised coordinates.
    /// - Returns: A tuple containing the `HapticPattern` to play and the intensity in the `0…1` range.
    func calculateHapticFeedback(for point: CGPoint) -> (HapticPattern, Float) {
        let distanceToCentre = hypot(point.x - parameters.center.x,
                                      point.y - parameters.center.y)
        let normalizedProximity = 1.0 - min(1.0, distanceToCentre / 0.5)
        var dynamicIntensity = Float(0.3 + 0.7 * normalizedProximity)
        dynamicIntensity = max(0.1, min(1.0, dynamicIntensity))

        var chosenPattern: HapticPattern = .none

        // Phase 1 – horizontal guidance until we are inside the central vertical corridor.
        if abs(point.x - parameters.center.x) >= parameters.centerRadius {
            if point.x < parameters.center.x - parameters.centerRadius {
                chosenPattern = .dotPause
            } else {
                chosenPattern = .dashPause
            }
        }
        // Phase 2 – fine vertical guidance once horizontally aligned.
        else {
            if point.y < parameters.center.y - parameters.centerRadius {
                chosenPattern = .dashDotPause
            } else if point.y > parameters.center.y + parameters.centerRadius {
                chosenPattern = .dotDashPause
            } else {
                // The target is fully centred.
                chosenPattern = .continuous
                dynamicIntensity = 1.0
            }
        }
        return (chosenPattern, dynamicIntensity)
    }

    /// Builds a short, directional phrase that helps the user align the target with the screen centre.
    /// The string is ready to be passed straight into a TTS engine.
    /// - Parameters:
    ///   - point: Current (smoothed) position of the recognised target.
    ///   - centerMessage: Phrase that should be spoken once the target is perfectly centred.
    /// - Returns: Complete phrase to be voiced.
    func buildSpeechGuidance(for point: CGPoint, searchType: searchType) -> String {
        var feedbackText = ""
        var textX = ""
        var textY = ""

        // Phase 1 – horizontal guidance.
        if abs(point.x - parameters.center.x) >= parameters.centerRadius {
            if point.x < parameters.center.x - parameters.centerRadius {
                textX = Constants.Alignment.leftPrompt
            } else {
                textX = Constants.Alignment.rightPrompt
            }

            if point.y < parameters.center.y - parameters.centerRadius {
                textY = Constants.Alignment.downPrompt
            } else if point.y > parameters.center.y + parameters.centerRadius {
                textY = Constants.Alignment.upPrompt
            } else {
                textY = Constants.Alignment.placeholder
            }
        }
        // Phase 2 – fine vertical guidance once horizontally centred.
        else {
            if point.y < parameters.center.y - parameters.centerRadius {
                textY = Constants.Alignment.downPrompt
            } else if point.y > parameters.center.y + parameters.centerRadius {
                textY = Constants.Alignment.upPrompt
            } else {
                feedbackText = searchType == .searchObject ? Constants.Alignment.objectCentered : Constants.Alignment.textCentered
            }
        }

        if feedbackText.isEmpty {
            feedbackText = textX + textY
        }
        return feedbackText
    }

    /// Returns the element whose centre is closest to the screen centre.
    func nearestToCentre<T>(_ items: [T],
                            centerOfItem: (T) -> CGPoint) -> T? {
        guard !items.isEmpty else { return nil }
        var minDistance = Double.greatestFiniteMagnitude
        var nearest: T? = nil
        for item in items {
            let c = centerOfItem(item)
            let d = hypot(c.x - parameters.center.x, c.y - parameters.center.y)
            if d < minDistance {
                minDistance = d
                nearest = item
            }
        }
        return nearest
    }
}
