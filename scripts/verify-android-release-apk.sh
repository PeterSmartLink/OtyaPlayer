#!/usr/bin/env bash
set -euo pipefail

APK="${1:?Usage: verify-android-release-apk.sh <apk> [evidence-dir]}"
EVIDENCE_DIR="${2:-build/release-contract}"
mkdir -p "$EVIDENCE_DIR"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_literal() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "ERROR: release APK is missing $label ($needle)" >&2
    return 1
  fi
}

require_regex() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -Eq -- "$pattern" "$file"; then
    echo "ERROR: release APK is missing $label (pattern: $pattern)" >&2
    return 1
  fi
}

[ -s "$APK" ] || fail "release APK missing or empty: $APK"
[ "$(stat -c%s "$APK")" -gt 5000000 ] || fail "release APK is unexpectedly small"

APKSIGNER="$(find "$ANDROID_HOME/build-tools" -type f -name apksigner -print | sort -V | tail -n 1)"
[ -x "$APKSIGNER" ] || fail "Android apksigner not found"

APKANALYZER="$(find "$ANDROID_HOME" -type f -name apkanalyzer -print | sort | tail -n 1)"
[ -x "$APKANALYZER" ] || fail "apkanalyzer not found"

"$APKSIGNER" verify --verbose --print-certs "$APK" \
  | tee "$EVIDENCE_DIR/signing.txt"

"$APKANALYZER" manifest print "$APK" > "$EVIDENCE_DIR/manifest.xml"
"$APKANALYZER" manifest permissions "$APK" > "$EVIDENCE_DIR/permissions.txt"
"$APKANALYZER" manifest application-id "$APK" > "$EVIDENCE_DIR/application-id.txt"
"$APKANALYZER" manifest version-name "$APK" > "$EVIDENCE_DIR/version-name.txt"
"$APKANALYZER" manifest version-code "$APK" > "$EVIDENCE_DIR/version-code.txt"
"$APKANALYZER" manifest debuggable "$APK" > "$EVIDENCE_DIR/debuggable.txt"
"$APKANALYZER" dex packages --defined-only "$APK" > "$EVIDENCE_DIR/dex-packages.txt"
"$APKANALYZER" files list "$APK" > "$EVIDENCE_DIR/files.txt"

APP_VERSION="$(awk '/^version:[[:space:]]*/ { print $2; exit }' pubspec.yaml)"
[ -n "$APP_VERSION" ] || fail "pubspec.yaml version missing"
EXPECTED_VERSION_NAME="${APP_VERSION%%+*}"
EXPECTED_VERSION_CODE="${APP_VERSION##*+}"

ACTUAL_APP_ID="$(tr -d '\r\n[:space:]' < "$EVIDENCE_DIR/application-id.txt")"
ACTUAL_VERSION_NAME="$(tr -d '\r\n[:space:]' < "$EVIDENCE_DIR/version-name.txt")"
ACTUAL_VERSION_CODE="$(tr -d '\r\n[:space:]' < "$EVIDENCE_DIR/version-code.txt")"
ACTUAL_DEBUGGABLE="$(tr -d '\r\n[:space:]' < "$EVIDENCE_DIR/debuggable.txt" | tr '[:upper:]' '[:lower:]')"

[ "$ACTUAL_APP_ID" = 'com.otyaplayer.app' ] || fail "wrong applicationId: $ACTUAL_APP_ID"
[ "$ACTUAL_VERSION_NAME" = "$EXPECTED_VERSION_NAME" ] || fail "versionName mismatch: apk=$ACTUAL_VERSION_NAME pubspec=$EXPECTED_VERSION_NAME"
[ "$ACTUAL_VERSION_CODE" = "$EXPECTED_VERSION_CODE" ] || fail "versionCode mismatch: apk=$ACTUAL_VERSION_CODE pubspec=$EXPECTED_VERSION_CODE"
[ "$ACTUAL_DEBUGGABLE" = 'false' ] || fail "release APK is debuggable"

# MediaSession + foreground-service contract. Android may render the enum as
# its symbolic value or its integer value in different SDK tool revisions.
require_literal "$EVIDENCE_DIR/manifest.xml" 'com.ryanheise.audioservice.AudioService' 'audio_service foreground service'
require_literal "$EVIDENCE_DIR/manifest.xml" 'com.ryanheise.audioservice.MediaButtonReceiver' 'media button receiver'
require_regex "$EVIDENCE_DIR/manifest.xml" 'android:foregroundServiceType="(mediaPlayback|2)"' 'mediaPlayback foreground service type'
require_literal "$EVIDENCE_DIR/manifest.xml" 'com.ryanheise.audioservice.NOTIFICATION_CHANNEL_ID' 'Now Playing notification channel metadata'
require_literal "$EVIDENCE_DIR/manifest.xml" 'com.otyaplayer.app.audio' 'Otya Now Playing channel id'

require_literal "$EVIDENCE_DIR/permissions.txt" 'android.permission.FOREGROUND_SERVICE' 'foreground service permission'
require_literal "$EVIDENCE_DIR/permissions.txt" 'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK' 'media playback foreground service permission'
require_literal "$EVIDENCE_DIR/permissions.txt" 'android.permission.WAKE_LOCK' 'wake-lock permission'
require_literal "$EVIDENCE_DIR/permissions.txt" 'android.permission.POST_NOTIFICATIONS' 'notification permission declaration'
require_literal "$EVIDENCE_DIR/permissions.txt" 'android.permission.NEARBY_WIFI_DEVICES' 'Nearby Wi-Fi permission for Otya Send'
require_literal "$EVIDENCE_DIR/permissions.txt" 'android.permission.CHANGE_WIFI_STATE' 'Wi-Fi state permission for Otya Send'

# R8 must retain the native Android entry points that are loaded by class name.
require_literal "$EVIDENCE_DIR/dex-packages.txt" 'com.ryanheise.audioservice.AudioService' 'AudioService class after R8'
require_literal "$EVIDENCE_DIR/dex-packages.txt" 'com.ryanheise.audioservice.MediaButtonReceiver' 'MediaButtonReceiver class after R8'
require_literal "$EVIDENCE_DIR/dex-packages.txt" 'com.otyaplayer.app.MainActivity' 'Otya MainActivity after R8'
require_literal "$EVIDENCE_DIR/dex-packages.txt" 'com.petersmartlink.otya_transfer_android.OtyaTransferAndroidPlugin' 'Otya offline-transfer plugin after R8'

# media_kit must ship its ARM64 native playback engine in the publication APK.
require_regex "$EVIDENCE_DIR/files.txt" '/lib/arm64-v8a/.*(mpv|media_kit).*\.so$' 'ARM64 media playback native library'

sha256sum "$APK" | tee "$EVIDENCE_DIR/sha256.txt"

echo 'Release APK contract verified:'
echo "  applicationId=$ACTUAL_APP_ID"
echo "  version=$ACTUAL_VERSION_NAME+$ACTUAL_VERSION_CODE"
echo "  debuggable=$ACTUAL_DEBUGGABLE"
