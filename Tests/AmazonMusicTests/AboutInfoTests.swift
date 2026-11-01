import Testing
import Foundation
@testable import AmazonMusic

@Suite struct AboutInfoTests {
    private func info(version: String = "1.1.4", build: String = "42") -> AboutInfo {
        AboutInfo(appVersion: version, build: build, bridgeVersion: "1.7.2", hideSectionsVersion: "4.2.0",
                  buildConfiguration: "Release", macOSVersion: "26.1.0")
    }

    @Test func testVersionLineIncludesBuild() {
        #expect(info().versionLine == "1.1.4 (42)")
        #expect(info(build: "").versionLine == "1.1.4")
    }

    @Test func testMissingOrPlaceholderVersionReadsAsDevelopmentBuild() {
        #expect(info(version: "").displayVersion == "development build")
        #expect(info(version: "0.0.0", build: "1").versionLine == "development build (1)")
    }

    @Test func testScriptVersionParsing() {
        #expect(AboutInfo.scriptVersion(in: "  const HIDE_SECTIONS_VERSION = \"4.2.0\";", constant: "HIDE_SECTIONS_VERSION") == "4.2.0")
        #expect(AboutInfo.scriptVersion(in: "const BRIDGE_VERSION=\"1.7.2\"", constant: "BRIDGE_VERSION") == "1.7.2")
        #expect(AboutInfo.scriptVersion(in: "const OTHER = \"1\"", constant: "BRIDGE_VERSION") == nil)
    }

    @Test func testBundledScriptsExposeVersions() {
        // The app bundle (test host) ships both scripts; the About panel reads their version constants.
        #expect(AboutInfo.scriptVersion(resource: "hideSections", constant: "HIDE_SECTIONS_VERSION") != nil)
        #expect(AboutInfo.scriptVersion(resource: "bridge", constant: "BRIDGE_VERSION") != nil)
    }

    @MainActor
    @Test func testUnconnectedBridgeIsLabelled() {
        #expect(AboutInfo.current(bridgeVersion: nil).bridgeVersion == "not connected")
        #expect(AboutInfo.current(bridgeVersion: "1.7.2").bridgeVersion == "1.7.2")
    }

    @MainActor
    @Test func testCreditsContainProjectLinkAndDisclaimer() {
        let s = AboutPanel.credits(info())
        #expect(s.string.contains("GitHub"))
        #expect(s.string.contains("Player bridge 1.7.2"))
        #expect(s.string.contains("Release build  ·  macOS 26.1.0"))
        #expect(s.string.contains("Not affiliated with or endorsed by Amazon"))
        var found = false
        s.enumerateAttribute(.link, in: NSRange(location: 0, length: s.length)) { v, _, _ in
            if (v as? URL) == AboutInfo.projectURL { found = true }
        }
        #expect(found)
    }
}
