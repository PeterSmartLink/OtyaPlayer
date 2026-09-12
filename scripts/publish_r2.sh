#!/usr/bin/env bash
# Publishes signed Otya APKs to Cloudflare R2, then starts the release workflow.

set -euo pipefail

RAW_TAG="${RELEASE_TAG:-${CI_COMMIT_TAG:-${GITHUB_REF_NAME:-}}}"
[ -n "$RAW_TAG" ] || { echo "ERROR: No release tag found"; exit 1; }
[[ "$RAW_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+[1-9][0-9]*$ ]] || {
  echo "ERROR: Invalid release tag '$RAW_TAG' (expected v<version>+<build>, for example v1.0.0+2)"
  exit 1
}
TAG_VERSION="${RAW_TAG#v}"
VERSION="${TAG_VERSION%%+*}"
TAG_BUILD="${TAG_VERSION##*+}"

PUBSPEC_VERSION=$(awk '/^version:/ {print $2; exit}' pubspec.yaml)
[ -n "$PUBSPEC_VERSION" ] || { echo "ERROR: pubspec.yaml has no version"; exit 1; }
PUBSPEC_NAME="${PUBSPEC_VERSION%%+*}"
PUBSPEC_CODE="${PUBSPEC_VERSION##*+}"
[ "$PUBSPEC_NAME" = "$VERSION" ] || {
  echo "ERROR: release tag $RAW_TAG does not match pubspec version $PUBSPEC_NAME"
  exit 1
}
[[ "$PUBSPEC_CODE" =~ ^[1-9][0-9]*$ ]] || {
  echo "ERROR: pubspec Android build number must be a positive integer"
  exit 1
}
[ "$TAG_BUILD" = "$PUBSPEC_CODE" ] || {
  echo "ERROR: release tag build $TAG_BUILD does not match pubspec build $PUBSPEC_CODE"
  exit 1
}
VERSION_CODE="$PUBSPEC_CODE"

WORKER_URL="${WORKER_URL:-https://petersmartlink.com}"
WORKER_URL="${WORKER_URL%/}"

: "${AWS_ACCESS_KEY_ID:?R2 access key is required}"
: "${AWS_SECRET_ACCESS_KEY:?R2 secret access key is required}"
: "${R2_ENDPOINT:?R2_ENDPOINT is required}"
: "${R2_BUCKET:?R2_BUCKET is required}"
: "${CF_ACCOUNT_ID:?CF_ACCOUNT_ID is required}"
: "${CF_API_TOKEN:?CF_API_TOKEN is required}"
[[ "$R2_ENDPOINT" == https://* ]] || {
  echo "ERROR: R2_ENDPOINT must use HTTPS"
  exit 1
}
[[ "$WORKER_URL" == https://* ]] || {
  echo "ERROR: WORKER_URL must use HTTPS"
  exit 1
}

ARM64_APK="${ARM64_APK:-build/app/outputs/flutter-apk/app-arm64-v8a-release.apk}"
ARM32_APK="${ARM32_APK:-build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk}"
MAX_APK_BYTES=40000000
WARN_APK_BYTES=35000000
for APK in "$ARM64_APK" "$ARM32_APK"; do
  test -f "$APK" || { echo "ERROR: APK not found: $APK"; exit 1; }
  SIZE=$(stat -c%s "$APK" 2>/dev/null || stat -f%z "$APK")
  [ "$SIZE" -ge 5000000 ] || { echo "ERROR: $APK looks too small ($SIZE bytes)"; exit 1; }
  [ "$SIZE" -le "$MAX_APK_BYTES" ] || {
    echo "ERROR: $APK is $SIZE bytes; Otya split APKs must stay at or below $MAX_APK_BYTES bytes"
    exit 1
  }
  if [ "$SIZE" -gt "$WARN_APK_BYTES" ]; then
    echo "WARNING: $APK is $SIZE bytes and has crossed Otya's $WARN_APK_BYTES-byte size warning line"
  fi
done

CHANGELOG_FILE=$(mktemp)
trap 'rm -f "$CHANGELOG_FILE"' EXIT
awk '/^## \[/{found++} found==1{print} found==2{exit}' CHANGELOG.md \
  | tail -n +2 | head -40 | tr '\n' ' ' \
  | sed 's/  */ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' > "$CHANGELOG_FILE"
CHANGELOG=$(cat "$CHANGELOG_FILE")
[ -n "$CHANGELOG" ] || CHANGELOG="Fixes and improvements"

MIN_SDK=$(grep 'minSdk' android/app/build.gradle | grep -v '//' | head -1 | grep -oP '\d+' || echo 24)
TARGET_SDK=$(grep 'targetSdk' android/app/build.gradle | grep -v '//' | head -1 | grep -oP '\d+' || echo 36)

upload_and_verify() {
  local SRC="$1" DEST_KEY="$2" CACHE_CONTROL="$3"
  local LOCAL_SIZE REMOTE_SIZE REMOTE_TYPE REMOTE_CACHE
  LOCAL_SIZE=$(stat -c%s "$SRC" 2>/dev/null || stat -f%z "$SRC")
  echo "Uploading $DEST_KEY ($LOCAL_SIZE bytes)..."
  aws s3 cp "$SRC" "s3://${R2_BUCKET}/${DEST_KEY}" \
    --endpoint-url "$R2_ENDPOINT" \
    --content-type application/vnd.android.package-archive \
    --cache-control "$CACHE_CONTROL"

  REMOTE_SIZE=$(aws s3api head-object \
    --bucket "$R2_BUCKET" \
    --key "$DEST_KEY" \
    --endpoint-url "$R2_ENDPOINT" \
    --query ContentLength \
    --output text)
  REMOTE_TYPE=$(aws s3api head-object \
    --bucket "$R2_BUCKET" \
    --key "$DEST_KEY" \
    --endpoint-url "$R2_ENDPOINT" \
    --query ContentType \
    --output text)
  REMOTE_CACHE=$(aws s3api head-object \
    --bucket "$R2_BUCKET" \
    --key "$DEST_KEY" \
    --endpoint-url "$R2_ENDPOINT" \
    --query CacheControl \
    --output text)

  [ "$REMOTE_SIZE" = "$LOCAL_SIZE" ] || {
    echo "ERROR: Upload size mismatch for $DEST_KEY (local=$LOCAL_SIZE remote=$REMOTE_SIZE)"
    return 1
  }
  [ "$REMOTE_TYPE" = "application/vnd.android.package-archive" ] || {
    echo "ERROR: Upload content type mismatch for $DEST_KEY ($REMOTE_TYPE)"
    return 1
  }
  [ "$REMOTE_CACHE" = "$CACHE_CONTROL" ] || {
    echo "ERROR: Upload cache-control mismatch for $DEST_KEY ($REMOTE_CACHE)"
    return 1
  }
  echo "Verified $DEST_KEY: size, APK MIME and cache policy are correct"
}

ARM64_VERSIONED="releases/${RAW_TAG}/Otya-arm64.apk"
ARM32_VERSIONED="releases/${RAW_TAG}/Otya-arm32.apk"

upload_and_verify "$ARM64_APK" "$ARM64_VERSIONED" "public, max-age=31536000, immutable"
upload_and_verify "$ARM32_APK" "$ARM32_VERSIONED" "public, max-age=31536000, immutable"

export RAW_TAG VERSION VERSION_CODE MIN_SDK TARGET_SDK WORKER_URL CHANGELOG_FILE ARM64_VERSIONED ARM32_VERSIONED CF_ACCOUNT_ID CF_API_TOKEN
WORKFLOW_ID=$(python3 - <<'PYEOF'
import json, os, sys, urllib.request, urllib.error
with open(os.environ['CHANGELOG_FILE']) as f:
    changelog = f.read().strip() or 'Fixes and improvements'
payload = {
    'tag': os.environ['RAW_TAG'],
    'version': os.environ['VERSION'],
    'versionCode': int(os.environ['VERSION_CODE']),
    'arm64Key': os.environ['ARM64_VERSIONED'],
    'arm32Key': os.environ['ARM32_VERSIONED'],
    'changelog': changelog,
    'minSdk': int(os.environ['MIN_SDK']),
    'targetSdk': int(os.environ['TARGET_SDK']),
    'workerUrl': os.environ['WORKER_URL'],
}
workflow_url = (
    'https://api.cloudflare.com/client/v4/accounts/'
    + os.environ['CF_ACCOUNT_ID']
    + '/workflows/otya-release/instances'
)
req = urllib.request.Request(workflow_url, data=json.dumps({
    'params': json.dumps(payload, separators=(',', ':')),
}).encode(), method='POST', headers={
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + os.environ['CF_API_TOKEN'],
})
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = json.load(resp)
except urllib.error.HTTPError as e:
    sys.stderr.write(f'ERROR: release workflow start failed HTTP {e.code}\n')
    sys.exit(1)
except Exception as e:
    sys.stderr.write(f'ERROR: release workflow start failed: {type(e).__name__}\n')
    sys.exit(1)
if data.get('success') is not True:
    sys.stderr.write('ERROR: Cloudflare rejected the release workflow request\n')
    sys.exit(1)
instance_id = (data.get('result') or {}).get('id')
if not instance_id:
    sys.stderr.write('ERROR: release workflow returned no instanceId\n')
    sys.exit(1)
print(instance_id)
PYEOF
)

echo "Release workflow: $WORKFLOW_ID"
export WORKFLOW_ID

python3 - <<'PYEOF'
import json, os, sys, time, urllib.parse, urllib.request
base = (
    'https://api.cloudflare.com/client/v4/accounts/'
    + os.environ['CF_ACCOUNT_ID']
    + '/workflows/otya-release/instances/'
    + urllib.parse.quote(os.environ['WORKFLOW_ID'], safe='')
    + '?simple=false&order=asc'
)
headers = {'Authorization': 'Bearer ' + os.environ['CF_API_TOKEN']}
terminal_fail = {'errored', 'terminated', 'unknown'}
poll_interval = 5
try:
    timeout_seconds = max(30, int(os.environ.get('WORKFLOW_TIMEOUT_SECONDS', '900')))
except ValueError:
    sys.stderr.write('ERROR: WORKFLOW_TIMEOUT_SECONDS must be an integer\n')
    sys.exit(1)
attempts = max(1, (timeout_seconds + poll_interval - 1) // poll_interval)
for attempt in range(attempts):
    req = urllib.request.Request(base, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.load(resp)
    except Exception as e:
        if attempt >= attempts - 1:
            sys.stderr.write(f'ERROR: could not read workflow status: {type(e).__name__}\n')
            sys.exit(1)
        time.sleep(5)
        continue
    if data.get('success') is not True:
        if attempt >= attempts - 1:
            sys.stderr.write('ERROR: Cloudflare rejected the workflow status request\n')
            sys.exit(1)
        time.sleep(5)
        continue
    workflow = data.get('result') or {}
    status = workflow.get('status')
    print(f'Release status: {status}')
    if status == 'complete':
        output = workflow.get('output')
        if isinstance(output, str):
            try:
                output = json.loads(output)
            except json.JSONDecodeError:
                pass
        if isinstance(output, dict) and output.get('ok') is False:
            sys.stderr.write('ERROR: release finished with an error\n')
            sys.exit(1)
        sys.exit(0)
    if status in terminal_fail:
        error = workflow.get('error') or {}
        message = error.get('message')
        if not message:
            for failed_step in reversed(workflow.get('steps') or []):
                for attempt_info in reversed(failed_step.get('attempts') or []):
                    step_error = attempt_info.get('error') or {}
                    if step_error.get('message'):
                        message = f"{failed_step.get('name', 'workflow step')}: {step_error['message']}"
                        break
                if message:
                    break
        sys.stderr.write('ERROR: release failed: ' + str(message or status) + '\n')
        sys.exit(1)
    time.sleep(poll_interval)
sys.stderr.write(
    f"ERROR: release workflow {os.environ['WORKFLOW_ID']} did not finish within {timeout_seconds} seconds\n"
)
sys.exit(1)
PYEOF

if ! upload_and_verify "$ARM64_APK" "Otya-arm64.apk" "public, max-age=300, must-revalidate"; then
  echo "WARNING: Otya arm64 shortcut was not refreshed"
fi
if ! upload_and_verify "$ARM32_APK" "Otya-arm32.apk" "public, max-age=300, must-revalidate"; then
  echo "WARNING: Otya arm32 shortcut was not refreshed"
fi

echo "====================================================="
echo " Otya ${RAW_TAG} is ready"
echo " Download: ${WORKER_URL}/download/otya-player"
echo "====================================================="
