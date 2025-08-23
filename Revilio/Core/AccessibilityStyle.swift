//
//  AccessibilityStyle.swift
//  Revilio
//
//  Created by Kirill Sharafutdinov.
//  Licensed under the AGPL-3.0 license.
//  See LICENSE file for full license details.
//

import UIKit

// MARK: - Constants
/// Centralised tweakable values for `AccessibilityStyle`.
/// Modify `horizontalPadding` to change the distance between the button edge
/// and its title on *all* styled buttons.
private enum AccessibilityStyleConstants {
    /// Left / right inset applied to every buttonʼs content to avoid text
    /// touching the rounded corners.  Feel free to tweak globally.
    static let horizontalPadding: CGFloat = 6
}

// MARK: - UIFont helper extension to get bold font of specified text style conveniently
private extension UIFont {
    /// Returns a bold version of the preferred font for the given text style.
    /// Falls back to the system bold font if the preferred font could not be created.
    static func boldPreferredFont(forTextStyle textStyle: UIFont.TextStyle, pointSize: CGFloat) -> UIFont {
        let baseFont = UIFont.preferredFont(forTextStyle: textStyle)
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) ?? baseFont.fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

// MARK: - UIView recursive styling to improve visibility for low-vision users
/// This protocol marks views whose textual contents should be transformed to
/// an uppercase, bold, large, white style for improved accessibility.
/// Currently adopted by `UILabel` and `UIButton` via extensions below.
private protocol AccessibilityStylable {}

extension UILabel: AccessibilityStylable {}
extension UIButton: AccessibilityStylable {}

extension UIView {
    /// Applies the accessibility style to the receiver and all of its subviews.
    /// Call this from a view controller's `viewDidLoad()` or `viewWillAppear()` to
    /// ensure that every label and button becomes large, bold, white, and uppercase.
    func applyAccessibilityStyleRecursively() {
        // Apply to current view if applicable
        if let button = self as? UIButton {
            // Prevent recursive styling caused by swizzled setters
            if button._isAccessibilityStyling { return }
            button._isAccessibilityStyling = true
            defer { button._isAccessibilityStyling = false }

            // Capture titles BEFORE removing configuration because configuration overrides title APIs.
            let titleNormal = button.title(for: .normal) ?? ""
            let titleHighlighted = button.title(for: .highlighted) ?? titleNormal

            // Remove configuration to prevent internal layout resetting our attributes
            button.configuration = nil

            let font = UIFont.systemFont(ofSize: 28, weight: .bold)
            let normalAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]

            let disabledAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.4)
            ]

            // Apply attributed titles (no stroke to avoid artifacts)
            button.setAttributedTitle(NSAttributedString(string: titleNormal.uppercased(with: .current), attributes: normalAttributes), for: .normal)
            button.setAttributedTitle(NSAttributedString(string: titleHighlighted.uppercased(with: .current), attributes: normalAttributes), for: .highlighted)
            button.setAttributedTitle(NSAttributedString(string: titleNormal.uppercased(with: .current), attributes: disabledAttributes), for: .disabled)

            // Adjust overall alpha for disabled state to visually dim entire button (background + text)
            button.alpha = button.isEnabled ? 1.0 : 0.5

            // Layout & adaptive font behavior
            button.titleLabel?.font = font
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.textAlignment = .center
            button.contentHorizontalAlignment = .center

            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.lineBreakMode = .byWordWrapping
            button.titleLabel?.adjustsFontSizeToFitWidth = false
            button.titleLabel?.minimumScaleFactor = 1.0
            
            /* TODO not working, searching for way to change this labels/hints on keyboards
            let systemHints = [
                "globe.keyboard.key.hint",
                "dictation.key.hint"
            ]
            
            if let hint = button.accessibilityHint?.lowercased(),
               systemHints.contains(hint) {
                
                DispatchQueue.main.async {
                    if let currentHint = button.accessibilityHint?.lowercased(),
                       systemHints.contains(currentHint) {
                        button.accessibilityLabel = "custom dictation label"
                        button.accessibilityHint = "custom dictation hint"
                        print("Custom hint applied: \(button.accessibilityHint ?? "")")
                    }
                }
            }
             */
            
            if button.bounds.width > 0 {
                adjustFontSizeForMultilineButton(button, title: titleNormal)
            } else {
                DispatchQueue.main.async {
                    self.adjustFontSizeForMultilineButton(button, title: titleNormal)
                }
            }
            
