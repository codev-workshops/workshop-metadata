#!/usr/bin/env bash
# Assembles the two-repo build context required by hosting-client-timesheet-app/docker/Dockerfile
# and builds the production image.
#
# The Dockerfile expects frontend/ and backend/ from the app repo PLUS docker/overrides/ from the
# hosting repo in a single context. Nothing in either repo automates this, which is why the image
# is never built in CI.
#
# Usage: ./build-image.sh [app_repo_path] [hosting_repo_path] [image_tag]
set -euo pipefail

APP_REPO="${1:-$HOME/repos/app_timesheet}"
HOSTING_REPO="${2:-$HOME/repos/hosting-client-timesheet-app}"
IMAGE_TAG="${3:-timesheet:local}"
CTX="${BUILD_CONTEXT:-/tmp/timesheet-build-context}"

for d in "$APP_REPO/frontend" "$APP_REPO/backend" "$HOSTING_REPO/docker"; do
  [ -d "$d" ] || { echo "MISSING: $d" >&2; exit 2; }
done

rm -rf "$CTX"
mkdir -p "$CTX"
cp -r "$APP_REPO/frontend" "$APP_REPO/backend" "$CTX/"
cp -r "$HOSTING_REPO/docker" "$CTX/"
rm -rf "$CTX/frontend/node_modules" "$CTX/backend/node_modules"

docker build -f "$CTX/docker/Dockerfile" -t "$IMAGE_TAG" "$CTX"
echo "built: $IMAGE_TAG"
