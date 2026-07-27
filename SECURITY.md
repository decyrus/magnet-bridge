# Security Policy

## Supported versions

Security fixes are applied to the latest released version.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability involving credential
exposure, URL handling, authentication, TLS, code signing, or release
integrity. Use GitHub's private vulnerability reporting for this repository.
Include reproduction steps and impact, but remove passwords and full magnet
links.

## Security model

- The Transmission password is stored in macOS Keychain and never in
  `UserDefaults`.
- Only `magnet:` URLs up to 32 KiB with a supported `xt` value are accepted.
- Incoming links are sent as JSON over `URLSession`; no shell command receives
  user-controlled URL content.
- HTTPS uses the system trust store. HTTP requires explicit acknowledgement.
- Diagnostics redact full magnet links and never include passwords.
- Release archives are signed with Developer ID, notarized by Apple, and
  published with SHA-256 checksums.
- Telemetry is disabled because no telemetry code is included.

Use a VPN or Tailscale for remote Transmission access. Do not expose its RPC
port directly to the public internet.
