#!/usr/bin/env bash
# End-to-end test of the auto-updater WITHOUT publishing anything to GitHub.
#
# Serves a crafted GitHub-releases response + a sshCM.zip asset from a local
# http server, points the app at it via the SSHCM_RELEASES_API env var, and
# launches sshCM so you can drive "Check for Updates…" through the real UI:
# download → parse → verify → (install | unsigned-opt-in prompt).
#
# Usage:
#   scripts/test-updater-e2e.sh [signed|adhoc] [/path/to/Source.app]
#
#   signed  (default) serve the app as-is. Use a Developer-ID-signed build
#           (dist/sshCM.app from build-release.sh) to see the happy path install.
#   adhoc   re-sign the served app ad-hoc, so signature pinning fails and the
#           "Signature verification failed — Install Anyway" prompt appears.
#
# The served release is version v9.9.9 so it always counts as "newer".
# Ctrl-C to stop the server and clean up.

set -euo pipefail

MODE="${1:-signed}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_APP="$REPO_ROOT/.build/DerivedData/Build/Products/Debug/sshCM.app"
SOURCE_APP="${2:-$DEFAULT_APP}"
PORT="${SSHCM_E2E_PORT:-8787}"
WORK="$(mktemp -d /tmp/sshcm-e2e.XXXXXX)"

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "ERROR: source app not found at: $SOURCE_APP" >&2
    echo "Build it first (see AGENTS.md 'Fast Debug build'), or pass a path." >&2
    exit 1
fi

BINARY="$SOURCE_APP/Contents/MacOS/sshCM"
if [[ ! -x "$BINARY" ]]; then
    echo "ERROR: no executable at $BINARY" >&2
    exit 1
fi

cleanup() {
    [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

echo "==> Staging fixture in $WORK"
cp -R "$SOURCE_APP" "$WORK/sshCM.app"

if [[ "$MODE" == "adhoc" ]]; then
    echo "==> Re-signing served app ad-hoc (signature pinning should REJECT it)"
    codesign --remove-signature "$WORK/sshCM.app" 2>/dev/null || true
    codesign -s - --force --deep "$WORK/sshCM.app"
fi

echo "==> Zipping asset (ditto, keepParent)"
( cd "$WORK" && ditto -c -k --keepParent "sshCM.app" "sshCM.zip" )
rm -rf "$WORK/sshCM.app"
ZIP_SIZE="$(stat -f%z "$WORK/sshCM.zip")"

echo "==> Writing crafted releases JSON"
cat > "$WORK/releases" <<EOF
[
  {
    "tag_name": "v9.9.9",
    "draft": false,
    "prerelease": false,
    "body": "# sshCM 9.9.9\n\nLocal end-to-end updater test build (mode: $MODE).\n\n- Served from localhost, not GitHub.",
    "assets": [
      {
        "name": "sshCM.zip",
        "browser_download_url": "http://localhost:$PORT/sshCM.zip",
        "size": $ZIP_SIZE
      }
    ]
  }
]
EOF

echo "==> Starting local server on http://localhost:$PORT"
( cd "$WORK" && exec python3 -m http.server "$PORT" ) &
SERVER_PID=$!
sleep 1

# Sanity-check the server is answering.
if ! curl -sf "http://localhost:$PORT/releases" >/dev/null; then
    echo "ERROR: local server did not come up on port $PORT" >&2
    exit 1
fi

echo "==> Launching sshCM pointed at the local release"
echo "    (mode: $MODE — expect: $([[ "$MODE" == "adhoc" ]] && echo 'unsigned opt-in prompt' || echo 'clean install/relaunch'))"
echo "    In the app: menu → Check for Updates…  (or Settings → Updates → Check Now)"
echo "    Ctrl-C here to stop the server."
echo
pkill -x sshCM 2>/dev/null || true
sleep 1

# GUI apps launched via `open` don't inherit shell env, so exec the binary
# directly to pass SSHCM_RELEASES_API through.
SSHCM_RELEASES_API="http://localhost:$PORT/releases" "$BINARY" &

# Stream server access logs until the user interrupts.
wait "$SERVER_PID"
