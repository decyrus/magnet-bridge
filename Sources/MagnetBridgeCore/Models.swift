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
  public var usesAuthentication: Bool
  public var browser: BrowserSelection
  public var timeout: TimeInterval
  public var opensWebUI: Bool
  public var startMode: TorrentStartMode
  public var hasAcknowledgedInsecureHTTP: Bool
  public var showsMenuBarIcon: Bool

  public static let defaults = AppSettings(
    rpcURL: "http://localhost:9091/transmission/rpc",
    webUIURL: "http://localhost:9091/transmission/web/",
    username: "",
    usesAuthentication: false,
    browser: .systemDefault,
    timeout: 15,
    opensWebUI: true,
    startMode: .immediately,
    hasAcknowledgedInsecureHTTP: false,
    showsMenuBarIcon: true
  )

  public init(
    rpcURL: String,
    webUIURL: String,
    username: String,
    usesAuthentication: Bool? = nil,
    browser: BrowserSelection,
    timeout: TimeInterval,
    opensWebUI: Bool,
    startMode: TorrentStartMode,
    hasAcknowledgedInsecureHTTP: Bool,
    showsMenuBarIcon: Bool = true
  ) {
    self.rpcURL = rpcURL
    self.webUIURL = webUIURL
    self.username = username
    self.usesAuthentication = usesAuthentication ?? !username.isEmpty
    self.browser = browser
    self.timeout = timeout
    self.opensWebUI = opensWebUI
    self.startMode = startMode
    self.hasAcknowledgedInsecureHTTP = hasAcknowledgedInsecureHTTP
    self.showsMenuBarIcon = showsMenuBarIcon
  }

  private enum CodingKeys: String, CodingKey {
    case rpcURL
    case webUIURL
    case username
    case usesAuthentication
    case browser
    case timeout
    case opensWebUI
    case startMode
    case hasAcknowledgedInsecureHTTP
    case showsMenuBarIcon
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    rpcURL = try container.decode(String.self, forKey: .rpcURL)
    webUIURL = try container.decode(String.self, forKey: .webUIURL)
    username = try container.decode(String.self, forKey: .username)
    usesAuthentication =
      try container.decodeIfPresent(Bool.self, forKey: .usesAuthentication)
      ?? !username.isEmpty
    browser = try container.decode(BrowserSelection.self, forKey: .browser)
    timeout = try container.decode(TimeInterval.self, forKey: .timeout)
    opensWebUI = try container.decode(Bool.self, forKey: .opensWebUI)
    startMode = try container.decode(TorrentStartMode.self, forKey: .startMode)
    hasAcknowledgedInsecureHTTP = try container.decode(
      Bool.self,
      forKey: .hasAcknowledgedInsecureHTTP
    )
    showsMenuBarIcon =
      try container.decodeIfPresent(Bool.self, forKey: .showsMenuBarIcon) ?? true
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(rpcURL, forKey: .rpcURL)
    try container.encode(webUIURL, forKey: .webUIURL)
    try container.encode(username, forKey: .username)
    try container.encode(usesAuthentication, forKey: .usesAuthentication)
    try container.encode(browser, forKey: .browser)
    try container.encode(timeout, forKey: .timeout)
    try container.encode(opensWebUI, forKey: .opensWebUI)
    try container.encode(startMode, forKey: .startMode)
    try container.encode(
      hasAcknowledgedInsecureHTTP,
      forKey: .hasAcknowledgedInsecureHTTP
    )
    try container.encode(showsMenuBarIcon, forKey: .showsMenuBarIcon)
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

  public var displayName: String {
    switch self {
    case .legacy:
      "legacy RPC"
    case .jsonRPC2:
      "JSON-RPC 2.0"
    }
  }
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
      "This HTTP connection is not encrypted. Allow HTTP in MagnetBridge settings first."
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
