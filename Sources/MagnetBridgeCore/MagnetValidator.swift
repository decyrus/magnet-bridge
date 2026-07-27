import Foundation

public struct ValidatedMagnet: Equatable, Sendable {
  public let url: URL
  public let infoHashes: [String]

  public init(url: URL, infoHashes: [String]) {
    self.url = url
    self.infoHashes = infoHashes
  }
}

public struct MagnetValidator: Sendable {
  public static let maximumLength = 32 * 1024

  private static let base32Alphabet = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
  )

  public init() {}

  public func validate(_ url: URL) throws -> ValidatedMagnet {
    let raw = url.absoluteString
    guard raw.utf8.count <= Self.maximumLength else {
      throw MagnetBridgeError.invalidMagnet("the link exceeds 32 KB")
    }
    guard url.scheme?.lowercased() == "magnet" else {
      throw MagnetBridgeError.invalidMagnet("the URL scheme must be magnet")
    }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw MagnetBridgeError.invalidMagnet("the URL could not be parsed")
    }

    let exactTopics =
      components.queryItems?
      .filter { $0.name.lowercased() == "xt" }
      .compactMap(\.value) ?? []
    let hashes = exactTopics.compactMap(parseExactTopic)
    guard !hashes.isEmpty else {
      throw MagnetBridgeError.invalidMagnet(
        "a supported xt=urn:btih:… or xt=urn:btmh:… parameter is required")
    }

    return ValidatedMagnet(url: url, infoHashes: hashes)
  }

  private func parseExactTopic(_ value: String) -> String? {
    let lower = value.lowercased()
    if lower.hasPrefix("urn:btih:") {
      let hash = String(value.dropFirst("urn:btih:".count))
      let isHex = hash.count == 40 && hash.allSatisfy(\.isHexDigit)
      let isBase32 =
        hash.count == 32
        && hash.uppercased().unicodeScalars.allSatisfy(Self.base32Alphabet.contains)
      return (isHex || isBase32) ? hash : nil
    }
    if lower.hasPrefix("urn:btmh:") {
      let multihash = String(value.dropFirst("urn:btmh:".count))
      let valid =
        (6...256).contains(multihash.count)
        && multihash.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
      return valid ? multihash : nil
    }
    return nil
  }
}
