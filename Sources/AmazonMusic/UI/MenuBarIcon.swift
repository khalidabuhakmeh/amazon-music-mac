import AppKit

/// Menu bar glyph: the app icon's seven-bar equalizer, drawn as a template image so macOS tints it
/// for light/dark menu bars and the highlighted state. Bar proportions match tools/icon/make_icon.swift.
enum MenuBarIcon {
    static let image: NSImage = {
        // Same relative heights as the app icon's bars (190…560 on a 1024 canvas).
        let heights: [CGFloat] = [190, 330, 500, 390, 560, 300, 170]
        let tallest = heights.max()!
        let barWidth: CGFloat = 1.8, gap: CGFloat = 0.9, maxHeight: CGFloat = 15
        let width = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
        let size = NSSize(width: ceil(width), height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            let x0 = (size.width - width) / 2
            for (i, h) in heights.enumerated() {
                let barHeight = max(barWidth, maxHeight * h / tallest)
                let rect = NSRect(x: x0 + CGFloat(i) * (barWidth + gap),
                                  y: (size.height - barHeight) / 2,
                                  width: barWidth, height: barHeight)
                NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Amazon Music"
        return image
    }()
}
