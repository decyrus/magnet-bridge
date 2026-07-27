<p align="center">
  <img
    src="Sources/MagnetBridgeApp/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png"
    width="144"
    height="144"
    alt="MagnetBridge app icon"
  >
</p>

<h1 align="center">MagnetBridge</h1>

<p align="center">
  <strong>Open magnet links from your Mac directly in Transmission on a NAS,
  home server, or VPS.</strong>
</p>

<p align="center">
  <a href="https://github.com/decyrus/magnet-bridge/actions/workflows/ci.yml"><img src="https://github.com/decyrus/magnet-bridge/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/decyrus/magnet-bridge/releases/latest"><img src="https://img.shields.io/github/v/release/decyrus/magnet-bridge?display_name=tag&sort=semver" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="https://github.com/decyrus/homebrew-tap"><img src="https://img.shields.io/badge/Homebrew-decyrus%2Ftap-FBB040?logo=homebrew&logoColor=black" alt="Homebrew tap"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/decyrus/magnet-bridge" alt="MIT license"></a>
</p>

MagnetBridge is a small open-source macOS companion for
[Transmission](https://transmissionbt.com/). It catches `magnet:` links from
Safari, Chrome, Firefox, and other apps, sends them to Transmission over its RPC
API, then opens Transmission Web UI in your preferred browser.

The torrent is downloaded by the Transmission server. Your Mac only handles
the magnet link.

## The use case

You browse on your Mac, but Transmission runs somewhere else: a NAS, a home
server, a seedbox, or a VPS.

1. Click a magnet link in your browser.
2. Choose **Send to Transmission Server** in MagnetBridge, or hand the link to
   another installed magnet client.
3. MagnetBridge validates the link and sends it to your configured Transmission
   instance.
4. Transmission downloads the torrent on the server and MagnetBridge opens its
   Web UI.

Repeated links are safe: an existing torrent is reported as already added
instead of being duplicated.

## Highlights

- Native Swift 6 and SwiftUI app for macOS 14 and later.
- Compact window, built-in help, and optional menu bar mode with a native
  monochrome status icon.
- Works with Transmission 4.0.x legacy RPC and Transmission 4.1+ JSON-RPC 2.0.
- Optional Basic Authentication with the password stored only in macOS
  Keychain.
- Opens the Web UI in the system browser or a selected installed browser,
  shown with its application icon.
- Secure in-app updates through Sparkle 2.9.4 and a signed appcast.
- Keeps full magnet links and credentials out of settings, logs, and diagnostics.
- Signed with Developer ID, notarized by Apple, and built for Apple Silicon and
  Intel Macs.
- No telemetry.

## Install

### Homebrew

Install the signed and notarized release from the
[`decyrus/tap`](https://github.com/decyrus/homebrew-tap) Cask:

```sh
brew install --cask decyrus/tap/magnet-bridge
open -a MagnetBridge
```

The fully qualified name adds the tap automatically; a separate `brew tap`
command is not required.

### Manual

Download the signed ZIP from the
[latest release](https://github.com/decyrus/magnet-bridge/releases/latest),
extract it, and move `MagnetBridge.app` to Applications. This requires no shell
pipeline.

### One-line installer

The installer verifies the published SHA-256 checksum, installs the app and
optional CLI, and opens the graphical setup:

```sh
curl -fsSL https://raw.githubusercontent.com/decyrus/magnet-bridge/main/scripts/install.sh | sh
```

To inspect it first:

```sh
curl -fsSLO https://raw.githubusercontent.com/decyrus/magnet-bridge/main/scripts/install.sh
less install.sh
sh install.sh
```

Set a custom CLI installation directory if needed:

```sh
MAGNETBRIDGE_BIN_DIR="$HOME/bin" sh install.sh
```

## Configure

Open MagnetBridge from Applications and enter one server address, such as
`https://transmission.example`. MagnetBridge adds Transmission's standard
`/transmission/rpc` and `/transmission/web/` paths automatically.

Enable **Use custom endpoint URLs** directly below the server field only when a
reverse proxy changes those paths. Enable **Use Basic Authentication** only
when the Transmission server requires credentials; the username and password
fields remain hidden otherwise. Configure the browser, timeout, and torrent
start mode, then use **Test Connection** and **Save & Make Default**.

The password is never loaded back into the form and is stored only in macOS
Keychain. Turning authentication off keeps any saved credential for later but
prevents MagnetBridge from reading or sending it. Plain HTTP requires an
explicit warning acknowledgement. For remote servers, prefer HTTPS through a
trusted reverse proxy, a VPN, or Tailscale; do not publish the Transmission RPC
port directly to the internet.

By default MagnetBridge stays available from the menu bar after its window is
closed. Turn off **Keep MagnetBridge in the menu bar** to use it as a regular
Dock app that quits when the window closes. Open the built-in guide from the
question-mark button or **MagnetBridge Help** in the app and status menus.

Test protocol handling with:

```sh
open "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
```

## Update

Use **Check for Updates…** from the app menu, status menu, or Help window.
**Automatically check for updates** is opt-in and can be changed under
**macOS Integration**. Sparkle 2.9.4 downloads the notarized release from the
project's signed appcast and verifies its EdDSA signature before installation;
anonymous system profiling is disabled.

Homebrew installations can also update with:

```sh
brew update
brew upgrade --cask magnet-bridge
```

For a manual installation, replace the app with the copy from the
[latest release](https://github.com/decyrus/magnet-bridge/releases/latest).
One-line installations can be updated by running the installer again.
Preferences and the Keychain password are preserved by all three methods.

An installation older than the first Sparkle-enabled release must be upgraded
once through Homebrew, the installer, or manual replacement. Native updating
works from that release onward. See
[Updating MagnetBridge](Documentation/Updating.md) for the trust model and
fallback methods.

## CLI

The GUI is the primary interface. The optional `magnetbridge` command remains
available for automation, diagnostics, and recovery:

```sh
magnetbridge status
magnetbridge register
magnetbridge unregister
magnetbridge test
magnetbridge config show
```

Configuration can also be scripted:

```sh
magnetbridge config set server https://server.example
magnetbridge config set timeout 15
magnetbridge config set start-mode immediately
magnetbridge config set open-web-ui true
magnetbridge config set browser system
magnetbridge config set menu-bar true
```

For a server that requires Basic Authentication:

```sh
magnetbridge config set username alice
magnetbridge config set password
```

Setting a username enables authentication, and the password command prompts
without echoing. Stop reading or sending the saved credential without deleting
it:

```sh
magnetbridge config set authentication false
```

Re-enable an already configured username with `authentication true`, or remove
the Keychain password with `magnetbridge config unset-password`.

An interactive terminal wizard is retained:

```sh
magnetbridge configure
magnetbridge configure --advanced
```

The advanced wizard exposes custom endpoints. They can also be scripted with
the `rpc-url` and `web-ui-url` configuration keys.

For an intentionally unencrypted endpoint:

```sh
magnetbridge config set allow-http true
magnetbridge config set server http://server.example:9091
```

## Uninstall

Homebrew:

```sh
brew uninstall --cask magnet-bridge
```

Also remove preferences and Keychain data:

```sh
brew uninstall --zap --cask magnet-bridge
```

Manual or one-line installation:

```sh
pkill -x MagnetBridge 2>/dev/null || true
rm -rf /Applications/MagnetBridge.app "$HOME/Applications/MagnetBridge.app"
rm -f /usr/local/bin/magnetbridge "$HOME/.local/bin/magnetbridge"
```

A normal uninstall intentionally leaves the Transmission password in Keychain.
To remove it and all preferences:

```sh
security delete-generic-password \
  -s org.magnetbridge.app \
  -a transmission-rpc 2>/dev/null || true
defaults delete org.magnetbridge.app 2>/dev/null || true
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

## Project

MagnetBridge intentionally focuses on one job: routing magnet links to one
Transmission server. Torrent management, multiple profiles, `.torrent` files,
file selection, download directories, mobile apps, and an embedded Web UI are
outside the current scope.

Read the [architecture](Documentation/Architecture.md),
[update guide](Documentation/Updating.md),
[Homebrew distribution guide](Documentation/Homebrew.md),
[release guide](Documentation/Releasing.md),
[contributing guide](CONTRIBUTING.md), and [security policy](SECURITY.md).

## License

MagnetBridge is available under the [MIT License](LICENSE).
