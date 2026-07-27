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
}

public actor TransmissionClient {
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
    try validateTransport()
    for _ in 0..<3 {
      let adapter = adapterForCurrentProtocol()
      let body = try adapter.makeAddRequest(magnetURL: magnetURL, paused: paused)
      let result = try await perform(body: body)
      if result.shouldRetry {
        continue
      }
      negotiatedProtocol = adapter.protocolKind
      return try adapter.parseAddResponse(result.data)
    }
    throw MagnetBridgeError.invalidResponse
  }

  public func testConnection() async throws -> ConnectionInfo {
    try validateTransport()
    for _ in 0..<3 {
      let adapter = adapterForCurrentProtocol()
      let result = try await perform(body: adapter.makeSessionRequest())
      if result.shouldRetry {
        continue
      }
      negotiatedProtocol = adapter.protocolKind
      return try adapter.parseSessionResponse(result.data)
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
      case 500...599:
        throw MagnetBridgeError.serverError(response.statusCode)
      default:
        throw MagnetBridgeError.serverError(response.statusCode)
      }
    } catch let error as MagnetBridgeError {
      throw error
    } catch let error as URLError {
      switch error.code {
      case .timedOut:
        throw MagnetBridgeError.timedOut
      case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
        .networkConnectionLost, .notConnectedToInternet:
        throw MagnetBridgeError.serverUnavailable
      default:
        throw MagnetBridgeError.serverUnavailable
      }
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
