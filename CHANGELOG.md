# Otya Changelog

This changelog describes public Otya releases. Earlier prototype version labels
are preserved in Git history and are not public Otya releases.

## [1.0.0+4] — release candidate

### Reliability and privacy

- Hardened Android audio-focus and interruption ownership so pause/resume behavior
  stays bound to the exact active player across calls, headsets, Bluetooth and
  app lifecycle changes.
- Added notification-permission recovery that can return users to Android app
  settings when notifications were previously denied.
- Redacted local media paths and app-private paths from crash diagnostics before
  reports leave the device.
- Kept the reviewed immutable MediaKit Android disposal-order fix pinned across
  the direct and overridden dependency graph.

### Together

- Enabled Watch Together in the public Otya candidate instead of hiding it behind
  an internal validation flag.
- Public Android builds now explicitly compile Together on for Nearby and
  Anywhere/Remote sessions while preserving an explicit emergency rollback build
  switch.
- Kept real-device quality gates for two-device Nearby, different-network/TURN,
  synchronization, reconnect, lifecycle, storage and data-usage behavior; public
  availability does not replace those release-acceptance checks.

### Publication readiness

- Advanced the candidate build number beyond the already-published `1.0.0+3`
  artifacts so no new binary can reuse the old Android versionCode.
- Added CI contracts that reject stale build numbers and prevent Play/privacy,
  media-service, advertising-permission and Together-public-state drift.
- Release-mode validation now builds the same Together-enabled configuration that
  public Android artifacts use, without duplicating an identical second APK build.
- Release candidates must still pass release-mode APK/privacy/size validation,
  signed APK/AAB verification and physical-device acceptance before tagging.

## [1.0.0] — 2026-09-03

### Highlights

- Offline-first local music and video libraries with background playback,
  subtitles, Picture-in-Picture, queue controls, speed controls and EQ.
- Me hub for Transfer, Files, Private, playlists, history, tools,
  personalization and storage.
- Authenticated same-Wi-Fi/hotspot Transfer with resume and integrity checks.
- Private app storage protected by device authentication and secure PIN fallback.
- Optional Otya account with recovery, 2FA, Google sign-in and user-selected
  Google Drive playlist recovery.
- Optional Next assistant that does not block local playback.
- English and Luganda localization foundations and a modern adaptive Otya icon.

### Reliability and security

- Hardened startup so network, Firebase, update and Next failures remain
  non-blocking.
- Fixed playback switching, notification metadata, video PiP state, transfer
  resume, Private collision handling, trim ranges and runtime ABI selection.
- Removed retired Online Music/Jamendo/Spotify paths from the v1 product.
- Added strict analysis, regression tests, secret scanning and signed APK/AAB
  verification to the release pipeline.
- Added Cloudflare-hosted release metadata with architecture-specific downloads
  and short-lived update aliases.

### Distribution

- Signed ARM64 and ARM32 APKs for direct public testing.
- Signed Android App Bundle for later store submission.
- Canonical download and release information at petersmartlink.com.
