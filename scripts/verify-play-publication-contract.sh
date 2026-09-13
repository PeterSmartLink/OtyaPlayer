#!/usr/bin/env bash
set -euo pipefail

MANIFEST='android/app/src/main/AndroidManifest.xml'
GRADLE='android/app/build.gradle'
PRIVACY='docs/PRIVACY_POLICY.md'
TOGETHER='lib/features/together/application/together_release_gate.dart'
RELEASE_CONFIG='scripts/android-release-config.sh'
PLAY_WORKFLOW='.github/workflows/play-closed-test.yml'

for file in "$MANIFEST" "$GRADLE" "$PRIVACY" "$TOGETHER" "$RELEASE_CONFIG" "$PLAY_WORKFLOW"; do
  test -s "$file" || { echo "ERROR: required publication contract file is missing: $file"; exit 1; }
done

grep -Eq 'targetSdk[[:space:]]*=[[:space:]]*36' "$GRADLE" || {
  echo 'ERROR: Otya public Android targetSdk must remain API 36 for this release.'
  exit 1
}

grep -Fq 'android.permission.READ_MEDIA_AUDIO' "$MANIFEST" || {
  echo 'ERROR: local audio-library permission disappeared from the manifest.'
  exit 1
}
grep -Fq 'android.permission.READ_MEDIA_VIDEO' "$MANIFEST" || {
  echo 'ERROR: local video-library permission disappeared from the manifest.'
  exit 1
}
grep -Fq 'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK' "$MANIFEST" || {
  echo 'ERROR: media-playback foreground-service permission is missing.'
  exit 1
}
grep -Fq 'android:foregroundServiceType="mediaPlayback"' "$MANIFEST" || {
  echo 'ERROR: AudioService must remain declared as mediaPlayback.'
  exit 1
}

# Otya v1 has no advertising SDK/advertising identity use and must not request
# package installation authority for the direct-update channel.
grep -A2 -F 'com.google.android.gms.permission.AD_ID' "$MANIFEST" | grep -Fq 'tools:node="remove"' || {
  echo 'ERROR: AD_ID must stay explicitly removed from the merged manifest.'
  exit 1
}
if grep -Fq 'android.permission.REQUEST_INSTALL_PACKAGES' "$MANIFEST"; then
  echo 'ERROR: Otya public v1 must not request REQUEST_INSTALL_PACKAGES.'
  exit 1
fi

# The WebRTC dependency must not silently expand Otya into a microphone app.
grep -A2 -F 'android.permission.RECORD_AUDIO' "$MANIFEST" | grep -Fq 'tools:node="remove"' || {
  echo 'ERROR: RECORD_AUDIO must stay removed from the merged manifest.'
  exit 1
}

grep -Fq 'You can delete an authenticated Otya cloud account from the account screen.' "$PRIVACY" || {
  echo 'ERROR: privacy policy no longer documents in-app account deletion.'
  exit 1
}
grep -Fq 'support@petersmartlink.com' "$PRIVACY" || {
  echo 'ERROR: privacy policy must retain the public support contact.'
  exit 1
}
grep -Fq 'Otya does not include an advertising SDK' "$PRIVACY" || {
  echo 'ERROR: privacy policy advertising statement is missing.'
  exit 1
}

grep -Fq "'OTYA_ENABLE_WATCH_TOGETHER'" "$TOGETHER" || {
  echo 'ERROR: Together release gate is missing.'
  exit 1
}
grep -Fq 'defaultValue: true' "$TOGETHER" || {
  echo 'ERROR: Watch Together must remain enabled by default in public builds.'
  exit 1
}
grep -Fq "OTYA_ENABLE_WATCH_TOGETHER='true'" "$RELEASE_CONFIG" || {
  echo 'ERROR: production Android release configuration must explicitly enable Watch Together.'
  exit 1
}
grep -Fq 'OTYA_ENABLE_WATCH_TOGETHER=${OTYA_ENABLE_WATCH_TOGETHER}' "$RELEASE_CONFIG" || {
  echo 'ERROR: production Android release defines are not carrying the Watch Together flag.'
  exit 1
}

grep -Fq "OTYA_SELF_UPDATE: 'false'" "$PLAY_WORKFLOW" || {
  echo 'ERROR: Play builds must not use the direct APK self-update channel.'
  exit 1
}

printf '%s\n' 'Otya Play/publication contract OK.'
