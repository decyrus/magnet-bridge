import Foundation

public enum TorrentStartMode: String, Codable, CaseIterable, Sendable {
  case immediately
  case paused
}

public struct BrowserSelection: Codable, Equatable, Hashable, Sendable {
  public var bundleIdentifier: String?
  public var displayName: String

  public static let systemDefault = BrowserSelection(
    bundleIdentifier: nil,
    displayName: "System Default Browser"
  )

  public init(bundleIdentifier: String?, displayName: String) {
    self.bundleIdentifier = bundleIdentifier
    self.displayName = displayName
  }
}

public struct AppSettings: Codable, Equatable, Sendable {
  public var rpcURL: String
  public var webUIURL: String
  public var username: String
  public var browser: BrowserSelection
  public var timeout: TimeInterval
  public var opensWebUI: Bool
  public var startMode: TorrentStartMode
  public var hasAcknowledgedInsecureHTTP: Bool

  public static let defaults = AppSettings(
    rpcURL: "http://localhost:9091/transmission/rpc",
    webUIURL: "http://localhost:9091/transmission/web/",
    username: "",
    browser: .systemDefault,
    timeout: 15,
    opensWebUI: true,
    startMode: .immediately,
    hasAcknowledgedInsecureHTTP: false
  )

  public init(
    rpcURL: String,
    webUIURL: String,
    username: String,
    browser: BrowserSelection,
    timeout: TimeInterval,
    opensWebUI: Bool,
    startMode: TorrentStartMode,
    hasAcknowledgedInsecureHTTP: Bool
  ) {
    self.rpcURL = rpcURL
    self.webUIURL = webUIURL
    self.username = username
    self.browser = browser
    self.timeout = timeout
    self.opensWebUI = opensWebUI
    self.startMode = startMode
    self.hasAcknowledgedInsecureHTTP = hasAcknowledgedInsecureHTTP
  }
}

public struct TorrentSummary: Equatable, Sendable {
  public let id: Int?
  public let name: String
  public let hash: String?

  public init(id: Int?, name: String, hash: String?) {
    self.id = id
    self.name = name
    self.hash = hash
  }
}

public enum TorrentAddOutcome: Equatable, Sendable {
  case added(TorrentSummary)
  case duplicate(TorrentSummary)
}

public struct ConnectionInfo: Equatable, Sendable {
  public let version: String
  public let protocolVersion: String?
  public let protocolKind: TransmissionProtocol

  public init(
    version: String,
    protocolVersion: String?,
    protocolKind: TransmissionProtocol
  ) {
    self.version = version
    self.protocolVersion = protocolVersion
    self.protocolKind = protocolKind
  }
}

public enum TransmissionProtocol: String, Codable, Sendable {
  case legacy
  case jsonRPC2
}

public enum MagnetBridgeError: Error, Equatable, LocalizedError, Sendable {
  case invalidMagnet(String)
  case invalidRPCURL
  case insecureHTTPRequiresConfirmation
  case authenticationFailed
  case serverUnavailable
  case timedOut
  case serverError(Int)
  case invalidResponse
  case rpcError(String)
  case keychain(String)
  case browserUnavailable(String)

  public var errorDescription: String? {
    switch self {
    case .invalidMagnet(let reason):
      "Invalid magnet link: \(reason)"
    case .invalidRPCURL:
      "The Transmission RPC URL is invalid."
    case .insecureHTTPRequiresConfirmation:
      "This HTTP connection is not encrypted. Enable it in the CLI configuration."
    case .authenticationFailed:
      "Transmission rejected the username or password."
    case .serverUnavailable:
      "The Transmission server is unavailable."
    case .timedOut:
      "Transmission did not respond within the configured timeout."
    case .serverError(let status):
      "Transmission returned HTTP error \(status)."
    case .invalidResponse:
      "Transmission returned an invalid response."
    case .rpcError(let message):
      "Transmission error: \(message)"
    case .keychain:
      "The password could not be retrieved from Keychain."
    case .browserUnavailable(let name):
      "The browser “\(name)” is unavailable."
    }
  }
}
