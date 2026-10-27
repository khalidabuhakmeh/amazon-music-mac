import XCTest
@testable import AmazonMusic

@MainActor
final class HideSectionsTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, () -> Void) {
        let name = "hideSectionsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        return (d, { d.removePersistentDomain(forName: name) })
    }

    func testPodcastsSettingDefaultsOffAndPersists() {
        let (d, cleanup) = makeDefaults(); defer { cleanup() }
        let s = AppSettings(defaults: d)
        XCTAssertFalse(s.hidePodcasts)
        s.hidePodcasts = true
        XCTAssertTrue(d.bool(forKey: "hidePodcasts"))
        XCTAssertTrue(AppSettings(defaults: d).hidePodcasts)
    }

    func testAudibleSettingDefaultsOnWhenUnsetPersistsAndIsIndependent() {
        let (d, cleanup) = makeDefaults(); defer { cleanup() }
        let s = AppSettings(defaults: d)
        XCTAssertTrue(s.hideAudible)            // never set -> true
        XCTAssertNil(d.object(forKey: "hideAudible"))
        s.hideAudible = false
        XCTAssertFalse(AppSettings(defaults: d).hideAudible) // explicit choice respected
        s.hideAudible = true
        XCTAssertTrue(d.bool(forKey: "hideAudible"))
        XCTAssertFalse(d.bool(forKey: "hidePodcasts"))
        XCTAssertFalse(AppSettings(defaults: d).hidePodcasts)
    }

    func testGetAppSettingDefaultsOnWhenUnsetAndPersists() {
        let (d, cleanup) = makeDefaults(); defer { cleanup() }
        let s = AppSettings(defaults: d)
        XCTAssertTrue(s.hideGetApp)
        s.hideGetApp = false
        XCTAssertFalse(d.bool(forKey: "hideGetApp"))
        XCTAssertFalse(AppSettings(defaults: d).hideGetApp)
        XCTAssertFalse(d.bool(forKey: "hidePodcasts"))
    }

    func testHomeBannerSettingDefaultsOnWhenUnsetAndPersists() {
        let (d, cleanup) = makeDefaults(); defer { cleanup() }
        let s = AppSettings(defaults: d)
        XCTAssertNil(d.object(forKey: "hideHomeBanner"))
        XCTAssertTrue(s.hideHomeBanner)
        s.hideHomeBanner = false
        XCTAssertFalse(d.bool(forKey: "hideHomeBanner"))
        XCTAssertFalse(AppSettings(defaults: d).hideHomeBanner) // explicit off preserved
        s.hideHomeBanner = true
        XCTAssertTrue(AppSettings(defaults: d).hideHomeBanner)
    }

    func testExistingPersistedHidePodcastsKeepsWorking() {
        let (d, cleanup) = makeDefaults(); defer { cleanup() }
        d.set(true, forKey: "hidePodcasts")
        let s = AppSettings(defaults: d)
        XCTAssertTrue(s.hidePodcasts)
        XCTAssertTrue(s.hideAudible)
    }

    func testScriptSourcePrefixesFlags() {
        XCTAssertEqual(HideSectionsScript.source(base: "X", podcasts: true, audible: false, getApp: true, homeBanner: true),
                       "window.__amzHideSectionsInitial = {podcasts: true, audible: false, getApp: true, homeBanner: true};\nX")
        XCTAssertTrue(HideSectionsScript.source(base: "X", podcasts: false, audible: true, getApp: false, homeBanner: false).hasPrefix("window.__amzHideSectionsInitial = {podcasts: false, audible: true, getApp: false, homeBanner: false};"))
        let call = HideSectionsScript.applyCall(podcasts: true, audible: false, getApp: true, homeBanner: true)
        XCTAssertTrue(call.contains("setEnabled('podcasts', true)"))
        XCTAssertTrue(call.contains("setEnabled('audible', false)"))
        XCTAssertTrue(call.contains("setEnabled('getApp', true)"))
        XCTAssertTrue(call.contains("setEnabled('homeBanner', true)"))
    }

    func testBundledScriptExposesBothSections() throws {
        let url = try XCTUnwrap(Bundle(for: HideSectionsTests.self).url(forResource: "hideSections", withExtension: "js")
            ?? Bundle.main.url(forResource: "hideSections", withExtension: "js"))
        let src = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(src.contains("__amzHideSections"))
        XCTAssertTrue(src.contains("audible:"))
        XCTAssertTrue(src.contains("podcasts:"))
        XCTAssertTrue(src.contains("getApp:"))
        XCTAssertTrue(src.contains("homeBanner:"))
    }
}
