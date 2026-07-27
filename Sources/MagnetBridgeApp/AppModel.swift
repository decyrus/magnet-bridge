import AppKit
import Foundation
import MagnetBridgeCore
import Observation

@MainActor
@Observable
final class AppModel {
  enum OperationState: Equatable {
    case idle
    case processing
    case success(title: String, detail: String)
    case failure(String)
  }

  enum ConnectionState: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
  }

  var settings: AppSettings
  var password = ""
  var browsers: [BrowserSelection]
  var operationState: OperationState = .idle
  var connectionState: ConnectionState = .idle
  var saveMessage: String?

  private(set) var lastIncomingURL: URL?

  private let settingsStore: SettingsStore
  private let keychainStore: KeychainStore
  private let browserLauncher: BrowserLauncher
  private let notificationService: NotificationService
  private let urlHandler: URLHandler

  init() {
    let settingsStore = SettingsStore()
    let keychainStore = KeychainStore()
    let browserLauncher = BrowserLauncher()
    let notificationService = NotificationService()

    self.settingsStore = settingsStore
    self.keychainStore = keychainStore
    self.browserLauncher = browserLauncher
    self.notificationService = notificationService
    self.settings = settingsStore.load()
    self.password = (try? keychainStore.readPassword()) ?? ""
    self.browsers = browserLauncher.installedBrowsers()
    self.urlHandler = URLHandler(
      settingsStore: settingsStore,
      passwordStore: keychainStore,
      browserLauncher: browserLauncher,
      notificationService: notificationService
    )
  }

  func start() {
    Task {
      await notificationService.requestAuthorization()
    }
  }

  func handleIncomingURL(_ url: URL) {
    lastIncomingURL = url
    operationState = .processing
    Task {
      let result = await urlHandler.handle(url)
      switch result {
      case .added(let torrent):
        operationState = .success(
          title: "Torrent Added",
          detail: torrent.name
        )
      case .duplicate(let torrent):
        operationState = .success(
          title: "Torrent Already Added",
          detail: torrent.name
        )
      case .failed(let error):
        operationState = .failure(error.localizedDescription)
      }
      NSApplication.shared.activate()
    }
  }

  func retry() {
    guard let lastIncomingURL else { return }
    handleIncomingURL(lastIncomingURL)
  }

  func copyLastURL() {
    guard let lastIncomingURL else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(lastIncomingURL.absoluteString, forType: .string)
  }

  func saveSettings() {
    do {
      try validateSettings()
      try settingsStore.save(settings)
      if password.isEmpty {
        try keychainStore.deletePassword()
      } else {
        try keychainStore.savePassword(password)
      }
      saveMessage = "Settings saved"
    } catch {
      saveMessage = error.localizedDescription
    }
  }

  func testConnection() {
    connectionState = .testing
    Task {
      do {
        try validateSettings()
        guard let rpcURL = URL(string: settings.rpcURL) else {
          throw MagnetBridgeError.invalidRPCURL
        }
        let client = TransmissionClient(
          configuration: TransmissionConfiguration(
            rpcURL: rpcURL,
            username: settings.username,
            password: password.isEmpty ? nil : password,
            timeout: settings.timeout,
            allowsInsecureHTTP: settings.hasAcknowledgedInsecureHTTP
          )
        )
        let info = try await client.testConnection()
        connectionState = .success(
          "Transmission \(info.version), RPC \(info.protocolVersion ?? "unknown") (\(info.protocolKind == .jsonRPC2 ? "JSON-RPC 2.0" : "legacy"))"
        )
      } catch {
        connectionState = .failure(error.localizedDescription)
      }
    }
  }

  func refreshBrowsers() {
    browsers = browserLauncher.installedBrowsers()
  }

  private func validateSettings() throws {
    guard let rpcURL = URL(string: settings.rpcURL),
      ["http", "https"].contains(rpcURL.scheme?.lowercased()),
      rpcURL.host != nil
    else {
      throw MagnetBridgeError.invalidRPCURL
    }
    guard let webURL = URL(string: settings.webUIURL),
      ["http", "https"].contains(webURL.scheme?.lowercased()),
      webURL.host != nil
    else {
      throw MagnetBridgeError.rpcError("The Web UI URL is invalid.")
    }
    if rpcURL.scheme?.lowercased() == "http",
      !settings.hasAcknowledgedInsecureHTTP
    {
      throw MagnetBridgeError.insecureHTTPRequiresConfirmation
    }
  }
}
