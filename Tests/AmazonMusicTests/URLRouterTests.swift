import XCTest
@testable import AmazonMusic

final class URLRouterTests: XCTestCase {
    private func r(_ s: String) -> URLRouter.Route? { URL(string: s).flatMap(URLRouter.route) }

    func testActions() {
        for a in PlayerAction.allCases { XCTAssertEqual(r("amazonmusic://\(a.urlName)"), .action(a)) }
        XCTAssertEqual(r("AmazonMusic://TOGGLE"), .action(.toggle))
        XCTAssertEqual(r("amazonmusic://next/"), .action(.next))
    }

    func testOpen() {
        XCTAssertEqual(r("amazonmusic://open?path=/albums/B0123"), .open(path: "/albums/B0123"))
        XCTAssertEqual(r("amazonmusic://open?path=/my/library"), .open(path: "/my/library"))
        XCTAssertEqual(r("https://music.amazon.com/albums/B0123"), .open(path: "/albums/B0123"))
        XCTAssertEqual(r("https://MUSIC.amazon.com/search/x?y=1"), .open(path: "/search/x?y=1"))
    }

    func testRejections() {
        let bad = [
            "javascript:alert(1)",
            "amazonmusic://open?path=//evil.com",
            "amazonmusic://open?path=/a/../b",
            "amazonmusic://open?path=..",
            "amazonmusic://open?path=/%2e%2e/x",
            "amazonmusic://open?path=/%2E%2E%2fx",
            "amazonmusic://open?path=/%252e%252e/x",
            "amazonmusic://open?path=/%25252e%25252e/x",
            "amazonmusic://open?path=/a%2f%2fb",
            "amazonmusic://open?path=/a%5cb",
            "amazonmusic://open?path=/a%0ab",
            "amazonmusic://open?path=/a%00b",
            "amazonmusic://open?path=/a%09b",
            "amazonmusic://open?path=https://evil.com",
            "amazonmusic://open?path=albums",
            "amazonmusic://open",
            "amazonmusic://open?path=/a&path=/b",
            "amazonmusic://open/extra?path=/a",
            "amazonmusic://open?path=/" + String(repeating: "a", count: 512),
            "amazonmusic://bogus",
            "amazonmusic://next/extra",
            "amazonmusic://next:80",
            "amazonmusic://user@next",
            "amazonmusic://u:p@next",
            "amazonmusic://next#frag",
            "amazonmusic://next?x=1",
            "amazonmusic:///next",
            "https://evil.com",
            "https://music.amazon.com.evil.com/",
            "https://user@music.amazon.com/",
            "https://music.amazon.com:444/",
            "https://www.amazon.com/",
            "http://music.amazon.com/",
            "file:///etc/passwd",
        ]
        for s in bad { XCTAssertNil(r(s), s) }
    }

    func testLengthBoundary() {
        XCTAssertNotNil(r("amazonmusic://open?path=/" + String(repeating: "a", count: 511)))
    }
}
