# Contributing

Thank you for improving MagnetBridge.

## Development

1. Install Xcode 16+ and XcodeGen.
2. Run `xcodegen generate`.
3. Run `swift test`.
4. Build and test the `MagnetBridge` scheme in Debug and Release.
5. Run `xcrun swift-format lint --recursive --strict Sources Tests`.

Keep networking and business logic in `MagnetBridgeCore`; SwiftUI views, the
menu bar controller, and the optional CLI should only orchestrate injected
services. Keep views small and move asynchronous work into `AppModel`. Add tests
for changes to validation, RPC messages, error mapping, credential handling,
browser launching, settings migration, CLI configuration, or redaction.

Never include real credentials, private server addresses, full magnet links, or
downloaded torrent metadata in issues, fixtures, snapshots, or logs.

Pull requests should explain the user-visible behavior, test coverage, and any
security implications. By contributing, you agree that your contribution is
licensed under the MIT License.
