import Testing
import Foundation
@testable import AmazonMusic

struct WebNavigationPolicyTests {
    @Test(arguments: ["music.amazon.com", "www.amazon.com", "amazon.com", "www.amazon.co.uk", "amazon.de",
                      "music.amazon.co.jp", "www.amazon.com.au", "m.media-amazon.com", "x.ssl-images-amazon.com", "Music.Amazon.COM"])
    func allowed(host: String) { #expect(WebNavigationPolicy.isAmazonHost(host)) }

    @Test(arguments: ["evil.com", "amazon.evil.com", "notamazon.com", "amazon.com.evil.xx", "example.com/amazon.com",
                      "amazonaws.com", "", "amazon", "amazon.evilcorp"])
    func denied(host: String) { #expect(!WebNavigationPolicy.isAmazonHost(host)) }

    @Test func nilHost() { #expect(!WebNavigationPolicy.isAmazonHost(nil)) }

    @Test func urls() {
        #expect(WebNavigationPolicy.shouldLoadInApp(URL(string: "https://www.amazon.com/ap/signin")!))
        #expect(WebNavigationPolicy.shouldLoadInApp(URL(string: "https://www.amazon.de/ap/signin")!))
        #expect(WebNavigationPolicy.shouldLoadInApp(URL(string: "about:blank")!))
        #expect(!WebNavigationPolicy.shouldLoadInApp(URL(string: "https://example.org")!))
        #expect(!WebNavigationPolicy.shouldLoadInApp(URL(string: "mailto:a@b.c")!))
    }
}
