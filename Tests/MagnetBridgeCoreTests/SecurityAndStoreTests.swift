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

  func testSettingsFromOlderReleaseEnablesMenuBarByDefault() throws {
    let currentData = try JSONEncoder().encode(AppSettings.defaults)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: currentData) as? [String: Any]
    )
    object.removeValue(forKey: "showsMenuBarIcon")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)

    XCTAssertTrue(decoded.showsMenuBarIcon)
  }

  func testSettingsFromOlderReleaseInfersAuthenticationFromUsername() throws {
    var configured = AppSettings.defaults
    configured.username = "alice"
    configured.usesAuthentication = true
    let currentData = try JSONEncoder().encode(configured)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: currentData) as? [String: Any]
    )
    object.removeValue(forKey: "usesAuthentication")

    let authenticatedData = try JSONSerialization.data(withJSONObject: object)
    let authenticated = try JSONDecoder().decode(AppSettings.self, from: authenticatedData)
    XCTAssertTrue(authenticated.usesAuthentication)

    object["username"] = ""
    let unauthenticatedData = try JSONSerialization.data(withJSONObject: object)
    let unauthenticated = try JSONDecoder().decode(AppSettings.self, from: unauthenticatedData)
    XCTAssertFalse(unauthenticated.usesAuthentication)
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
