# User stories

Status key: done = delivered; `[x]` criteria are verified by tests, snapshots or self-test; `[ ]` need a person or later work. Manual checks live in docs/QA.md.

## M1 Core playback

### S-001 Sign in and play music in the app
As the user, I sign in to music.amazon.com inside the app and play a full track.
Screens: main-window
Acceptance:
- [ ] Web player loads in a WKWebView with its own data store (QA §1 Login).
- [ ] Full track plays past the 30 s preview mark (QA §2 DRM).
- [ ] [manual] Sign-in persists across quit and relaunch; popup sign-in returns to the main view.
Status: todo

### S-002 Control playback with media keys
As the user, I press F7/F8/F9, use Control Center or AirPods to control playback.
Depends: S-001
Acceptance:
- [x] [unit] NowPlayingSnapshot maps player state to Now Playing info (NowPlayingSnapshotTests).
- [ ] [manual] Exactly one Now Playing entry; keys work with the window closed (QA §3 rows 1-12).
- [ ] [manual] AirPods stem/double/triple tap controls (QA §3 row 6).
Status: doing

### S-003 See artwork at display size in Control Center
As the user, artwork appears sharp without the app decoding full-size images.
Screens: menu-bar-player
Acceptance:
- [x] [unit] Thumbnail decode caps the long edge at the requested pixel size (ArtworkCacheTests).
- [x] [unit] Non-image and oversize data are rejected; untrusted hosts are refused.
- [x] [unit] Second request is served from memory; a different size reuses the disk file without refetching.
Status: done

### S-004 Keep playing when the window is closed
As the user, I close the window and music continues.
Depends: S-001
Acceptance:
- [ ] [manual] Playback continues; Open reopens the window (QA §7).
Status: todo


## M2 Menu bar mini player

### S-005 Control playback from the menu bar
As the user, I open the mini player to see cover, title, progress and controls.
Screens: menu-bar-player, menu-bar-idle
Acceptance:
- [x] [snap] Playing, paused and idle fixtures render with no pixel diff (scripts/snapshot.sh --diff).
- [x] [unit] StatusMenuModel titles and enabled states match player state (StatusMenuModelTests).
- [ ] [manual] Scrub bar seeks; updates on track change (QA §4).
Status: done

### S-006 Like a track from the mini player
As the user, I tap the heart badge to like or unlike the current track.
Screens: menu-bar-player
Acceptance:
- [x] [snap] Liked, unliked and unknown states render (docs/LIKE.md).
- [ ] [manual] Like state matches the web player (QA Like).
Status: done

### S-007 Toggle shuffle and repeat
As the user, I change shuffle and repeat from the mini player.
Screens: menu-bar-player
Acceptance:
- [x] [unit] Repeat maps to PlayerAction.repeatMode with raw value 'repeat' (PlayerActionTests).
- [ ] [manual] Modes match the web player (QA Shuffle / Repeat).
Status: done

### S-008 Play similar music
As the user, I start a station based on the current track.
Screens: menu-bar-player
Acceptance:
- [x] [unit] The action exists in the PlayerAction catalog.
- [ ] [manual] Station starts (QA Play Similar Music).
Status: done

### S-009 Browse and jump in Up Next
As the user, I expand Up Next and click a song to play it.
Screens: menu-bar-player-upnext
Acceptance:
- [x] [snap] Collapsed and expanded queue render.
- [ ] [manual] Clicking a row jumps to it; queue refreshes after Next/Previous (QA Up Next, Jump to an Up Next song).
Status: done

### S-010 Use the right-click menu on the menu bar item
As the user, I right-click the status item for Play/Pause, Next, Previous, Open.
Screens: status-menu
Acceptance:
- [x] [unit] Menu model titles and states (StatusMenuModelTests).
- [ ] [manual] Works with the main window closed (QA §4).
Status: done

### S-011 Use the Dock menu
As the user, I right-click the Dock icon for now playing and transport items.
Screens: dock-menu
Acceptance:
- [x] [unit] DockMenuModel (DockMenuModelTests).
- [ ] [manual] Items act on the bridge (QA §6).
Status: done

### S-012 Get track-change notifications
As the user, I see a notification with title, artist and artwork on track change.
Acceptance:
- [x] [unit] NotificationPolicy decides when to post (NotificationPolicyTests).
- [ ] [manual] Permission prompt and delivery on an ad-hoc signed build (QA §5).
Status: done


## M3 Keyboard and system

### S-013 Use Controls menu shortcuts
As the user, I press ⌘P play/pause, ⌘→ next, ⌘← previous, ⌘L like, ⌥⌘S shuffle, ⌥⌘R repeat, ⇧⌘S play similar.
Acceptance:
- [x] [unit] CommandMenuModel titles and shortcuts (CommandMenuModelTests).
- [x] [self] Menu items map to PlayerAction cases (scripts/build.sh --selftest).
- [ ] [manual] ⌘←/⌘→ inside the Amazon search field behave sensibly (unverified).
Status: done

### S-014 Navigate the web player from the menu
As the user, I press ⌘[ back, ⌘] forward, ⌘R reload, ⇧⌘H home.
Acceptance:
- [x] [unit] Navigation items in CommandMenuModel.
- [ ] [manual] Each shortcut acts on the web view.
Status: done

