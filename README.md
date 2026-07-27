# MagnetBridge

MagnetBridge is an open-source macOS 14+ utility that sends `magnet:` links to
Transmission running on a local or remote server, then opens Transmission Web
UI in your chosen browser. Torrent data is downloaded by the server — never by
the Mac running MagnetBridge.

The compact Swift 6 and SwiftUI app can stay in the menu bar or behave like a
regular Dock app. It supports the legacy RPC API used by Transmission 4.0.x and
the JSON-RPC 2.0 API introduced in Transmission 4.1.

When a magnet link arrives, MagnetBridge asks whether to send it to the
configured Transmission server or open it in another installed magnet client.
The complete link is kept in memory only for the duration of that choice.

## Install

The recommended one-line installer downloads the signed and notarized release,
verifies its published SHA-256 checksum, installs the app and optional CLI, and
opens the graphical setup:

```sh
curl -fsSL https://raw.githubusercontent.com/decyrus/magnet-bridge/main/scripts/install.sh | sh
```

To inspect the installer before running it:

```sh
curl -fsSLO https://raw.githubusercontent.com/decyrus/magnet-bridge/main/scripts/install.sh
less install.sh
sh install.sh
```

Set a custom CLI installation directory if needed:

```sh
MAGNETBRIDGE_BIN_DIR="$HOME/bin" sh install.sh
```

A generated Homebrew Cask is attached to each release. Until a dedicated
`decyrus/homebrew-magnet-bridge` tap is published, install it from a downloaded
Cask file:

```sh
curl -fLO https://github.com/decyrus/magnet-bridge/releases/latest/download/magnet-bridge.rb
brew install --cask ./magnet-bridge.rb
open -a MagnetBridge
```

## Uninstall

If MagnetBridge was installed with Homebrew:

```sh
brew uninstall --cask magnet-bridge
```

To remove the app and its saved preferences:

```sh
brew uninstall --zap --cask magnet-bridge
```

For a manual or one-line installation:

```sh
pkill -x MagnetBridge 2>/dev/null || true
rm -rf /Applications/MagnetBridge.app "$HOME/Applications/MagnetBridge.app"
rm -f /usr/local/bin/magnetbridge "$HOME/.local/bin/magnetbridge"
```

The Transmission password is intentionally left in macOS Keychain during a
normal uninstall. To remove the password and preferences as well:

```sh
security delete-generic-password \
  -s org.magnetbridge.app \
  -a transmission-rpc 2>/dev/null || true
defaults delete org.magnetbridge.app 2>/dev/null || true
```

## Configure

Open MagnetBridge from Applications. Enter one server address, such as
`https://transmission.example`; the standard `/transmission/rpc` and
`/transmission/web/` paths are added automatically. Configure optional Basic
Authentication, browser, timeout, and torrent start mode, then use **Test
Connection** and **Save & Make Default**.

The password is never loaded back into the form and is stored only in macOS
Keychain. Custom RPC and Web UI paths are hidden under **Custom endpoint
paths**. HTTP requires an explicit warning acknowledgement.

By default MagnetBridge stays available from the menu bar after its window is
closed. Turn off **Keep MagnetBridge in the menu bar** to use it as a regular
Dock app that quits when the window closes.

The CLI remains available for automation and recovery:

Check or repair the system protocol association at any time:

```sh
magnetbridge status
magnetbridge register
magnetbridge unregister
```

Configuration can be scripted:

```sh
magnetbridge config set server https://server.example
magnetbridge config set username alice
magnetbridge config set password
magnetbridge config set timeout 15
magnetbridge config set start-mode immediately
magnetbridge config set open-web-ui true
magnetbridge config set browser system
magnetbridge config set menu-bar true
magnetbridge test
```

Inspect the current non-secret configuration:

```sh
magnetbridge config show
```

An interactive terminal wizard is also retained:

```sh
magnetbridge configure
magnetbridge configure --advanced
```

The individual `rpc-url` and `web-ui-url` keys also remain available for
advanced scripted configuration.

For an intentionally unencrypted RPC endpoint, explicitly opt in:

```sh
magnetbridge config set allow-http true
magnetbridge config set server http://server.example:9091
```

For remote servers, prefer HTTPS through a trusted reverse proxy, a VPN, or
Tailscale. Do not expose the Transmission RPC port directly to the internet.

Test protocol handling with:

```sh
open "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
```

MagnetBridge will show a choice between the configured server and other
installed magnet handlers, such as the local Transmission app.

## Build

Requirements: macOS 14+, Xcode 16+ with Swift 6, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild \
  -project MagnetBridge.xcodeproj \
  -scheme MagnetBridge \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build test
```

The standalone core tests can also be run with `swift test`.

## Privacy and scope

MagnetBridge has no telemetry. Logs and diagnostics must not contain passwords
or complete magnet links. The MVP intentionally excludes torrent management,
multiple servers, `.torrent` files, file selection, download directories,
mobile apps, and an embedded Web UI.

See [architecture](Documentation/Architecture.md), [contributing
guide](CONTRIBUTING.md), [release guide](Documentation/Releasing.md), and
[security policy](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
