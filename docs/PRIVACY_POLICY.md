# Otya Privacy Policy

**Effective date:** September 5, 2026

**Policy version:** 1.0

**Provider:** PeterSmart Link

This policy explains how Otya's Android app, account services, website, support
channels and optional connected features handle information.

## What stays on your device

Otya is offline-first. Core music and video playback and Smart Search do not
require an Otya account or an internet connection. The following information is
normally stored on your device:

- media file paths and metadata needed to build your library;
- playback history, seek positions, playlists, favourites and settings;
- local Smart Search history when that setting is enabled;
- Private media stored in Otya's app-private area;
- local Send/Transfer pairing and progress state; and
- pending diagnostic reports while your device is offline.

Otya does not upload your raw music or video library as part of normal playback,
local search, device registration, analytics or Google Drive recovery.

## Information Otya services process

Depending on the connected features you choose, Otya may process:

- account details such as your Otya ID, name, email address, username, linked
  sign-in provider and consent status;
- security records needed for verification, password recovery, 2FA, sessions
  and abuse prevention;
- a randomly generated Otya device ID, device model, Android version, app
  version/build, architecture and locale;
- a Firebase Cloud Messaging token for notifications;
- ratings, problem reports and any contact details or descriptions you choose
  to submit; and
- diagnostic records containing the Otya device ID, app version/build, error
  type, truncated error description, truncated stack trace and timestamp.

Otya does not sell personal information. Otya does not use your local media
library for advertising.

## Optional connected features

### Otya account

Creating an account is optional for local playback, Smart Search and nearby
Send. Account information is used to authenticate you, protect your account,
provide recovery and operate the connected features you request.

### Google Sign-In and Google Drive

Google Sign-In is optional. If you explicitly start backup, restore or backup
deletion, Otya requests the Google Drive permission needed to use the hidden
Drive app data folder. Recovery snapshots can contain playlist names, playlist
media references and related supported recovery data; they do not contain the
raw media files or Private media. Google access tokens are used for the
requested operation and are not persisted by the Android app.

### Send

Otya Send moves supported media directly between devices on the same Wi-Fi or
hotspot connection. Otya's cloud is not used as a general file relay. Pairing
uses an authenticated local connection and short-lived transfer credentials.

### Together

Together is optional. Nearby Together can connect participants over the same
Wi-Fi or hotspot and is designed to keep local playback independent of internet
availability. Connected/remote Together may use Otya services for account
identity, room membership and short-lived setup or signaling data needed to
connect participants.

The Otya Together control plane does not store the shared movie or room chat
content. Session conversation is scoped to the active Together experience rather
than a permanent social inbox. If a participant chooses a save/download action,
the resulting media copy is stored on that participant's device according to the
feature shown to them.

## Service providers

Otya uses service providers only for the connected function involved:

- **Cloudflare** for the website, authentication and application services,
  storage, security, rate limiting, diagnostics, release delivery and Together
  control-plane functions;
- **Google Firebase** for push notifications, App Check/Play Integrity,
  analytics and performance measurement when enabled by Otya's current policy;
- **Google Identity and Drive** when you choose Google Sign-In or Drive recovery;
- **Resend** for transactional and support email; and
- **Telegram** when you choose a Telegram sign-in or community interaction.

These providers process information under their own terms and privacy policies.
Otya does not include an advertising SDK in the current v1 Android build.

## Android permissions

Otya may request media-read access, network and Wi-Fi state, camera access for
QR pairing, biometric/device authentication, foreground media playback, wake
lock, notifications and vibration. Permissions are used for the feature shown
to you. Otya v1 does not request all-files access or package-installer access.
Android performs biometric matching; Otya does not receive or store your
biometric template.

## Retention and deletion

Local information remains until you remove it, clear Otya's storage or uninstall
the app. Pending crash records are capped on-device and removed after successful
upload.

You can delete an authenticated Otya cloud account from the account screen.
Account deletion is reported as complete only after the server confirms it.
Google Drive recovery data is controlled separately and can be deleted from the
Otya account screen or your Google account. Information that must be retained
for security, fraud prevention or legal compliance may be kept only for the
applicable purpose and period.

For help with access or deletion, contact **support@petersmartlink.com** or use
the privacy controls at **https://space.petersmartlink.com**.

## Security

Otya uses HTTPS for internet-facing services, protected application storage,
short-lived authentication sessions and request-integrity controls. Local Send
and Nearby Together use authenticated local-network sessions. No service can
guarantee absolute security. Please report suspected security issues through
the private process described in the repository security policy or the official
support channel.

## Children

Otya is not directed to children under 13, and PeterSmart Link does not knowingly
collect personal information from children under 13.

## Changes

Material changes will update the effective date and policy version. When a new
acceptance is required, Otya will request it through the relevant account flow.

## Contact

PeterSmart Link

Email: **support@petersmartlink.com**

Website: **https://petersmartlink.com**