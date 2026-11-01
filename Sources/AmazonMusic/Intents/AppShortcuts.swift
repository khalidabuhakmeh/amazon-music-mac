import AppIntents

struct AmazonMusicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayPauseIntent(), phrases: ["Play or pause \(.applicationName)", "Toggle \(.applicationName)"],
                    shortTitle: "Play/Pause", systemImageName: "playpause.fill")
        AppShortcut(intent: NextTrackIntent(), phrases: ["Next track in \(.applicationName)", "Skip in \(.applicationName)"],
                    shortTitle: "Next", systemImageName: "forward.end.fill")
        AppShortcut(intent: PreviousTrackIntent(), phrases: ["Previous track in \(.applicationName)"],
                    shortTitle: "Previous", systemImageName: "backward.end.fill")
        AppShortcut(intent: LikeTrackIntent(), phrases: ["Like this song in \(.applicationName)"],
                    shortTitle: "Like", systemImageName: "heart")
        AppShortcut(intent: PlaySimilarIntent(), phrases: ["Play similar in \(.applicationName)"],
                    shortTitle: "Play Similar", systemImageName: "dot.radiowaves.left.and.right")
        AppShortcut(intent: NowPlayingIntent(), phrases: ["What's playing in \(.applicationName)"],
                    shortTitle: "Now Playing", systemImageName: "music.note")
    }
}
