import SwiftUI

/// Spacing scale on a 4 pt grid. `xxs` is for hairline gaps only. See design/DESIGN-SYSTEM.md.
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

/// Corner radii. Inner radius = outer radius - inset.
enum Radius {
    static let xs: CGFloat = 4   // artwork thumbnails in rows
    static let s: CGFloat = 8    // row hover fills
    static let m: CGFloat = 12   // cover artwork
}

/// Named opacities. Never write a raw `opacity(0.x)` in a view.
enum Surface {
    static let secondaryText = 0.65 // de-emphasised text and glyphs, divider, track
    static let hoverFill = 0.07     // row hover
    static let hairline = 0.12      // 0.5 pt borders around artwork
    static let scrim = 0.5          // black behind glyphs on artwork
    static let faint = 0.3          // disabled controls, scrub track, shadows
    static let dim = 0.7            // resting/pending controls, popover tint layer
}

/// Animation curves. Views never write a duration.
enum Motion {
    static let quick = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeOut(duration: 0.2)
}

/// Fixed-size SF Symbol glyph fonts (icons, not text; text uses system text styles).
enum Glyph {
    static let small = Font.system(size: 11, weight: .semibold)
    static let control = Font.system(size: 14, weight: .semibold)
    static let skip = Font.system(size: 16, weight: .semibold)
    static let play = Font.system(size: 20, weight: .semibold)
    static let placeholder = Font.system(size: 30)
}
