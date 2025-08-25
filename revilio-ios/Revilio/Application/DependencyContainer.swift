//
//  DependencyContainer.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import UIKit
import Combine

// MARK: - Shared cross-cutting dependencies

/// A single shared logger instance used across the application layers. Can be swapped for
/// a different implementation (e.g. unified logger to file) from a single place.
private let sharedLogger: Logger = OSLogger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: "App")

/// Dependency container manages the creation and configuration of all components in the application
class DependencyContainer {
    
    // MARK: - Properties

    private var internalCancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        _ = LocalizationManager.shared
        
        #if DEBUG
        LogOverlayViewController.install()
        
        // Subscribe to DomainEvent log / error stream for console print & optional haptic.
        EventBus.shared.publisher
            .sink { [weak self] event in
                switch event {
                case .error(let message):
                    sharedLogger.log(.error, "Domain error: \(message)", category: "DOMAIN_EVENT", file: #file, function: #function, line: #line)
                    self?.hapticFeedbackRepository.playPattern(.dotPause, intensity: Constants.hapticButtonIntensity)
                default:
                    break
                }
            }
            .store(in: &internalCancellables)
        #endif
        
        // Register shared singletons for @Inject resolution.
        Resolver.register(hapticFeedbackRepository as HapticFeedbackRepository)
        Resolver.register(speechSynthesizerRepository as SpeechSynthesizerRepository)
        Resolver.register(appModeCoordinator as AppModeCoordinating)
        Resolver.register(sharedLogger as Logger)
        Resolver.register(EventBus.shared)
        Resolver.register(cameraRepository as CameraRepository)
        Resolver.register(StopController.shared)
        Resolver.register(speechRecognizerRepository as SpeechRecognizerRepository)
        Resolver.register(ItemsForSearchRegistryService.shared as ItemsForSearchRegistryService)
    }
    
    // MARK: - Public Methods
    
