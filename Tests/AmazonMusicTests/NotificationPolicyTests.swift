import Testing
@testable import AmazonMusic

struct NotificationPolicyTests {
    private func f(_ e: Bool, _ fk: Bool, _ nf: Bool, _ same: Bool) -> Bool {
        NotificationPolicy.shouldNotify(enabled: e, appIsFrontmostAndMainWindowKey: fk, notifyWhenFrontmost: nf, isSameTrackAsLast: same)
    }
    @Test func off() { #expect(!f(false, false, true, false)) }
    @Test func frontmostSkipped() { #expect(!f(true, true, false, false)) }
    @Test func frontmostAllowedWhenOptedIn() { #expect(f(true, true, true, false)) }
    @Test func sameTrack() { #expect(!f(true, false, false, true)) }
    @Test func background() { #expect(f(true, false, false, false)) }
}
