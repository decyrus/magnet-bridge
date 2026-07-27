import Foundation

public protocol TransmissionRPCAdapting: Sendable {
  var protocolKind: TransmissionProtocol { get }
  func makeAddRequest(magnetURL: URL, paused: Bool) throws -> Data
  func makeSessionRequest() throws -> Data
  func parseAddResponse(_ data: Data) throws -> TorrentAddOutcome
  func parseSessionResponse(_ data: Data) throws -> ConnectionInfo
}

public struct LegacyRPCAdapter: TransmissionRPCAdapting {
  public let protocolKind = TransmissionProtocol.legacy

  public init() {}

  public func makeAddRequest(magnetURL: URL, paused: Bool) throws -> Data {
    try encode([
      "method": "torrent-add",
      "arguments": [
        "filename": magnetURL.absoluteString,
        "paused": paused,
      ],
    ])
  }

  public func makeSessionRequest() throws -> Data {
    try encode([
      "method": "session-get",
      "arguments": [
        "fields": ["version", "rpc-version-semver"]
      ],
    ])
  }

  public func parseAddResponse(_ data: Data) throws -> TorrentAddOutcome {
    let root = try dictionary(data)
    guard root["result"] as? String == "success",
      let arguments = root["arguments"] as? [String: Any]
    else {
      if let result = root["result"] as? String {
        throw MagnetBridgeError.rpcError(result)
      }
      throw MagnetBridgeError.invalidResponse
    }
    if let added = arguments["torrent-added"] as? [String: Any] {
      return .added(try summary(added, hashKey: "hashString"))
    }
    if let duplicate = arguments["torrent-duplicate"] as? [String: Any] {
      return .duplicate(try summary(duplicate, hashKey: "hashString"))
    }
    throw MagnetBridgeError.invalidResponse
  }

  public func parseSessionResponse(_ data: Data) throws -> ConnectionInfo {
    let root = try dictionary(data)
    guard root["result"] as? String == "success",
      let arguments = root["arguments"] as? [String: Any],
      let version = arguments["version"] as? String
    else {
      if let result = root["result"] as? String {
        throw MagnetBridgeError.rpcError(result)
      }
      throw MagnetBridgeError.invalidResponse
    }
    return ConnectionInfo(
      version: version,
      protocolVersion: arguments["rpc-version-semver"] as? String,
      protocolKind: .legacy
    )
  }
}

public struct JSONRPCAdapter: TransmissionRPCAdapting {
  public let protocolKind = TransmissionProtocol.jsonRPC2
  private let requestID: Int

  public init(requestID: Int = 1) {
    self.requestID = requestID
  }

  public func makeAddRequest(magnetURL: URL, paused: Bool) throws -> Data {
    try encode([
      "jsonrpc": "2.0",
      "method": "torrent_add",
      "params": [
        "filename": magnetURL.absoluteString,
        "paused": paused,
      ],
      "id": requestID,
    ])
  }

  public func makeSessionRequest() throws -> Data {
    try encode([
      "jsonrpc": "2.0",
      "method": "session_get",
      "params": [
        "fields": ["version", "rpc_version_semver"]
      ],
      "id": requestID,
    ])
  }

  public func parseAddResponse(_ data: Data) throws -> TorrentAddOutcome {
    let root = try dictionary(data)
    if let error = root["error"] as? [String: Any] {
      throw MagnetBridgeError.rpcError(
        error["message"] as? String ?? "JSON-RPC error"
      )
    }
    guard let result = root["result"] as? [String: Any] else {
      throw MagnetBridgeError.invalidResponse
    }
    if let added = result["torrent_added"] as? [String: Any] {
      return .added(try summary(added, hashKey: "hash_string"))
    }
    if let duplicate = result["torrent_duplicate"] as? [String: Any] {
      return .duplicate(try summary(duplicate, hashKey: "hash_string"))
    }
    throw MagnetBridgeError.invalidResponse
  }

  public func parseSessionResponse(_ data: Data) throws -> ConnectionInfo {
    let root = try dictionary(data)
    if let error = root["error"] as? [String: Any] {
      throw MagnetBridgeError.rpcError(
        error["message"] as? String ?? "JSON-RPC error"
      )
    }
    guard
      let result = root["result"] as? [String: Any],
      let version = result["version"] as? String
    else {
      throw MagnetBridgeError.invalidResponse
    }
    return ConnectionInfo(
      version: version,
      protocolVersion: result["rpc_version_semver"] as? String,
      protocolKind: .jsonRPC2
    )
  }
}

private func encode(_ object: [String: Any]) throws -> Data {
  do {
    return try JSONSerialization.data(withJSONObject: object)
  } catch {
    throw MagnetBridgeError.invalidResponse
  }
}

private func dictionary(_ data: Data) throws -> [String: Any] {
  do {
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw MagnetBridgeError.invalidResponse
    }
    return value
  } catch let error as MagnetBridgeError {
    throw error
  } catch {
    throw MagnetBridgeError.invalidResponse
  }
}

private func summary(_ object: [String: Any], hashKey: String) throws -> TorrentSummary {
  guard let name = object["name"] as? String else {
    throw MagnetBridgeError.invalidResponse
  }
  let id: Int?
  if let number = object["id"] as? NSNumber {
    id = number.intValue
  } else {
    id = nil
  }
  return TorrentSummary(id: id, name: name, hash: object[hashKey] as? String)
}
