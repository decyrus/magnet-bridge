import Foundation
import XCTest

@testable import MagnetBridgeCore

final class TransmissionClientTests: XCTestCase {
  private let rpcURL = URL(string: "https://transmission.example/rpc")!
  private let magnetURL = URL(
    string: "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567")!

  func testRetries409AndUsesLegacyProtocol() async throws {
    let session = ScriptedSession([
      .response(status: 409, headers: ["X-Transmission-Session-Id": "old-session"]),
      .response(
        status: 200,
        body:
          #"{"result":"success","arguments":{"torrent-added":{"id":1,"name":"One","hashString":"a"}}}"#
      ),
    ])
    let client = makeClient(session: session)
    let result = try await client.add(magnetURL: magnetURL, paused: false)
    XCTAssertEqual(result, .added(TorrentSummary(id: 1, name: "One", hash: "a")))
    let requests = await session.requests
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(
      requests[1].value(forHTTPHeaderField: "X-Transmission-Session-Id"), "old-session")
    XCTAssertEqual(try method(in: requests[1]), "torrent-add")
  }

  func testNegotiatesJSONRPC2From409Header() async throws {
    let session = ScriptedSession([
      .response(
        status: 409,
        headers: [
          "X-Transmission-Session-Id": "new-session",
          "X-Transmission-Rpc-Version": "6.0.0",
        ]
      ),
      .response(
        status: 200,
        body:
          #"{"jsonrpc":"2.0","id":1,"result":{"torrent_duplicate":{"id":2,"name":"Two","hash_string":"b"}}}"#
      ),
    ])
    let client = makeClient(session: session)
    let result = try await client.add(magnetURL: magnetURL, paused: true)
    XCTAssertEqual(result, .duplicate(TorrentSummary(id: 2, name: "Two", hash: "b")))
    let requests = await session.requests
    XCTAssertEqual(try method(in: requests[1]), "torrent_add")
  }

  func testConnectionReturnsServerVersion() async throws {
    let session = ScriptedSession([
      .response(
        status: 409,
        headers: [
          "X-Transmission-Session-Id": "new",
          "X-Transmission-Rpc-Version": "6.0.1",
        ]
      ),
      .response(
        status: 200,
        body: #"{"jsonrpc":"2.0","id":1,"result":{"version":"4.1.1","rpc_version_semver":"6.0.1"}}"#
      ),
    ])
    let client = makeClient(session: session)
    let info = try await client.testConnection()
    XCTAssertEqual(
      info,
      ConnectionInfo(version: "4.1.1", protocolVersion: "6.0.1", protocolKind: .jsonRPC2)
    )
  }

  func testBasicAuthentication() async throws {
    let session = ScriptedSession([
      .response(
        status: 200,
        body: #"{"result":"success","arguments":{"torrent-added":{"id":1,"name":"One"}}}"#
      )
    ])
    let client = TransmissionClient(
      configuration: TransmissionConfiguration(
        rpcURL: rpcURL,
        username: "alice",
        password: "secret",
        timeout: 2,
        allowsInsecureHTTP: false
      ),
      session: session
    )
    _ = try await client.add(magnetURL: magnetURL, paused: false)
    let requests = await session.requests
    XCTAssertEqual(
      requests[0].value(forHTTPHeaderField: "Authorization"),
      "Basic \(Data("alice:secret".utf8).base64EncodedString())"
    )
  }

  func testHTTPStatusesAreMapped() async {
    for (status, expected) in [
      (401, MagnetBridgeError.authenticationFailed),
      (403, MagnetBridgeError.authenticationFailed),
      (404, MagnetBridgeError.serverError(404)),
      (500, MagnetBridgeError.serverError(500)),
      (503, MagnetBridgeError.serverError(503)),
    ] {
      let client = makeClient(session: ScriptedSession([.response(status: status)]))
      do {
        _ = try await client.add(magnetURL: magnetURL, paused: false)
        XCTFail("Expected \(expected)")
      } catch let error as MagnetBridgeError {
        XCTAssertEqual(error, expected)
      } catch {
        XCTFail("Unexpected error \(error)")
      }
    }
  }

  func testTimeoutAndUnavailableAreMapped() async {
    for (code, expected) in [
      (URLError.timedOut, MagnetBridgeError.timedOut),
      (URLError.cannotConnectToHost, MagnetBridgeError.serverUnavailable),
    ] {
      let client = makeClient(session: ScriptedSession([.failure(code)]))
      do {
        _ = try await client.add(magnetURL: magnetURL, paused: false)
        XCTFail("Expected \(expected)")
      } catch let error as MagnetBridgeError {
        XCTAssertEqual(error, expected)
      } catch {
        XCTFail("Unexpected error \(error)")
      }
    }
  }

  func testInsecureHTTPNeedsAcknowledgement() async {
    let client = TransmissionClient(
      configuration: TransmissionConfiguration(
        rpcURL: URL(string: "http://example.com/rpc")!,
        username: "",
        password: nil,
        timeout: 1,
        allowsInsecureHTTP: false
      ),
      session: ScriptedSession([])
    )
    do {
      _ = try await client.add(magnetURL: magnetURL, paused: false)
      XCTFail("Expected warning")
    } catch let error as MagnetBridgeError {
      XCTAssertEqual(error, .insecureHTTPRequiresConfirmation)
    } catch {
      XCTFail("Unexpected error \(error)")
    }
  }

  private func makeClient(session: ScriptedSession) -> TransmissionClient {
    TransmissionClient(
      configuration: TransmissionConfiguration(
        rpcURL: rpcURL,
        username: "",
        password: nil,
        timeout: 2,
        allowsInsecureHTTP: false
      ),
      session: session
    )
  }

  private func method(in request: URLRequest) throws -> String {
    let body = try XCTUnwrap(request.httpBody)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    return try XCTUnwrap(object["method"] as? String)
  }
}

private actor ScriptedSession: NetworkSession {
  enum Item: Sendable {
    case response(status: Int, body: String = "", headers: [String: String] = [:])
    case failure(URLError.Code)
  }

  private var items: [Item]
  private(set) var requests: [URLRequest] = []

  init(_ items: [Item]) {
    self.items = items
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    guard !items.isEmpty else {
      throw URLError(.badServerResponse)
    }
    let item = items.removeFirst()
    switch item {
    case .failure(let code):
      throw URLError(code)
    case .response(let status, let body, let headers):
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
      )!
      return (Data(body.utf8), response)
    }
  }
}
