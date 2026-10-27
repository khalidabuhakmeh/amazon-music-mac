# Amazon Music for Mac

<img src="docs/icon.png" alt="App icon" width="128">

An unofficial, native Apple silicon macOS app for Amazon Music.

## Why

Amazon's official desktop app is going away, and the web player lacks macOS integration (media keys, Control Center, menu bar). This app wraps the web player in a native shell and adds that integration.

## Features

- Native Apple silicon (arm64) app, macOS 26+
- Hosts music.amazon.com in a `WKWebView`; playback uses WebKit's FairPlay, so audio is delivered by Amazon's own player
- Media keys, Control Center and AirPods controls via Now Playing
- Menu bar mini player: cover, title, progress, controls, shuffle, repeat, like
- Dock menu, and a right-click menu on the menu bar item
- Track-change notifications
- Keeps playing when the window is closed
- Settings: hide podcasts, hide Audible, hide the "Get App" button, hide the Home banner, region/start URL, user-agent override, reset website data

## Requirements

- macOS 26
- Xcode 27+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build and install

```sh
./scripts/build.sh                    # Debug
CONFIG=Release ./scripts/build.sh     # Release
cp -R build/Build/Products/Release/AmazonMusic.app /Applications/
```

The app is ad-hoc signed and runs locally. If you copy it to another Mac, right-click and choose Open to get past Gatekeeper. Developer ID signing and notarization are not set up.

## First run

Launch the app and sign in to Amazon once. The session persists across launches.

## How it works

- A `WKWebView` shell loads the Amazon Music web player.
- `bridge.js` is injected into the page. It reads `navigator.mediaSession` and the media element, reports state, and sends commands (play, pause, next, previous, seek, shuffle, repeat, like).
- Messages are decoded into `PlayerState`, which feeds the integrations: Now Playing, menu bar mini player, Dock menu, notifications.
- `hideSections.js` hides page sections according to settings.
- All DOM selectors live in `bridge.js` and `hideSections.js` and are versioned, so page changes are fixed in one place.

## Project layout

```
Sources/AmazonMusic/
  App/            app entry, delegate, window coordinator
  Bridge/         message decoding, commands, WKScriptMessage handler
  Integrations/   Now Playing, Dock menu, status item, notifications, artwork cache
  Model/          PlayerState, TrackInfo
  Resources/      bridge.js, hideSections.js, assets, entitlements
  Settings/       AppSettings
  UI/             main window, mini player, settings view
  Web/            web view, popups, navigation policy
Tests/            XCTest unit tests
tools/            JS tests (bridge, hideSections), icon generator
scripts/          build.sh
docs/             investigation notes and QA checklist
project.yml       XcodeGen project definition
```

## Testing

```sh
xcodebuild test -scheme AmazonMusic -destination 'platform=macOS,arch=arm64' -derivedDataPath build
node tools/bridge-test/bridge.test.mjs
node tools/hidesections-test/hidesections.test.mjs
```

Manual checklist: [docs/QA.md](docs/QA.md).

Further notes: [media controls](docs/MEDIA_CONTROLS.md), [shuffle/repeat](docs/CONTROLS.md), [like](docs/LIKE.md), [podcasts/Audible](docs/PODCASTS.md), [initial spike](docs/SPIKE.md).

## Known limitations and risks

- It depends on Amazon's page structure and may break when the site changes.
- Use it for personal use in line with Amazon's Terms of Service. This project is not affiliated with or endorsed by Amazon.
- It does not circumvent DRM; playback goes through WebKit's own FairPlay support.
- WebKit may publish its own Now Playing entry alongside the app's. See [docs/MEDIA_CONTROLS.md](docs/MEDIA_CONTROLS.md).

## Disclaimer

Unofficial project. "Amazon Music" is a trademark of Amazon.com, Inc. or its affiliates.

## License

[MIT](LICENSE), copyright 2026 Khalid Abuhakmeh.
