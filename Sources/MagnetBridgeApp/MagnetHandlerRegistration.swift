import AppKit
import CoreServices
import Foundation
import MagnetBridgeCore

@MainActor
enum MagnetHandlerRegistration {
  private static let scheme = "magnet"
  private static let bundleIdentifier = "org.magnetbridge.app"
  private static let previousHandlerKey = "previousMagnetHandlerBundleIdentifier"
  private static let defaults =
    UserDefaults(suiteName: SettingsStore.applicationSuiteName) ?? .standard

  static func makeDefault() async throws {
    let applicationURL = try installedApplicationURL()
    if let currentIdentifier = currentHandlerBundleIdentifier(),
      currentIdentifier.caseInsensitiveCompare(bundleIdentifier) != .orderedSame
    {
      defaults.set(currentIdentifier, forKey: previousHandlerKey)
    } else if defaults.string(forKey: previousHandlerKey) == nil,
      let fallbackIdentifier = alternativeHandlerBundleIdentifier()
    {
      defaults.set(fallbackIdentifier, forKey: previousHandlerKey)
    }

    try await setDefaultApplication(at: applicationURL)

    guard
      currentHandlerBundleIdentifier()?.caseInsensitiveCompare(bundleIdentifier)
        == .orderedSame
    else {
      throw RegistrationError.notSelected
    }
  }

  static func restorePrevious() async throws -> String {
    guard
      let identifier =
        defaults.string(forKey: previousHandlerKey)
        ?? alternativeHandlerBundleIdentifier()
    else {
      throw RegistrationError.noPreviousHandler
    }
    guard let applicationURL = applicationURL(for: identifier) else {
      throw RegistrationError.previousHandlerUnavailable(identifier)
    }

    try await setDefaultApplication(at: applicationURL)

    guard
      currentHandlerBundleIdentifier()?.caseInsensitiveCompare(identifier)
        == .orderedSame
    else {
      throw RegistrationError.notRestored
    }
    return handlerDescription(for: identifier)
  }

  static func previousHandlerDescription() -> String {
    guard
      let identifier =
        defaults.string(forKey: previousHandlerKey)
        ?? alternativeHandlerBundleIdentifier()
    else {
      return "not available"
    }
    return handlerDescription(for: identifier)
  }

  private static func setDefaultApplication(at applicationURL: URL) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      NSWorkspace.shared.setDefaultApplication(
        at: applicationURL,
        toOpenURLsWithScheme: scheme
      ) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  static func currentHandlerDescription() -> String {
    guard let identifier = currentHandlerBundleIdentifier() else {
      return "not registered"
    }
    return handlerDescription(for: identifier)
  }

  private static func handlerDescription(for identifier: String) -> String {
    if identifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame {
      return "MagnetBridge (\(identifier))"
    }
    if identifier.localizedCaseInsensitiveContains("transmission") {
      return "Transmission (\(identifier))"
    }
    return identifier
  }

  private static func alternativeHandlerBundleIdentifier() -> String? {
    guard
      let probeURL = URL(
        string: "magnet:?xt=urn:btih:0000000000000000000000000000000000000000"
      )
    else {
      return nil
    }
    let discoveredIdentifiers =
      NSWorkspace.shared.urlsForApplications(toOpen: probeURL)
      .compactMap { Bundle(url: $0)?.bundleIdentifier }
    if let discoveredIdentifier = discoveredIdentifiers.first(where: {
      $0.caseInsensitiveCompare(bundleIdentifier) != .orderedSame
    }) {
      return discoveredIdentifier
    }

    for knownIdentifier in ["org.m0k.transmission"] {
      if applicationURL(for: knownIdentifier) != nil {
        return knownIdentifier
      }
    }
    return nil
  }

  private static func applicationURL(for identifier: String) -> URL? {
    if let registeredURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: identifier
    ) {
      return registeredURL
    }

    for domain: FileManager.SearchPathDomainMask in [.localDomainMask, .userDomainMask] {
      for directory in FileManager.default.urls(
        for: .applicationDirectory,
        in: domain
      ) {
        let candidate = directory.appendingPathComponent("Transmission.app")
        if Bundle(url: candidate)?.bundleIdentifier?.caseInsensitiveCompare(identifier)
          == .orderedSame
        {
          return candidate
        }
      }
    }
    return nil
  }

  private static func currentHandlerBundleIdentifier() -> String? {
    guard let handler = LSCopyDefaultHandlerForURLScheme(scheme as CFString) else {
      return nil
    }
    return handler.takeRetainedValue() as String
  }

  private static func installedApplicationURL() throws -> URL {
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
      .resolvingSymlinksInPath()
    let applicationURL =
      executableURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .standardizedFileURL

    guard
      applicationURL.pathExtension == "app",
      Bundle(url: applicationURL)?.bundleIdentifier == bundleIdentifier
    else {
      throw RegistrationError.notInstalledBundle
    }
    return applicationURL
  }
}

private enum RegistrationError: LocalizedError {
  case notInstalledBundle
  case notSelected
  case noPreviousHandler
  case previousHandlerUnavailable(String)
  case notRestored

  var errorDescription: String? {
    switch self {
    case .notInstalledBundle:
      "The CLI must run from an installed MagnetBridge.app bundle."
    case .notSelected:
      "macOS did not select MagnetBridge as the default magnet: handler."
    case .noPreviousHandler:
      "No previous magnet: handler is available to restore."
    case .previousHandlerUnavailable(let identifier):
      "The previous magnet: handler \(identifier) is no longer installed."
    case .notRestored:
      "macOS did not restore the previous magnet: handler."
    }
  }
}
