//
//  Constants.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation
import CoreGraphics

/// Centralised place for magic numbers and constants.
public enum Constants {
    /// UI tap debounce interval (reduced for snappier response)
    public static let searchDebounceInterval: TimeInterval = 0.005

    /// Debounce for single-tap "Read Text" control (was 0.2 s)
    public static let readTextDebounceInterval: TimeInterval = 0.003

    // MARK: - Camera zoom presets
    /// Discrete zoom levels exposed to the UI layer. Presentation code can iterate
    /// over this array to build segmented controls or stepper actions instead of
    /// hard-coding numeric literals.
    public static let zoomLevels: [CGFloat] = [1.0, 1.25, 1.8, 3.0, 5.0]

    /// Localised names for each zoom level. The two arrays share the same index.
    /// Computed dynamically so it picks up language switches at runtime.
    public static var zoomLevelNames: [String] {
        [
            R.string.synth.zoom1x(),
            R.string.synth.zoom1_3x(),
            R.string.synth.zoom1_8x(),
            R.string.synth.zoom3x(),
            R.string.synth.zoom5x()
        ]
    }

    // MARK: - FPS presets

    /// Default target FPS used across the app for camera frame processing.
    public static let defaultTargetFPS: Double = 15.0

    // MARK: - Haptic intensities

    /// Intensity for subtle button tap feedback.
    public static let hapticButtonIntensity: Float = 0.7

    /// Intensity for success confirmations.
    public static let hapticSuccessIntensity: Float = 0.8

    /// Intensity for error notifications.
    public static let hapticErrorIntensity: Float = 1.0

    // MARK: - Search Item parameters
    public enum SearchItem {
        
        public static var awaitObjectName: String { R.string.synth.searchItemAwaitObjectName() }
        /// Localizated prefix of announcement message about the start of item search
        public static var announcementPrefix: String { R.string.synth.searchItemAnnouncementPrefix() }
        
        public static var objectNotSupported: String { R.string.synth.objectNotSupported() }
        /// Localized message for auto-off notification
        public static var autooffTriggered: String { R.string.synth.itemSearchAutooffTriggered() }
        
        public static var itemSearchAutooffPrimary: Double = 300 // 5 min
        
        public static var itemSearchAutooffSecondary: Double = 120 // 2 min
    }
    // MARK: - Search Text parameters
    public enum SearchText {
        /// Localizated prefix of announcement message about the start of text search
        public static var announcementPrefix: String { R.string.synth.searchTextAnnouncementPrefix() }
        /// TODO in settings
        public static var recognizerLanguageMain: String { R.string.synth.searchTextLanguageMain() }
        public static var recognizerLanguageSecondary: String { R.string.synth.searchTextLanguageSecondary() }
        
        public static let minTextHeight: Float = 0.016
        /// Localized message for auto-off notification
        public static var autooffTriggered: String { R.string.synth.textSearchAutooffTriggered() }
        
        public static var textSearchAutooffPrimary: Double = 300 // 5 min
        
        public static var textSearchAutooffSecondary: Double = 120 // 2 min
        
        public static let startSearchTextSound: URL? = {
            if let url = Bundle.main.url(
                forResource: "startTextSearch",
                withExtension: "aac",
                subdirectory: "Resources/Audio"
            ) {
                return url
            }
            
            if let url = Bundle.main.url(forResource: "startTextSearch", withExtension: "aac") {
                return url
            }
            
            print("⚠️ Sound file not found in bundle. Available files:")
            if let resources = Bundle.main.urls(forResourcesWithExtension: "aac", subdirectory: nil) {
                resources.forEach { print(" - \($0.lastPathComponent)") }
            }
            
            return nil
        }()
    }
    
    // MARK: - Read Text parameters
    public enum ReadText {
        ///
        public static var announcement: String { R.string.synth.readTextAnnouncement() }
        
        public static var textNotDetected: String { R.string.synth.readTextNotDetected() }
        
