import Testing
import Foundation
@testable import AmazonMusic

@Suite struct SettingsValidationTests {
    func ok(_ s: String) -> URL? { if case .success(let u) = SettingsValidation.validateStartURL(s) { u } else { nil } }
    func err(_ s: String) -> SettingsValidation.URLError? { if case .failure(let e) = SettingsValidation.validateStartURL(s) { e } else { nil } }

    @Test func testValid() {
        #expect(ok("https://music.amazon.com")?.host == "music.amazon.com")
        #expect(ok("  https://music.amazon.co.uk/home ")?.host == "music.amazon.co.uk")
        #expect(ok("music.amazon.de")?.absoluteString == "https://music.amazon.de")
    }
    @Test func testInvalid() {
        #expect(err("") == .empty)
        #expect(err("http://music.amazon.com") == .notHTTPS)
        #expect(err("https://evil.com") == .notAmazonHost)
        #expect(err("https://amazon.com.evil.com") == .notAmazonHost)
        #expect(err("ftp://music.amazon.com") == .notHTTPS)
        #expect(err("https://") != nil)
    }
    @Test func testAllPresetsValid() {
        for h in SettingsValidation.presetHosts {
            #expect(ok("https://" + h) != nil, "\(h)")
            #expect(SettingsValidation.presetHost(for: "https://" + h) == h)
        }
        #expect(SettingsValidation.presetHost(for: "https://music.amazon.com/foo") == nil)
    }
}
