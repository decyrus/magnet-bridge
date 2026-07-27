import Foundation

/// Unchecked conformance: the only stored property is a compiled
/// `NSRegularExpression`, which is immutable and documented as thread safe.
public struct SecretRedactor: @unchecked Sendable {
  private let magnetPattern = try? NSRegularExpression(
    pattern: #"(?i)magnet:\?[^\s"'<>\]]+"#
  )

  public init() {}

  public func redact(_ text: String, secrets: [String] = []) -> String {
    var redacted = text
    if let magnetPattern {
      let range = NSRange(redacted.startIndex..., in: redacted)
      redacted = magnetPattern.stringByReplacingMatches(
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
