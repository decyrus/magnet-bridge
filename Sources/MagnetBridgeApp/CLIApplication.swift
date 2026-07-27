import AppKit
import Darwin
import Foundation
import MagnetBridgeCore

enum CLIApplication {
  static func run(_ arguments: [String]) async -> Int32 {
    guard let command = arguments.first else {
      printHelp()
      return 0
    }

    do {
      switch command {
      case "configure":
        try await configure()
      case "test":
        try await testConnection()
      case "config":
        try await runConfig(Array(arguments.dropFirst()))
      case "version", "--version", "-v":
        print(version)
      case "help", "--help", "-h":
        printHelp()
      default:
        throw CLIError("Unknown command: \(command)")
      }
      return 0
    } catch {
      writeError("Error: \(error.localizedDescription)")
      return 1
    }
  }

  private static let settingsStore = SettingsStore()
  private static let passwordStore = KeychainStore()

  private static var version: String {
    if let bundleVersion = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String {
      return bundleVersion
    }

    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
      .resolvingSymlinksInPath()
    let infoURL =
      executableURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Info.plist")
    guard
      let data = try? Data(contentsOf: infoURL),
      let info = try? PropertyListSerialization.propertyList(
        from: data,
        format: nil
      ) as? [String: Any],
      let version = info["CFBundleShortVersionString"] as? String
    else {
      return "development"
    }
    return version
  }

  private static func configure() async throws {
    guard isatty(STDIN_FILENO) != 0 else {
      throw CLIError("The configuration wizard requires an interactive terminal.")
    }

    var settings = settingsStore.load()
    print("MagnetBridge Configuration")
    print("==========================")
    print("Press Return to keep the value shown in brackets.\n")

    settings.rpcURL = prompt("Transmission RPC URL", default: settings.rpcURL)
    settings.webUIURL = prompt("Transmission Web UI URL", default: settings.webUIURL)
    settings.username = prompt("Username", default: settings.username)

    let hasPassword = (try passwordStore.readPassword())?.isEmpty == false
    var passwordUpdate: String?
    if promptBoolean(
      hasPassword ? "Replace the saved password?" : "Save a Transmission password?",
      default: !hasPassword
    ) {
      passwordUpdate = readSecret("Transmission password: ")
    }

    settings.timeout = promptTimeout(default: settings.timeout)
    settings.startMode = promptStartMode(default: settings.startMode)
    settings.opensWebUI = promptBoolean(
      "Open the Web UI after adding a torrent?",
      default: settings.opensWebUI
    )
    settings.browser = promptBrowser(default: settings.browser)

    if URL(string: settings.rpcURL)?.scheme?.lowercased() == "http" {
      settings.hasAcknowledgedInsecureHTTP = promptBoolean(
        "Allow unencrypted HTTP for Transmission RPC?",
        default: settings.hasAcknowledgedInsecureHTTP
      )
    } else {
      settings.hasAcknowledgedInsecureHTTP = false
    }

    try validate(settings)
    try settingsStore.save(settings)
    if let passwordUpdate {
      if passwordUpdate.isEmpty {
        try passwordStore.deletePassword()
      } else {
        try passwordStore.savePassword(passwordUpdate)
      }
    }
    print("\nConfiguration saved.")

    if promptBoolean("Test the connection now?", default: true) {
      try await testConnection()
    }
  }

  private static func runConfig(_ arguments: [String]) async throws {
    guard let subcommand = arguments.first else {
      throw CLIError("Usage: magnetbridge config <show|set|reset|unset-password>")
    }
    switch subcommand {
    case "show":
      try showConfiguration()
    case "set":
      try setConfiguration(Array(arguments.dropFirst()))
    case "reset":
      try settingsStore.save(.defaults)
      try passwordStore.deletePassword()
      print("Configuration and saved password reset.")
    case "unset-password":
      try passwordStore.deletePassword()
      print("Saved password removed.")
    default:
      throw CLIError("Unknown config command: \(subcommand)")
    }
  }

  private static func showConfiguration() throws {
    let settings = settingsStore.load()
    let hasPassword = (try passwordStore.readPassword())?.isEmpty == false
    print("rpc-url: \(settings.rpcURL)")
    print("web-ui-url: \(settings.webUIURL)")
    print("username: \(settings.username)")
    print("password: \(hasPassword ? "configured" : "not configured")")
    print("browser: \(settings.browser.bundleIdentifier ?? "system")")
    print("timeout: \(Int(settings.timeout))")
    print("open-web-ui: \(settings.opensWebUI)")
    print("start-mode: \(settings.startMode.rawValue)")
    print("allow-http: \(settings.hasAcknowledgedInsecureHTTP)")
  }

  private static func setConfiguration(_ arguments: [String]) throws {
    guard let key = arguments.first else {
      throw CLIError("Usage: magnetbridge config set <key> <value>")
    }

    if key == "password" {
      let password = readSecret("Transmission password: ")
      if password.isEmpty {
        try passwordStore.deletePassword()
      } else {
        try passwordStore.savePassword(password)
      }
      print("Password updated.")
      return
    }

    guard arguments.count >= 2 else {
      throw CLIError("Usage: magnetbridge config set <key> <value>")
    }
    let value = arguments.dropFirst().joined(separator: " ")
    var settings = settingsStore.load()

    switch key {
    case "rpc-url":
      settings.rpcURL = value
    case "web-ui-url":
      settings.webUIURL = value
    case "username":
      settings.username = value
    case "browser":
      settings.browser = try browserSelection(for: value)
    case "timeout":
      guard let timeout = TimeInterval(value), (3...60).contains(timeout) else {
        throw CLIError("Timeout must be between 3 and 60 seconds.")
      }
      settings.timeout = timeout
    case "open-web-ui":
      settings.opensWebUI = try parseBoolean(value)
    case "start-mode":
      guard let mode = TorrentStartMode(rawValue: value) else {
        throw CLIError("Start mode must be immediately or paused.")
      }
      settings.startMode = mode
    case "allow-http":
      settings.hasAcknowledgedInsecureHTTP = try parseBoolean(value)
    default:
      throw CLIError("Unknown configuration key: \(key)")
    }

    try validate(settings)
    try settingsStore.save(settings)
    print("\(key) updated.")
  }

