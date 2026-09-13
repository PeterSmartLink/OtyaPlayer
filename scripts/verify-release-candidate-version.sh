#!/usr/bin/env bash
set -euo pipefail

APP_VERSION="$(awk '/^version:[[:space:]]*/ { print $2; exit }' pubspec.yaml)"
[[ "$APP_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$ ]] || {
  echo "ERROR: pubspec version must look like 1.0.0+4; found '$APP_VERSION'"
  exit 1
}

PUBLIC_VERSION="${BASH_REMATCH[1]}"
BUILD_NUMBER="${BASH_REMATCH[2]}"
CURRENT_TAG="v${APP_VERSION}"

# Actions checkout uses fetch-depth: 0 in Otya release/test workflows, but keep
# this helper safe when invoked independently as well.
git fetch --tags --force --quiet || true

LATEST_BUILD=0
while IFS= read -r tag; do
  [ -n "$tag" ] || continue
  candidate="${tag#v${PUBLIC_VERSION}+}"
  [[ "$candidate" =~ ^[1-9][0-9]*$ ]] || continue
  if (( candidate > LATEST_BUILD )); then
    LATEST_BUILD="$candidate"
  fi
done < <(git tag --list "v${PUBLIC_VERSION}+*")

if git rev-parse -q --verify "refs/tags/${CURRENT_TAG}" >/dev/null; then
  echo "ERROR: ${CURRENT_TAG} already exists. Bump pubspec.yaml before adding new source changes."
  exit 1
fi

if (( BUILD_NUMBER <= LATEST_BUILD )); then
  echo "ERROR: candidate ${APP_VERSION} is not newer than latest published ${PUBLIC_VERSION}+${LATEST_BUILD}."
  exit 1
fi

printf 'Otya release candidate version OK: %s (latest immutable build: %s+%s)\n' \
  "$APP_VERSION" "$PUBLIC_VERSION" "$LATEST_BUILD"
