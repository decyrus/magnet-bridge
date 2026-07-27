import Foundation

public struct DiagnosticsService: Sendable {
  private let redactor: SecretRedactor

  public init(redactor: SecretRedactor = SecretRedactor()) {
    self.redactor = redactor
  }

  public func report(
    settings: AppSettings,
    connection: ConnectionInfo? = nil,
    recentMessages: [String] = []
  ) -> String {
    let rpcHost = URL(string: settings.rpcURL)?.host ?? "invalid"
    let webHost = URL(string: settings.webUIURL)?.host ?? "invalid"
    let lines = [
      "MagnetBridge diagnostics",
      "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
      "RPC host: \(rpcHost)",
      "Web UI host: \(webHost)",
      "HTTPS: \(URL(string: settings.rpcURL)?.scheme?.lowercased() == "https")",
      "Timeout: \(settings.timeout)s",
      "Browser: \(settings.browser.displayName)",
      "Transmission: \(connection?.version ?? "not tested")",
      "RPC protocol: \(connection?.protocolKind.rawValue ?? "unknown")",
      "Recent messages:",
      recentMessages.joined(separator: "\n"),
    ]
    return redactor.redact(lines.joined(separator: "\n"))
  }
}