  private static func testConnection() async throws {
    let settings = settingsStore.load()
    try validate(settings)
    guard let rpcURL = URL(string: settings.rpcURL) else {
      throw MagnetBridgeError.invalidRPCURL
    }
    let client = TransmissionClient(
      configuration: TransmissionConfiguration(
        rpcURL: rpcURL,
        username: settings.username,
        password: try passwordStore.readPassword(),
        timeout: settings.timeout,
        allowsInsecureHTTP: settings.hasAcknowledgedInsecureHTTP
      )
    )
    let info = try await client.testConnection()
    print(
      "Connected to Transmission \(info.version), RPC \(info.protocolVersion ?? "unknown") (\(info.protocolKind == .jsonRPC2 ? "JSON-RPC 2.0" : "legacy")."
    )
  }

  private static func validate(_ settings: AppSettings) throws {
    guard
      let rpcURL = URL(string: settings.rpcURL),
      ["http", "https"].contains(rpcURL.scheme?.lowercased()),
      rpcURL.host != nil,
      rpcURL.user == nil,
      rpcURL.password == nil
    else {
      throw MagnetBridgeError.invalidRPCURL
    }
    guard
      let webURL = URL(string: settings.webUIURL),
      ["http", "https"].contains(webURL.scheme?.lowercased()),
      webURL.host != nil
    else {
      throw CLIError("The Web UI URL is invalid.")
    }
    if rpcURL.scheme?.lowercased() == "http",
      !settings.hasAcknowledgedInsecureHTTP
    {
      throw MagnetBridgeError.insecureHTTPRequiresConfirmation
    }
  }

  private static func prompt(_ label: String, default defaultValue: String) -> String {
    write("\(label) [\(defaultValue)]: ")
    let value = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? defaultValue : value
  }

  private static func promptBoolean(_ label: String, default defaultValue: Bool) -> Bool {
    while true {
      write("\(label) [\(defaultValue ? "Y/n" : "y/N")]: ")
      let value =
        readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
      if value.isEmpty { return defaultValue }
      if ["y", "yes", "true", "1"].contains(value) { return true }
      if ["n", "no", "false", "0"].contains(value) { return false }
      print("Enter yes or no.")
    }
  }

  private static func promptTimeout(default defaultValue: TimeInterval) -> TimeInterval {
    while true {
      let value = prompt("Connection timeout in seconds", default: "\(Int(defaultValue))")
      if let timeout = TimeInterval(value), (3...60).contains(timeout) {
        return timeout
      }
      print("Enter a number between 3 and 60.")
    }
  }

  private static func promptStartMode(default defaultValue: TorrentStartMode)
    -> TorrentStartMode
  {
    while true {
      let value = prompt(
        "Start new torrents (immediately/paused)",
        default: defaultValue.rawValue
      )
      if let mode = TorrentStartMode(rawValue: value.lowercased()) {
        return mode
      }
      print("Enter immediately or paused.")
    }
  }

  private static func promptBrowser(default defaultValue: BrowserSelection)
    -> BrowserSelection
  {
    let browsers = BrowserLauncher().installedBrowsers()
    print("\nAvailable browsers:")
    for (index, browser) in browsers.enumerated() {
      print("  \(index + 1). \(browser.displayName)")
    }
    while true {
      let selected = prompt(
        "Browser number",
        default: browserDefaultIndex(
          defaultValue,
          in: browsers
        ))
      if let index = Int(selected), browsers.indices.contains(index - 1) {
        return browsers[index - 1]
      }
      print("Enter one of the listed numbers.")
    }
  }

  private static func browserDefaultIndex(
    _ browser: BrowserSelection,
    in browsers: [BrowserSelection]
  ) -> String {
    let index = browsers.firstIndex(of: browser) ?? 0
    return "\(index + 1)"
  }

  private static func browserSelection(for value: String) throws -> BrowserSelection {
    if value.lowercased() == "system" {
      return .systemDefault
    }
    if let browser = BrowserLauncher().installedBrowsers().first(where: {
      $0.bundleIdentifier == value
    }) {
      return browser
    }
    throw CLIError("No installed browser has bundle identifier \(value).")
  }

  private static func parseBoolean(_ value: String) throws -> Bool {
    switch value.lowercased() {
    case "true", "yes", "1", "on":
      true
    case "false", "no", "0", "off":
      false
    default:
      throw CLIError("Expected true or false.")
    }
  }

  private static func readSecret(_ prompt: String) -> String {
    guard let pointer = getpass(prompt) else { return "" }
    return String(cString: pointer)
  }

  private static func write(_ value: String) {
    FileHandle.standardOutput.write(Data(value.utf8))
  }

  private static func writeError(_ value: String) {
    FileHandle.standardError.write(Data("\(value)\n".utf8))
  }

  private static func printHelp() {
    print(
      """
      MagnetBridge \(version)

      Usage:
        magnetbridge configure
        magnetbridge test
        magnetbridge config show
        magnetbridge config set <key> <value>
        magnetbridge config unset-password
        magnetbridge config reset
        magnetbridge version

      Configuration keys:
        rpc-url, web-ui-url, username, password, browser, timeout,
        open-web-ui, start-mode, allow-http
      """
    )
  }
}

private struct CLIError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}
