# MagnetBridge

MagnetBridge is an open-source macOS 14+ utility that sends `magnet:` links to
Transmission running on a local or remote server, then opens Transmission Web
UI in your chosen browser. Torrent data is downloaded by the server — never by
the Mac running MagnetBridge.

The application is written in Swift 6 and SwiftUI. It supports the legacy RPC
API used by Transmission 4.0.x and the JSON-RPC 2.0 API introduced in
Transmission 4.1.

## Install

Download the signed and notarized `MagnetBridge.zip` from
[GitHub Releases](https://github.com/decyrus/magnet-bridge/releases), verify the
published SHA-256 file, and move the app to `/Applications`.

One-line installer (the release archive is SHA-256 verified):

```sh
curl -fsSL https://raw.githubusercontent.com/decyrus/magnet-bridge/main/scripts/install.sh | sh
```

To inspect the installer before running it:

```sh
curl -fsSLO https://raw.githubusercontent.com/decyrus/magnet-bridge/main/scripts/install.sh
less install.sh
sh install.sh
```

A generated Homebrew Cask is attached to each release. Until a dedicated
`decyrus/homebrew-magnet-bridge` tap is published, install it from a downloaded
Cask file:

```sh
curl -fLO https://github.com/decyrus/magnet-bridge/releases/latest/download/magnet-bridge.rb
brew install --cask ./magnet-bridge.rb
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

For a manual or one-line installation, quit MagnetBridge and move
`MagnetBridge.app` from `/Applications` or `~/Applications` to the Trash.

The Transmission password is intentionally left in macOS Keychain during a
normal uninstall. To remove it as well, open **Keychain Access**, search for
`org.magnetbridge.app`, and delete the item whose account is
`transmission-rpc`. Alternatively:

```sh
security delete-generic-password \
  -s org.magnetbridge.app \
  -a transmission-rpc
```

To remove saved preferences after a manual installation:

```sh
defaults delete org.magnetbridge.app
```

## Configure

1. Open MagnetBridge → Settings.
2. Enter the Transmission RPC URL (usually
   `http://host:9091/transmission/rpc`) and Web UI URL.
3. Enter credentials. The password is saved only in macOS Keychain.
4. Acknowledge the warning if you intentionally use unencrypted HTTP.
5. Choose the browser and whether newly added torrents start immediately.
6. Click **Test Connection**, then **Save**.

For remote servers, prefer HTTPS through a trusted reverse proxy, a VPN, or
Tailscale. Do not expose the Transmission RPC port directly to the internet.

If macOS does not select MagnetBridge automatically, open the app once and then
test with:

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
