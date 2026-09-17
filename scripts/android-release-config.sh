#!/usr/bin/env bash

# Shared Android production/release configuration for every Otya artifact.
# Workflows may intentionally vary only SELF_UPDATE:
# - direct/R2 APK: true
# - Google Play AAB: false
# Everything else must stay identical so debug/release behavior does not drift.

: "${FIREBASE_API_KEY:?FIREBASE_API_KEY is required}"

OTYA_GOOGLE_WEB_CLIENT_ID='82776565585-obr8k53b8n6djsggissv8qne81cm3u5u.apps.googleusercontent.com'
OTYA_FIREBASE_APP_ID='1:82776565585:android:085cf9b4eecb76e9535570'
OTYA_FIREBASE_MESSAGING_SENDER_ID='82776565585'
OTYA_FIREBASE_PROJECT_ID='otya-player'
OTYA_ENABLE_WATCH_TOGETHER='true'

configure_otya_release_defines() {
  local self_update="${1:-${OTYA_SELF_UPDATE:-true}}"
  case "$self_update" in
    true|false) ;;
    *)
      echo "ERROR: SELF_UPDATE must be true or false; got '$self_update'" >&2
      return 1
      ;;
  esac

  # Flutter consumes SELF_UPDATE as a Dart define while Gradle consumes the
  # exported value to include/remove REQUEST_INSTALL_PACKAGES in the merged
  # Android manifest. Keeping both sourced from one value prevents channel drift.
  export OTYA_SELF_UPDATE="$self_update"

  OTYA_RELEASE_DART_DEFINES=(
    "--dart-define=SELF_UPDATE=${self_update}"
    "--dart-define=OTYA_ENABLE_WATCH_TOGETHER=${OTYA_ENABLE_WATCH_TOGETHER}"
    "--dart-define=GOOGLE_WEB_CLIENT_ID=${OTYA_GOOGLE_WEB_CLIENT_ID}"
    "--dart-define=FIREBASE_API_KEY=${FIREBASE_API_KEY}"
    "--dart-define=FIREBASE_APP_ID=${OTYA_FIREBASE_APP_ID}"
    "--dart-define=FIREBASE_MESSAGING_SENDER_ID=${OTYA_FIREBASE_MESSAGING_SENDER_ID}"
    "--dart-define=FIREBASE_PROJECT_ID=${OTYA_FIREBASE_PROJECT_ID}"
  )
}

configure_otya_release_defines "${OTYA_SELF_UPDATE:-true}"
