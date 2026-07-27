import AppKit
import Foundation
import MagnetBridgeCore
import Observation

@MainActor
@Observable
final class AppModel {
  struct BrowserOption: Identifiable {
    let selection: BrowserSelection
    let icon: NSImage

    var id: String {
      selection.bundleIdentifier ?? "system-default"
    }
  }

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
  private let settingsValidator = SettingsValidator()

  var settings: AppSettings
  var serverAddress: String
  var usesCustomEndpoints: Bool
  var passwordInput = ""
  var hasStoredPassword = false
  var browserOptions: [BrowserOption]
  var handlerApplications: [HandlerApplication] = []
  var pendingMagnetURL: URL?
  var notice: Notice?
  var isBusy = false
  var currentHandler = ""
  var restoreTarget = ""
  var showsHelp = false

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
    self.browserOptions = Self.makeBrowserOptions(
      from: browserLauncher.installedBrowsers(),
      selectedBrowser: loadedSettings.browser
    )
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

  func setAuthenticationEnabled(_ isEnabled: Bool) {
    settings.usesAuthentication = isEnabled
    passwordInput = ""
    refreshPasswordState()
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
      try await NSWorkspace.shared.open(
        url,
        withApplicationAt: application.applicationURL
      )
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
      let password: String?
      if normalized.usesAuthentication {
        password =
          passwordInput.isEmpty ? try passwordStore.readPassword() : passwordInput
      } else {
        password = nil
      }
      let client = TransmissionClient(
        configuration: try TransmissionConfiguration(
          settings: normalized,
          password: password
        )
      )
      let info = try await client.testConnection()
      notice = .success(
        "Connected to Transmission \(info.version) using \(info.protocolKind.displayName)."
      )
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
    if !usesCustomEndpoints {
      let endpoints = try TransmissionEndpointResolver.resolve(
        serverAddress: serverAddress
      )
      normalized.rpcURL = endpoints.rpcURL
      normalized.webUIURL = endpoints.webUIURL
    }
    return try settingsValidator.validated(normalized)
  }

  private func refreshLocalState() {
    refreshPasswordState()
    refreshHandlerState()
  }

  private func refreshPasswordState() {
    guard settings.usesAuthentication else {
      hasStoredPassword = false
      return
    }
    hasStoredPassword = (try? passwordStore.readPassword())?.isEmpty == false
  }

  private static func makeBrowserOptions(
    from installedBrowsers: [BrowserSelection],
    selectedBrowser: BrowserSelection
  ) -> [BrowserOption] {
    var browsers = installedBrowsers
    if !browsers.contains(selectedBrowser) {
      browsers.append(selectedBrowser)
    }

    return browsers.map { browser in
      let icon: NSImage
      if let bundleIdentifier = browser.bundleIdentifier,
        let applicationURL = NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: bundleIdentifier
        )
      {
        icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
      } else if browser.bundleIdentifier == nil,
        let sampleURL = URL(string: "https://example.invalid"),
        let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: sampleURL)
      {
        icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
      } else {
        icon =
          NSImage(
            systemSymbolName: "app.dashed",
            accessibilityDescription: browser.displayName
          ) ?? NSImage()
      }
      icon.size = NSSize(width: 18, height: 18)
      return BrowserOption(selection: browser, icon: icon)
    }
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
}
