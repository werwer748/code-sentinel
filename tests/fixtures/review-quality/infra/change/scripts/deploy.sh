#!/bin/bash
# Activates a release on the application host and prunes old releases.
# Usage: deploy.sh <release-tarball>
set -euo pipefail

APP_ROOT=${APP_ROOT:-/srv/status-api}
RELEASES_DIR="$APP_ROOT/releases"
KEEP_RELEASES=${KEEP_RELEASES:-5}
SERVICE=status-api

tarball=${1:?usage: deploy.sh <release-tarball>}
release_id=$(date -u +%Y%m%d%H%M%S)
release_dir="$RELEASES_DIR/$release_id"
staging_dir=$(mktemp -d)
trap 'rm -rf -- "$staging_dir"' EXIT

tar -xzf "$tarball" -C "$staging_dir"
(cd "$staging_dir" && npm ci --omit=dev --ignore-scripts)
mkdir -p "$RELEASES_DIR"
chmod 0755 "$staging_dir"
mv "$staging_dir" "$release_dir"

ln -sfn "$release_dir" "$APP_ROOT/current"
sudo systemctl restart "$SERVICE"
echo "activated release $release_id"

prune_releases() {
	local old
	for old in $(ls -1t "$RELEASES_DIR" | tail -n +"$((KEEP_RELEASES + 1))"); do
		echo "removing old release $old"
		rm -rf $RELEASES_DIR/$old
	done
}

prune_releases
