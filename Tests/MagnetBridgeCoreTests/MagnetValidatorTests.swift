import XCTest

@testable import MagnetBridgeCore

final class MagnetValidatorTests: XCTestCase {
  private let validator = MagnetValidator()

  func testAcceptsBTIHHex() throws {
    let url = try XCTUnwrap(
      URL(string: "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Ubuntu"))
    let result = try validator.validate(url)
    XCTAssertEqual(result.infoHashes, ["0123456789abcdef0123456789abcdef01234567"])
  }

  func testAcceptsBTIHBase32() throws {
    let url = try XCTUnwrap(URL(string: "magnet:?xt=urn:btih:ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"))
    XCTAssertNoThrow(try validator.validate(url))
  }

  func testAcceptsBTMH() throws {
    let url = try XCTUnwrap(
      URL(
        string:
          "magnet:?xt=urn:btmh:12200123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
      ))
    XCTAssertNoThrow(try validator.validate(url))
  }

  func testRejectsWrongScheme() throws {
    let url = try XCTUnwrap(URL(string: "https://example.com/file"))
    XCTAssertThrowsError(try validator.validate(url))
  }

  func testRejectsMissingExactTopic() throws {
    let url = try XCTUnwrap(URL(string: "magnet:?dn=NoHash"))
    XCTAssertThrowsError(try validator.validate(url))
  }

  func testRejectsMalformedBTIH() throws {
    let url = try XCTUnwrap(URL(string: "magnet:?xt=urn:btih:not-a-hash"))
    XCTAssertThrowsError(try validator.validate(url))
  }

  func testRejectsOversizedURL() throws {
    let raw =
      "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn="
      + String(repeating: "a", count: MagnetValidator.maximumLength)
    let url = try XCTUnwrap(URL(string: raw))
    XCTAssertThrowsError(try validator.validate(url))
  }
}
