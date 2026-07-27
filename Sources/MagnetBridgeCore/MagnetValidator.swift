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

  public init() {}

  public func validate(_ url: URL) throws -> ValidatedMagnet {
    let raw = url.absoluteString
    guard raw.utf8.count <= Self.maximumLength else {
      throw MagnetBridgeError.invalidMagnet("длина превышает 32 КБ")
    }
    guard url.scheme?.lowercased() == "magnet" else {
      throw MagnetBridgeError.invalidMagnet("ожидается схема magnet")
    }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw MagnetBridgeError.invalidMagnet("URL не удалось разобрать")
    }

    let exactTopics =
      components.queryItems?
      .filter { $0.name.lowercased() == "xt" }
      .compactMap(\.value) ?? []
    let hashes = exactTopics.compactMap(parseExactTopic)
    guard !hashes.isEmpty else {
      throw MagnetBridgeError.invalidMagnet(
        "отсутствует поддерживаемый параметр xt=urn:btih:… или xt=urn:btmh:…")
    }

    return ValidatedMagnet(url: url, infoHashes: hashes)
  }

  private func parseExactTopic(_ value: String) -> String? {
    let lower = value.lowercased()
    if lower.hasPrefix("urn:btih:") {
      let hash = String(value.dropFirst("urn:btih:".count))
      let isHex = hash.count == 40 && hash.allSatisfy(\.isHexDigit)
      let base32 = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
      let isBase32 =
        hash.count == 32 && hash.uppercased().unicodeScalars.allSatisfy(base32.contains)
      return (isHex || isBase32) ? hash : nil
    }
    if lower.hasPrefix("urn:btmh:") {
      let multihash = String(value.dropFirst("urn:btmh:".count))
      let allowed = CharacterSet.alphanumerics
      let valid =
        (6...256).contains(multihash.count) && multihash.unicodeScalars.allSatisfy(allowed.contains)
      return valid ? multihash : nil
    }
    return nil
  }
}
