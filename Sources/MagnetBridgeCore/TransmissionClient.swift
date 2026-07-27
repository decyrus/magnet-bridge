import Foundation

public protocol NetworkSession: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionNetworkSession: NetworkSession, @unchecked Sendable {
  private let session: URLSession

  public init(configuration: URLSessionConfiguration = .ephemeral) {
    self.session = URLSession(configuration: configuration)
  }

  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw MagnetBridgeError.invalidResponse
    }
    return (data, http)
  }
}

public struct TransmissionConfiguration: Equatable, Sendable {
  public let rpcURL: URL
  public let username: String
  public let password: String?
  public let timeout: TimeInterval
  public let allowsInsecureHTTP: Bool

  public init(
    rpcURL: URL,
    username: String,
    password: String?,
    timeout: TimeInterval,
    allowsInsecureHTTP: Bool
  ) {
    self.rpcURL = rpcURL
    self.username = username
    self.password = password
    self.timeout = timeout
    self.allowsInsecureHTTP = allowsInsecureHTTP
  }

  /// Builds the configuration described by `settings`.
  ///
  /// Credentials are carried only while Basic Authentication is enabled, so a
  /// disabled toggle cannot put a stored username or password on the wire.
  public init(settings: AppSettings, password: String?) throws {
    guard let rpcURL = URL(string: settings.rpcURL) else {
      throw MagnetBridgeError.invalidRPCURL
    }
    self.init(
      rpcURL: rpcURL,
      username: settings.usesAuthentication ? settings.username : "",
      password: settings.usesAuthentication ? password : nil,
      timeout: settings.timeout,
      allowsInsecureHTTP: settings.hasAcknowledgedInsecureHTTP
    )
  }
}

public actor TransmissionClient {
  private static let maximumAttempts = 3

  private let configuration: TransmissionConfiguration
  private let session: any NetworkSession
  private var sessionID: String?
  private var negotiatedProtocol: TransmissionProtocol?

  public init(
    configuration: TransmissionConfiguration,
    session: any NetworkSession = URLSessionNetworkSession()
  ) {
    self.configuration = configuration
    self.session = session
  }

  public func add(magnetURL: URL, paused: Bool) async throws -> TorrentAddOutcome {
    try await negotiating(
      request: { try $0.makeAddRequest(magnetURL: magnetURL, paused: paused) },
      response: { try $0.parseAddResponse($1) }
    )
  }

  public func testConnection() async throws -> ConnectionInfo {
    try await negotiating(
      request: { try $0.makeSessionRequest() },
      response: { try $0.parseSessionResponse($1) }
    )
  }

  /// Sends a request built by the adapter for the protocol negotiated so far,
  /// retrying while Transmission answers 409 to hand out a session identifier
  /// or to announce a different RPC protocol.
  private func negotiating<Value>(
    request makeRequest: (any TransmissionRPCAdapting) throws -> Data,
    response parseResponse: (any TransmissionRPCAdapting, Data) throws -> Value
  ) async throws -> Value {
    try validateTransport()
    for _ in 0..<Self.maximumAttempts {
      let adapter = adapterForCurrentProtocol()
      let body = try makeRequest(adapter)
      let result = try await perform(body: body)
      if result.shouldRetry {
        continue
      }
      negotiatedProtocol = adapter.protocolKind
      return try parseResponse(adapter, result.data)
    }
    throw MagnetBridgeError.invalidResponse
  }

  private func adapterForCurrentProtocol() -> any TransmissionRPCAdapting {
    switch negotiatedProtocol {
    case .jsonRPC2:
      JSONRPCAdapter()
    case .legacy, .none:
      LegacyRPCAdapter()
    }
  }

  private func validateTransport() throws {
    guard let scheme = configuration.rpcURL.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      configuration.rpcURL.host != nil
    else {
      throw MagnetBridgeError.invalidRPCURL
    }
    if scheme == "http" && !configuration.allowsInsecureHTTP {
      throw MagnetBridgeError.insecureHTTPRequiresConfirmation
    }
  }

  private func perform(body: Data) async throws -> NetworkResult {
    var request = URLRequest(
      url: configuration.rpcURL,
      timeoutInterval: configuration.timeout
    )
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let sessionID {
      request.setValue(sessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
    }
    if !configuration.username.isEmpty || configuration.password != nil {
      let credentials = "\(configuration.username):\(configuration.password ?? "")"
      request.setValue(
        "Basic \(Data(credentials.utf8).base64EncodedString())",
        forHTTPHeaderField: "Authorization"
      )
    }

    do {
      let (data, response) = try await session.data(for: request)
      switch response.statusCode {
      case 200..<300:
        return NetworkResult(data: data, shouldRetry: false)
      case 409:
        guard
          let newSessionID = response.value(
            forHTTPHeaderField: "X-Transmission-Session-Id"
          ), !newSessionID.isEmpty
        else {
          throw MagnetBridgeError.invalidResponse
        }
        sessionID = newSessionID
        if let version = response.value(
          forHTTPHeaderField: "X-Transmission-Rpc-Version"
        ) {
          negotiatedProtocol = protocolKind(for: version)
        } else if negotiatedProtocol == nil {
          negotiatedProtocol = .legacy
        }
        return NetworkResult(data: data, shouldRetry: true)
      case 401, 403:
        throw MagnetBridgeError.authenticationFailed
      default:
        throw MagnetBridgeError.serverError(response.statusCode)
      }
    } catch let error as MagnetBridgeError {
      throw error
    } catch let error as URLError {
      throw error.code == .timedOut
        ? MagnetBridgeError.timedOut
        : MagnetBridgeError.serverUnavailable
    } catch {
      throw MagnetBridgeError.serverUnavailable
    }
  }

  private func protocolKind(for semanticVersion: String) -> TransmissionProtocol {
    let major = Int(semanticVersion.split(separator: ".").first ?? "0") ?? 0
    return major >= 6 ? .jsonRPC2 : .legacy
  }
}

private struct NetworkResult {
  let data: Data
  let shouldRetry: Bool
}
