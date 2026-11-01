import Testing
import Foundation
@testable import AmazonMusic

@MainActor
@Suite(.serialized) struct HideSectionsTests {
    private func makeDefaults() -> (UserDefaults, () -> Void) {
        let name = "hideSectionsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        return (d, { d.removePersistentDomain(forName: name) })
    }

    @Test func testPodcastsSettingDefaultsOffAndPersists() {
        let (d, cleanup) = makeDefaults(); defer { cleanup() }
        let s = AppSettings(defaults: d)
        #expect(!(s.hidePodcasts))
        s.hidePodcasts = true
        #expect(d.bool(forKey: "hidePodcasts"))
        #expect(AppSettings(defaults: d).hidePodcasts)
    }

    @Test func testAudibleSettingDefaultsOnWhenUnsetPersistsAndIsIndependent() {
        let (d, cleanup) = makeDefaults(); defer { cleanup() }
        let s = AppSettings(defaults: d)
        #expect(s.hideAudible)            // never set -> true
        #expect(d.object(forKey: "hideAudible") == nil)
        s.hideAudible = false
        #expect(!(AppSettings(defaults: d).hideAudible)) // explicit choice respected
        s.hideAudible = true
        #expect(d.bool(forKey: "hideAudible"))
        #expect(!(d.bool(forKey: "hidePodcasts")))
        #expect(!(AppSettings(defaults: d).hidePodcasts))
    }

    @Test func testGetAppSettingDefaultsOnWhenUnsetAndPersists() {
        let (d, cleanup) = makeDefaults(); defer { cleanup() }
        let s = AppSettings(defaults: d)
        #expect(s.hideGetApp)
        s.hideGetApp = false
        #expect(!(d.bool(forKey: "hideGetApp")))
        #expect(!(AppSettings(defaults: d).hideGetApp))
        #expect(!(d.bool(forKey: "hidePodcasts")))
    }

    @Test func testHomeBannerSettingDefaultsOnWhenUnsetAndPersists() {
        let (d, cleanup) = makeDefaults(); defer { cleanup() }
        let s = AppSettings(defaults: d)
        #expect(d.object(forKey: "hideHomeBanner") == nil)
        #expect(s.hideHomeBanner)
        s.hideHomeBanner = false
        #expect(!(d.bool(forKey: "hideHomeBanner")))
        #expect(!(AppSettings(defaults: d).hideHomeBanner)) // explicit off preserved
        s.hideHomeBanner = true
        #expect(AppSettings(defaults: d).hideHomeBanner)
    }

    @Test func testExistingPersistedHidePodcastsKeepsWorking() {
        let (d, cleanup) = makeDefaults(); defer { cleanup() }
        d.set(true, forKey: "hidePodcasts")
        let s = AppSettings(defaults: d)
        #expect(s.hidePodcasts)
        #expect(s.hideAudible)
    }

    @Test func testScriptSourcePrefixesFlags() {
        #expect(HideSectionsScript.source(base: "X", podcasts: true, audible: false, getApp: true, homeBanner: true) == "window.__amzHideSectionsInitial = {podcasts: true, audible: false, getApp: true, homeBanner: true};\nX")
        #expect(HideSectionsScript.source(base: "X", podcasts: false, audible: true, getApp: false, homeBanner: false).hasPrefix("window.__amzHideSectionsInitial = {podcasts: false, audible: true, getApp: false, homeBanner: false};"))
        let call = HideSectionsScript.applyCall(podcasts: true, audible: false, getApp: true, homeBanner: true)
        #expect(call.contains("setEnabled('podcasts', true)"))
        #expect(call.contains("setEnabled('audible', false)"))
        #expect(call.contains("setEnabled('getApp', true)"))
        #expect(call.contains("setEnabled('homeBanner', true)"))
    }

    @Test func testBundledScriptExposesBothSections() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "hideSections", withExtension: "js")
            ?? Bundle.main.url(forResource: "hideSections", withExtension: "js"))
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(src.contains("__amzHideSections"))
        #expect(src.contains("audible:"))
        #expect(src.contains("podcasts:"))
        #expect(src.contains("getApp:"))
        #expect(src.contains("homeBanner:"))
    }
}
private final class BundleToken {}
