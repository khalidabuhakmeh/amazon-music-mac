import Testing
@testable import AmazonMusic

@MainActor
struct IntentTests {
    @Test func titlesMatchActions() { #expect(SelfTest.checkIntentTitles() == nil) }
    @Test func nowPlayingText() {
        #expect(NowPlayingIntent.describe(TrackInfo(title: "A", artist: "B")) == "A — B")
        #expect(NowPlayingIntent.describe(nil) == "Nothing playing")
    }
}
