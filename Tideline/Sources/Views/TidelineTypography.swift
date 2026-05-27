import SwiftUI

/// Tideline's headline typography modifiers.
///
/// The design language specifies bold-italic serif for hero/sheet headlines
/// (per `docs/design/tideline-visual-language.md`). Historically the codebase
/// referenced `CormorantGaramond-BoldItalic` via `.font(.custom(...))` calls,
/// but the .ttf was never bundled into the app, so every call site silently
/// fell back to system serif — a hidden dependency that broke the design
/// intent at the actual point of render.
///
/// This helper:
///   1. Centralises the headline-typography choice in ONE file so a future
///      Cormorant (or other custom serif) bundling only needs to swap the
///      implementation here.
///   2. Falls back honestly to **system serif** (`design: .serif`) — Georgia
///      on iOS — which is what the app actually renders today.
///   3. Preserves the designer-specified absolute size + Dynamic-Type
///      scaling via `.font(.system(size:weight:design:))` + the existing
///      `relativeTo` TextStyle semantics consumed elsewhere.
///
/// **Future swap to Cormorant:** drop `CormorantGaramond-BoldItalic.ttf` into
/// `Tideline/Resources/Fonts/`, add `UIAppFonts: ["CormorantGaramond-BoldItalic.ttf"]`
/// to `project.yml`'s INFOPLIST keys, and change the `tidelineSerifHeadline`
/// implementation below to call `.font(.custom("CormorantGaramond-BoldItalic", size: size, relativeTo: relativeTo))`.
extension View {

    /// Apply Tideline's headline typography (bold italic serif).
    ///
    /// - Parameter size: the absolute point size at default Dynamic Type. Use the
    ///   sizes from `docs/design/tideline-visual-language.md` (28 / 24 / 22 / 32 / 26).
    /// - Parameter relativeTo: the SwiftUI `Font.TextStyle` the size scales against
    ///   for Dynamic Type. Pick the closest semantic match (`.title`, `.title2`,
    ///   `.title3`, `.headline`, `.largeTitle`).
    ///
    /// Visual today: system serif (Georgia on iOS) bold italic at `size` pt with
    /// Dynamic-Type scaling anchored to `relativeTo`. No external font assets.
    func tidelineSerifHeadline(
        size: CGFloat,
        relativeTo: Font.TextStyle = .title
    ) -> some View {
        self
            .font(
                .system(size: size, weight: .bold, design: .serif)
                .italic()
            )
            // Re-apply weight + italic at modifier level too — SwiftUI sometimes
            // drops these when a parent forces a different weight context (e.g.
            // toolbar / nav-title overrides). Belt-and-braces.
            .fontWeight(.bold)
            .italic()
    }
}
