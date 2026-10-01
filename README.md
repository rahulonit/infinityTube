# InfinityTube

InfinityTube is an OLED-first Flutter shell around the YouTube web experience,
with native offline downloads, playback utilities, and a strict navigation
allowlist. Android is the currently verified runtime target; iOS source support
is present but the checked-in project still needs its build configuration.

## Implemented

- Multi-layer page ad cleanup: player-response pruning, fast ad termination,
  skip-button handling, anti-adblock overlay cleanup, and cosmetic filtering.
- Pitch-black `#000000` UI and native four-tab navigation: Home, Shorts,
  Settings, and Download.
- Video and Shorts download actions injected into YouTube's own action areas.
- Download quality discovery for muxed video, video-only high resolutions, and
  M4A/WebM audio streams.
- Pause/resume with HTTP range requests, expired-stream renewal, percentage,
  byte counts, and measured transfer speed.
- Offline library with search, sorting, storage totals, playback, sharing, and
  deletion.
- Centralized persistent Settings for playback, PiP, seek time, layout,
  downloads, storage reserve, Smart Downloads, filtering, privacy, and logs.
- Smart Downloads with configurable limits, persistent queue playback, and
  persistent Continue Watching checkpoints.
- Configurable double-tap seeking, +30-second jump, fullscreen handling, and
  PiP. Android native PiP supports auto-enter, source animation, seamless
  resizing, and the active video's aspect ratio when the web API is unavailable.
- YouTube Music and YouTube Kids entry points.
- iOS background-audio mode and Android hardware-accelerated Hybrid
  Composition.

## Important limitations

- YouTube frequently changes private web markup and player responses, so DOM
  injection and stream extraction require ongoing compatibility testing.
- High-resolution YouTube streams are often video-only. InfinityTube exposes
  those honestly; it does not currently mux a separate audio stream into them.
- Audio downloads retain their source codec/container. An option labelled M4A
  is not transcoded to MP3.
- Interrupted downloads are restored as paused tasks after an app restart and
  can resume using HTTP range requests. A platform background-download service
  that continues after the operating system kills the app is not yet included.
- The Flutter Web target cannot host `webview_flutter`; a browser extension or
  separate web architecture is required for feature parity. Android TV also
  needs a dedicated D-pad/leanback pass before it should be distributed as a TV
  app.
- Google may reject account authentication inside embedded web views.
- The iOS directory currently lacks the complete Flutter iOS build
  configuration, so `flutter build ios` reports "Application not configured for
  iOS" until that platform setup is regenerated or repaired.
- Downloading or modifying playback may be restricted by YouTube's terms and by
  local law. Only download media you are authorized to save.

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Verified in this workspace with `flutter analyze`, all 43 tests, and a debug
Android APK build.
