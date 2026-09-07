# Otya system truth audit

This document records the cross-feature seams that must agree before an Otya build is considered publishable. A green isolated widget test is not sufficient if the installed Android binary, browser surface, release metadata, Cloudflare runtime and published artifact disagree.

## Video input ownership

The video surface has one pointer owner for hidden-state gestures. `VideoGestureLayer` handles tap-to-show controls, left-edge brightness, right-edge volume, edge double-tap seek, horizontal seek and hold-for-speed. No invisible full-screen tap detector may sit above it and consume the first swipe.

## First-party browser boundary

The in-app browser may execute first-party HTTPS pages only on the exact production surfaces:

- `petersmartlink.com`
- `www.petersmartlink.com`
- `space.petersmartlink.com`
- `docs.petersmartlink.com`
- `status.petersmartlink.com`

Off-domain navigation remains external. APK/archive/executable navigation is also handed to the system instead of being rendered inside the WebView. Account authentication continuity must be verified separately because an app bearer token and an HttpOnly browser cookie are different session mechanisms.

## Release authority

Direct PeterSmart Link APK builds use `https://petersmartlink.com/latest` as the canonical release authority. A response is accepted as a published update only when all of the following agree:

- `published` is explicitly `true`;
- `tag` matches `vX.Y.Z+BUILD`;
- the tag's public version equals `version`;
- the tag's build equals `versionCode`;
- the selected ABI has an official PeterSmart Link HTTPS download target.

Google Play builds do not sideload from the direct APK channel; their update delivery remains owned by Google Play. Failure, pre-release and Play-managed states must never be reported as “up to date”.

## Publication boundary

Source changes are not production deployment. Release-mode validation proves that a candidate can compile and that required Android runtime components survive release optimization. Public release truth additionally requires the matching server source to be deployed, immutable release metadata to be published, and the exact signed artifact to be inspected.
