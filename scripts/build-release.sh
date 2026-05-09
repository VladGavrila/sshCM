#!/usr/bin/env bash
# Build, sign, and notarize sshCM (SSH Config Manager).
#
# Required env vars for signing/notarization:
#   DEVELOPER_ID_CERT_BASE64   - base64-encoded Developer ID Application .p12
#   DEVELOPER_ID_CERT_PASSWORD - .p12 password
#   NOTARIZE_APPLE_ID          - Apple ID for notarytool
#   NOTARIZE_TEAM_ID           - Team ID (defaults to project's DEVELOPMENT_TEAM)
#   NOTARIZE_APP_PASSWORD      - App-specific password
#
# Optional:
#   BUNDLE_VERSION             - CFBundleVersion (default: 1)
#   BUNDLE_SHORT_VERSION       - CFBundleShortVersionString (default: 1.0.0)
#   TEAM_ID                    - Override DEVELOPMENT_TEAM for signing (default: 2RZL73M634)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$REPO_ROOT/sshCM"
PROJECT_FILE="$PROJECT_DIR/sshCM.xcodeproj"
SCHEME="sshCM"
APP_NAME="sshCM"
CONFIGURATION="Release"

DERIVED_DATA="$REPO_ROOT/.build/DerivedData"
ARCHIVE_PATH="$REPO_ROOT/.build/${APP_NAME}.xcarchive"
EXPORT_DIR="$REPO_ROOT/dist"
APP_DIR="$EXPORT_DIR/${APP_NAME}.app"

BUNDLE_VERSION="${BUNDLE_VERSION:-1}"
BUNDLE_SHORT_VERSION="${BUNDLE_SHORT_VERSION:-1.0.0}"
TEAM_ID="${TEAM_ID:-2RZL73M634}"

# xcodebuild needs a full Xcode, not just Command Line Tools. If the active
# developer dir is CLT, fall back to /Applications/Xcode.app when present.
if ! /usr/bin/xcrun --find xcodebuild >/dev/null 2>&1 \
   || [[ "$(/usr/bin/xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
    if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
        echo "==> Using DEVELOPER_DIR=$DEVELOPER_DIR (xcode-select points at CLT)"
    else
        echo "ERROR: Xcode.app not found; install Xcode or 'sudo xcode-select -s' to its Developer dir." >&2
        exit 1
    fi
fi

echo "==> Cleaning previous artifacts..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

# Render ExportOptions.plist with the team id substituted.
EXPORT_OPTIONS="$REPO_ROOT/.build/ExportOptions.plist"
mkdir -p "$REPO_ROOT/.build"
sed "s/__TEAM_ID__/$TEAM_ID/g" "$SCRIPT_DIR/ExportOptions.plist" > "$EXPORT_OPTIONS"

KEYCHAIN_PATH=""
PRIOR_KEYCHAINS=""
cleanup() {
    if [[ -n "$KEYCHAIN_PATH" && -f "$KEYCHAIN_PATH" ]]; then
        if [[ -n "$PRIOR_KEYCHAINS" ]]; then
            # shellcheck disable=SC2086
            security list-keychain -d user -s $PRIOR_KEYCHAINS >/dev/null 2>&1 || true
        fi
        security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
    fi
    rm -f "${TMPDIR%/}/cert.p12" 2>/dev/null || true
}
trap cleanup EXIT

if [[ -n "${DEVELOPER_ID_CERT_BASE64:-}" ]]; then
    echo "==> Importing signing certificate into temporary keychain..."
    KEYCHAIN_PATH="${TMPDIR%/}/sshcm-build.keychain-db"
    KEYCHAIN_PASSWORD="$(uuidgen)"

    rm -f "$KEYCHAIN_PATH"
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-keychain-settings -lut 3600 "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

    echo "$DEVELOPER_ID_CERT_BASE64" | base64 --decode > "${TMPDIR%/}/cert.p12"
    security import "${TMPDIR%/}/cert.p12" \
        -k "$KEYCHAIN_PATH" \
        -P "${DEVELOPER_ID_CERT_PASSWORD}" \
        -T /usr/bin/codesign \
        -T /usr/bin/security \
        -T /usr/bin/productsign \
        -A

    PRIOR_KEYCHAINS="$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g' | tr '\n' ' ')"
    security list-keychain -d user -s "$KEYCHAIN_PATH" $PRIOR_KEYCHAINS
    security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null

    SIGN_ARGS=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="Developer ID Application"
        DEVELOPMENT_TEAM="$TEAM_ID"
        OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"
    )
else
    echo "  DEVELOPER_ID_CERT_BASE64 not set; archiving with project's automatic signing."
    SIGN_ARGS=()
fi

echo "==> Archiving (xcodebuild)..."
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$BUNDLE_SHORT_VERSION" \
    CURRENT_PROJECT_VERSION="$BUNDLE_VERSION" \
    "${SIGN_ARGS[@]}" \
    archive

echo "==> Exporting app bundle..."
if [[ -n "${DEVELOPER_ID_CERT_BASE64:-}" ]]; then
    xcodebuild \
        -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        -exportPath "$EXPORT_DIR"
else
    # Without a Developer ID cert, just copy the unsigned/ad-hoc archive product out.
    cp -R "$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app" "$APP_DIR"
    codesign --deep --force --sign - "$APP_DIR"
fi

if [[ ! -d "$APP_DIR" ]]; then
    echo "ERROR: expected app at $APP_DIR" >&2
    exit 1
fi

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR" || true
codesign --display --verbose=2 "$APP_DIR" 2>&1 | sed -n '1,5p' || true

echo "==> Creating zip archive..."
cd "$EXPORT_DIR"
ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"

if [[ -n "${NOTARIZE_APPLE_ID:-}" ]]; then
    echo "==> Notarizing..."
    xcrun notarytool submit "${APP_NAME}.zip" \
        --apple-id "$NOTARIZE_APPLE_ID" \
        --team-id "${NOTARIZE_TEAM_ID:-$TEAM_ID}" \
        --password "$NOTARIZE_APP_PASSWORD" \
        --wait

    echo "==> Stapling..."
    xcrun stapler staple "${APP_NAME}.app"

    rm "${APP_NAME}.zip"
    ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"
else
    echo "  Skipping notarization (NOTARIZE_APPLE_ID not set)"
fi

echo "==> Done: $EXPORT_DIR/${APP_NAME}.zip"
