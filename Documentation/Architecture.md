# Architecture

MagnetBridge has a compact SwiftUI macOS application target, an embedded
optional CLI mode, and a UI-independent `MagnetBridgeCore` target. `AppModel`
owns graphical state and asynchronous actions; networking and business rules
remain outside SwiftUI. Sparkle is linked only to the application target through
the small `UpdateController` adapter.

## Request flow

```mermaid
flowchart LR
    Browser["Browser / open command"] --> Chooser["Magnet destination chooser"]
    Chooser --> OtherApp["Another installed magnet client"]
    Chooser --> URLHandler
    URLHandler --> MagnetValidator
    URLHandler --> SettingsStore
    URLHandler --> KeychainStore
    URLHandler --> TransmissionClient
    TransmissionClient --> Negotiation["409 session + RPC version negotiation"]
    Negotiation --> Legacy["Legacy adapter: torrent-add"]
    Negotiation --> Modern["JSON-RPC 2.0 adapter: torrent_add"]
    URLHandler --> NotificationService
    URLHandler --> BrowserLauncher
    BrowserLauncher --> WebUI["Transmission Web UI"]
```

`URLHandler` orchestrates one incoming link. `MagnetValidator` enforces scheme,
size, and `btih`/`btmh` exact-topic rules. `SettingsStore` persists one profile
without a password; `KeychainStore` owns the password. `usesAuthentication`
explicitly controls whether credentials participate in a request. Disabling
Basic Authentication retains a saved Keychain item for later but prevents both
the UI test action and `URLHandler` from reading or sending it.

The same signed executable has two entry paths. With CLI arguments it runs a
command and exits. Without arguments it starts the GUI. It may run as a menu bar
accessory or as a regular Dock application according to the saved preference.
When LaunchServices delivers a `magnet:` Apple Event, the app shows its window
and offers the configured server plus other installed handlers discovered with
`NSWorkspace`. Selecting another client uses `NSWorkspace` directly and never a
shell command.

The settings window keeps optional configuration out of the primary path.
**Use custom endpoint URLs** sits directly below the server address and reveals
the RPC and Web UI fields only when enabled. **Use Basic Authentication**
similarly reveals username and password controls only when enabled. Browser
choices use application icons loaded through `NSWorkspace`. Help is an in-app
sheet reachable from both application presentations, and the status item uses a
single-color template asset so macOS supplies the correct menu-bar appearance.

`TransmissionClient` is an actor. It sends requests through the injectable
`NetworkSession` interface and caches the CSRF session ID for its lifetime. On
HTTP 409 it reads `X-Transmission-Session-Id` and
`X-Transmission-Rpc-Version`. RPC semantic version 6 or later selects JSON-RPC
2.0; older or absent version headers select the legacy adapter.

The two adapters own wire-format differences:

| Transmission | Envelope | Add method | Parameter style |
| --- | --- | --- | --- |
| 4.0.x | Transmission legacy RPC | `torrent-add` | kebab/camel case |
| 4.1+ | JSON-RPC 2.0 | `torrent_add` | snake case |

Core errors distinguish invalid input, authentication, timeout, unavailable
server, HTTP server errors, RPC errors, and malformed responses. A duplicate is
a successful `TorrentAddOutcome`, never an error.

## Data boundaries

The complete magnet URL exists only in the incoming event, the in-memory
destination choice, the in-memory retry state, and the outbound RPC body. It is
not persisted or logged. The password crosses only the Keychain boundary and
the transient HTTP Authorization header.
Diagnostics contain hostnames, not URL paths, query strings, credentials, or
magnet payloads.

`BrowserLauncher` uses `NSWorkspace`, never shell commands. If the selected
bundle identifier is no longer installed, it opens the system browser and
reports a fallback.

## Update flow

```mermaid
flowchart LR
    User["Check for Updates / opt-in schedule"] --> UpdateController
    UpdateController --> Sparkle["Sparkle 2.9.4"]
    Sparkle --> Feed["Signed appcast.xml"]
    Feed --> Archive["EdDSA-signed MagnetBridge.zip"]
    Archive --> Gatekeeper["Developer ID + notarization"]
    Gatekeeper --> Install["Atomic install and relaunch"]
```

`UpdateController` owns one `SPUStandardUpdaterController` for the application
lifetime. Manual checks from the app menu, status menu, settings, and Help all
invoke the same controller. Sparkle persists the automatic-check preference
itself; it is not duplicated in `AppSettings`.

The feed is the `appcast.xml` asset of the latest GitHub Release. The app
requires a signed feed and verifies the update archive before extraction.
Release notes are embedded before the appcast is signed, and anonymous system
profiling is disabled. CI keeps the private EdDSA key in
`SPARKLE_ED_PRIVATE_KEY`; only the public key ships in the bundle.

Sparkle compares `CURRENT_PROJECT_VERSION`, which must increase for every
release. An installation that predates the first Sparkle-enabled build requires
one Homebrew, installer, or manual upgrade before it can use this flow.
