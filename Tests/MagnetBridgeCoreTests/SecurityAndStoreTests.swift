import XCTest

@testable import MagnetBridgeCore

final class SecurityAndStoreTests: XCTestCase {
  func testRedactorRemovesMagnetAndSecrets() {
    let source = "open magnet:?xt=urn:btih:0123456789abcdef user secret-password now"
    let result = SecretRedactor().redact(source, secrets: ["secret-password"])
    XCTAssertFalse(result.contains("0123456789abcdef"))
    XCTAssertFalse(result.contains("secret-password"))
    XCTAssertTrue(result.contains("magnet:[REDACTED]"))
  }

  func testSettingsRoundTripContainsNoPasswordField() throws {
    let suite = "MagnetBridgeTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SettingsStore(defaults: defaults)
    var settings = AppSettings.defaults
    settings.username = "alice"
    settings.rpcURL = "https://example.com/rpc"
    try store.save(settings)
    XCTAssertEqual(store.load(), settings)
    let encoded = try JSONEncoder().encode(settings)
    XCTAssertFalse(String(decoding: encoded, as: UTF8.self).lowercased().contains("password"))
  }

  func testDiagnosticsContainsHostsButNotFullURLsOrMagnet() {
    var settings = AppSettings.defaults
    settings.rpcURL = "https://user@example.com/private/rpc?token=secret"
    settings.webUIURL = "https://example.com/private/web"
    let report = DiagnosticsService().report(
      settings: settings,
      recentMessages: ["failed magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"]
    )
    XCTAssertTrue(report.contains("RPC host: example.com"))
    XCTAssertFalse(report.contains("token=secret"))
    XCTAssertFalse(report.contains("0123456789abcdef"))
  }
}
