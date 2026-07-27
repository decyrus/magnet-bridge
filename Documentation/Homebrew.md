# Homebrew distribution

MagnetBridge is a native macOS application, so Homebrew distributes it as a
Cask rather than a Formula.

## Project tap

The public
[`decyrus/homebrew-tap`](https://github.com/decyrus/homebrew-tap) repository
contains:

```text
Casks/
└── magnet-bridge.rb
```

Homebrew maps the repository name `homebrew-tap` to the short tap name
`decyrus/tap`. Users can then install MagnetBridge without downloading a script:

```sh
brew install --cask decyrus/tap/magnet-bridge
```

The fully qualified command automatically adds the tap. A separate
`brew tap decyrus/tap` command is not required.

## Release automation

Each MagnetBridge release generates a checksum-pinned `magnet-bridge.rb`. The
release workflow updates the tap automatically when `HOMEBREW_TAP_TOKEN` is
configured:

1. Build the universal app with Sparkle, then sign, notarize, and staple it.
2. Create `MagnetBridge.zip` and calculate SHA-256.
3. Generate and verify the EdDSA-signed `appcast.xml`.
4. Publish the GitHub release.
5. Update `Casks/magnet-bridge.rb` in `decyrus/homebrew-tap`.
6. Commit the new version and checksum to the tap.

Because the tap is a different repository, this step needs either a GitHub App
or a fine-grained token with Contents write access to only
`decyrus/homebrew-tap`. Store it as `HOMEBREW_TAP_TOKEN`; do not use a
developer's broad personal token. The workflow emits a warning and leaves the
published Cask unchanged when the secret is absent.

## In-app updates

The Cask declares `auto_updates true` because MagnetBridge can download and
install a release through Sparkle's **Check for Updates…** action. Homebrew can
therefore account for a bundle changed outside its own installation record.

MagnetBridge keeps a fixed Cask version and checksum. For a versioned Cask with
a readable application bundle, Homebrew compares the installed bundle version
to the current Cask and avoids downgrading a copy that Sparkle has already
updated. Users may use either the in-app updater or:

```sh
brew update
brew upgrade --cask magnet-bridge
```

Do not remove `auto_updates true` while the native updater is present. Continue
publishing checksum-pinned Casks even though later in-app updates are
authenticated independently by Sparkle and Developer ID.

## Official Homebrew Cask

Submitting directly to `Homebrew/homebrew-cask` is a later milestone. Homebrew's
acceptance rules expect a brand-new application to demonstrate independently
verifiable public interest. MagnetBridge should first build a release history
and real usage through its own tap.

Before submitting upstream, keep these requirements true:

- releases are versioned and hosted at stable public URLs;
- the app is signed, notarized, and accepted by Gatekeeper;
- the Cask has a fixed version and SHA-256;
- uninstall and `zap` behavior are documented and tested;
- the project has an active maintenance history.

Official references:

- [How to Create and Maintain a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [Adding Software to Homebrew](https://docs.brew.sh/Adding-Software-to-Homebrew)
- [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)
