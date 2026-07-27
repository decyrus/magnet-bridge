# MagnetBridge

MagnetBridge is an open-source macOS 14+ utility that sends `magnet:` links to
Transmission running on a local or remote server, then opens Transmission Web
UI in your chosen browser. Torrent data is downloaded by the server — never by
the Mac running MagnetBridge.

The headless application is written in Swift 6. It supports the legacy RPC API
used by Transmission 4.0.x and the JSON-RPC 2.0 API introduced in Transmission
4.1. Configuration is performed exclusively through its command-line interface.

## Install

The recommended one-line installer downloads the signed and notarized release,
verifies its published SHA-256 checksum, installs the app and CLI, and starts
the interactive configuration wizard:

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
magnetbridge configure
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

Run the interactive wizard after installation:

```sh
magnetbridge configure
```

The wizard asks for one server address, such as
`https://transmission.example`, and automatically uses the standard
`/transmission/rpc` and `/transmission/web/` paths. It also configures Basic
Authentication, timeout, browser, and torrent start mode, then offers to test
the connection. The password is read without terminal echo and stored only in
macOS Keychain.

Interactive output uses color, clear sections, and status icons. Colors are
disabled automatically when output is redirected. Set `NO_COLOR=1` or
`TERM=dumb` to disable ANSI colors explicitly.

Configuration can also be scripted:

```sh
magnetbridge config set server https://server.example
magnetbridge config set username alice
magnetbridge config set password
magnetbridge config set timeout 15
magnetbridge config set start-mode immediately
magnetbridge config set open-web-ui true
magnetbridge config set browser system
magnetbridge test
```

Inspect the current non-secret configuration:

```sh
magnetbridge config show
```

Servers with custom RPC or Web UI paths can use the advanced wizard:

```sh
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
