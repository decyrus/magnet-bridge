# Updating MagnetBridge

MagnetBridge includes [Sparkle 2.9.4](https://sparkle-project.org/) for native,
user-controlled updates.

## In-app updates

Choose **Check for Updates…** from the application menu, menu-bar status menu,
or Help window. The **Check Now** button under **macOS Integration** performs
the same action.

Automatic checks are opt-in. Enable or disable **Automatically check for
updates** under **macOS Integration** at any time. Sparkle owns this preference
and its schedule; MagnetBridge does not enable system profiling or send
telemetry with update checks.

The app reads its feed from:

```text
https://github.com/decyrus/magnet-bridge/releases/latest/download/appcast.xml
```

Every release publishes this appcast as a GitHub Release asset. The feed,
embedded release notes, and ZIP enclosure are signed with the project's
dedicated Sparkle EdDSA key. Sparkle verifies the signed feed and archive before
extraction. The application inside the archive is also signed with Developer
ID, notarized, and stapled by Apple.

These checks are complementary:

- Sparkle EdDSA authenticates the appcast and exact update archive.
- Developer ID authenticates the application bundle.
- Apple notarization and Gatekeeper validate its distribution status.
- Homebrew's SHA-256 authenticates the archive selected by the Cask.

## Bootstrap limitation

An installed version that predates Sparkle cannot discover or install the first
Sparkle-enabled release by itself. Upgrade that installation once with
Homebrew, the installer, or manual replacement. In-app updates work from the
first Sparkle-enabled release onward.

## Other update methods

### Homebrew

```sh
brew update
brew upgrade --cask magnet-bridge
```

The Cask declares `auto_updates true`, allowing Homebrew to account for an app
bundle that Sparkle has already updated. Homebrew compares readable bundle
version metadata and avoids replacing a newer installed copy with an older
one.

### One-line installer

Run the installer again. It downloads the latest GitHub release, verifies the
published checksum, replaces the application bundle, and leaves preferences
and Keychain items intact.

### Manual installation

Download `MagnetBridge.zip` and `MagnetBridge.zip.sha256` from the latest GitHub
release, verify the checksum, quit MagnetBridge, and replace the application in
`/Applications`.

## Versioning policy

MagnetBridge uses a semantic `MARKETING_VERSION` and an independent,
machine-readable `CURRENT_PROJECT_VERSION`.

- Increment `CURRENT_PROJECT_VERSION` for every release. Sparkle compares this
  build number and it must be strictly greater than every published build.
- Patch releases fix bugs without breaking configuration compatibility.
- Minor releases add backward-compatible features.
- Major releases may require a documented settings or workflow migration.

Settings stored by older releases must continue to load, and Keychain service
and account identifiers must remain stable across upgrades.
