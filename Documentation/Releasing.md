# Releasing

Tagged releases are universal (`arm64` + `x86_64`), signed with Developer ID,
notarized, stapled, and published as a ZIP with a SHA-256 checksum. The release
also contains a checksum-pinned Homebrew Cask.

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
| `HOMEBREW_TAP_TOKEN` | Fine-grained token with Contents write access only to `decyrus/homebrew-tap` |

Create a release by pushing a semantic version tag:

```sh
git tag -a v0.3.1 -m "MagnetBridge v0.3.1"
git push origin v0.3.1
```

The workflow fails rather than publishing an unsigned or unnotarized archive.
After it succeeds, verify that the GitHub release contains:

- `MagnetBridge.zip`
- `MagnetBridge.zip.sha256`
- `magnet-bridge.rb`

Do not move or replace a published version tag. Fixes belong in a new patch
release.

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
VERSION=0.3.1 \
SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE=magnetbridge-notary \
scripts/release.sh
```

The script verifies both executable architectures, code-signing integrity,
notarization, stapling, and Gatekeeper assessment before writing anything to
`release/`.

## Homebrew tap

With `HOMEBREW_TAP_TOKEN` configured, the release workflow copies the generated
Cask to `decyrus/homebrew-tap` and commits it automatically. Test the published
Cask:

```sh
brew install --cask decyrus/tap/magnet-bridge
brew uninstall --cask magnet-bridge
```

The automation design and required repository credential are documented in
[Homebrew distribution](Homebrew.md).
