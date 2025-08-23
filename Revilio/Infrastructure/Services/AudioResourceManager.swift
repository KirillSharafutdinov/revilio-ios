//
//  AudioResourceManager.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import Speech
import AVFoundation

/// Centralized manager for audio resource management with thread-safe operations
class AudioResourceManager {
    private let lock = NSLock()
    
    // MARK: - Audio Engine Management
    
    /// Safely start the audio engine with proper error handling
    /// - Parameter engine: The AVAudioEngine to start
    /// - Returns: Success status
    func safeStart(engine: AVAudioEngine) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard !engine.isRunning else { return true }
        
        engine.prepare()
        
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }
    
    /// Safely stop audio resources with proper cleanup order
    /// - Parameters:
    ///   - engine: The AVAudioEngine to stop
    ///   - task: The SFSpeechRecognitionTask to cancel
    ///   - request: The SFSpeechAudioBufferRecognitionRequest to end
    func safeStop(engine: AVAudioEngine, task: SFSpeechRecognitionTask?, request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        defer { lock.unlock() }
        
        // 1. Cancel recognition task first to prevent callbacks
        if let task = task {
            task.cancel()
        }
        
        // 2. Stop audio engine
        if engine.isRunning {
            engine.stop()
        }
        
        // 3. End audio request
        if let request = request {
            request.endAudio()
        }
        
        // 4. Remove audio tap safely
        safeRemoveTap(from: engine)
        
        // 5. Release the shared audio session usage acquired in `configureAudioSession()`.
        SharedAudioSessionController.shared.endUse(after: 0.0)
    }
    
    // MARK: - Audio Tap Management
    
    /// Safely install audio tap with proper error handling
    /// - Parameters:
    ///   - engine: The AVAudioEngine
    ///   - request: The recognition request to append buffers to
    ///   - isActiveCallback: Callback to check if recognition is still active
    ///   - silenceHandler: Optional closure fired once when sustained silence is detected. Use this to end audio early.
    /// - Returns: Success status
    func safeInstallTap(on engine: AVAudioEngine,
                       request: SFSpeechAudioBufferRecognitionRequest,
                       isActiveCallback: @escaping () -> Bool,
                       silenceHandler: (() -> Void)? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            return false
        }
        
        safeRemoveTap(from: engine)
        
        let silenceThreshold: Float = 0.0005   // Rough empirical value; tweak as needed.
        let requiredSilentFrames = 15          // ≈15×23 ms ≈ 350 ms of silence for 44.1 kHz/1024.
        var consecutiveSilentFrames = 0
        var silenceAlreadyTriggered = false
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            guard isActiveCallback() else { return }

            request.append(buffer)

            // Exit early if caller does not need silence detection or it has already fired.
            guard let silenceHandler = silenceHandler, !silenceAlreadyTriggered else { return }

            // Basic RMS calculation for first channel.
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                var rms: Float = 0.0
                var sum: Float = 0.0
                for i in 0..<frameLength {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                rms = sqrt(sum / Float(frameLength))

                if rms < silenceThreshold {
                    consecutiveSilentFrames += 1
                } else {
                    consecutiveSilentFrames = 0
                }

                if consecutiveSilentFrames >= requiredSilentFrames {
                    silenceAlreadyTriggered = true  // Fire once
                    consecutiveSilentFrames = 0
                    silenceHandler()
                }
            }
        }
        
        return true
    }
    
    // MARK: - Audio Session Management
    
    /// Configure audio session with proper settings
    /// - Returns: Success status
    func configureAudioSession() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // Delegate to the shared audio-session controller which handles reference counting.
        let desiredSpeaker = (UserDefaults.standard.string(forKey: "AudioOutputRoutePreference") ?? "speaker") == "speaker"
        let route: AudioOutputRoute = desiredSpeaker ? .speaker : .receiver
        let success = SharedAudioSessionController.shared.beginUse(route: route)
        
        return success
    }
    
    /// Safely deactivate audio session
    /// - Returns: Success status
    func deactivateAudioSession() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let success = SharedAudioSessionController.shared.forceDeactivate()

        return success
    }
    
    // MARK: - Recognition Request Management
    
    /// Create a new recognition request with proper configuration
    /// - Parameter usePartialResults: Whether to enable partial results
    /// - Returns: Configured recognition request or nil if creation fails
    func createRecognitionRequest(usePartialResults: Bool) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = usePartialResults
        
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = true
        }
        
        return request
    }
    
    /// Safely remove audio tap
    /// - Parameter engine: The AVAudioEngine
    private func safeRemoveTap(from engine: AVAudioEngine) {
        if engine.inputNode.engine == engine {
            engine.inputNode.removeTap(onBus: 0)
        }
    }
}
