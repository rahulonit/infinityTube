# InfinityTube

InfinityTube is an OLED-first Flutter shell around the YouTube web experience,
with native offline downloads, playback utilities, and a strict navigation
allowlist. Android and iOS are the current supported runtime targets.

## Implemented

- Multi-layer page ad cleanup: player-response pruning, fast ad termination,
  skip-button handling, anti-adblock overlay cleanup, and cosmetic filtering.
- Pitch-black `#000000` UI and native four-tab navigation: Home, Shorts, You,
  and Download.
- Video and Shorts download actions injected into YouTube's own action areas.
- Download quality discovery for muxed video, video-only high resolutions, and
  M4A/WebM audio streams.
- Pause/resume with HTTP range requests, expired-stream renewal, percentage,
  byte counts, and measured transfer speed.
- Offline library with search, sorting, storage totals, playback, sharing, and
  deletion.
- Smart Downloads with configurable limits, queue playback, and persistent
  Continue Watching checkpoints.
- Double-tap 10-second seeking, +30-second jump, fullscreen handling, and PiP.
  Android uses native activity PiP when the web API is unavailable.
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
- Active downloads are resumable while the app process remains alive, but a
  platform background-download service and restart-persistent task database are
  not yet included.
- The Flutter Web target cannot host `webview_flutter`; a browser extension or
  separate web architecture is required for feature parity. Android TV also
  needs a dedicated D-pad/leanback pass before it should be distributed as a TV
  app.
- Google may reject account authentication inside embedded web views.
- Downloading or modifying playback may be restricted by YouTube's terms and by
  local law. Only download media you are authorized to save.

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Verified in this workspace with `flutter analyze`, all 37 tests, and a debug
Android APK build.
