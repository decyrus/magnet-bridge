import AppKit
import Foundation

public struct BrowserLaunchResult: Equatable, Sendable {
  public let usedFallback: Bool

  public init(usedFallback: Bool) {
    self.usedFallback = usedFallback
  }
}

public protocol BrowserLaunching: Sendable {
  func installedBrowsers() -> [BrowserSelection]
  func open(_ url: URL, using browser: BrowserSelection) async throws -> BrowserLaunchResult
}

public final class BrowserLauncher: BrowserLaunching, @unchecked Sendable {
  private let workspace: NSWorkspace

  public init(workspace: NSWorkspace = .shared) {
    self.workspace = workspace
  }

  public func installedBrowsers() -> [BrowserSelection] {
    guard let sampleURL = URL(string: "https://example.invalid") else {
      return [.systemDefault]
    }
    let browsers: [BrowserSelection] = workspace.urlsForApplications(toOpen: sampleURL).compactMap {
      appURL -> BrowserSelection? in
      guard let bundle = Bundle(url: appURL),
        let identifier = bundle.bundleIdentifier
      else {
        return nil
      }
      let name =
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? appURL.deletingPathExtension().lastPathComponent
      return BrowserSelection(bundleIdentifier: identifier, displayName: name)
    }
    let unique: [BrowserSelection] = Dictionary(
      grouping: browsers,
      by: { $0.bundleIdentifier ?? $0.displayName }
    )
    .compactMap { $0.value.first }
    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    return [.systemDefault] + unique
  }

  public func open(
    _ url: URL,
    using browser: BrowserSelection
  ) async throws -> BrowserLaunchResult {
    guard let bundleIdentifier = browser.bundleIdentifier else {
      guard workspace.open(url) else {
        throw MagnetBridgeError.browserUnavailable(browser.displayName)
      }
      return BrowserLaunchResult(usedFallback: false)
    }
    guard
      let applicationURL = workspace.urlForApplication(
        withBundleIdentifier: bundleIdentifier
      )
    else {
      guard workspace.open(url) else {
        throw MagnetBridgeError.browserUnavailable(browser.displayName)
      }
      return BrowserLaunchResult(usedFallback: true)
    }

    do {
      try await open(url, withApplicationAt: applicationURL)
      return BrowserLaunchResult(usedFallback: false)
    } catch {
      guard workspace.open(url) else {
        throw MagnetBridgeError.browserUnavailable(browser.displayName)
      }
      return BrowserLaunchResult(usedFallback: true)
    }
  }

  private func open(_ url: URL, withApplicationAt applicationURL: URL) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      workspace.open(
        [url],
        withApplicationAt: applicationURL,
        configuration: NSWorkspace.OpenConfiguration()
      ) { _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }
}
