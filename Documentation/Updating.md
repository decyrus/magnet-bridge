# Updating MagnetBridge

MagnetBridge currently supports explicit, user-initiated updates. The next
stage is a secure native update flow.

## Supported today

### Homebrew

```sh
brew update
brew upgrade --cask magnet-bridge
```

Homebrew downloads the new notarized ZIP and verifies the SHA-256 checksum
stored in the Cask before replacing the app.

### One-line installer

Run the installer again. It downloads the latest GitHub release, verifies the
published checksum, replaces the application bundle, and leaves preferences and
Keychain items intact.

### Manual installation

Download `MagnetBridge.zip` and `MagnetBridge.zip.sha256` from the latest GitHub
release, verify the checksum, quit MagnetBridge, and replace the application in
`/Applications`.

## Proposed native updater

[Sparkle 2](https://sparkle-project.org/) is the preferred implementation for
automatic update checks and installation. It is mature, supports sandboxed and
non-sandboxed macOS applications, and verifies updates independently of HTTPS.

The rollout should be staged:

1. Add a non-intrusive **Check for Updates…** action and an opt-in automatic
   check setting.
2. Generate an appcast from GitHub Releases.
3. Sign every appcast item with a dedicated Sparkle EdDSA key.
4. Keep the private update key in GitHub Actions secrets and publish only the
   public key in the application.
5. Test upgrade and rollback behavior on both Apple Silicon and Intel Macs.
6. Only then enable automatic download and installation.

The Developer ID signature, Apple notarization, release SHA-256, and Sparkle
signature serve different purposes and should all remain in place.

## Versioning policy

MagnetBridge uses semantic versions:

- Patch releases fix bugs and documentation without changing configuration
  compatibility.
- Minor releases add backward-compatible features.
- Major releases may require settings or workflow migration.

Settings stored by older releases must continue to load, and Keychain service
and account identifiers must remain stable across upgrades.
