# Revilio - A Companion for the Blind and Visually Impaired

![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Platform](https://img.shields.io/badge/Platform-iOS_17.6+-lightgrey?logo=apple)
![License](https://img.shields.io/badge/License-AGPLv3-blue)

> **🚀 Download on the App Store:** [**Get Revilio for iPhone/iPad**](https://apps.apple.com/app/revilio/id6751191877)

# 🌟 Overview

Revilio is an iOS application designed to help blind and visually impaired people. It helps users navigate the physical world by locating objects or specific text, and reading documents or inscriptions aloud using artificial intelligence. It uses advanced Apple technologies and provides maximum performance on iPhones or iPads

**Revilio** — iOS-приложение, созданное для помощи незрячим и слабовидящим людям. Позволяет находить предметы или текст, а также читать документы и другие надписи вслух с помощью искусственного интеллекта. Использует передовые технологии Apple и обеспечивает максимальную производительность на iPhone или iPad.

**Revilio** 一款 iOS 应用，旨在帮助盲人和视障人士。它利用人工智能查找物体或文本，并大声朗读文档和其他文字。它采用先进的 Apple 技术，可在您的 iPhone 或 iPad 上提供最佳性能。

## 🎥 Demo

### Screenshots

| Read Text | Search text | Search Object |
| :---: | :---: | :---: |
| <img src="https://kirillsharafutdinov.github.io/revilio/assets/screen_1_rt_en.png" width="200"> | <img src="https://kirillsharafutdinov.github.io/revilio/assets/screen_2_ft_en.png" width="200"> | <img src="https://kirillsharafutdinov.github.io/revilio/assets/screen_3_fo_en.png" width="200"> |

## ✨ Features

### 🔍 Object Search
Never lose your essentials again. Find your keys, phone, or other common items simply by asking. Revilio scans your environment and guides you with intuitive haptic and audio cues that get stronger as you get closer.
   - **Recognizes 95 Items and Objects:** 80 common objects from the COCO dataset plus 15 custom items
   - **Voice-Activated:** Just speak the name of what you're looking for
   - **Intuitive Guidance:** Follow the sound and vibration to locate your item

### 📝 Text Search
Find anything written around you in an instant. Looking for a specific room number, street name, or product label? Just tell Revilio what text to find, and it will scan the environment and guide you directly to it with clear feedback.
   - **Flexible Input:** Speak your query naturally or type it for precision
   - **Live Text Detection:** Powerful on-device OCR scans the camera feed in real time
   - **Precision Guidance:** Get directed with intuitive cues that lead you to the exact location of the text

### 📖 Text Reading
Instantly read any printed text. Point your camera at a document, book, or sign, and Revilio will read it aloud clearly and naturally. Our smart clustering algorithm focuses on the text you're pointing at, ignoring distractions like the opposite page of an open book.
   - **The Best Accuracy:** Just point and push button. The App will automatically select the best quality frame
   - **Smart Text Clustering:** Focuses on the central text block automatically
   - **Navigation Control:** Easily jump between sentences or lines

### ♿ Comprehensive Accessibility
The entire interface is built according to accessibility guidelines, featuring high contrast, large bold uppercase text, and complete VoiceOver support. The app provides spoken feedback for all actions, menus, and state changes, ensuring you are always aware of what is happening. Feedback type (haptic, audio, or both) is configurable to suit individual preferences.

### 🎯 Stability & Quality
A sophisticated pipeline ensures reliable results. The app waits for the camera to stabilize (focus & exposure) and uses Metal-accelerated sharpness detection to analyze the frame quality before processing, significantly improving recognition accuracy while reading text.

### 🗣️ Siri Shortcuts Integration
Launch any core feature hands-free with voice commands via Siri. Just say "Hey Siri, Revilio find object keys", "Hey Siri, Revilio find text", then say "Exit" or "Hey Siri, Revilio reading" to get started.

### 🌍 Multi-Language Support
Fully supported in English, Russian, and Simplified Chinese across the entire stack: user interface, speech recognition, and text-to-speech output.

# 🚀 Installation and usage

## 📋 Requirements

- **Xcode:** 15.0 or later
- **Swift:** 6.0
- **iOS:** 17.6 or later
- **Device:** Physical iPhone or iPad with A12 Bionic chip or newer (Neural Engine required)
- **Dependencies:**
  - [R.swift](https://github.com/mac-cain13/R.swift) for resource management (managed via Swift Package Manager)
  - YOLOv8 and YOLO11 models from [Ultralytics](https://github.com/ultralytics/ultralytics) (included in repository)
 
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

## 🚨 Important User Notice: Limitations of AI

Revilio relies on artificial intelligence and computer vision technologies, which are inherently probabilistic and not infallible.

- **Accuracy is not guaranteed:** The object detection, text recognition, and text reading features may sometimes produce incorrect, incomplete, or misleading results.
- **Do not rely on Revilio in high-risk situations:** This application is **not designed** for and **must not be used** as a primary tool in situations where failure could lead to injury, legal consequences, or significant personal harm. This includes, but is not limited to:
    - Navigation near roads, stairs, or other physical hazards
    - Reading critical medical, legal, or financial documents
    - Identifying objects that could be dangerous if misidentified
- **Always use common sense:** The information provided by Revilio should be treated as an assistive suggestion, not an absolute truth. Always verify critical information through other means if possible.

## 📱 How to Use

Revilio is designed with simplicity and accessibility in mind. Here's how to use each of the three core features:

### 🔍 Object Search
1. Open Revilio and tap the "Find object" button on the main screen or use a Siri shortcut ("Hey Siri, Revilio find object [object name]")
2. Speak the name of the item you want to find when prompted (e.g., "spoon", "keys", "book")
   - You can switch the input method to "List" in settings menu: when you tap the "Find object" button, a screen with all supported objects will appear
3. Point your device's camera toward the area where the item might be located
4. Follow the haptic and audio feedback cues that intensify as the camera's center gets closer to the target object

### 📝 Text Search
1. Open Revilio and tap the "Find text" button on the main screen or use a Siri shortcut ("Hey Siri, Revilio find text" -> "[text_to_search]")
2. Speak the text you're looking for
   - You can switch the input method to "Keyboard" in settings menu: when you tap the "Find text" button, a screen with a text input field will appear
3. Scan your environment with the camera - the app will automatically detect text in view
4. Receive feedback when your searched text is detected, with guidance toward its location

### 📖 Text Reading
1. Position your device so the camera sees the text you want to read (document, book, sign)
2. Tap the "Read" button on Revilio's main screen
3. Wait momentarily for the camera to stabilize, you will feel a haptic signal when frame capture begins
4. Listen as the app begins reading the text aloud automatically
   - The app will detect the page with text in the center of the camera's view and ignore text in other areas. You can toggle this feature off in the settings menu
6. Navigate using the back/forward buttons to move between sentences if needed
   - You can switch the navigation type to "Lines" in settings menu
7. Use the pause/resume button and toggle speech speed button to control the reading flow at your pace

# 🏗️ Architecture & Technical Details

## Architecture Overview

Revilio follows **Clean Architecture** principles with a clear separation of concerns across four distinct layers:

### Domain Layer
- **Core business entities**: `ObjectObservation`, `TextObservation`, `BoundingBox`, `CameraFrame`
- **Key capabilities**: `CentralTextClusterDetector`, `ContinuousFrameProcessor`, `FeedbackPresenter`, `ItemQueryAcquisitionService`, `TextQueryAcquisitionService`, `PredictionService`, `StateMachine` and `SessionOrchestrator`
- **Use cases**: `SearchItemUseCase`, `SearchTextUseCase`, `ReadTextUseCase`
- **Repository protocols**: `CameraRepository`, `ObjectDetectionRepository`, `TextRecognizerRepository`, `SpeechRecognizerRepository`, `SpeechSynthesizerRepository`, `HapticFeedbackRepository`
- **Platform-agnostic**: Almost pure Swift with minimum external dependencies

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

### ⚡ Concurrency Model

The application employs a sophisticated hybrid concurrency architecture optimized for real-time performance.

- **Async/Await Foundation**: Infrastructure layer utilizes modern async/await patterns for camera frame acquisition and processing tasks
- **Combine Integration**: Custom bridge efficiently converts AsyncStream sequences into Combine publishers for reactive UI updates
- **Structured Concurrency**: OperationBag mechanism enforces rigorous lifecycle management and cancellation
- **Task Coordination**: FeatureLifecycle protocol ensures clean state transitions across application modes
- **Optimized Processing**: Intensive operations managed on dedicated, prioritized dispatch queues

### 🧩 Dependency Injection System

A lightweight, custom-built Dependency Injection system ensures clean architecture and testability.

- **Centralized Management**: DependencyContainer handles complex initialization and inter-service relationships
- **Service Locator Pattern**: Central Resolver registry provides single source of truth for all dependencies
- **Property Wrapper Injection**: Custom @Inject wrapper enables concise, type-safe dependency resolution
- **Testing Optimization**: Protocol-based design simplifies mocking and unit testing
- **Lifecycle Management**: Automatic dependency resolution and cleanup throughout application lifecycle

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
  
### Central Text Clustering
To ensure a seamless reading experience, especially when dealing with multi-column layouts or open books, Revilio employs a text clustering algorithm, which identifies and isolates the central block of text, ignoring adjacent text regions (like the opposite page in an open book). The process involves:

- **Grid-based Analysis**: The camera frame is divided into a fine grid where each cell records the presence of recognized text, creating a density map of textual content
- **Concentric Expansion**: Starting from the most central text-containing cell, the algorithm expands outward in all four directions, growing the cluster boundary while maintaining a configurable fill-density threshold
- **Adaptive Boundary Detection**: In the second phase, the algorithm performs intelligent gap detection beyond the initial cluster, scanning for significant empty regions in all directions using both straight and diagonal sampling patterns
- **Rotation-Resistant Gap Analysis**: The system tests multiple diagonal angles to account for page skew and perspective distortion, ensuring accurate boundary detection even with rotated text

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

### 🗣️ Siri & App Intents Integration

Revilio features deep system-level integration with Siri through the modern App Intents framework, enabling seamless voice-controlled operation.

- **Hands-Free Operation**: Launch any core feature using natural voice commands without touching the device
- **Entity Resolution**: Advanced query parsing that correctly maps spoken phrases to application functionality and objects
- **Context Preservation**: Maintains user context during transition from Siri to active application session
- **Multi-Language Support**: All intent phrases and parameters fully localized in English, Russian, and Simplified Chinese for native user experience

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
- **Efficient ML inference**: Converted to CoreML, INT8 quantized SOTA object detection YOLO11m model, Apple's Vision framework APIs for OCR provide maximum optimization and efficiency for iOS

## Testing Architecture

### Protocol-Based Testing
- **Repository protocols**: Enable mock implementations for testing
- **Use case isolation**: Test business logic without infrastructure dependencies
- **View model testing**: Mock use cases and repositories for UI testing

### Debug Infrastructure
- **Logging system**: Unified logging through Logger protocol
- **Event bus**: Cross-component communication for debug events
- **Debug overlays**: Visual debugging tools for bounding boxes and text recognition

Clear separation of concerns and the use of protocols and abstractions make it easy to maintain and test.

## 🗺️ Roadmap & Future Enhancements

We are committed to expanding Revilio's capabilities through ongoing development.

- **LiDAR Integration**: Implement distance estimation to located objects and texts for supported devices
- **Language Expansion**: Add support for Spanish, Portuguese, Hindi and Bengali across all application layers
- **Model Upgrade**: Transition from YOLOv8 to custom-trained YOLO11 for improved accuracy and performance
- **Dataset Enhancement**: Significant expansion and refinement of custom object dataset to improve detection quality
- **Comprehensive testing**: Implement comprehensive unit and UI test suites to ensure high quality and facilitate future development.

# 📄 License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. This means that any derivative works or services using this code must also be open source and distributed under the same license.

The complete license text can be found in the [LICENSE](LICENSE) file in the root of this repository.

## ⚠️ Disclaimer of Warranty

The GNU Affero General Public License v3.0 explicitly states:

**THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW. THE PROGRAM IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM IS WITH YOU.**

The developer of Revilio is not liable for any damages, data loss, or any other issues arising from the use of this software. Should the program prove defective, you assume the cost of all necessary servicing, repair, or correction.

## 📚 Citation and Attribution

This project uses the following open-source software and models. If you use this project in your work, please cite the original authors accordingly.

### Ultralytics YOLOv8
The object detection functionality is powered by the YOLOv8 model from [Ultralytics](https://github.com/ultralytics/ultralytics).
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

**Model License Note:** The YOLOv8 model is used under the AGPL-3.0 license. This requires any project using this model to be licensed under the same AGPL-3.0 or another compatible license. The original model was trained on custom dataset and converted to CoreML format for use within this iOS application. For more details, see [/Models](/Models)

### Ultralytics YOLO11
The object detection functionality is also powered by the YOLO11 model from [Ultralytics](https://github.com/ultralytics/ultralytics).
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

**Model License Note:** The YOLO11 model is used under the AGPL-3.0 license. This requires any project using this model to be licensed under the same AGPL-3.0 or another compatible license. The original model was converted to CoreML format for use within this iOS application, see [LICENSE.yolo11mCOCO.txt](revilio-ios/Revilio/Models/LICENSE.yolo11mCOCO) for details

### R.swift
This project uses [R.swift](https://github.com/mac-cain13/R.swift) [(MIT License)](https://github.com/mac-cain13/R.swift/blob/main/License) for safe, autocompleted resource management.
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
- **Contributions:** We are open to suggestions and pull requests. Please feel free to create issues to discuss bugs or new features before submitting PRs
- **Accessibility Testing:** We particularly welcome feedback from blind and visually impaired users to help improve the accessibility features of Revilio

We appreciate your interest in helping to make Revilio better for everyone.