            // === Background color selection ===
            // Controllers can opt-in to "adaptive" background where color switches between
            // light (white) in dark mode and dark (black) in light mode with some alpha.
            // Otherwise we use a constant dark style for main view buttons.

            let owningVC = self.parentViewController()
            let useAdaptive = owningVC?.usesAdaptiveButtonBackground ?? false

            button.layer.cornerRadius = 10
            button.layer.borderWidth = 3
            
            if useAdaptive {
                // Light button on dark theme, dark button on light theme
                let adaptiveBackground = UIColor { trait in
                    if trait.userInterfaceStyle == .dark {
                        button.layer.borderColor = UIColor.white.cgColor
                        return UIColor.white.withAlphaComponent(0.1)
                    } else {
                        button.layer.borderColor = UIColor.black.cgColor
                        return UIColor.black
                    }
                }
                button.backgroundColor = adaptiveBackground
            } else {
                button.backgroundColor = UIColor.black.withAlphaComponent(0.4)
                button.layer.borderColor = UIColor.white.cgColor
            }
        }
        // Recurse to children
        subviews.forEach { $0.applyAccessibilityStyleRecursively() }
    }
    
    private func adjustFontSizeForMultilineButton(_ button: UIButton, title: String) {
        guard button.titleLabel != nil else { return }
        let uppercaseTitle = title.uppercased(with: .current)
        
        let maxFontSize: CGFloat = 28
        let minFontSize: CGFloat = 14
        let availableWidth = button.bounds.width - 8
        
        guard availableWidth > 10 else { return }
        
        let words = uppercaseTitle.split(separator: " ").map { String($0) }
        guard !words.isEmpty else { return }
        
        var fontSize = maxFontSize
        var currentFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        
        func textSize(for text: String, font: UIFont) -> CGSize {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
            
            return (text as NSString).boundingRect(
                with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).size
        }
        
        var allWordsFit = false
        while !allWordsFit && fontSize > minFontSize {
            allWordsFit = true
            currentFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            
            for word in words {
                let wordSize = (word as NSString).size(withAttributes: [.font: currentFont])
                if wordSize.width > availableWidth {
                    allWordsFit = false
                    break
                }
            }
            
            if !allWordsFit {
                fontSize -= 0.5
            }
        }
        
        var fullTextFits = false
        while !fullTextFits && fontSize > minFontSize {
            currentFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let fullTextSize = textSize(for: uppercaseTitle, font: currentFont)
            let maxAllowedHeight = currentFont.lineHeight * 2.2
            
            let lines = calculateLines(for: uppercaseTitle, font: currentFont, width: availableWidth)
            let wordsNotBroken = lines.allSatisfy { line in
                words.allSatisfy { word in
                    !line.contains("\(word.prefix(word.count-1)) ") &&
                    !line.contains(" \(word.suffix(word.count-1))")
                }
            }
            
            if fullTextSize.height <= maxAllowedHeight && wordsNotBroken {
                fullTextFits = true
            } else {
                fontSize -= 0.5
            }
        }
        
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: currentFont,
            .foregroundColor: UIColor.white
        ]
        
        let disabledAttributes: [NSAttributedString.Key: Any] = [
            .font: currentFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.4)
        ]
        
        button.setAttributedTitle(NSAttributedString(string: uppercaseTitle, attributes: normalAttributes), for: .normal)
        button.setAttributedTitle(NSAttributedString(string: uppercaseTitle, attributes: normalAttributes), for: .highlighted)
        button.setAttributedTitle(NSAttributedString(string: uppercaseTitle, attributes: disabledAttributes), for: .disabled)
        button.titleLabel?.font = currentFont
    }

    private func calculateLines(for text: String, font: UIFont, width: CGFloat) -> [String] {
        let textStorage = NSTextStorage(string: text)
        let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()
        
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        textStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: textStorage.length))
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        
        var lines: [String] = []
        layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: text.count)) { _, _, _, glyphRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let line = (text as NSString).substring(with: charRange)
            lines.append(line)
        }
        
        return lines
    }

    /// Returns the nearest owning view controller traversing responder chain.
    private func parentViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}

// MARK: - Convenience on UIViewController
public extension UIViewController {
    /// Traverses the root view hierarchy and applies the accessibility styling.
    /// You can call this in `viewDidLoad()` or `viewWillAppear(_: )`.
    func applyGlobalAccessibilityStyling() {
        view.applyAccessibilityStyleRecursively()
    }
}

