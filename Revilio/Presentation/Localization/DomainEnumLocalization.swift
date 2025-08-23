//
//  DomainEnumLocalization.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import Foundation

/// Mapping of pure Domain enums → UI-ready localized strings.
extension ItemInputMethod {
    /// User-visible description shown in Settings UI.
    var localizedDescription: String {
        switch self {
        case .voice:
            return R.string.settings.itemInputMethodVoice()
        case .list:
            return R.string.settings.itemInputMethodList()
        }
    }
}

extension TextInputMethod {
    /// User-visible description shown in Settings UI.
    var localizedDescription: String {
        switch self {
        case .voice:
            return R.string.settings.textInputMethodVoice()
        case .keyboard:
            return R.string.settings.textInputMethodKeyboard()
        }
    }
}

extension AudioOutputRoute {
    /// Human-readable name used for VoiceOver announcements.
    var description: String {
        switch self {
        case .receiver:
            return R.string.synth.audioQuiet()
        case .speaker:
            return R.string.synth.audioLoud()
        }
    }
}

extension ReadingSpeed {
    /// Spoken label for the current TTS speed.
    var description: String {
        switch self {
        case .normal:
            return R.string.synth.speedNormal()
        case .accelerated:
            return R.string.synth.speedFast()
        }
    }
} 
