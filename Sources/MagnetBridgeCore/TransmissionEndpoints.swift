import Foundation

public struct TransmissionEndpoints: Equatable, Sendable {
  public let serverAddress: String
  public let rpcURL: String
  public let webUIURL: String

  public init(serverAddress: String, rpcURL: String, webUIURL: String) {
    self.serverAddress = serverAddress
    self.rpcURL = rpcURL
    self.webUIURL = webUIURL
  }
}

public enum TransmissionEndpointResolver {
  public static let rpcPath = "/transmission/rpc"
  public static let webUIPath = "/transmission/web/"

  /// Whether both URLs still end in the standard Transmission paths, meaning
  /// the server address on its own describes them.
  public static func usesStandardPaths(rpcURL: String, webUIURL: String) -> Bool {
    rpcURL.hasSuffix(rpcPath) && webUIURL.hasSuffix(webUIPath)
  }

  public static func resolve(serverAddress rawAddress: String) throws
    -> TransmissionEndpoints
  {
    let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      var components = URLComponents(string: address),
      ["http", "https"].contains(components.scheme?.lowercased()),
      components.host != nil,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/"
    else {
      throw MagnetBridgeError.invalidRPCURL
    }

    components.scheme = components.scheme?.lowercased()
    components.percentEncodedPath = ""
    guard let normalizedAddress = components.url?.absoluteString else {
      throw MagnetBridgeError.invalidRPCURL
    }

    components.percentEncodedPath = rpcPath
    guard let rpcURL = components.url?.absoluteString else {
      throw MagnetBridgeError.invalidRPCURL
    }

    components.percentEncodedPath = webUIPath
    guard let webUIURL = components.url?.absoluteString else {
      throw MagnetBridgeError.invalidRPCURL
    }

    return TransmissionEndpoints(
      serverAddress: normalizedAddress,
      rpcURL: rpcURL,
      webUIURL: webUIURL
    )
  }

  public static func serverAddress(fromRPCURL rawURL: String) -> String? {
    guard
      var components = URLComponents(string: rawURL),
      ["http", "https"].contains(components.scheme?.lowercased()),
      components.host != nil
    else {
      return nil
    }
    components.user = nil
    components.password = nil
    components.percentEncodedPath = ""
    components.query = nil
    components.fragment = nil
    return components.url?.absoluteString
  }
}