// MARK: - Automatic Swizzling to enforce styling across the app
private extension UIViewController {
    @objc func _accessibilityStyled_viewWillAppear(_ animated: Bool) {
        // Call the original implementation (will be swapped at runtime)
        _accessibilityStyled_viewWillAppear(animated)
        applyGlobalAccessibilityStyling()
    }
}

// MARK: - Swizzle UIButton title setters to re-apply styling if texts change
private extension UIButton {
    @objc func _accessibilityStyled_setTitle(_ title: String?, for state: UIControl.State) {
        // Call original implementation (after swizzling)
        _accessibilityStyled_setTitle(title, for: state)
        // Re-apply accessibility style to keep font/stroke after any update
        self.applyAccessibilityStyleRecursively()
    }
}

private let _buttonSwizzleOnce: Void = {
    let originalSelector = #selector(UIButton.setTitle(_:for:))
    let swizzledSelector = #selector(UIButton._accessibilityStyled_setTitle(_:for:))
    if let original = class_getInstanceMethod(UIButton.self, originalSelector),
       let swizzled = class_getInstanceMethod(UIButton.self, swizzledSelector) {
        method_exchangeImplementations(original, swizzled)
    }
}()

// MARK: - Swizzle UIButton.configuration setter to restyle after external changes
private extension UIButton {
    @objc func _accessibilityStyled_setConfiguration(_ configuration: UIButton.Configuration?) {
        // Call original implementation first
        _accessibilityStyled_setConfiguration(configuration)
        // Prevent recursion when style function internally sets configuration
        guard !_isAccessibilityStyling else { return }
        if configuration != nil {
            self.applyAccessibilityStyleRecursively()
        }
    }
}

private let _buttonConfigSwizzleOnce: Void = {
    let originalSelector = NSSelectorFromString("setConfiguration:")
    let swizzledSelector = #selector(UIButton._accessibilityStyled_setConfiguration(_:))
    if let original = class_getInstanceMethod(UIButton.self, originalSelector),
       let swizzled = class_getInstanceMethod(UIButton.self, swizzledSelector) {
        method_exchangeImplementations(original, swizzled)
    }
}()

// MARK: - Swizzle UIButton.isEnabled setter to refresh style when state changes
private extension UIButton {
    @objc func _accessibilityStyled_setEnabled(_ enabled: Bool) {
        _accessibilityStyled_setEnabled(enabled) // original implementation (after swizzling)
        self.applyAccessibilityStyleRecursively()
    }
}

private let _buttonEnabledSwizzleOnce: Void = {
    let originalSelector = #selector(setter: UIButton.isEnabled)
    let swizzledSelector = #selector(UIButton._accessibilityStyled_setEnabled(_:))
    if let original = class_getInstanceMethod(UIButton.self, originalSelector),
       let swizzled = class_getInstanceMethod(UIButton.self, swizzledSelector) {
        method_exchangeImplementations(original, swizzled)
    }
}()

// Activate button swizzle together with view controller swizzle
public extension UIViewController {
    static let enableAccessibilityStylingAutomaticSwizzle: Void = {
        // Existing VC swizzle code preserved
        let originalSelector = #selector(UIViewController.viewWillAppear(_:))
        let swizzledSelector = #selector(UIViewController._accessibilityStyled_viewWillAppear(_:))
        if let originalMethod = class_getInstanceMethod(UIViewController.self, originalSelector),
           let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzledSelector) {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
        // Swizzle UIButton.setTitle and configuration setter as well
        _ = _buttonSwizzleOnce
        _ = _buttonConfigSwizzleOnce
        _ = _buttonEnabledSwizzleOnce
    }()
}

// MARK: - Recursion-guard helper on UIButton using associated objects
private extension UIButton {
    private static var isStylingKey: UInt8 = 0
    
    var _isAccessibilityStyling: Bool {
        get {
            (objc_getAssociatedObject(self, &Self.isStylingKey) as? Bool) ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &Self.isStylingKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

// MARK: - Adaptive Button Background Opt-In
private struct AssociatedKeys {
    static var adaptiveButtonBackgroundKey: UInt8 = 0
}

public extension UIViewController {
    var usesAdaptiveButtonBackground: Bool {
        get {
            (objc_getAssociatedObject(
                self,
                &AssociatedKeys.adaptiveButtonBackgroundKey
            ) as? Bool) ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &AssociatedKeys.adaptiveButtonBackgroundKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    func enableAdaptiveButtonBackground() {
        self.usesAdaptiveButtonBackground = true
    }
}