    func makeMainViewController() -> MainViewController {
        _ = self.mainViewModel
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let viewController = storyboard.instantiateViewController(withIdentifier: "MainViewController") as? MainViewController else {
            sharedLogger.log(.error, "Failed to load MainViewController from storyboard", category: "DEPENDENCY", file: #file, function: #function, line: #line)
            // Return a basic error view controller instead of crashing
            return createErrorViewController()
        }
        
        viewController.setViewModel(mainViewModel)
        
        return viewController
    }

    /// Public accessor for the shared speech synthesizer repository so that other
    /// screens (e.g. the settings view) can change the audio route preference.
    var speechSynthesizer: SpeechSynthesizerRepository { speechSynthesizerRepository }
    
    /// Public accessor for the shared speech recognizer repository so that other
    /// screens (e.g. the settings view) can change language.
    var speechRecognizer: SpeechRecognizerRepository { speechRecognizerRepository }
    
    // MARK: - Repositories
    
    private lazy var cameraRepository: CameraRepository = {
        return AVCaptureService(logger: sharedLogger)
    }()
    
    private lazy var speechRecognizerRepository: SpeechRecognizerRepository = {
        return SFSpeechRecognizerService()
    }()
    
    private lazy var speechSynthesizerRepository: SpeechSynthesizerRepository = {
        return AVSpeechSynthesizerService()
    }()
    
    private lazy var objectDetectionRepository: ObjectDetectionRepository = {
        return VisionObjectDetectionService(logger: sharedLogger, thermalThrottlingService: thermalThrottlingService)
    }()
    
    private lazy var thermalThrottlingService: ThermalThrottlingService = {
        return ThermalThrottlingService(logger: sharedLogger)
    }()
    
    private lazy var textRecognizerRepository: TextRecognizerRepository = {
        return VisionTextRecognizerService(logger: sharedLogger, thermalThrottlingService: thermalThrottlingService)
    }()
    
    private lazy var hapticFeedbackRepository: HapticFeedbackRepository = {
        return CoreHapticsFeedbackManager()
    }()
    
    /// Chosen at runtime: GPU-accelerated blur evaluator if Metal is available,
    private lazy var frameQualityRepository: FrameQualityRepository = {
        if let service = MPSQualityService(logger: sharedLogger) {
            sharedLogger.log(.info, "FrameQuality: Using Metal Performance Shaders implementation (grid)", category: "INIT", file: #file, function: #function, line: #line)
            return service
        } else {
            sharedLogger.log(.warn, "FrameQuality: Metal unavailable, using fallback implementation", category: "INIT", file: #file, function: #function, line: #line)
            // Return a fallback implementation that always returns nil
            return FallbackFrameQualityService(logger: sharedLogger)
        }
    }()
    
    // MARK: - Error Handling
    
    private func createErrorViewController() -> MainViewController {
        // Create a basic MainViewController that shows an error state
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: "MainViewController") as! MainViewController
        viewController.setViewModel(mainViewModel)
        return viewController
    }
    
    // MARK: - Feedback Presenters

    /// Presenter configured for object search context.
    private lazy var objectSearchFeedback: FeedbackRepository = {
        let presenter = FeedbackPresenter(haptics: hapticFeedbackRepository,
                                 tts: speechSynthesizerRepository,
                                 context: .objectSearch)
        return presenter
    }()
    
    /// Presenter configured for text search context.
    private lazy var textSearchFeedback: FeedbackRepository = {
        let presenter = FeedbackPresenter(haptics: hapticFeedbackRepository,
                                 tts: speechSynthesizerRepository,
                                 context: .textSearch)
        return presenter
    }()
    
    // MARK: - Use Cases
    
    private lazy var searchItemUseCase: SearchItemUseCase = {
        let useCase = SearchItemUseCase(
            objectDetectionRepository: objectDetectionRepository,
            speechRecognizerRepository: speechRecognizerRepository,
            cameraRepository: cameraRepository,
            feedbackRepository: objectSearchFeedback,
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
            logger: sharedLogger
        )
                
        return useCase
    }()
    
    private lazy var searchTextUseCase: SearchTextUseCase = {
        let useCase = SearchTextUseCase(
            textRecognizerRepository: textRecognizerRepository,
            speechRecognizerRepository: speechRecognizerRepository,
            cameraRepository: cameraRepository,
            feedbackRepository: textSearchFeedback,
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
            logger: sharedLogger
        )
        
        return useCase
    }()
    
    private lazy var readTextUseCase: ReadTextUseCase = {
        let useCase = ReadTextUseCase(
            textRecognizerRepository: textRecognizerRepository,
            feedbackRepository: textSearchFeedback,
            cameraRepository: cameraRepository,
            frameQualityRepository: frameQualityRepository,
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
            logger: sharedLogger
        )
        
        return useCase
    }()
    
    // MARK: - View Models
    
    private lazy var mainViewModel: MainViewModel = {
        return MainViewModel(
            searchItemUseCase: searchItemUseCase,
            searchTextUseCase: searchTextUseCase,
            readTextUseCase: readTextUseCase,
            cameraRepository: cameraRepository,
            speechSynthesizerRepository: speechSynthesizerRepository,
            objectDetectionRepository: objectDetectionRepository,
            textRecognizerRepository: textRecognizerRepository,
            speechRecognizerRepository: speechRecognizerRepository,
            hapticFeedbackRepository: hapticFeedbackRepository,
            appModeCoordinator: appModeCoordinator
        )
    }()
    
    // MARK: - Coordinators
    
    private lazy var appModeCoordinator: AppModeCoordinator = {
        let coordinator = AppModeCoordinator(cameraRepository: cameraRepository,
                                             speechSynthesizerRepository: speechSynthesizerRepository,
                                             hapticFeedbackRepository: hapticFeedbackRepository,
                                             speechRecognizerRepository: speechRecognizerRepository,
                                             objectDetectionRepository: objectDetectionRepository,
                                             textRecognizerRepository: textRecognizerRepository,
                                             searchItemUseCase: searchItemUseCase,
                                             searchTextUseCase: searchTextUseCase,
                                             readTextUseCase: readTextUseCase)
        return coordinator
    }()

    // Provide a read-only public accessor so that external modules (e.g., App Intents, Siri)
    // can trigger features without tampering with the lifetime management.
    public var publicMainViewModel: MainViewModel { mainViewModel }
}
