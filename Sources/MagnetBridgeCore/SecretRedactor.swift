import Foundation

public struct SecretRedactor: Sendable {
  public init() {}

  public func redact(_ text: String, secrets: [String] = []) -> String {
    var redacted = text
    if let regex = try? NSRegularExpression(
      pattern: #"(?i)magnet:\?[^\s"'<>\]]+"#
    ) {
      let range = NSRange(redacted.startIndex..., in: redacted)
      redacted = regex.stringByReplacingMatches(
        in: redacted,
        range: range,
        withTemplate: "magnet:[REDACTED]"
      )
    }
    for secret in secrets where !secret.isEmpty {
      redacted = redacted.replacingOccurrences(of: secret, with: "[REDACTED]")
    }
    return redacted
  }
}
