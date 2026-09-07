#!/usr/bin/env bash

# Shared Android production/release configuration for every Otya artifact.
# Workflows may intentionally override only OTYA_SELF_UPDATE:
# - direct/R2 APK: true
# - Google Play AAB: false
# Everything else must stay identical so debug/release behavior does not drift.

: "${FIREBASE_API_KEY:?FIREBASE_API_KEY is required}"

OTYA_SELF_UPDATE="${OTYA_SELF_UPDATE:-true}"
case "$OTYA_SELF_UPDATE" in
  true|false) ;;
  *)
    echo "ERROR: OTYA_SELF_UPDATE must be true or false; got '$OTYA_SELF_UPDATE'" >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

readonly OTYA_GOOGLE_WEB_CLIENT_ID='82776565585-obr8k53b8n6djsggissv8qne81cm3u5u.apps.googleusercontent.com'
readonly OTYA_FIREBASE_APP_ID='1:82776565585:android:085cf9b4eecb76e9535570'
readonly OTYA_FIREBASE_MESSAGING_SENDER_ID='82776565585'
readonly OTYA_FIREBASE_PROJECT_ID='otya-player'

OTYA_RELEASE_DART_DEFINES=(
  "--dart-define=SELF_UPDATE=${OTYA_SELF_UPDATE}"
  "--dart-define=GOOGLE_WEB_CLIENT_ID=${OTYA_GOOGLE_WEB_CLIENT_ID}"
  "--dart-define=FIREBASE_API_KEY=${FIREBASE_API_KEY}"
  "--dart-define=FIREBASE_APP_ID=${OTYA_FIREBASE_APP_ID}"
  "--dart-define=FIREBASE_MESSAGING_SENDER_ID=${OTYA_FIREBASE_MESSAGING_SENDER_ID}"
  "--dart-define=FIREBASE_PROJECT_ID=${OTYA_FIREBASE_PROJECT_ID}"
)
