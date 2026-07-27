import Foundation

public protocol SettingsStoring: Sendable {
  func load() -> AppSettings
  func save(_ settings: AppSettings) throws
}

public final class SettingsStore: SettingsStoring, @unchecked Sendable {
  public static let applicationSuiteName = "org.magnetbridge.app"

  private let defaults: UserDefaults
  private let key: String
  private let lock = NSLock()

  public init(
    defaults: UserDefaults? = nil,
    key: String = "MagnetBridge.settings.v1"
  ) {
    self.defaults =
      defaults
      ?? UserDefaults(suiteName: Self.applicationSuiteName)
      ?? .standard
    self.key = key
  }

  public func load() -> AppSettings {
    lock.withLock {
      guard
        let data = defaults.data(forKey: key),
        let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
      else {
        return .defaults
      }
      return settings
    }
  }

  public func save(_ settings: AppSettings) throws {
    let data = try JSONEncoder().encode(settings)
    lock.withLock {
      defaults.set(data, forKey: key)
    }
  }
}
