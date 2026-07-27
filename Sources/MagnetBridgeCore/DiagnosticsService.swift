import Foundation

public struct DiagnosticsService: Sendable {
  /// Shorter values are left alone: a one or two character username matches
  /// too much ordinary text to be replaced safely.
  private static let minimumRedactableSecretLength = 4

  private let redactor: SecretRedactor

  public init(redactor: SecretRedactor = SecretRedactor()) {
    self.redactor = redactor
  }

  /// Builds a report suitable for a bug report. Hosts appear without their
  /// paths or query strings, magnet links are redacted, and the configured
  /// username is removed from the recent messages when it is long enough to
  /// match unambiguously. The password is never read.
  public func report(
    settings: AppSettings,
    connection: ConnectionInfo? = nil,
    recentMessages: [String] = [],
    appVersion: String = "unknown"
  ) -> String {
    let rpcURL = URL(string: settings.rpcURL)
    let lines = [
      "MagnetBridge diagnostics",
      "MagnetBridge: \(appVersion)",
      "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
      "RPC host: \(rpcURL?.host ?? "invalid")",
      "Web UI host: \(URL(string: settings.webUIURL)?.host ?? "invalid")",
      "HTTPS: \(rpcURL?.scheme?.lowercased() == "https")",
      "Timeout: \(settings.timeout)s",
      "Authentication: \(settings.usesAuthentication ? "enabled" : "disabled")",
      "Browser: \(settings.browser.displayName)",
      "Transmission: \(connection?.version ?? "not tested")",
      "RPC protocol: \(connection?.protocolKind.rawValue ?? "unknown")",
      "Recent messages:",
      recentMessages.joined(separator: "\n"),
    ]
    return redactor.redact(
      lines.joined(separator: "\n"),
      secrets: secrets(in: settings)
    )
  }

  private func secrets(in settings: AppSettings) -> [String] {
    guard
      settings.usesAuthentication,
      settings.username.count >= Self.minimumRedactableSecretLength
    else {
      return []
    }
    return [settings.username]
  }
}