        public static let minTextHeight: Float = 0.012
        /// Only one consecutive stable frame needed
        public static let requiredStableFrames: Int = 1
        /// Slightly relaxed lens movement tolerance – small movements are acceptable.
        public static let lensDeltaTolerance: Float = 0.005
        /// Relax exposure tolerance a little (1/6 EV) to accept more frames.
        public static let exposureTolerance: Float = 0.25
        /// TODO.
        public static let gridSize: Int = 60
        /// Base blur-score threshold (0 = razor-sharp, 1 = blurry).
        public static let blurScoreThreshold: Float = 0.25
        /// TODO.
        public static let minNumberOfSharpCellsReducingFactor: Double = 1.5

        // Cluster-detection tuning --------------------------------
        
        public static let minNumberOfObservationsForClustering = 6
        /// A strip/rectangle is considered mostly empty when > this proportion
        /// of its cells have **no** recognised text.
        public static let clusterEmptyThreshold: CGFloat = 0.9
        /// Vertical gap (in grid rows) allowed when dilating the cluster.
        public static let clusterVerticalGap: Int = 8
        /// Horizontal gap (in grid columns) allowed when dilating the cluster.
        public static let clusterHorizontalGap: Int = 1
        /// Slope step per diagonal emptiness test (in **degrees**).
        public static let clusterDiagonalDegreeStep: Double = 5.0
        /// Number of slope steps tested in each direction (total checks = 2*steps).
        public static let clusterDiagonalSteps: Int = 4
        /// Rows / columns are added to base cluster if empty cells amount < this value
        public static let clusterBaseFillEmptyThreshold: CGFloat = 0.1
    }

    // MARK: - Haptic parameters
    public enum Haptics {
        /// Slope factor used by CoreHapticsFeedbackManager.speedFactor(for:)
        public static let speedFactorSlope: Double = 7.0
    }

    // MARK: - Alignment guidance phrases for haptic/speech feedback
    /// Localised phrases that guide the user when aligning a target with the screen centre.
    /// These strings live in Synth.strings and are surfaced via R.swift.  Domain layer must
    /// not depend on R.swift directly – instead it references these constants.
    public enum Alignment {
        public static var leftPrompt: String { R.string.synth.alignLeft() }
        public static var rightPrompt: String { R.string.synth.alignRight() }
        public static var downPrompt: String { R.string.synth.alignDown() }
        public static var upPrompt: String { R.string.synth.alignUp() }
        /// Ellipsis placeholder – used when no vertical adjustment is needed.
        public static var placeholder: String { R.string.synth.alignPlaceholder() }

        /// Announcements used when the object / text is perfectly centred.
        public static var objectCentered: String { R.string.synth.objectCentered() }
        public static var textCentered: String { R.string.synth.textCentered() }
    }

    // MARK: - Settings keys (UserDefaults)
    public enum SettingsKeys {
        /// Key for Text Reading navigation segmented control preference (0 = lines, 1 = sentences.
        public static let textReadingNavigation = "settings.textReadingNavigation"
        /// Key for Text Reading area segmented control preference (0 = whole frame, 1 = page).
        public static let textReadingMethod = "settings.textReadingMethod"
        /// Key for Item Search auto-off preference (0 = off, 1 = 2 min, 2 = 5 min).
        public static let itemSearchAutooff = "settings.itemSearchAutooff"
        /// Key for Text Search auto-off preference (0 = off, 1 = 2 min, 2 = 5 min).
        public static let textSearchAutooff = "settings.textSearchAutooff"
    }

    public enum UserPreferences {
        /// Returns stored index of text reading navigation method. Defaults to 1 (sentences).
        public static var textReadingNavigationIndex: Int {
            UserDefaults.standard.integer(forKey: Constants.SettingsKeys.textReadingNavigation)
        }
        /// Returns stored index of text reading method. Defaults to 0 (whole frame).
        public static var textReadingMethodIndex: Int {
            UserDefaults.standard.integer(forKey: Constants.SettingsKeys.textReadingMethod)
        }
        /// Returns stored index of item search auto-off. Defaults to 1 (2 minutes).
        public static var itemSearchAutooffIndex: Int {
            UserDefaults.standard.object(forKey: Constants.SettingsKeys.itemSearchAutooff) as? Int ?? 1
        }
        /// Returns stored index of text search auto-off. Defaults to 1 (2 minutes).
        public static var textSearchAutooffIndex: Int {
            UserDefaults.standard.object(forKey: Constants.SettingsKeys.textSearchAutooff) as? Int ?? 1
        }
    }
} 
