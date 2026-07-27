import AppKit
import Foundation
import MagnetBridgeCore
import Observation

@MainActor
@Observable
final class AppModel {
  struct HandlerApplication: Identifiable {
    let applicationURL: URL
    let bundleIdentifier: String
    let name: String
    let icon: NSImage

    var id: String { bundleIdentifier }
  }

  enum Notice {
    case progress(String)
    case success(String)
    case warning(String)
    case failure(String)

    var message: String {
      switch self {
      case .progress(let message),
        .success(let message),
        .warning(let message),
        .failure(let message):
        message
      }
    }
  }

  private let settingsStore: SettingsStore
  private let passwordStore: KeychainStore
  private let browserLauncher: BrowserLauncher
  private let notificationService: NotificationService
  private let urlHandler: URLHandler
  private let validator = MagnetValidator()

  var settings: AppSettings
  var serverAddress: String
  var usesCustomEndpoints: Bool
  var passwordInput = ""
  var hasStoredPassword = false
  var browsers: [BrowserSelection]
  var handlerApplications: [HandlerApplication] = []
  var pendingMagnetURL: URL?
  var notice: Notice?
  var isBusy = false
  var currentHandler = ""
  var restoreTarget = ""

  var onMenuBarPreferenceChanged: ((Bool) -> Void)?
  var onHandlerStateChanged: (() -> Void)?
  var onHandlingFinished: (() -> Void)?

  init(
    settingsStore: SettingsStore = SettingsStore(),
    passwordStore: KeychainStore = KeychainStore(),
    browserLauncher: BrowserLauncher = BrowserLauncher(),
    notificationService: NotificationService = NotificationService()
  ) {
    self.settingsStore = settingsStore
    self.passwordStore = passwordStore
    self.browserLauncher = browserLauncher
    self.notificationService = notificationService
    let loadedSettings = settingsStore.load()
    self.settings = loadedSettings
    self.serverAddress =
      TransmissionEndpointResolver.serverAddress(fromRPCURL: loadedSettings.rpcURL)
      ?? loadedSettings.rpcURL
    self.usesCustomEndpoints =
      !loadedSettings.rpcURL.hasSuffix("/transmission/rpc")
      || !loadedSettings.webUIURL.hasSuffix("/transmission/web/")
    self.browsers = browserLauncher.installedBrowsers()
    self.urlHandler = URLHandler(
      settingsStore: settingsStore,
      passwordStore: passwordStore,
      browserLauncher: browserLauncher,
      notificationService: notificationService
    )
    refreshLocalState()
  }

  var showsMenuBarIcon: Bool {
    get { settings.showsMenuBarIcon }
    set {
      settings.showsMenuBarIcon = newValue
      onMenuBarPreferenceChanged?(newValue)
    }
  }

  var isUsingInsecureHTTP: Bool {
    let value = usesCustomEndpoints ? settings.rpcURL : serverAddress
    return URL(string: value)?.scheme?.lowercased() == "http"
  }

  var pendingMagnetName: String {
    guard
      let pendingMagnetURL,
      let components = URLComponents(url: pendingMagnetURL, resolvingAgainstBaseURL: false),
      let name = components.queryItems?.first(where: { $0.name == "dn" })?.value,
      !name.isEmpty
    else {
      return "Magnet link"
    }
    return String(name.prefix(120))
  }

  func receive(_ url: URL) {
    do {
      pendingMagnetURL = try validator.validate(url).url
      handlerApplications = discoverAlternativeHandlers(for: url)
      notice = nil
    } catch {
      pendingMagnetURL = nil
      notice = .failure(error.localizedDescription)
    }
  }

  func sendPendingMagnetToServer() async {
    guard let url = pendingMagnetURL, !isBusy else { return }
    isBusy = true
    notice = .progress("Sending to Transmission…")
    let result = await urlHandler.handle(url)
    switch result {
    case .added(let torrent):
      notice = .success("Added “\(torrent.name)” to Transmission.")
      pendingMagnetURL = nil
      onHandlingFinished?()
    case .duplicate(let torrent):
      notice = .success("“\(torrent.name)” is already in Transmission.")
      pendingMagnetURL = nil
      onHandlingFinished?()
    case .failed(let error):
      notice = .failure(error.localizedDescription)
    }
    isBusy = false
  }

  func openPendingMagnet(with application: HandlerApplication) async {
    guard let url = pendingMagnetURL, !isBusy else { return }
    isBusy = true
    notice = .progress("Opening in \(application.name)…")
    do {
      try await open(url, withApplicationAt: application.applicationURL)
      pendingMagnetURL = nil
      notice = .success("Opened in \(application.name).")
      onHandlingFinished?()
    } catch {
      notice = .failure("Couldn’t open \(application.name): \(error.localizedDescription)")
    }
    isBusy = false
  }

  func copyPendingMagnet() {
    guard let pendingMagnetURL else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(pendingMagnetURL.absoluteString, forType: .string)
    notice = .success("Magnet link copied.")
  }

  func cancelPendingMagnet() {
    pendingMagnetURL = nil
    notice = nil
    onHandlingFinished?()
  }

  func save(makeDefault: Bool = true) async {
    guard !isBusy else { return }
    isBusy = true
    notice = .progress("Saving settings…")
    do {
      let normalized = try normalizedSettings()
      try settingsStore.save(normalized)
      settings = normalized
      if !passwordInput.isEmpty {
        try passwordStore.savePassword(passwordInput)
        passwordInput = ""
      }
      if makeDefault {
        try await MagnetHandlerRegistration.makeDefault()
      }
      refreshLocalState()
      notice = .success(
        makeDefault
          ? "Settings saved. MagnetBridge is the default magnet handler."
          : "Settings saved."
      )
    } catch {
      notice = .failure(error.localizedDescription)
    }
    isBusy = false
  }

