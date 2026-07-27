import XCTest

@testable import MagnetBridgeCore

final class RPCAdapterTests: XCTestCase {
  func testLegacyAddedAndDuplicate() throws {
    let adapter = LegacyRPCAdapter()
    let added = Data(
      #"{"result":"success","arguments":{"torrent-added":{"id":7,"name":"Ubuntu","hashString":"abc"}}}"#
        .utf8)
    let duplicate = Data(
      #"{"result":"success","arguments":{"torrent-duplicate":{"id":7,"name":"Ubuntu","hashString":"abc"}}}"#
        .utf8)
    XCTAssertEqual(
      try adapter.parseAddResponse(added),
      .added(TorrentSummary(id: 7, name: "Ubuntu", hash: "abc"))
    )
    XCTAssertEqual(
      try adapter.parseAddResponse(duplicate),
      .duplicate(TorrentSummary(id: 7, name: "Ubuntu", hash: "abc"))
    )
  }

  func testJSONRPCAddedAndDuplicate() throws {
    let adapter = JSONRPCAdapter()
    let added = Data(
      #"{"jsonrpc":"2.0","id":1,"result":{"torrent_added":{"id":8,"name":"Fedora","hash_string":"def"}}}"#
        .utf8)
    let duplicate = Data(
      #"{"jsonrpc":"2.0","id":1,"result":{"torrent_duplicate":{"id":8,"name":"Fedora","hash_string":"def"}}}"#
        .utf8)
    XCTAssertEqual(
      try adapter.parseAddResponse(added),
      .added(TorrentSummary(id: 8, name: "Fedora", hash: "def"))
    )
    XCTAssertEqual(
      try adapter.parseAddResponse(duplicate),
      .duplicate(TorrentSummary(id: 8, name: "Fedora", hash: "def"))
    )
  }

  func testAdaptersEncodePausedAndCorrectMethodNames() throws {
    let url = try XCTUnwrap(
      URL(string: "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"))
    let legacy = try json(LegacyRPCAdapter().makeAddRequest(magnetURL: url, paused: true))
    XCTAssertEqual(legacy["method"] as? String, "torrent-add")
    XCTAssertEqual((legacy["arguments"] as? [String: Any])?["paused"] as? Bool, true)

    let modern = try json(JSONRPCAdapter().makeAddRequest(magnetURL: url, paused: false))
    XCTAssertEqual(modern["method"] as? String, "torrent_add")
    XCTAssertEqual(modern["jsonrpc"] as? String, "2.0")
    XCTAssertEqual((modern["params"] as? [String: Any])?["paused"] as? Bool, false)
  }

  func testInvalidJSONAndRPCErrorAreReported() {
    XCTAssertThrowsError(try LegacyRPCAdapter().parseAddResponse(Data("nope".utf8)))
    let error = Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-1,"message":"bad request"}}"#.utf8)
    XCTAssertThrowsError(try JSONRPCAdapter().parseAddResponse(error))
  }

  private func json(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
