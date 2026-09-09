# OTYA next-release feature-completion gate

OTYA must be functionally complete in source before the exact release artifact enters physical-device acceptance. A file, route, backend flag, old implementation, or hidden screen does **not** count as complete unless its intended user-facing surface is reachable, its runtime owner is wired, and the behavior is covered by release evidence.

This gate is about **intended current OTYA capabilities**. Retired, unsafe, duplicate, placeholder, or deliberately policy-disabled functionality must not be revived merely to make a feature count look larger.

## Release rule

Physical-device acceptance starts only after every applicable required row below is source-complete and the final candidate passes Security, Flutter analysis/tests, release-mode Android verification, manifest/privacy checks, and the size budget. CI success is not physical-device acceptance and does not authorize publication.

## Required app surfaces

| Surface | Required functionality | Source status |
| --- | --- | --- |
| Core shell | one coherent app; permanent Video / Music / Me navigation; no duplicate top-level Transfer, Together, Chat, Friends or AI mini-app | complete |
| Video library | local scan, folders, thumbnails, recent/resume, search/refresh, queue handoff | complete |
| Video player | playback, resume, seek, prev/next, speed, aspect/orientation, control lock, PiP, audio tracks, embedded subtitles, brightness/volume gestures, double-tap seek, 2x hold, share/details, trim, extract audio | complete |
| Music library | songs, albums, artists, folders, playlists, local-first search/shuffle | complete |
| Music player | queue, prev/next, seek, resume, favorite, shuffle, repeat, speed memory, background/notification controls, lyrics, EQ, sleep timer, Drive Mode, share/details, contextual Private/Transfer | complete |
| Android media integration | MediaSession ownership, Now Playing notification, lock-screen/headset controls, artwork/metadata fallback, background audio and video foreground/background policy | source complete; physical-device acceptance required |
| Downloads | Download/Downloads media view with All/Music/Video filters; files remain part of normal Video/Music library | complete |
| Me hub | Transfer, Files, Private, Converter, Playlists, History, Tools, Appearance/Personalize, Storage, account/support entry points | complete |
| Transfer | authenticated local sender/receiver, streaming, integrity, collision-safe receive, safe resume, cancellation/retry/progress | complete |
| Private | app-private storage, device auth, Private PIN, secure PIN hashing, persistent retry throttle, lock lifecycle, safe restore/delete | complete |
| Converter | local video-to-audio extraction | complete for current scope |
| Tools | EQ, video trim and existing local media utilities | complete |
| Storage | storage report, cache clear, read-only Duplicate Finder | complete |
| Appearance / Personalize | light/dark/AMOLED, OTYA themes/wallpaper/seasonal artwork | complete |
| App Lock | persisted setting, root app gate, device authentication, background relock | complete |
| Local search | offline-first media/folder/playlist/help discovery without remote catalog requests while typing | complete |
| Account | email registration/login, Google sign-in, verification/recovery, consent, 2FA/recovery code, profile/session and sign-out/recovery behavior | complete in source; production/physical acceptance required |
| Backup | user-selected supported Google Drive playlist backup/restore only; no claim of full media cloud sync | complete for current scope |
| Notifications | contextual permission, Now Playing/local task notifications, FCM registration, foreground/background push, safe route allow-list and category/channel separation | source complete; physical-device acceptance required |
| Updates | compact notification copy; full release notes stay in What's New/update/download surfaces; direct APK self-update remains separate from Play AAB update path | complete in source |
| What’s New / usage/history | release changes, playback history/recent activity and usage statistics routes | complete |
| Offline-first startup | UI/local library/playback are not blocked by Cloudflare, Firebase, auth, Next, Resend or update service | complete by architecture/tests |

## Together — OTYA New Way

Together is an intended next-release capability, but it is not allowed to become public merely because the source exists.

| Capability | Source status | Release evidence still required |
| --- | --- | --- |
| Nearby Together | implemented | two-device offline/local-network acceptance |
| Anywhere/Remote Together | WebRTC peer/runtime/media bridge/ICE/control-plane implemented | different-network direct + TURN-relayed acceptance |
| One host + one guest | implemented | real-device session acceptance |
| Play/pause/seek synchronization | implemented | drift, reconnect and interruption acceptance |
| Session chat, Moment messages and small reactions | implemented | lifecycle/reconnect acceptance |
| After Watch lifecycle | implemented | real-device end/leave/rejoin acceptance |
| Stream-only / optional save behavior | implemented in current runtime policy | storage/data-usage acceptance |
| Local playback isolation | designed so transport failure does not own the local player | failure/recovery acceptance |
| Size/privacy gate | CI builds a Together-enabled ARM64 release candidate | enabled candidate must remain <= 40,000,000 bytes and pass manifest/privacy verification |

`OTYA_ENABLE_WATCH_TOGETHER` remains false by default for public artifacts until the real-device/cross-network gates above pass. The release-mode workflow deliberately builds a second Together-enabled candidate so hidden transport code cannot bypass Android size/privacy verification.

## Next / AI product boundary

Next remains an OTYA system/web/backend capability and product-support service. It is **not** a duplicate public Android Player destination. The Android Player stays media-first; legacy `/ai` and `/support` app routes intentionally converge on the appropriate About/help surface rather than resurrecting an in-app AI mini-app.

Therefore, “none left behind” does not mean restoring the retired Android Next card/chat route. It means the backend/web Next service, product knowledge, account boundaries, failure behavior and support handoff remain healthy without blocking local playback.

## Intentionally not part of this release

These must stay retired or unavailable unless a separate product decision changes them:

- Online Music / Jamendo remote catalog
- a duplicate consumer AI/Next mini-app inside OTYA Player
- a public Admin button or separate Admin identity flow
- unconsented marketing push
- direct release-pipeline bypasses
- placeholder/Coming Soon controls presented as working features
- unsupported claims of full media cloud synchronization

## Final pre-device gate

1. The feature-surface regression contracts pass so required routes/actions cannot disappear silently.
2. Security and backend validation are green on the final source-complete commits.
3. `flutter analyze` and all unit/widget tests are green on the exact app head.
4. Normal and Together-enabled ARM64 release-mode candidates build successfully.
5. Both candidates pass Android manifest/privacy verification and the hard 40 MB size ceiling.
6. No tracked service-account, signing key, private key, provider token, or other private credential exists in source.
7. Remote-config flags and backend-advertised capabilities match actual supported product surfaces.

## Physical/pre-publication quality checks

- clean install and upgrade on physical Android devices
- launcher/splash and OTYA notification branding on real launcher/system skins
- audio/video playback, seeking, queues, background audio, lock-screen controls, headset/Bluetooth/call interruptions and PiP
- storage permissions, media scan, thumbnails and large-library behavior
- Private, App Lock, Transfer and local tools
- Account, Google sign-in, OTP/recovery/2FA, Drive backup where user-selected, FCM and App Check
- compact update notification in foreground/background/killed states, dedupe and tap/open routing
- Together Nearby on two devices and Anywhere on different networks, including TURN relay, reconnect, drift, lifecycle and data/storage behavior
- text scaling, accessibility, small/large screens, tablets/foldables, landscape, edge-to-edge and Android system gestures
- memory, battery and startup/playback performance in profile/release mode
- website/account/Space/Admin/support/Next production smoke tests
- signed APK and Play AAB behavior

Do not tag or publish the next public release until the applicable acceptance evidence passes on the exact release candidate.
