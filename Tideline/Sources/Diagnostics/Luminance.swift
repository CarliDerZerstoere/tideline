import SwiftUI
import UIKit

/// Pure WCAG-2.1 relative luminance and contrast-ratio helpers.
///
/// Lives in `Diagnostics/` rather than `Views/` because the only consumers
/// are tests + dev-time assertions; the runtime app uses SwiftUI's
/// `.foregroundStyle(.primary/.secondary)` semantic colours which Apple
/// already certifies for WCAG AA in their own design pass.
///
/// Audit fix (#133): the previous "WCAG AA contrast audit" task was
/// `completed` without a single ratio assertion in the codebase — visual
/// inspection only. This file + `LuminanceTests.swift` close that gap by
/// pinning the load-bearing color pairs to >= 4.5 (WCAG AA body text)
/// against drift.
///
/// Formula references:
///   - WCAG 2.1 §1.4.3 (Contrast — Minimum, Level AA, ratio ≥ 4.5:1 for normal text).
///   - W3C relative-luminance: https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
///   - W3C contrast-ratio: https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio
public enum Luminance {

    /// Relative luminance of an sRGB colour per WCAG 2.1.
    ///
    /// - Parameter color: any UIColor; alpha is ignored (caller is
    ///   responsible for compositing translucent overlays against a known
    ///   background before passing here).
    /// - Returns: relative luminance in 0...1 (0 = black, 1 = white).
    public static func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        func linearise(_ component: CGFloat) -> Double {
            let c = Double(component)
            return c <= 0.03928
                ? c / 12.92
                : pow((c + 0.055) / 1.055, 2.4)
        }

        let rl = linearise(r)
        let gl = linearise(g)
        let bl = linearise(b)
        return 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
    }

    /// WCAG 2.1 contrast ratio between two colours. Range: 1.0 (identical)
    /// to 21.0 (#000000 vs #FFFFFF).
    ///
    /// Thresholds:
    ///   - ≥ 4.5 → WCAG AA body text
    ///   - ≥ 3.0 → WCAG AA large text (18pt+ or 14pt+ bold) / UI elements
    ///   - ≥ 7.0 → WCAG AAA body text
    public static func contrastRatio(_ a: UIColor, _ b: UIColor) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Convenience over `contrastRatio` returning whether the pair meets
    /// the given WCAG threshold. Default `4.5` is the AA body-text rule.
    public static func meetsWCAG(
        _ a: UIColor,
        _ b: UIColor,
        threshold: Double = 4.5
    ) -> Bool {
        contrastRatio(a, b) >= threshold
    }
}
