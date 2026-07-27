#!/bin/sh
set -eu

VERSION="${VERSION:?Set VERSION, for example 0.1.0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:?Set the Developer ID Application identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set a notarytool Keychain profile}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:?Set the Sparkle EdDSA private key file}"
OUTPUT_DIRECTORY="${OUTPUT_DIRECTORY:-$PWD/release}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"
BUILD_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/magnetbridge-release.XXXXXX")"
trap 'rm -rf "$BUILD_DIRECTORY"' EXIT HUP INT TERM

case "$VERSION" in
    v*) VERSION="${VERSION#v}" ;;
esac
RELEASE_TAG="v$VERSION"

mkdir -p "$OUTPUT_DIRECTORY"
xcodegen generate

xcodebuild \
    -project MagnetBridge.xcodeproj \
    -scheme MagnetBridge \
    -configuration Release \
    -derivedDataPath "$BUILD_DIRECTORY/DerivedData" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_SOURCE="$BUILD_DIRECTORY/DerivedData/Build/Products/Release/MagnetBridge.app"
APP_STAGING="$BUILD_DIRECTORY/staging/MagnetBridge.app"
mkdir -p "$BUILD_DIRECTORY/staging"
ditto "$APP_SOURCE" "$APP_STAGING"

ARCHITECTURES="$(lipo -archs "$APP_STAGING/Contents/MacOS/MagnetBridge")"
case "$ARCHITECTURES" in
    *arm64*x86_64*|*x86_64*arm64*) ;;
    *)
        echo "Expected a universal binary, got: $ARCHITECTURES" >&2
        exit 1
        ;;
esac

SPARKLE_FRAMEWORK="$APP_STAGING/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIRECTORY="$SPARKLE_FRAMEWORK/Versions/B"
if [ ! -d "$SPARKLE_VERSION_DIRECTORY" ]; then
    echo "Sparkle.framework was not embedded in MagnetBridge.app" >&2
    exit 1
fi

codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_VERSION_DIRECTORY/XPCServices/Installer.xpc"
codesign \
    --force \
    --options runtime \
    --timestamp \
    --preserve-metadata=entitlements \
    --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_VERSION_DIRECTORY/XPCServices/Downloader.xpc"
codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_VERSION_DIRECTORY/Autoupdate"
codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_VERSION_DIRECTORY/Updater.app"
codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_FRAMEWORK"
codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements Sources/MagnetBridgeApp/MagnetBridge.entitlements \
    --sign "$SIGNING_IDENTITY" \
    "$APP_STAGING"
codesign --verify --deep --strict --verbose=2 "$APP_STAGING"

SUBMISSION_ARCHIVE="$BUILD_DIRECTORY/MagnetBridge-notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_STAGING" "$SUBMISSION_ARCHIVE"
xcrun notarytool submit \
    "$SUBMISSION_ARCHIVE" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$APP_STAGING"
xcrun stapler validate "$APP_STAGING"
spctl --assess --type execute --verbose=2 "$APP_STAGING"

FINAL_ARCHIVE="$OUTPUT_DIRECTORY/MagnetBridge.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_STAGING" "$FINAL_ARCHIVE"
(
    cd "$OUTPUT_DIRECTORY"
    shasum -a 256 MagnetBridge.zip > MagnetBridge.zip.sha256
)

ARCHIVE_SHA256="$(shasum -a 256 "$FINAL_ARCHIVE" | awk '{print $1}')"
sed \
    -e "s/__VERSION__/$VERSION/g" \
    -e "s/__SHA256__/$ARCHIVE_SHA256/g" \
    packaging/homebrew/magnet-bridge.rb.template \
    > "$OUTPUT_DIRECTORY/magnet-bridge.rb"

GENERATE_APPCAST="$(
    find "$BUILD_DIRECTORY/DerivedData/SourcePackages/artifacts" \
        -type f \
        -path '*/Sparkle/bin/generate_appcast' \
        -print \
        -quit
)"
SIGN_UPDATE="$(
    find "$BUILD_DIRECTORY/DerivedData/SourcePackages/artifacts" \
        -type f \
        -path '*/Sparkle/bin/sign_update' \
        -print \
        -quit
)"
if [ -z "$GENERATE_APPCAST" ] || [ -z "$SIGN_UPDATE" ]; then
    echo "Sparkle release tools were not found in Xcode SourcePackages" >&2
    exit 1
fi

APPCAST_DIRECTORY="$BUILD_DIRECTORY/appcast"
mkdir -p "$APPCAST_DIRECTORY"
ditto "$FINAL_ARCHIVE" "$APPCAST_DIRECTORY/MagnetBridge.zip"
if [ -n "$RELEASE_NOTES_FILE" ]; then
    cp "$RELEASE_NOTES_FILE" "$APPCAST_DIRECTORY/MagnetBridge.md"
else
    printf '# MagnetBridge %s\n\nSee the GitHub release for details.\n' \
        "$VERSION" \
        > "$APPCAST_DIRECTORY/MagnetBridge.md"
fi

"$GENERATE_APPCAST" \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    --download-url-prefix \
        "https://github.com/decyrus/magnet-bridge/releases/download/$RELEASE_TAG/" \
    --link "https://github.com/decyrus/magnet-bridge/releases/tag/$RELEASE_TAG" \
    --full-release-notes-url \
        "https://github.com/decyrus/magnet-bridge/releases/tag/$RELEASE_TAG" \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    --embed-release-notes \
    -o "$OUTPUT_DIRECTORY/appcast.xml" \
    "$APPCAST_DIRECTORY"
xmllint --noout "$OUTPUT_DIRECTORY/appcast.xml"
"$SIGN_UPDATE" \
    --verify \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    "$OUTPUT_DIRECTORY/appcast.xml"

echo "Release artifacts:"
echo "  $FINAL_ARCHIVE"
echo "  $FINAL_ARCHIVE.sha256"
echo "  $OUTPUT_DIRECTORY/magnet-bridge.rb"
echo "  $OUTPUT_DIRECTORY/appcast.xml"
