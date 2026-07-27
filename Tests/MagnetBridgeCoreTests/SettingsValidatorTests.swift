import XCTest

@testable import MagnetBridgeCore

final class SettingsValidatorTests: XCTestCase {
  private let validator = SettingsValidator()

  func testTrimsURLsAndUsername() throws {
    var input = makeSettings(
      rpcURL: "  https://example.com/transmission/rpc  ",
      webUIURL: "\thttps://example.com/transmission/web/\n"
    )
    input.usesAuthentication = true
    input.username = "  alice  "

    let validated = try validator.validated(input)

    XCTAssertEqual(validated.rpcURL, "https://example.com/transmission/rpc")
    XCTAssertEqual(validated.webUIURL, "https://example.com/transmission/web/")
    XCTAssertEqual(validated.username, "alice")
  }

  func testRejectsCredentialsInTheRPCURL() {
    assertRejects(
      makeSettings(rpcURL: "https://alice:secret@example.com/transmission/rpc"),
      with: .invalidRPCURL
    )
  }

  func testRejectsAnUnsupportedRPCScheme() {
    assertRejects(makeSettings(rpcURL: "ftp://example.com/rpc"), with: .invalidRPCURL)
  }

  func testRejectsAnInvalidWebUIURL() {
    assertRejects(makeSettings(webUIURL: "example.com"), with: .invalidWebUIURL)
  }

  func testRejectsTimeoutsOutsideTheAllowedRange() {
    var tooShort = makeSettings()
    tooShort.timeout = SettingsValidator.allowedTimeouts.lowerBound - 1
    assertRejects(tooShort, with: .invalidTimeout)

    var tooLong = makeSettings()
    tooLong.timeout = SettingsValidator.allowedTimeouts.upperBound + 1
    assertRejects(tooLong, with: .invalidTimeout)
  }

  func testRequiresAUsernameWhenAuthenticationIsEnabled() {
    var input = makeSettings()
    input.usesAuthentication = true
    input.username = "   "
    assertRejects(input, with: .missingUsername)
  }

  func testRequiresAcknowledgementForHTTP() {
    var input = makeSettings(
      rpcURL: "http://example.com/transmission/rpc",
      webUIURL: "http://example.com/transmission/web/"
    )
    assertRejects(input, with: .insecureHTTPRequiresConfirmation)

    input.hasAcknowledgedInsecureHTTP = true
    XCTAssertNoThrow(try validator.validated(input))
  }

  private func makeSettings(
    rpcURL: String = "https://example.com/transmission/rpc",
    webUIURL: String = "https://example.com/transmission/web/"
  ) -> AppSettings {
    var settings = AppSettings.defaults
    settings.rpcURL = rpcURL
    settings.webUIURL = webUIURL
    return settings
  }

  private func assertRejects(
    _ settings: AppSettings,
    with expected: MagnetBridgeError,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try validator.validated(settings), file: file, line: line) {
      error in
      XCTAssertEqual(error as? MagnetBridgeError, expected, file: file, line: line)
    }
  }
}
