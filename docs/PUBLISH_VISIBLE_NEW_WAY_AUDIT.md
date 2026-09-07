# Otya publish-visible New Way audit

This branch exists to close the gap between code that had been developed and the product actually visible in installable/public builds.

## Confirmed root causes

- The public `v1.0.0` release source is older than current `main`, so it cannot contain New Way behavior.
- The canonical cyan/blue WebP is valid, but the PNG previously used by the Flutter logo and the Android launcher foreground is malformed. Runtime fallback therefore hid the intended identity.
- Legacy density/Play Store icon copies still carry the older purple/blue music-note identity.
- Offline local-hotspot Send work existed in preserved history but had not been integrated into the active New Way tree.
- Green source/tests alone did not prove that visible image binaries decoded correctly.

## Fixes in this branch

- Use `assets/branding/otya_app_icon.webp` as the single canonical runtime identity.
- Generate the Android launcher resource from that exact WebP at build time.
- Stop the active launcher/Flutter UI from referencing the malformed PNG copies.
- Decode the canonical image in Flutter tests so malformed brand binaries fail CI.
- Restore the small first-party `otya_transfer_android` plugin.
- Restore permission-scoped local-only hotspot support.
- Expose an `Offline network` action inside the existing Send surface; no new main-navigation tab.
- Preserve Video · Music · Me as the primary one-app navigation.

## Release rule

Do not repoint or rewrite the historical `v1.0.0` tag. After this branch is proven and merged, produce the next immutable release tag from the exact validated `main` commit and build both the signed direct-install APK and Play AAB from that commit.
