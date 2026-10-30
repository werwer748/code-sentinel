#!/bin/bash
# Activates a release on the application host.
# Usage: deploy.sh <release-tarball>
set -euo pipefail

APP_ROOT=${APP_ROOT:-/srv/status-api}
RELEASES_DIR="$APP_ROOT/releases"
SERVICE=status-api

tarball=${1:?usage: deploy.sh <release-tarball>}
release_id=$(date -u +%Y%m%d%H%M%S)
release_dir="$RELEASES_DIR/$release_id"

mkdir -p "$release_dir"
tar -xzf "$tarball" -C "$release_dir"
(cd "$release_dir" && npm ci --omit=dev --ignore-scripts)

ln -sfn "$release_dir" "$APP_ROOT/current"
sudo systemctl restart "$SERVICE"
echo "activated release $release_id"
