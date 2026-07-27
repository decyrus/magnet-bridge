# Contributing

Thank you for improving MagnetBridge.

## Development

1. Install Xcode 16+ and XcodeGen.
2. Run `xcodegen generate`.
3. Run `swift test`.
4. Build and test the `MagnetBridge` scheme in Debug and Release.
5. Run `xcrun swift-format lint --recursive --strict Sources Tests`.

Keep networking and business logic in `MagnetBridgeCore`; the headless app and
CLI should only orchestrate injected services. Do not add configuration windows
or other GUI settings. Add tests for changes to validation, RPC messages, error
mapping, credential handling, browser launching, CLI configuration, or
redaction.

Never include real credentials, private server addresses, full magnet links, or
downloaded torrent metadata in issues, fixtures, snapshots, or logs.

Pull requests should explain the user-visible behavior, test coverage, and any
security implications. By contributing, you agree that your contribution is
licensed under the MIT License.
