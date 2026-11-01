import Foundation

/// Web UI themes: injected CSS on top of Amazon's (dark-only) player. `default` = no override.
/// Adding a theme = add `Resources/themes/<rawValue>.css` + list the case in `available`.
/// See docs/THEMES.md.
enum Theme: String, CaseIterable, Sendable {
    case `default`, light, synthwave, cyberpunk, vampire

    /// Themes shown in Settings (those with a finished CSS file).
    static let available: [Theme] = [.default, .light, .synthwave, .cyberpunk, .vampire]

    /// Unknown / missing stored value falls back to `.default`.
    init(stored: String?) { self = stored.flatMap(Theme.init(rawValue:)) ?? .default }

    var displayName: String {
        switch self {
        case .default: "Default"
        case .light: "Light"
        case .synthwave: "Synthwave"
        case .cyberpunk: "Cyberpunk"
        case .vampire: "Vampire"
        }
    }

    /// Bundled CSS file name (no extension). `nil` for Default (no override).
    var cssResource: String? { self == .default ? nil : rawValue }

    /// CSS `color-scheme` the theme wants (page widgets, scrollbars).
    var colorScheme: String { self == .light ? "light" : "dark" }

    /// Window / under-page background to avoid flashes. nil => system default.
    var underPageRGB: (r: Double, g: Double, b: Double)? {
        switch self {
        case .light: (0.97, 0.97, 0.98)
        case .synthwave: (0.071, 0.039, 0.165)   // #120a2a
        case .cyberpunk: (0.043, 0.043, 0.059)   // #0b0b0f
        case .vampire: (0.039, 0.016, 0.020)     // #0a0405
        case .default: nil
        }
    }

    func loadCSS(bundle: Bundle = .main) -> String? {
        guard let name = cssResource, let url = bundle.url(forResource: name, withExtension: "css") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// Pure builders for the theme JavaScript. CSS is always JSON-encoded, never interpolated raw.
enum ThemeScript {
    static let styleId = "amz-theme-style"

    /// JSON string literal (valid JS) for arbitrary text. Escapes `</`, U+2028/9 too.
    static func literal(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s], options: []),
              var arr = String(data: data, encoding: .utf8) else { return "\"\"" }
        arr.removeFirst(); arr.removeLast() // strip [ ]
        return arr.replacingOccurrences(of: "</", with: "<\\/")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// Statement that sets the desired theme (css nil/empty => remove). Safe to run repeatedly.
    static func applyCall(css: String?, colorScheme: String) -> String {
        let c = (css?.isEmpty ?? true) ? "null" : literal(css!)
        return "try { var h = window.__amzTheme; if (h) h.set(\(c), \(literal(colorScheme))); } catch (e) {}"
    }

    /// Document-start script: helper + initial theme (no flash).
    static func source(helper: String, css: String?, colorScheme: String) -> String {
        helper + "\n" + applyCall(css: css, colorScheme: colorScheme)
    }
}
