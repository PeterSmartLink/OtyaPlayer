<div align="center">

<img src="assets/branding/otya_app_icon.webp" alt="Otya" width="112" height="112" />

# Otya

**Private. Powerful. Offline-first media.**

Otya by PeterSmart Link combines local video and music playback, nearby Send, Private media, practical media tools and optional connected Together/account services without making core playback depend on the cloud.

[Otya](https://petersmartlink.com) · [Documents](https://petersmartlink.com/docs) · [Download](https://petersmartlink.com/download/otya-player) · [Security](SECURITY.md)

</div>

---

## Product surfaces

| Experience | Highlights |
|---|---|
| **Video** | Local video library, folders, playback, subtitles, PiP, gestures, aspect/orientation, queue and trim/extract |
| **Music** | Local songs, albums, artists, folders, playlists, search and background playback |
| **Me** | Send, Files, Private, playlists, history, tools, personalization, storage, account and settings |
| **Audio Player** | Queue, shuffle/repeat, speed, EQ, lyrics, sleep timer, background playback and media controls |
| **Send** | Authenticated same-Wi-Fi/hotspot media transfer without a cloud relay |
| **Private** | App-private media protection with device authentication/biometrics and secure PIN fallback |
| **Together** | Optional invited shared-watch sessions with host-controlled playback, temporary conversation, Moments and reactions |
| **Account** | Otya-owned authentication, recovery, 2FA and optional Google sign-in |

Consumer AI is not part of the Android product surface. Administrative AI remains a server-side owner tool and is not required for local playback.

## Music scope

Otya Music is local-first. The built-in Online Music/Jamendo provider integration has been retired because the available catalog did not meet the product's music-coverage needs.

- Search local songs, videos, albums, artists, folders and playlists on the device.
- Local search must not contact a music provider merely because the user is typing.
- Jamendo catalog, OAuth, status and download-proxy routes are not part of the current product.
- Spotify provider plumbing is not bundled as a dormant fallback.
- Removed music-provider behavior cannot be re-enabled through stale remote configuration.
- A future provider is outside the current v1 scope and requires a separate reviewed product, security and privacy decision.

## Privacy and security principles

- Core local playback must not depend on Cloudflare, Firebase, AI or any permanently available backend.
- Production secrets must never be committed or bundled into Flutter.
- The shared Otya account provides identity across Otya surfaces; third-party service connections remain explicit and separately revocable.
- Google Drive recovery is explicit and user-initiated.
- Recovery data must not upload a user's raw media library or Private media.
- Production releases must be signed and fail closed when signing credentials are missing.
- Internet-facing Otya services use HTTPS. Cleartext HTTP is limited to authenticated same-LAN Send/Together links on private/local addresses.
- Send accepts supported media only, refuses redirects, verifies the Otya sender marker, checks MIME and declared size, and rejects oversized/unknown-length streams.
- Security reports use the private process documented in [SECURITY.md](SECURITY.md).

## Release validation

A public Otya release is valid only when its exact immutable build tag and current `main` commit agree, strict Flutter analysis and tests pass, publication-equivalent Android release binaries are verified, signing is proven and the public download metadata points to those exact artifacts.

Official public surfaces:

- Otya: **https://petersmartlink.com**
- Documents: **https://petersmartlink.com/docs**
- Download: **https://petersmartlink.com/download/otya-player**

Do not publish source archives, internal deployment instructions, backend credentials, signing material, private endpoints or infrastructure inventories as customer documentation.

---

<div align="center">

**Otya · PeterSmart Link**

</div>
