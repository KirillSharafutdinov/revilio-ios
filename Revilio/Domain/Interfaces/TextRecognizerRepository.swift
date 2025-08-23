//
//  TextRecognizerRepository.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Combine

/// Recognition accuracy levels for text recognition
public enum TextRecognitionAccuracy {
    case fast
    case accurate
}

/// Protocol for text recognition operations
protocol TextRecognizerRepository {
    /// Set the languages to recognize
    /// - Parameter languages: Language codes to recognize
    func setLanguages(_ languages: [String])
    
    /// Set the minimum text height for detection
    /// - Parameter minimumTextHeight: Minimum height of text to detect
    func setMinimumTextHeight(_ minimumTextHeight: Float?)
    
    /// Process a frame for text recognition
    /// - Parameters:
    ///   - cameraFrame: Pure-Swift `CameraFrame` DTO
    ///   - accuracy: Recognition accuracy level (.fast or .accurate)
    func processFrame(cameraFrame: CameraFrame, accuracy: TextRecognitionAccuracy)

    // MARK: – AsyncSequence
    /// Stream of recognised text observations.
    func recognizedTextStream() -> AsyncStream<[TextObservation]>
}

extension TextRecognizerRepository {
    /// Combine publisher bridging `recognizedTextStream()` async sequence.
    public func recognizedTextPublisher() -> AnyPublisher<[TextObservation], Never> {
        let subject = PassthroughSubject<[TextObservation], Never>()
        Task {
            for await batch in self.recognizedTextStream() {
                subject.send(batch)
            }
            subject.send(completion: .finished)
        }
        return subject.share().eraseToAnyPublisher()
    }
}
