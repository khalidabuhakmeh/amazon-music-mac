import XCTest
@testable import AmazonMusic

final class AboutInfoTests: XCTestCase {
    private func info(version: String = "1.1.4", build: String = "42") -> AboutInfo {
        AboutInfo(appVersion: version, build: build, bridgeVersion: "1.7.2", hideSectionsVersion: "4.2.0",
                  buildConfiguration: "Release", macOSVersion: "26.1.0")
    }

    func testVersionLineIncludesBuild() {
        XCTAssertEqual(info().versionLine, "1.1.4 (42)")
        XCTAssertEqual(info(build: "").versionLine, "1.1.4")
    }

    func testMissingOrPlaceholderVersionReadsAsDevelopmentBuild() {
        XCTAssertEqual(info(version: "").displayVersion, "development build")
        XCTAssertEqual(info(version: "0.0.0", build: "1").versionLine, "development build (1)")
    }

    func testScriptVersionParsing() {
        XCTAssertEqual(AboutInfo.scriptVersion(in: "  const HIDE_SECTIONS_VERSION = \"4.2.0\";", constant: "HIDE_SECTIONS_VERSION"), "4.2.0")
        XCTAssertEqual(AboutInfo.scriptVersion(in: "const BRIDGE_VERSION=\"1.7.2\"", constant: "BRIDGE_VERSION"), "1.7.2")
        XCTAssertNil(AboutInfo.scriptVersion(in: "const OTHER = \"1\"", constant: "BRIDGE_VERSION"))
    }

    func testBundledScriptsExposeVersions() {
        // The app bundle (test host) ships both scripts; the About panel reads their version constants.
        XCTAssertNotNil(AboutInfo.scriptVersion(resource: "hideSections", constant: "HIDE_SECTIONS_VERSION"))
        XCTAssertNotNil(AboutInfo.scriptVersion(resource: "bridge", constant: "BRIDGE_VERSION"))
    }

    @MainActor
    func testUnconnectedBridgeIsLabelled() {
        XCTAssertEqual(AboutInfo.current(bridgeVersion: nil).bridgeVersion, "not connected")
        XCTAssertEqual(AboutInfo.current(bridgeVersion: "1.7.2").bridgeVersion, "1.7.2")
    }

    @MainActor
    func testCreditsContainProjectLinkAndDisclaimer() {
        let s = AboutPanel.credits(info())
        XCTAssertTrue(s.string.contains("GitHub"))
        XCTAssertTrue(s.string.contains("Player bridge 1.7.2"))
        XCTAssertTrue(s.string.contains("Release build  ·  macOS 26.1.0"))
        XCTAssertTrue(s.string.contains("Not affiliated with or endorsed by Amazon"))
        var found = false
        s.enumerateAttribute(.link, in: NSRange(location: 0, length: s.length)) { v, _, _ in
            if (v as? URL) == AboutInfo.projectURL { found = true }
        }
        XCTAssertTrue(found)
    }
}
