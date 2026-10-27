import XCTest
@testable import AmazonMusic

final class SettingsValidationTests: XCTestCase {
    func ok(_ s: String) -> URL? { if case .success(let u) = SettingsValidation.validateStartURL(s) { u } else { nil } }
    func err(_ s: String) -> SettingsValidation.URLError? { if case .failure(let e) = SettingsValidation.validateStartURL(s) { e } else { nil } }

    func testValid() {
        XCTAssertEqual(ok("https://music.amazon.com")?.host, "music.amazon.com")
        XCTAssertEqual(ok("  https://music.amazon.co.uk/home ")?.host, "music.amazon.co.uk")
        XCTAssertEqual(ok("music.amazon.de")?.absoluteString, "https://music.amazon.de")
    }
    func testInvalid() {
        XCTAssertEqual(err(""), .empty)
        XCTAssertEqual(err("http://music.amazon.com"), .notHTTPS)
        XCTAssertEqual(err("https://evil.com"), .notAmazonHost)
        XCTAssertEqual(err("https://amazon.com.evil.com"), .notAmazonHost)
        XCTAssertEqual(err("ftp://music.amazon.com"), .notHTTPS)
        XCTAssertNotNil(err("https://"))
    }
    func testAllPresetsValid() {
        for h in SettingsValidation.presetHosts {
            XCTAssertNotNil(ok("https://" + h), h)
            XCTAssertEqual(SettingsValidation.presetHost(for: "https://" + h), h)
        }
        XCTAssertNil(SettingsValidation.presetHost(for: "https://music.amazon.com/foo"))
    }
}
