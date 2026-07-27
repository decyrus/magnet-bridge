import Foundation

/// The running build's version, resolved once for the GUI and the CLI.
enum AppVersion {
  /// The marketing version, or `"development"` when no bundle declares one.
  static let short = value(forKey: "CFBundleShortVersionString") ?? "development"

  /// The build number, or `"—"` when no bundle declares one.
  static let build = value(forKey: "CFBundleVersion") ?? "—"

  static var displayString: String {
    "Version \(short) (\(build))"
  }

  private static func value(forKey key: String) -> String? {
    if let bundleValue = Bundle.main.object(forInfoDictionaryKey: key) as? String {
      return bundleValue
    }
    // The CLI runs from `Contents/MacOS`, where `Bundle.main` is the executable
    // directory rather than the app bundle, so read `Contents/Info.plist`.
    let infoURL = URL(fileURLWithPath: CommandLine.arguments[0])
      .resolvingSymlinksInPath()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Info.plist")
    guard
      let data = try? Data(contentsOf: infoURL),
      let info = try? PropertyListSerialization.propertyList(
        from: data,
        format: nil
      ) as? [String: Any]
    else {
      return nil
    }
    return info[key] as? String
  }
}
