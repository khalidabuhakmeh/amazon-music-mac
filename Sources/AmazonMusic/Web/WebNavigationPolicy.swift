import Foundation

/// Pure host-matching logic for main-frame navigation filtering.
/// Subresources (media-amazon, ssl-images-amazon, amazonaws, cloudfront) are never filtered;
/// they are listed in `subresourceHosts` for documentation/tests only.
enum WebNavigationPolicy {
    static let subresourceHosts = ["media-amazon.com", "ssl-images-amazon.com", "amazonaws.com", "cloudfront.net"]

    /// True if `host` is amazon.<tld> or *.amazon.<tld> (tld: com, de, ..., co.uk, com.au),
    /// or media-amazon.com / ssl-images-amazon.com (and subdomains).
    static func isAmazonHost(_ host: String?) -> Bool {
        guard var h = host?.lowercased(), !h.isEmpty else { return false }
        if h.hasSuffix(".") { h.removeLast() }
        for d in ["media-amazon.com", "ssl-images-amazon.com"] where h == d || h.hasSuffix("." + d) { return true }
        let labels = h.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let i = labels.firstIndex(of: "amazon") else { return false }
        let tld = Array(labels[(i + 1)...])
        func alpha(_ s: String, _ r: ClosedRange<Int>) -> Bool {
            r.contains(s.count) && s.unicodeScalars.allSatisfy { ("a"..."z").contains($0) }
        }
        switch tld.count {
        case 1: return alpha(tld[0], 2...3)
        case 2: return ["co", "com"].contains(tld[0]) && alpha(tld[1], 2...2)
        default: return false
        }
    }

    /// Whether a main-frame URL should load inside the app.
    static func shouldLoadInApp(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "about", "blob", "data": return true
        case "http", "https": return isAmazonHost(url.host)
        default: return false
        }
    }
}
