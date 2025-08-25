# Revilio - Companion for the Blind and Visually Impaired

![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Platform](https://img.shields.io/badge/Platform-iOS_17.6+-lightgrey?logo=apple)
![License](https://img.shields.io/badge/License-AGPLv3-blue)

> **🚀 Download on the App Store:** [**Get Revelio for iPhone/iPad**](https://apps.apple.com/app/id6571191877)

# 🌟 Overview

Revilio is an iOS application designed to help blind and visually impaired people. It helps navigate the physical world by finding objects, locating specific text, and reading documents or inscriptions aloud using artificial intelligence. Uses advanced Apple technologies and provides maximum performance on iPhone or iPad

**Revilio** — iOS-приложение, созданное для помощи незрячим и слабовидящим людям. Позволяет находить предметы или текст, а также читать документы и другие надписи вслух с помощью искусственного интеллекта. Использует передовые технологии Apple и обеспечивает максимальную производительность на iPhone или iPad.

**Revilio** 一款 iOS 应用，旨在帮助盲人和视障人士。它利用人工智能查找物体或文本，并大声朗读文档和其他文字。它采用先进的 Apple 技术，可在您的 iPhone 或 iPad 上提供最佳性能。

## 🎥 Demo TODO

**Video Demonstration:** [Watch a quick overview of Revilio's core features in action on](https://youtube.com)

### Screenshots TODO

| Main Screen | Item Selection | Text Input | Settings |
| :---: | :---: | :---: | :---: |
| <img src="Docs/Images/screenshot-main.png" width="200"> | <img src="Docs/Images/screenshot-list.png" width="200"> | <img src="Docs/Images/screenshot-text.png" width="200"> | <img src="Docs/Images/screenshot-settings.png" width="200"> |

## ✨ Features

### 🔍 Object Search
Speak the name of an item from a vast catalog (80 COCO objects, 15 custom items). Revilio will use the device's camera to locate it in your environment and provide intuitive haptic and audio feedback to guide you towards its location.

### 📝 Text Search
Find a specific word or phrase around you. Speak your query or type it using the accessible keyboard. The app uses real-time OCR to scan the camera feed and guides you with feedback once the text is found.

### 📖 Text Reading
Point your camera at a document, book, or sign. Revilio automatically detects, clusters, and reads the text blocks aloud with a natural voice. Smart algorithms ignore adjacent text blocks (like the other page of an open book) for a seamless reading experience.

### ♿ Deep Accessibility
The entire interface is built according to WCAG guidelines, featuring high contrast, large bold uppercase text, and full VoiceOver support. Feedback type (haptic, audio, or both) is configurable to suit individual preferences.

### 🎯 Stability & Quality
A sophisticated pipeline ensures reliable results. The app waits for the camera to stabilize (focus & exposure) and uses Metal-accelerated sharpness detection to analyze frame quality before processing, significantly improving recognition accuracy.

### 🗣️ Siri Shortcuts Integration
Launch any core feature hands-free with voice commands via Siri. Just say "Hey Siri, Revilio find my keys" or "Hey Siri, Revilio read this" to get started.

### 🌍 Multi-Language Support
Fully supported in English, Russian, and Simplified Chinese across the entire stack: user interface, speech recognition, and text-to-speech output.

# 🏗️ Architecture & Technical Details

## Architecture Overview

Revilio follows **Clean Architecture** principles with a clear separation of concerns across four distinct layers:

### Domain Layer
- **Core business entities**: `ObjectObservation`, `TextObservation`, `BoundingBox`, `CameraFrame`
- **Key capabilities**: `CentralTextClusterDetector`, `ContinuousFrameProcessor`, `FeedbackPresenter`, `Item(Text)QueryAcquisitionService`, `PredictionService`, `StateMachine` and `SessionOrchestrator`
- **Use cases**: `SearchItemUseCase`, `SearchTextUseCase`, `ReadTextUseCase`
- **Repository protocols**: `CameraRepository`, `ObjectDetectionRepository`, `TextRecognizerRepository`, `SpeechRecognizerRepository`, `SpeechSynthesizerRepository`, `HapticFeedbackRepository`
- **Platform-agnostic**: Almost pure Swift with no external dependencies

### Application Layer
- **Coordinators**: `AppModeCoordinator` (state management), `FeatureCoordinator` (feature orchestration)
- **Services**: `LocalizationManager`, `StopController`, `EventBus`, `FeatureManager`
- **Dependency management**: `DependencyContainer`, `Resolver` with `@Inject` property wrapper

### Infrastructure Layer
- **Framework adapters**: 
  - `AVCaptureService` (AVFoundation)
  - `VisionObjectDetectionService` (Vision + Core ML)
  - `VisionTextRecognizerService` (Vision)
  - `SFSpeechRecognizerService` (Speech)
  - `AVSpeechSynthesizerService` (AVFoundation)
  - `CoreHapticsFeedbackManager` (Core Haptics)
  - `MPSQualityService` (Metal Performance Shaders)
- **Platform-specific implementations** of all repository protocols

### Presentation Layer
- **View Models**: `MainViewModel` (reactive UI state management)
- **View Controllers**: `MainViewController`, `SettingsViewController`, `ItemListViewController`, `TextInputViewController`, ...
- **Custom Views**: `BoundingBoxView`, `QuadView`
- **Accessibility**: Comprehensive VoiceOver support and high-contrast UI

## Reactive State Management

The application uses **Combine** framework extensively for reactive programming:

### State Flow
```swift
// ViewModel exposes publishers
var boundingBoxesPublisher: AnyPublisher<[BoundingBox], Never>
var currentModePublisher: AnyPublisher<AppMode, Never>
var isSpeakingPublisher: AnyPublisher<Bool, Never>

// Coordinators manage application state
@Published private(set) var currentMode: AppMode = .idle
@Published private var buttonStates: [AppMode: MainViewModel.ButtonState]
```

### Event System
- **DomainEvent** enum for cross-component communication
- **EventBus** for centralized event distribution
- **StopController** for coordinated feature termination

## Concurrency Model

Revilio employs a sophisticated hybrid concurrency approach:

### Async/Await
```swift
// Infrastructure layer uses async/await
func singleFrame() async -> CameraFrame
func evaluate(frame: CameraFrame) async -> FrameSharpnessData?
```

### Combine Integration
```swift
// Bridges between async sequences and Combine
func framePublisher() -> AnyPublisher<CameraFrame, Never> {
    let subject = PassthroughSubject<CameraFrame, Never>()
    Task {
        for await frame in self.frames() {
            subject.send(frame)
        }
        subject.send(completion: .finished)
    }
    return subject.eraseToAnyPublisher()
}
```

### Structured Concurrency
- **OperationBag** for structured cancellation
- **Task coordination** through FeatureLifecycle protocol
- **Thread management** with dedicated processing queues

## Dependency Injection System

### Service Locator Pattern
```swift
// Resolver service locator
public enum Resolver {
    private static var registry: [String: Any] = [:]
    public static func register<T>(_ value: T) {
        let key = String(describing: T.self)
        registry[key] = value
    }
    public static func resolve<T>(_ type: T.Type) throws -> T
}
```

### Property Wrapper Injection
```swift
// @Inject property wrapper
@propertyWrapper public struct Inject<T> {
    public var wrappedValue: T {
        do {
            return try Resolver.resolve(T.self)
        } catch {
            // Error handling
        }
    }
}

// Usage in classes
@Inject var logger: Logger
@Inject var hapticFeedbackRepository: HapticFeedbackRepository
```

### Centralized Container
```swift
// DependencyContainer manages complex initialization
class DependencyContainer {
    private lazy var cameraRepository: CameraRepository = {
        return AVCaptureService(logger: sharedLogger)
    }()
    
    private lazy var searchItemUseCase: SearchItemUseCase = {
        return SearchItemUseCase(
            objectDetectionRepository: objectDetectionRepository,
            speechRecognizerRepository: speechRecognizerRepository,
            cameraRepository: cameraRepository,
            feedbackRepository: objectSearchFeedback,
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
            logger: sharedLogger
        )
    }()
}
```

## Computer Vision Pipeline

### Camera Management
- **AVCaptureService**: Manages camera lifecycle, zoom, torch control
- **Frame streaming**: Both Combine publishers and AsyncStream interfaces
- **Stability monitoring**: `CameraStabilityMonitor` for AF/AE convergence

### Real-time Processing
```swift
// Object detection pipeline
func processFrame(cameraFrame: CameraFrame) {
    // Convert to CVPixelBuffer
    // Perform VNImageRequestHandler processing
    // Convert results to domain objects
}

// Text recognition pipeline
func processFrame(cameraFrame: CameraFrame, accuracy: TextRecognitionAccuracy) {
    // Vision text recognition request
    // Language configuration based on settings
    // Results conversion to TextObservation
}
```

### Quality Assurance
- **CameraStabilityMonitor**: `AVCaptureDevice` AF/AE convergence observation
- **MPSQualityService**: Metal-accelerated sharpness evaluation
- **FrameSharpnessData**: Grid-based sharpness analysis (60×60 cells)

## Audio & Haptics System

### Speech Recognition
- **SFSpeechRecognizerService**: Real-time transcription (partial results and force finalization supported)
- **Audio session coordination**: `SharedAudioSessionController` for STT/TTS harmony
- **Multi-language support**: Dynamic language switching

### Speech Synthesis
```swift
// AVSpeechSynthesizerService features
func setAudioOutputRoute(_ route: AudioOutputRoute)
func setReadingSpeed(_ speed: ReadingSpeed)
func toggleReadingSpeed()
func setVoice(for localeId: String)
```

### Haptic Feedback
- **CoreHapticsFeedbackManager**: Pattern-based haptics with intensity control
- **Context-aware patterns**: Different patterns for guidance, success, errors
- **Accessibility integration**: Configurable feedback types

## Internationalization Architecture

### Runtime Language Switching
```swift
// LocalizationManager with dynamic bundle switching
func set(language: AppLanguage) {
    currentLanguage = language
    UserDefaults.standard.set(language.rawValue, forKey: storageKey)
    activateBundle(for: language)
    forceUIRefresh()
}
```

### Multi-layer Support
- **UI localization**: Through R.swift and dynamic bundle loading
- **Speech recognition**: Language configuration for SFSpeechRecognizer
- **Speech synthesis**: Voice selection based on locale
- **Text recognition**: VNRecognizeTextRequest.recognitionLanguages and .customWords configuration
- **ML models**: Multi-language object definitions

## Accessibility Implementation

### Comprehensive Support
- **VoiceOver integration**: Full accessibility labels and hints
- **Voice feedback for all actions**: Spoken prompts for navigation, settings changes and app state transitions
- **Tutorial menu**: Training sequence explaining all features and buttons
- **Dynamic Type support**: Responsive text sizing
- **High contrast mode**: Custom accessibility styling
- **Alternative input**: Multiple input methods (voice, keyboard, list)

### Programmatic Accessibility
```swift
// Recursive accessibility styling
func applyAccessibilityStyleRecursively() {
    if let button = self as? UIButton {
        // Apply bold, uppercase, large text styling
        // High contrast background and border
    }
    subviews.forEach { $0.applyAccessibilityStyleRecursively() }
}
```

## Siri Shortcuts Integration

### Deep Linking
- **Entity resolution**: From Siri queries to application objects
- **Context preservation**: Seamless transition from Siri to app
- **Multi-language support**: Intent phrases in all supported languages

### AppIntents Implementation
```swift
    // Text search shortcut
    AppShortcut(
        intent: FindTextIntent(),
        phrases: [
            "\(.applicationName) найти текст",
            "\(.applicationName) найти текст \(\.$query)",
            "\(.applicationName) искать текст \(\.$query)",
            "\(.applicationName) поиск текста \(\.$query)",
            
            "\(.applicationName) find text",
            "\(.applicationName) find text \(\.$query)",
            "\(.applicationName) search text \(\.$query)",
            
            "\(.applicationName) 查找文本",
            "\(.applicationName) 查找文本 \(\.$query)",
            "\(.applicationName) 搜索文本 \(\.$query)",
            "\(.applicationName) 文本搜索 \(\.$query)",
        ],
        shortTitle: "findTextShortTitle",
        systemImageName: "text.magnifyingglass"
    )
    
    // Item search shortcut
    AppShortcut(
        intent: FindItemIntent(),
        phrases: [
            "\(.applicationName) найти объект \(\.$item)",
            "\(.applicationName) поиск объекта \(\.$item)",
            "\(.applicationName) искать объект \(\.$item)",
            
            "\(.applicationName) find object \(\.$item)",
            "\(.applicationName) search object \(\.$item)",
            
            "\(.applicationName) 查找物体 \(\.$item)",
            "\(.applicationName) 物体搜索 \(\.$item)",
            "\(.applicationName) 搜索物体 \(\.$item)",
        ],
        shortTitle: "findItemShortTitle",
        systemImageName: "magnifyingglass"
    )

    // Text reading shortcut
    AppShortcut(
        intent: ReadTextIntent(),
        phrases: [
            "\(.applicationName) читай",
            "\(.applicationName) читать",
            "\(.applicationName) читай текст",
            "\(.applicationName) читать текст",
            
            "\(.applicationName) reading",
            "\(.applicationName) read text",
            
            "\(.applicationName) 阅读",
            "\(.applicationName) 读文本",
            "\(.applicationName) 阅读文本",
        ],
        shortTitle: "readTextShortTitle",
        systemImageName: "text.below.photo"
    )
```

## Performance Optimization

### Memory Management
- **Camera frame handling**: Zero-copy where possible, efficient buffer management
- **ML model lifecycle**: On-demand loading and unloading
- **Cancellation support**: Structured task cancellation throughout

### Thermal Management
- **ThermalThrottlingService**: Monitors device thermal state
- **Adaptive processing**: Adjusts frame rate and processing intensity
- **Graceful degradation**: Maintains functionality under constraints

### Battery Efficiency
- **Smart resource allocation**: Only activate necessary components
- **Background task management**: Properly handle app state transitions
- **Efficient ML inference**: Converted to CoreML, INT8 quantized SOTA object detection YOLO11m model, Apple Vision framework APIs for OCR provides maximum optimization and efficiency for iOS

## Testing Architecture

### Protocol-Based Testing
- **Repository protocols**: Enable mock implementations for testing
- **Use case isolation**: Test business logic without infrastructure dependencies
- **View model testing**: Mock use cases and repositories for UI testing
- **Camera fallback**: TODO StaticImageCameraRepository for run on simulator

### Debug Infrastructure
- **Logging system**: Unified logging through Logger protocol
- **Event bus**: Cross-component communication for debug events
- **Debug overlays**: Visual debugging tools for bounding boxes and text recognition

This architecture provides a robust foundation for accessibility-focused applications, with particular attention to performance, internationalization, and adaptive interfaces. The clear separation of concerns enables maintainability and testability while the reactive programming model ensures responsive and predictable behavior.

# 🚀 Installation and usage

## 📋 Requirements

- **Xcode:** 15.0 or later
- **Swift:** 6.0
- **iOS:** 17.6 or later
- **Device:** Physical iPhone with A12 Bionic chip or newer (Neural Engine required for optimal performance)
- **Dependencies:**
  - R.swift for resource management (managed via Swift Package Manager)
  - YOLOv8 and YOLO11 models from Ultralytics (included in repository)

## 🛠️ Installation & Build

1. **Clone the repository:**
```bash
   git clone https://github.com/KirillSharafutdinov/revilio-ios.git
   cd revilio-ios/revilio-ios
```
2. **Open the project in Xcode:**
```bash
   open Revilio.xcodeproj
```
3. **Configure code signing:**
- Select your development team in the "Signing & Capabilities" tab of the main target
- Ensure the bundle identifier is unique to avoid conflicts

4. **Install dependencies:**
- The project uses Swift Package Manager for dependencies
- Xcode should automatically resolve and download packages on opening

5. **Build and run:**
- Select your physical iOS device as the build target (simulator won't work for camera features)
- Press ⌘R to build and run the application

6. **Grant permissions:**
- On first launch, grant necessary permissions for:
  - Camera access
  - Microphone access (for speech recognition)
  - Speech recognition

> **Note:** The included ML models (YOLOv8, YOLO11) may need to be processed by Xcode on first build, which can take several minutes depending on your machine's performance.

## 📱 How to Use

Revilio is designed with simplicity and accessibility in mind. Here's how to use each of the three core features:

### 🔍 Object Search
1. Open Revilio and tap the "Find object" button on the main screen or use a Siri shortcut ("Hey Siri, Revilio find object [object name]")
2. Speak the name of the item you want to find when prompted (e.g., "spoon", "keys", "book")
   - You can switch the input method to "List" in settings menu: when you tap the "Find object" button, screen with all supported objects will appear. 
3. Point your device's camera toward the area where the item might be located
4. Follow the haptic and audio feedback cues that intensify as camera center get closer to the target object

### 📝 Text Search
1. Open Revilio and tap the "Find text" button on the main screen or use a Siri shortcut ("Hey Siri, Revilio find text" -> "[text_to_search]")
2. Speak the text you're looking for
  - You can switch the input method to "Keyboard" in settings menu: when you tap the "Find text" button, screen with text input field will appear. 
3. Scan your environment with the camera - the app will automatically detect text in view
4. Receive feedback when your searched text is detected, with guidance toward its location

### 📖 Text Reading
1. Position your device so the camera sees the text you want to read (document, book, sign)
2. Tap the "Read" button on Revilio's main screen
3. Wait momentarily for the camera to stabilize, you will feel haptic signals when the frames capture starts
4. Listen as the app begins reading the text aloud automatically
   - App will detect page with text in center of camera and discard the remaining areas of text, you can toggle this feature to off in settings menu
6. Navigate using the back/forward buttons to move between sentences if needed
   - You can switch navigation type to "Lines" in settings menu
7. Use the pause/resume button and toggle speech speed button to control the reading flow at your pace

# 📄 License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. This means that any derivative works or services using this code must also be open source and distributed under the same license.

The complete license text can be found in the [LICENSE](LICENSE) file in the root of this repository.

## 📚 Citation and Attribution

This project uses the following open-source software and models. If you use this project in your work, please cite the original authors accordingly.

### Ultralytics YOLOv8
The object detection functionality is powered by the YOLOv8 model from Ultralytics.
```bibtex
@software{yolov8_ultralytics,
  author = {Glenn Jocher and Ayush Chaurasia and Jing Qiu},
  title = {Ultralytics YOLOv8},
  version = {8.0.0},
  year = {2023},
  url = {https://github.com/ultralytics/ultralytics},
  orcid = {0000-0001-5950-6979, 0000-0002-7603-6750, 0000-0003-3783-7069},
  license = {AGPL-3.0}
}
```

**Model License Note:** The YOLOv8 model is used under the AGPL-3.0 license. This necessitates of any project using this model to be licensed under the same AGPL-3.0 license. The original model was trained on custom dataset and converted to CoreML format for use within this iOS application. For more details, see [/Models](/Models)

### Ultralytics YOLO11
The object detection functionality is also powered by the YOLO11 model from Ultralytics.
```bibtex
@software{yolo11_ultralytics,
  author = {Glenn Jocher and Jing Qiu},
  title = {Ultralytics YOLO11},
  version = {11.0.0},
  year = {2024},
  url = {https://github.com/ultralytics/ultralytics},
  orcid = {0000-0001-5950-6979, 0000-0003-3783-7069},
  license = {AGPL-3.0}
}
```

**Model License Note:** The YOLO11 model is used under the AGPL-3.0 license. This necessitates of any project using this model to be licensed under the same AGPL-3.0 license. The original model was converted to CoreML format for use within this iOS application, see [LICENSE.yolo11mCOCO.txt](revilio-ios/Revilio/Models/LICENSE.yolo11mCOCO) for details

### R.swift
This project uses [R.swift](https://github.com/mac-cain13/R.swift) (MIT License) for safe, autocompleted resource management.
```bibtex
@misc{rswift,
  author = {Mathijs Kadijk},
  title = {R.swift: Get strong typed, autocompleted resources in Swift projects},
  year = {2014},
  publisher = {GitHub},
  journal = {GitHub repository},
  howpublished = {\url{https://github.com/mac-cain13/R.swift}},
}
```

# 📬 Contact & Contributing

We welcome questions, feedback, and contributions from the community:

- **Questions & Issues:** If you have questions about the project or encounter any issues, please open an issue in this repository or contact us at [revilio.ios@gmail.com](mailto:revilio.ios@gmail.com)
- **Contributions:** We're open to suggestions and pull requests. Please feel free to create issues to discuss bugs or new features before submitting PRs
- **Accessibility Testing:** We particularly welcome feedback from blind and visually impaired users to help us improve the accessibility features of Revilio

We appreciate your interest in making Revilio better for everyone.
