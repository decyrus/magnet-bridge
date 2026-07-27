#!/bin/sh
set -eu

REPOSITORY="decyrus/magnet-bridge"
ARCHIVE_NAME="MagnetBridge.zip"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"
REQUESTED_VERSION="${MAGNETBRIDGE_VERSION:-latest}"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "MagnetBridge requires macOS." >&2
    exit 1
fi

case "$REQUESTED_VERSION" in
    latest)
        RELEASE_PATH="latest/download"
        ;;
    v*)
        RELEASE_PATH="download/$REQUESTED_VERSION"
        ;;
    *)
        RELEASE_PATH="download/v$REQUESTED_VERSION"
        ;;
esac

BASE_URL="https://github.com/$REPOSITORY/releases/$RELEASE_PATH"
WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/magnetbridge-install.XXXXXX")"
trap 'rm -rf "$WORK_DIRECTORY"' EXIT HUP INT TERM

echo "Downloading MagnetBridge…"
curl -fL "$BASE_URL/$ARCHIVE_NAME" -o "$WORK_DIRECTORY/$ARCHIVE_NAME"
curl -fL "$BASE_URL/$CHECKSUM_NAME" -o "$WORK_DIRECTORY/$CHECKSUM_NAME"

(
    cd "$WORK_DIRECTORY"
    shasum -a 256 -c "$CHECKSUM_NAME"
)

ditto -x -k "$WORK_DIRECTORY/$ARCHIVE_NAME" "$WORK_DIRECTORY/unpacked"
APP_SOURCE="$WORK_DIRECTORY/unpacked/MagnetBridge.app"
if [ ! -d "$APP_SOURCE" ]; then
    echo "The verified archive does not contain MagnetBridge.app." >&2
    exit 1
fi

if [ -w "/Applications" ]; then
    INSTALL_DIRECTORY="/Applications"
else
    INSTALL_DIRECTORY="${HOME}/Applications"
    mkdir -p "$INSTALL_DIRECTORY"
fi

APP_DESTINATION="$INSTALL_DIRECTORY/MagnetBridge.app"
BACKUP_DESTINATION="$WORK_DIRECTORY/MagnetBridge.previous.app"
if [ -e "$APP_DESTINATION" ]; then
    mv "$APP_DESTINATION" "$BACKUP_DESTINATION"
fi

if ! ditto "$APP_SOURCE" "$APP_DESTINATION"; then
    if [ -e "$BACKUP_DESTINATION" ]; then
        mv "$BACKUP_DESTINATION" "$APP_DESTINATION"
    fi
    echo "Installation failed; the previous app was restored." >&2
    exit 1
fi

if [ -n "${MAGNETBRIDGE_BIN_DIR:-}" ]; then
    CLI_DIRECTORY="$MAGNETBRIDGE_BIN_DIR"
elif [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
    CLI_DIRECTORY="/usr/local/bin"
else
    CLI_DIRECTORY="${HOME}/.local/bin"
fi

mkdir -p "$CLI_DIRECTORY"
CLI_DESTINATION="$CLI_DIRECTORY/magnetbridge"
ln -sfn "$APP_DESTINATION/Contents/MacOS/MagnetBridge" "$CLI_DESTINATION"

echo "Installed MagnetBridge at $APP_DESTINATION"
echo "Installed the CLI at $CLI_DESTINATION"
echo "The installer did not remove macOS quarantine or bypass Gatekeeper."

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$APP_DESTINATION" >/dev/null 2>&1 || \
        echo "Warning: macOS did not register MagnetBridge with LaunchServices." >&2
fi

case ":${PATH}:" in
    *":${CLI_DIRECTORY}:"*) ;;
    *)
        echo "Add $CLI_DIRECTORY to PATH to run magnetbridge from any shell."
        ;;
esac

if [ -r "/dev/tty" ]; then
    echo "Starting the configuration wizard…"
    if ! "$CLI_DESTINATION" configure </dev/tty >/dev/tty 2>/dev/tty; then
        echo "Configuration was not completed. Run: $CLI_DESTINATION configure" >&2
    fi
else
    echo "Run the configuration wizard: $CLI_DESTINATION configure"
fi
