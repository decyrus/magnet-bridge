import Foundation

/// Normalizes and checks the settings both front ends persist, so the GUI and
/// the CLI cannot disagree about what counts as a usable configuration.
public struct SettingsValidator: Sendable {
  public static let allowedTimeouts: ClosedRange<TimeInterval> = 3...60

  public init() {}

  /// Returns `settings` with surrounding whitespace removed from the URLs and
  /// the username, or throws the first rule the settings violate.
  public func validated(_ settings: AppSettings) throws -> AppSettings {
    var normalized = settings
    normalized.rpcURL = normalized.rpcURL.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    normalized.webUIURL = normalized.webUIURL.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    normalized.username = normalized.username.trimmingCharacters(
      in: .whitespacesAndNewlines
    )

    guard
      let rpcURL = URL(string: normalized.rpcURL),
      let rpcScheme = rpcURL.scheme?.lowercased(),
      rpcScheme == "http" || rpcScheme == "https",
      rpcURL.host != nil,
      rpcURL.user == nil,
      rpcURL.password == nil
    else {
      throw MagnetBridgeError.invalidRPCURL
    }

    guard
      let webUIURL = URL(string: normalized.webUIURL),
      let webScheme = webUIURL.scheme?.lowercased(),
      webScheme == "http" || webScheme == "https",
      webUIURL.host != nil
    else {
      throw MagnetBridgeError.invalidWebUIURL
    }

    guard Self.allowedTimeouts.contains(normalized.timeout) else {
      throw MagnetBridgeError.invalidTimeout
    }

    if normalized.usesAuthentication, normalized.username.isEmpty {
      throw MagnetBridgeError.missingUsername
    }

    if rpcScheme == "http", !normalized.hasAcknowledgedInsecureHTTP {
      throw MagnetBridgeError.insecureHTTPRequiresConfirmation
    }

    return normalized
  }
}
