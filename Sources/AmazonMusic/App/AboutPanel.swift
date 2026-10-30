import AppKit
import SwiftUI

/// Content of the About panel. Pure data so it can be unit tested; `AboutPanel` renders it.
struct AboutInfo: Equatable {
    static let projectURL = URL(string: "https://github.com/khalidabuhakmeh/amazon-music-mac")!
    static let releasesURL = URL(string: "https://github.com/khalidabuhakmeh/amazon-music-mac/releases")!
    static let issuesURL = URL(string: "https://github.com/khalidabuhakmeh/amazon-music-mac/issues")!

    var appVersion: String
    var build: String
    var bridgeVersion: String
    var hideSectionsVersion: String
    var buildConfiguration: String
    var macOSVersion: String

    /// Marketing version; a missing one (e.g. a plain Xcode build) reads "development build".
    var displayVersion: String { appVersion.isEmpty || appVersion == "0.0.0" ? "development build" : appVersion }

    /// "1.1.4 (42)".
    var versionLine: String { build.isEmpty ? displayVersion : "\(displayVersion) (\(build))" }


    @MainActor
    static func current(bridgeVersion: String?, bundle: Bundle = .main) -> AboutInfo {
        let info = bundle.infoDictionary ?? [:]
        #if DEBUG
        let config = "Debug"
        #else
        let config = "Release"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return AboutInfo(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            bridgeVersion: bridgeVersion ?? "not connected",
            hideSectionsVersion: scriptVersion(resource: "hideSections", constant: "HIDE_SECTIONS_VERSION", bundle: bundle) ?? "unknown",
            buildConfiguration: config,
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }

    /// Reads `const NAME = "x.y.z"` from a bundled script (the version the app injects into the page).
    static func scriptVersion(resource: String, constant: String, bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: resource, withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return scriptVersion(in: src, constant: constant)
    }

    static func scriptVersion(in source: String, constant: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: constant)
        guard let re = try? NSRegularExpression(pattern: "\\b\(escaped)\\s*=\\s*\"([^\"]+)\""),
              let m = re.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let r = Range(m.range(at: 1), in: source) else { return nil }
        return String(source[r])
    }
}

/// Standard macOS About panel (icon, name, version, copyright) with project credits.
@MainActor
enum AboutPanel {
    static func show(bridgeVersion: String?) {
        let info = AboutInfo.current(bridgeVersion: bridgeVersion)
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            // AppKit renders "Version <applicationVersion> (<version>)".
            .applicationVersion: info.displayVersion,
            .version: info.build,
            .credits: credits(info),
        ])
    }

    static func credits(_ info: AboutInfo) -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        center.paragraphSpacing = 2
        let base: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: center]
        let muted = base.merging([.foregroundColor: NSColor.secondaryLabelColor]) { $1 }

        let s = NSMutableAttributedString()
        func add(_ text: String, _ attrs: [NSAttributedString.Key: Any] = base) { s.append(NSAttributedString(string: text, attributes: attrs)) }
        func link(_ text: String, _ url: URL) { add(text, base.merging([.link: url]) { $1 }) }

        // Kept short: the panel's credits area has a fixed height and scrolls (hiding the top) when overfilled.
        // The app version is already in the panel header, so only the injected scripts and build/OS are listed here.
        add("An unofficial, native macOS app for Amazon Music.\n")
        link("GitHub", AboutInfo.projectURL); add("  ·  ")
        link("Releases", AboutInfo.releasesURL); add("  ·  ")
        link("Report an Issue", AboutInfo.issuesURL); add("\n\n")
        add("Player bridge ", muted); add(info.bridgeVersion); add("  ·  Hide sections ", muted); add(info.hideSectionsVersion + "\n")
        add(info.buildConfiguration + " build  ·  macOS " + info.macOSVersion + "\n\n", muted)
        add("Not affiliated with or endorsed by Amazon.", muted)
        return s
    }
}

/// Replaces the default "About Amazon Music" item in the app menu.
struct AboutCommands: Commands {
    let player: PlayerState
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Amazon Music") { AboutPanel.show(bridgeVersion: player.bridgeVersion) }
        }
    }
}