  func testConnection() async {
    guard !isBusy else { return }
    isBusy = true
    notice = .progress("Testing the Transmission connection…")
    do {
      let normalized = try normalizedSettings()
      guard let rpcURL = URL(string: normalized.rpcURL) else {
        throw MagnetBridgeError.invalidRPCURL
      }
      let password =
        passwordInput.isEmpty ? try passwordStore.readPassword() : passwordInput
      let client = TransmissionClient(
        configuration: TransmissionConfiguration(
          rpcURL: rpcURL,
          username: normalized.username,
          password: password,
          timeout: normalized.timeout,
          allowsInsecureHTTP: normalized.hasAcknowledgedInsecureHTTP
        )
      )
      let info = try await client.testConnection()
      let protocolName = info.protocolKind == .jsonRPC2 ? "JSON-RPC 2.0" : "legacy RPC"
      notice = .success("Connected to Transmission \(info.version) using \(protocolName).")
    } catch {
      notice = .failure(error.localizedDescription)
    }
    isBusy = false
  }

  func removeStoredPassword() {
    do {
      try passwordStore.deletePassword()
      hasStoredPassword = false
      passwordInput = ""
      notice = .success("Saved password removed from Keychain.")
    } catch {
      notice = .failure(error.localizedDescription)
    }
  }

  func makeDefaultHandler() async {
    guard !isBusy else { return }
    isBusy = true
    notice = .progress("Updating the magnet handler…")
    do {
      try await MagnetHandlerRegistration.makeDefault()
      refreshHandlerState()
      notice = .success("MagnetBridge is the default magnet handler.")
    } catch {
      notice = .failure(error.localizedDescription)
    }
    isBusy = false
  }

  func restorePreviousHandler() async {
    guard !isBusy else { return }
    isBusy = true
    notice = .progress("Restoring the previous magnet handler…")
    do {
      let restored = try await MagnetHandlerRegistration.restorePrevious()
      refreshHandlerState()
      notice = .success("Restored \(restored).")
    } catch {
      notice = .failure(error.localizedDescription)
    }
    isBusy = false
  }

  func refreshHandlerState() {
    currentHandler = MagnetHandlerRegistration.currentHandlerDescription()
    restoreTarget = MagnetHandlerRegistration.previousHandlerDescription()
    onHandlerStateChanged?()
  }

  private func normalizedSettings() throws -> AppSettings {
    var normalized = settings
    if usesCustomEndpoints {
      normalized.rpcURL = normalized.rpcURL.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      normalized.webUIURL = normalized.webUIURL.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
    } else {
      let endpoints = try TransmissionEndpointResolver.resolve(
        serverAddress: serverAddress
      )
      normalized.rpcURL = endpoints.rpcURL
      normalized.webUIURL = endpoints.webUIURL
    }

    guard
      let rpcURL = URL(string: normalized.rpcURL),
      ["http", "https"].contains(rpcURL.scheme?.lowercased()),
      rpcURL.host != nil,
      rpcURL.user == nil,
      rpcURL.password == nil
    else {
      throw MagnetBridgeError.invalidRPCURL
    }
    guard
      let webURL = URL(string: normalized.webUIURL),
      ["http", "https"].contains(webURL.scheme?.lowercased()),
      webURL.host != nil
    else {
      throw AppModelError.invalidWebUIURL
    }
    guard (3...60).contains(normalized.timeout) else {
      throw AppModelError.invalidTimeout
    }
    if rpcURL.scheme?.lowercased() == "http",
      !normalized.hasAcknowledgedInsecureHTTP
    {
      throw MagnetBridgeError.insecureHTTPRequiresConfirmation
    }
    return normalized
  }

  private func refreshLocalState() {
    hasStoredPassword = (try? passwordStore.readPassword())?.isEmpty == false
    refreshHandlerState()
  }

  private func discoverAlternativeHandlers(for url: URL) -> [HandlerApplication] {
    let ownIdentifier = Bundle.main.bundleIdentifier ?? "org.magnetbridge.app"
    var seen = Set<String>()
    return NSWorkspace.shared.urlsForApplications(toOpen: url).compactMap { applicationURL in
      guard
        let bundle = Bundle(url: applicationURL),
        let identifier = bundle.bundleIdentifier,
        identifier.caseInsensitiveCompare(ownIdentifier) != .orderedSame,
        seen.insert(identifier.lowercased()).inserted
      else {
        return nil
      }
      let name =
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? applicationURL.deletingPathExtension().lastPathComponent
      return HandlerApplication(
        applicationURL: applicationURL,
        bundleIdentifier: identifier,
        name: name,
        icon: NSWorkspace.shared.icon(forFile: applicationURL.path)
      )
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func open(_ url: URL, withApplicationAt applicationURL: URL) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      NSWorkspace.shared.open(
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

private enum AppModelError: LocalizedError {
  case invalidWebUIURL
  case invalidTimeout

  var errorDescription: String? {
    switch self {
    case .invalidWebUIURL:
      "The Transmission Web UI URL is invalid."
    case .invalidTimeout:
      "The timeout must be between 3 and 60 seconds."
    }
  }
}
