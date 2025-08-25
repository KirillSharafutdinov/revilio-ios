//
//  SpeechRecognizerRepository.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// High-level state of the speech recogniser.
public enum SpeechRecognizerState: Equatable {
    case idle
    case listening
    case error(String)
}

/// Protocol for speech recognition operations
protocol SpeechRecognizerRepository {
    /// Start speech recognition
    /// - Parameter usePartialResults: Whether to use partial results during recognition
    func startRecognition(usePartialResults: Bool)
    
    /// Stop speech recognition
    func stopRecognition()
    
    /// Force finalization of current recognition session
    func forceFinalization()
    
    /// Set recognizer language for localization
    func setLanguage(for localeId: String)
    
    /// Check if speech recognition is available
    var isAvailable: Bool { get }
    
    /// Async throwing stream of recognised speech text.
    /// Implementations **must** yield every recognised phrase (partial or final) and
    /// finish with an error if recognition fails.
    func recognizedSpeechStream(usePartialResults: Bool) -> AsyncThrowingStream<String, Error>

    /// Combine publisher that emits partial & final speech recognition results.
    func transcriptPublisher() -> AnyPublisher<String, Never>

    /// Combine publisher exposing the recogniserʼs high-level state (idle / listening / error).
    func statePublisher() -> AnyPublisher<SpeechRecognizerState, Never>
}
