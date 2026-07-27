import XCTest

@testable import MagnetBridgeCore

final class TransmissionEndpointResolverTests: XCTestCase {
  func testBuildsStandardPathsFromHTTPSAddress() throws {
    let endpoints = try TransmissionEndpointResolver.resolve(
      serverAddress: "https://transmission.example"
    )

    XCTAssertEqual(endpoints.serverAddress, "https://transmission.example")
    XCTAssertEqual(endpoints.rpcURL, "https://transmission.example/transmission/rpc")
    XCTAssertEqual(endpoints.webUIURL, "https://transmission.example/transmission/web/")
  }

  func testPreservesHTTPAndPort() throws {
    let endpoints = try TransmissionEndpointResolver.resolve(
      serverAddress: "http://192.0.2.10:9091/"
    )

    XCTAssertEqual(endpoints.serverAddress, "http://192.0.2.10:9091")
    XCTAssertEqual(endpoints.rpcURL, "http://192.0.2.10:9091/transmission/rpc")
    XCTAssertEqual(endpoints.webUIURL, "http://192.0.2.10:9091/transmission/web/")
  }

  func testRejectsPathCredentialsQueryAndUnsupportedScheme() {
    for address in [
      "https://example.com/custom",
      "https://alice:secret@example.com",
      "https://example.com?token=secret",
      "ftp://example.com",
      "example.com",
    ] {
      XCTAssertThrowsError(
        try TransmissionEndpointResolver.resolve(serverAddress: address),
        "Expected \(address) to be rejected"
      )
    }
  }

  func testDetectsStandardAndCustomPaths() throws {
    let endpoints = try TransmissionEndpointResolver.resolve(
      serverAddress: "https://example.com:9091"
    )
    XCTAssertTrue(
      TransmissionEndpointResolver.usesStandardPaths(
        rpcURL: endpoints.rpcURL,
        webUIURL: endpoints.webUIURL
      )
    )
    XCTAssertFalse(
      TransmissionEndpointResolver.usesStandardPaths(
        rpcURL: "https://example.com:9091/custom/rpc",
        webUIURL: endpoints.webUIURL
      )
    )
    XCTAssertFalse(
      TransmissionEndpointResolver.usesStandardPaths(
        rpcURL: endpoints.rpcURL,
        webUIURL: "https://example.com:9091/custom/web/"
      )
    )
  }

  func testExtractsServerAddressFromRPCURL() {
    XCTAssertEqual(
      TransmissionEndpointResolver.serverAddress(
        fromRPCURL: "https://example.com:9443/transmission/rpc"
      ),
      "https://example.com:9443"
    )
  }
}