### S-015 Drive the app with amazonmusic:// URLs
As the user, I open amazonmusic://next (and other actions) from Terminal or a link.
Acceptance:
- [x] [unit] URLRouter parses actions and rejects malformed or non-ASCII URLs (URLRouterTests).
- [ ] [manual] Effect on a signed-in session (needs sign-in).
Status: done

### S-016 Use Shortcuts and Spotlight via App Intents
As the user, I run Play/Pause, Next and others from Shortcuts.
Acceptance:
- [x] [unit] Intent titles match the PlayerAction catalog (IntentTests).
- [x] [self] Selftest checks intent titles.
- [ ] [manual] Actions appear in Shortcuts and Next takes effect.
Status: done

### S-017 Launch at Login
As the user, I toggle Launch at Login in Settings.
Screens: settings-general
Acceptance:
- [x] [unit] LoginItemPresentation mapping and FakeLoginItem (LoginItemTests).
- [ ] [manual] Real SMAppService registration across a reboot.
Status: done

### S-018 Control the app from the agent CLI and MCP server
As the user, I run `amazonmusic` commands, or an agent calls the MCP server.
Acceptance:
- [x] [unit] 15 commands decode and encode (AgentCommandsTests).
- [x] [unit] Socket mode 600, directory 700, peer uid check via getpeereid.
- [ ] [manual] `claude mcp add` live verification.
- [ ] [unit] Connection from a different uid is rejected.
Status: done


## M4 Settings and look

### S-019 Hide sections of the web player
As the user, I hide podcasts, Audible, the Get App button and the Home banner.
Screens: settings
Acceptance:
- [x] [unit] HideSections script generation and bridge tests (HideSectionsTests, tools/hidesections-test).
- [ ] [manual] Hidden nav leaves no gap (hideSections.js v4.3.0); a brief pre-hydration flash is possible.
Status: done

### S-020 Set region, start URL and user agent
As the user, I change the start URL, user agent and reset website data.
Screens: settings
Acceptance:
- [x] [unit] SettingsValidation (SettingsValidationTests).
- [x] [snap] Settings pages render sized to content (settings-general, settings-advanced).
Status: done

### S-021 Choose a web theme
As the user, I pick Default, Light, Synthwave, Cyberpunk or Vampire in Settings.
Screens: settings
Acceptance:
- [x] [unit] Theme CSS and attribute selectors generated (ThemeTests; docs/THEMES.md).
- [x] [manual] Cyberpunk live screenshots and fixes (yellow player edge) re-viewed on an unlocked screen.
- [x] [manual] Synthwave fill alpha re-viewed; Settings picker live switching driven (all five themes, no reload).
- [x] [manual] light-nowplaying.png refreshed.
Status: done

### S-022 See a consistent, spaced top bar
As the user, the top bar has no overlap or cramped spacing.
Screens: main-window
Acceptance:
- [x] [snap] Top bar spacing fix verified with no diff against baseline.
Status: done

### S-023 Read About info
As the user, I open About for version and build number.
Screens: about
Acceptance:
- [x] [unit] AboutInfo (AboutInfoTests).
- [x] [snap] about-* may differ after each commit (build number = commit count); re-baseline.
Status: done


## M5 Engineering and release

### S-024 Render snapshots and self-test from the command line
As the user, launch modes render every page offscreen and run an in-app self-test.
Screens: all snapshot pages
Acceptance:
- [x] [snap] scripts/snapshot.sh --baseline / --diff compare build/snapshots (0 px, deterministic).
- [x] [self] scripts/build.sh --selftest passes, including grid-lint.
- [x] [self] build.sh --open opens the built app.
Status: done

### S-025 Use shared design tokens
As the user, spacing, radius, surfaces, motion and glyph sizes come from DesignTokens.swift.
Screens: menu-bar-player
Acceptance:
- [x] [snap] Mini player title 15 pt, hit areas 32/44, scrub bar 8 render consistently.
- [x] [self] grid-lint reports no off-grid numbers.
Status: done

### S-026 Keep the mini player maintainable
As the user, MiniPlayerView is split into focused views.
Screens: menu-bar-player
Acceptance:
- [x] [snap] 0 px diff after the split; MiniPlayerView.swift is 136 lines.
Status: done

### S-027 Run the full test suite
As the user, contributors run one suite for Swift and the web scripts.
Acceptance:
- [x] [unit] Swift Testing suite (121+ tests) passes via xcodebuild test.
- [x] [unit] node tools/bridge-test and tools/hidesections-test pass.
Status: done

### S-028 Install a signed, notarized release
As the user, I install a release without a Gatekeeper warning.
Acceptance:
- [ ] [manual] Developer ID signing and notarization are set up; releases are currently ad-hoc signed (README).
Status: todo

### S-029 Manual QA pass
As the user, a person runs docs/QA.md on a release build.
Acceptance:
- [ ] [manual] Sections 1-10 and the bridge hardening checks completed (QA Build & install, §8 Settings, §9 Bridge, Hardening checks).
Status: todo


## Dropped

- Intel (x86_64) support: Apple silicon only.
- Native audio playback: audio stays in Amazon's own web player (FairPlay).
- Offline downloads: not available through the web player.

## Later

- Developer ID signing and notarization in the release workflow.
