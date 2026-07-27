# Releasing

Tagged releases are universal (`arm64` + `x86_64`), signed with Developer ID,
notarized, stapled, and published as a ZIP with a SHA-256 checksum. The release
also contains a checksum-pinned Homebrew Cask and a Sparkle 2.9.4 appcast
signed with a dedicated EdDSA key.

## GitHub Actions secrets

Configure these repository secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password protecting that `.p12` |
| `DEVELOPER_ID_APPLICATION` | Full identity, for example `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APP_SPECIFIC_PASSWORD` | App-specific password for the Apple ID |
| `SPARKLE_ED_PRIVATE_KEY` | Private key exported by Sparkle `generate_keys`; used only to sign updates and the appcast |
| `HOMEBREW_TAP_TOKEN` | Fine-grained token with Contents write access only to `decyrus/homebrew-tap` |

The Sparkle public key is committed in the application `Info.plist`. Keep the
private key in GitHub Actions and a separate encrypted offline backup. Never
commit it, add it to release assets, or print it in workflow output.

## Prepare the version

Before tagging, update both version fields in `project.yml`:

- `MARKETING_VERSION` is the user-facing semantic version.
- `CURRENT_PROJECT_VERSION` is Sparkle's machine-readable build number and must
  be strictly greater than every previously published build.

Regenerate the project with `xcodegen generate`, commit the generated project
and resolved package state, then complete CI before creating the tag.

Create a release by pushing a semantic version tag:

```sh
git tag -a v0.4.0 -m "MagnetBridge v0.4.0"
git push origin v0.4.0
```

The workflow fails rather than publishing an unsigned or unnotarized archive.
After it succeeds, verify that the GitHub release contains:

- `MagnetBridge.zip`
- `MagnetBridge.zip.sha256`
- `magnet-bridge.rb`
- `appcast.xml`

Do not move or replace a published version tag. Fixes belong in a new patch
release. The appcast uses the immutable tag URL for its enclosure and the
stable `releases/latest/download/appcast.xml` URL as its feed.

The workflow:

1. Builds the universal app with Sparkle 2.9.4 embedded.
2. Signs Sparkle's nested helpers and framework from the inside out, then signs
   MagnetBridge; release signing must not use `codesign --deep`.
3. Notarizes and staples the final app.
4. Generates and verifies a signed appcast from the final ZIP and generated
   release notes.
5. Publishes all four assets and updates the Homebrew tap.

## Local release

Store notarization credentials once:

```sh
xcrun notarytool store-credentials magnetbridge-notary \
  --apple-id "developer@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then run:

```sh
VERSION=0.4.0 \
SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE=magnetbridge-notary \
SPARKLE_PRIVATE_KEY_FILE="/secure/path/magnetbridge-sparkle-key" \
scripts/release.sh
```

The script verifies both executable architectures, code-signing integrity,
notarization, stapling, Gatekeeper assessment, appcast XML, and its EdDSA
signature before writing the final artifacts to `release/`.

Export the local Sparkle key with the `generate_keys` tool from the resolved
Sparkle package. Restrict the exported file to the current user and remove the
working copy after the release; retain only the protected source and encrypted
backup.

## Post-release verification

- Download the ZIP, verify its published SHA-256, architectures, Developer ID
  signature, notarization ticket, and Gatekeeper assessment.
- Fetch `releases/latest/download/appcast.xml` and confirm it points to the new
  tagged ZIP with the expected short version and incremented build number.
- Run **Check for Updates…** from both Dock and menu-bar modes.
- Test an actual native upgrade between two signed, notarized Sparkle-enabled
  builds on Apple Silicon and Intel.

Versions installed before the first Sparkle-enabled release cannot bootstrap
the updater. Those users must install that release once through Homebrew, the
installer, or manual replacement.

## Homebrew tap

With `HOMEBREW_TAP_TOKEN` configured, the release workflow copies the generated
Cask to `decyrus/homebrew-tap` and commits it automatically. Test the published
Cask:

```sh
brew install --cask decyrus/tap/magnet-bridge
brew uninstall --cask magnet-bridge
```

The Cask declares `auto_updates true` because Sparkle can replace the app bundle
outside Homebrew. Keep this declaration while the in-app updater is present.

The automation design and required repository credential are documented in
[Homebrew distribution](Homebrew.md).
