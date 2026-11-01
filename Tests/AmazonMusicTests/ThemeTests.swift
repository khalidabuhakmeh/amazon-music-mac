import Foundation
import Testing
@testable import AmazonMusic

private final class BundleLocator {}

@Suite("Theme")
struct ThemeTests {
    private var bundle: Bundle {
        let b = Bundle(for: BundleLocator.self)
        return b.url(forResource: "themeHelper", withExtension: "js") != nil ? b : Bundle.main
    }

    // MARK: stored value

    @Test func storedValueParsingAndFallback() {
        #expect(Theme(stored: "light") == .light)
        #expect(Theme(stored: "default") == .default)
        #expect(Theme(stored: "synthwave") == .synthwave)
        #expect(Theme(stored: nil) == .default)
        #expect(Theme(stored: "") == .default)
        #expect(Theme(stored: "Light") == .default) // raw values are exact
        #expect(Theme(stored: "nonsense") == .default)
    }

    @Test func displayNamesAndAvailability() {
        #expect(Theme.allCases.map(\.displayName) == ["Default", "Light", "Synthwave", "Cyberpunk", "Vampire"])
        #expect(Theme.available == [.default, .light])
        #expect(Theme.default.cssResource == nil)
    }

    @MainActor @Test func settingDefaultsPersistsAndIgnoresUnknown() {
        let name = "themeTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        #expect(AppSettings(defaults: d).theme == .default)
        #expect(d.object(forKey: "theme") == nil)
        let s = AppSettings(defaults: d)
        s.theme = .light
        #expect(d.string(forKey: "theme") == "light")
        #expect(AppSettings(defaults: d).theme == .light)
        d.set("bogus", forKey: "theme")
        #expect(AppSettings(defaults: d).theme == .default)
    }

    // MARK: script builder

    private static let nasty = "a{content:\"q\\\"uote\\\\\"} /* </style></script> */\nline2\r\n${x} `tick` 'sq' \u{2028}\u{2029} \u{0}end"

    /// Extracts the JSON string literal used in the call and parses it back.
    private func roundTrip(_ s: String) throws -> String {
        let lit = ThemeScript.literal(s)
        let data = Data(("[" + lit + "]").utf8)
        let arr = try #require(try JSONSerialization.jsonObject(with: data) as? [String])
        return try #require(arr.first)
    }

    @Test func literalRoundTripsHostileCSS() throws {
        #expect(try roundTrip(Self.nasty) == Self.nasty)
        #expect(try roundTrip("") == "")
    }

    @Test func literalNeverContainsRawBreakoutSequences() {
        let lit = ThemeScript.literal(Self.nasty)
        #expect(!lit.contains("</"))
        #expect(!lit.contains("\n"))
        #expect(!lit.contains("\r"))
        #expect(!lit.contains("\u{2028}"))
        #expect(!lit.contains("\u{2029}"))
        #expect(lit.hasPrefix("\"") && lit.hasSuffix("\""))
        // ${...} and backticks are inert inside a double-quoted JS string, and we never emit a template literal.
        #expect(!lit.hasPrefix("`"))
    }

    @Test func applyCallEmbedsOnlyEncodedCSS() throws {
        let call = ThemeScript.applyCall(css: Self.nasty, colorScheme: "light")
        #expect(call.hasPrefix("try {"))
        #expect(call.contains("window.__amzTheme"))
        #expect(!call.contains("</style>"))
        #expect(!call.contains("\n")) // single line: newlines in CSS were escaped
        #expect(call.contains(ThemeScript.literal(Self.nasty)))
        #expect(call.contains("\"light\""))
    }

    @Test func defaultThemeRemovesTheInjectedStyle() {
        for css in [nil, ""] as [String?] {
            let call = ThemeScript.applyCall(css: css, colorScheme: "dark")
            #expect(call.contains("h.set(null,"))
        }
        let source = ThemeScript.source(helper: "/*helper*/", css: nil, colorScheme: "dark")
        #expect(source.hasPrefix("/*helper*/"))
        #expect(source.contains("h.set(null,"))
        // Theme.default has no CSS at all, so the controller always passes nil for it.
        #expect(Theme.default.loadCSS(bundle: bundle) == nil)
    }

    @Test func helperRemovesStyleNodeWhenCSSNull() throws {
        let url = try #require(bundle.url(forResource: "themeHelper", withExtension: "js"))
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(src.contains("window.__amzTheme"))
        #expect(src.contains("el.remove()"))
        #expect(src.contains(ThemeScript.styleId))
    }

    // MARK: bundled CSS

    @Test(arguments: Theme.available.filter { $0 != .default })
    func availableThemeCSSExistsAndIsNonEmpty(theme: Theme) throws {
        let css = try #require(theme.loadCSS(bundle: bundle), "missing \(theme.rawValue).css in bundle")
        #expect(css.trimmingCharacters(in: .whitespacesAndNewlines).count > 200)
        #expect(!css.contains("filter: invert")) // themes must not invert artwork
    }
}
