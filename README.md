# Revilio - Companion for the Blind and Visually Impaired

![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Platform](https://img.shields.io/badge/Platform-iOS_17.6+-lightgrey?logo=apple)
![License](https://img.shields.io/badge/License-AGPLv3-blue)

## 🌟 Overview

Revilio is a powerful iOS application designed to empower blind and visually impaired users. It helps navigate the physical world by finding objects, locating specific text, and reading documents and inscriptions aloud through a sophisticated combination of advanced computer vision, machine learning, and thoughtful accessibility design.

**Revilio** — это мощное iOS-приложение, созданное для помощи незрячим и слабовидящим людям. Оно позволяет находить предметы или текст, а также читать документы и другие надписи вслух с помощью продвинутого компьютерного зрения и искусственного интеллекта.

**Revilio** 是一款功能强大的 iOS 应用程序，旨在通过先进的计算机视觉和人工智能帮助盲人和视障用户导航他们的环境，查找物体，定位文本和朗读文档。

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

## 🏗️ Tech Stack & Architecture

Revilio is built with a robust, scalable architecture that emphasizes separation of concerns, testability, and maintainability. The application follows Clean Architecture principles with clear boundaries between different layers of responsibility.

### Architecture Overview
**Clean Architecture Layers:**
- **Domain Layer:** Contains business logic entities, use cases, and repository protocols
- **Application Layer:** Coordinates between domain and presentation layers, manages state
- **Infrastructure Layer:** Concrete implementations of domain protocols and device-specific operations
- **Presentation Layer:** UIKit-based UI components with accessibility enhancements

### 🛠️ Core Technologies & Frameworks
- **Swift 6:** Modern Swift with full concurrency support (async/await)
- **UIKit:** Primary UI framework with extensive accessibility support
- **Combine:** Reactive programming throughout the application for state management
- **Core ML:** Machine learning model inference for object detection
- **Vision:** Computer vision framework for text recognition and object detection
- **AVFoundation:** Camera capture, audio session management, and speech synthesis
- **Speech:** Real-time speech recognition with partial results support
- **Core Haptics:** Advanced haptic feedback patterns with precise intensity control
- **Metal Performance Shaders:** GPU-accelerated image processing for real-time performance
- **AppIntents:** Siri Shortcuts integration and system-level functionality

### 🔑 Key Architectural Patterns
- **Reactive State Management:** The entire application state is managed reactively using Combine publishers and subscribers
- **Dependency Management:** Сentralized dependency management in DependencyContainer
- **Dependency Injection:** A lightweight DI system using the `@Inject` property wrapper and Resolver service locator pattern for additional dependency controls
- **State Machines:** Complex feature lifecycles are managed through a custom generic StateMachine implementation
- **Repository Pattern:** All external dependencies are abstracted through repository protocols

## 🧩 Key Components & Modules

### Application Coordination
- **AppModeCoordinator:** Manages high-level application mode transitions (idle, searching, reading)
- **FeatureCoordinator:** Orchestrates feature-specific workflows and processing state
- **StopController:** Centralized point for terminating all active features with a single call

### Camera Pipeline
- **AVCaptureService:** Manages the AVFoundation capture pipeline with Combine and async/await interfaces
- **CameraStabilityMonitor:** Observes AF/AE convergence using KVO for stable captures
- **MPSQualityService:** GPU-accelerated frame quality evaluation using Metal Performance Shaders
- **ContinuousFrameProcessor:** Coordinates the continuous capture loop and frame publishing

### Computer Vision
- **VisionObjectDetectionService:** Real-time object detection using Core ML models with configurable thresholds
- **VisionTextRecognizerService:** OCR implementation using Vision framework with multi-language support
- **CentralTextClusterDetector:** Smart text block identification using grid-based clustering algorithm
- **PredictionService:** Handles detection conviction, position smoothing using ring buffers, and prediction history

### Speech & Audio
- **SFSpeechRecognizerService:** Speech recognition with partial results support and timeout handling
- **AVSpeechSynthesizerService:** Text-to-speech with configurable parameters and audio routing
- **SharedAudioSessionController:** Coordinates audio session between STT and TTS to prevent conflicts
- **ItemQueryAcquiring:** Protocols for acquiring user queries through speech or other input methods

### Feedback System
- **CoreHapticsFeedbackManager:** Tactile feedback patterns with intensity control
- **FeedbackPresenter:** Coordinates haptic and audio feedback based on context and user preferences
- **FeedbackPolicy:** Strategy pattern for converting detection results into feedback directives

### Accessibility System
- **AccessibilityStylable:** Protocol for views that need enhanced accessibility styling
- Recursive accessibility styling through `applyAccessibilityStyleRecursively()`
- Configurable feedback types (haptic, audio, or both) based on user preferences

### Infrastructure Services
- **ItemsForSearchRegistryService:** Centralized registry for all searchable items across ML models
- **LocalizationManager:** Runtime language switching with persistence in UserDefaults
- **ThermalThrottlingService:** Monitors device thermal state and provides throttling recommendations
- **RecentTextSearchesService:** Manages persistent storage of text search history

## ⚡ Concurrency Model

Revilio employs a sophisticated concurrency model that combines:

- **Async/Await:** For modern asynchronous operations, especially in the Infrastructure layer
- **Combine:** For reactive state management and event streaming
- **OperationBag:** For structured cancellation of asynchronous work
- **Dedicated Queues:** For performance-critical operations like image processing

The application carefully manages thread hopping to ensure UI operations always happen on the main thread while keeping heavy processing off the main thread.

## 📋 Requirements

- **Xcode:** 15.0 or later
- **Swift:** 6.0
- **iOS:** 17.0 or later
- **Device:** Physical iPhone with A12 Bionic chip or newer (Neural Engine required for optimal performance)
- **Dependencies:**
  - R.swift for resource management (managed via Swift Package Manager)
  - YOLOv8 and YOLO11 models from Ultralytics (included in repository)

## 🛠️ Installation & Build

1. **Clone the repository:**

   git clone https://github.com/KirillSharafutdinov/revilio-ios.git
   cd revilio

2. **Open the project in Xcode:**
   
   open Revilio.xcodeproj

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
1. Open Revilio and tap the "Find text" button on the main screen or use a Siri shortcut ("Hey Siri, Revilio find text -> [text_to_search]")
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

## 📄 License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. This means that any derivative works or services using this code must also be open source and distributed under the same license.

The complete license text can be found in the [LICENSE](LICENSE) file in the root of this repository.

## 🙏 Acknowledgements

We extend our gratitude to the following projects and communities that made Revilio possible:

- **R.swift:** We use R.swift (MIT License) for safe and convenient resource management throughout the application. We thank [mac-cain13](https://github.com/mac-cain13/R.swift) for this library
- **YOLO Models:** The object search functionality utilizes computer vision models based on the YOLOv8 and YOLO11 architectures from Ultralytics, distributed under the AGPL-3.0 license. We thank the [Ultralytics community](https://github.com/ultralytics/ultralytics) for their exceptional work

## 📬 Contact & Contributing

We welcome questions, feedback, and contributions from the community:

- **Questions & Issues:** If you have questions about the project or encounter any issues, please open an issue in this repository or contact us at [revilio.ios@gmail.com](mailto:revilio.ios@gmail.com)
- **Contributions:** While this is primarily a portfolio project, we're open to suggestions and pull requests. Please feel free to create issues to discuss bugs or new features before submitting PRs
- **Accessibility Testing:** We particularly welcome feedback from blind and visually impaired users to help us improve the accessibility features of Revilio

We believe in the open-source philosophy of collaboration and continuous improvement, and we appreciate your interest in making Revilio better for everyone.
