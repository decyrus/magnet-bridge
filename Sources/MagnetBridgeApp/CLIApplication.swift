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
        try await configure(Array(arguments.dropFirst()))
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
      TerminalUI.failure(error.localizedDescription)
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

  private static func configure(_ arguments: [String]) async throws {
    guard isatty(STDIN_FILENO) != 0 else {
      throw CLIError("The configuration wizard requires an interactive terminal.")
    }
    let usesAdvancedEndpoints: Bool
    switch arguments {
    case []:
      usesAdvancedEndpoints = false
    case ["--advanced"]:
      usesAdvancedEndpoints = true
    default:
      throw CLIError("Usage: magnetbridge configure [--advanced]")
    }

    var settings = settingsStore.load()
    TerminalUI.banner(version: version)
    TerminalUI.heading("Configuration")
    TerminalUI.note("Press Return to keep the value shown in brackets.")

    TerminalUI.section("🌐", "Transmission server")
    if usesAdvancedEndpoints {
      settings.rpcURL = prompt("Transmission RPC URL", default: settings.rpcURL)
      settings.webUIURL = prompt("Transmission Web UI URL", default: settings.webUIURL)
    } else {
      TerminalUI.note("Standard RPC and Web UI paths are added automatically.")
      let defaultAddress =
        TransmissionEndpointResolver.serverAddress(fromRPCURL: settings.rpcURL)
        ?? "http://localhost:9091"
      let address = prompt(
        "Transmission server address",
        default: defaultAddress
      )
      let endpoints = try standardEndpoints(for: address)
      settings.rpcURL = endpoints.rpcURL
      settings.webUIURL = endpoints.webUIURL
    }

    TerminalUI.section("🔐", "Basic Authentication")
    settings.username = prompt(
      "Basic Auth username (leave empty to disable)",
      default: settings.username
    )

    let hasPassword = (try passwordStore.readPassword())?.isEmpty == false
    var passwordUpdate: String?
    if settings.username.isEmpty, hasPassword {
      if promptBoolean("Remove the saved Basic Auth password?", default: true) {
        passwordUpdate = ""
      }
    } else if !settings.username.isEmpty,
      promptBoolean(
        hasPassword ? "Replace the saved password?" : "Save a Transmission password?",
        default: !hasPassword
      )
    {
      passwordUpdate = readSecret("Transmission password")
    }

    TerminalUI.section("⚙️", "Behavior")
    settings.timeout = promptTimeout(default: settings.timeout)
    settings.startMode = promptStartMode(default: settings.startMode)
    settings.opensWebUI = promptBoolean(
      "Open the Web UI after adding a torrent?",
      default: settings.opensWebUI
    )

    TerminalUI.section("🌍", "Browser")
    settings.browser = promptBrowser(default: settings.browser)

    if URL(string: settings.rpcURL)?.scheme?.lowercased() == "http" {
      TerminalUI.section("⚠️", "Transport security")
      TerminalUI.warning("Basic Auth over HTTP is not encrypted.")
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
    TerminalUI.line("")
    TerminalUI.success("Configuration saved")

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
      try showConfiguration(Array(arguments.dropFirst()))
    case "set":
      try setConfiguration(Array(arguments.dropFirst()))
    case "reset":
      try settingsStore.save(.defaults)
      try passwordStore.deletePassword()
      TerminalUI.success("Configuration and saved password reset")
    case "unset-password":
      try passwordStore.deletePassword()
      TerminalUI.success("Saved password removed")
    default:
      throw CLIError("Unknown config command: \(subcommand)")
    }
  }

  private static func showConfiguration(_ arguments: [String]) throws {
    let showsAdvancedEndpoints: Bool
    switch arguments {
    case []:
      showsAdvancedEndpoints = false
    case ["--advanced"]:
      showsAdvancedEndpoints = true
    default:
      throw CLIError("Usage: magnetbridge config show [--advanced]")
    }

    let settings = settingsStore.load()
    let hasPassword = (try passwordStore.readPassword())?.isEmpty == false
    TerminalUI.banner(version: version)
    TerminalUI.heading("Configuration")
    if let address = TransmissionEndpointResolver.serverAddress(fromRPCURL: settings.rpcURL) {
      TerminalUI.keyValue("server", address)
    }
    if showsAdvancedEndpoints {
      TerminalUI.keyValue("rpc-url", settings.rpcURL)
      TerminalUI.keyValue("web-ui-url", settings.webUIURL)
    }
    TerminalUI.keyValue("username", settings.username.isEmpty ? "disabled" : settings.username)
    TerminalUI.keyValue("password", hasPassword ? "configured" : "not configured")
    TerminalUI.keyValue("browser", settings.browser.bundleIdentifier ?? "system")
    TerminalUI.keyValue("timeout", "\(Int(settings.timeout)) seconds")
    TerminalUI.keyValue("open-web-ui", "\(settings.opensWebUI)")
    TerminalUI.keyValue("start-mode", settings.startMode.rawValue)
    TerminalUI.keyValue("allow-http", "\(settings.hasAcknowledgedInsecureHTTP)")
  }

  private static func setConfiguration(_ arguments: [String]) throws {
    guard let key = arguments.first else {
      throw CLIError("Usage: magnetbridge config set <key> <value>")
    }

    if key == "password" {
      let password = readSecret("Transmission password")
      if password.isEmpty {
        try passwordStore.deletePassword()
      } else {
        try passwordStore.savePassword(password)
      }
      TerminalUI.success("Password updated")
      return
    }

    guard arguments.count >= 2 else {
      throw CLIError("Usage: magnetbridge config set <key> <value>")
    }
    let value = arguments.dropFirst().joined(separator: " ")
    var settings = settingsStore.load()

    switch key {
    case "server":
      let endpoints = try standardEndpoints(for: value)
      settings.rpcURL = endpoints.rpcURL
      settings.webUIURL = endpoints.webUIURL
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
    TerminalUI.success("\(key) updated")
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
    TerminalUI.info("Testing the Transmission connection…")
    let info = try await client.testConnection()
    TerminalUI.success(
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
    TerminalUI.write(TerminalUI.prompt(label, default: defaultValue))
    let value = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? defaultValue : value
  }

  private static func promptBoolean(_ label: String, default defaultValue: Bool) -> Bool {
    while true {
      TerminalUI.write(
        TerminalUI.prompt(label, default: defaultValue ? "Y/n" : "y/N")
      )
      let value =
        readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
      if value.isEmpty { return defaultValue }
      if ["y", "yes", "true", "1"].contains(value) { return true }
      if ["n", "no", "false", "0"].contains(value) { return false }
      TerminalUI.warning("Enter yes or no.")
    }
  }

  private static func promptTimeout(default defaultValue: TimeInterval) -> TimeInterval {
    while true {
      let value = prompt("Connection timeout in seconds", default: "\(Int(defaultValue))")
      if let timeout = TimeInterval(value), (3...60).contains(timeout) {
        return timeout
      }
      TerminalUI.warning("Enter a number between 3 and 60.")
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
      TerminalUI.warning("Enter immediately or paused.")
    }
  }

  private static func promptBrowser(default defaultValue: BrowserSelection)
    -> BrowserSelection
  {
    let browsers = BrowserLauncher().installedBrowsers()
    TerminalUI.note("Available browsers:")
    for (index, browser) in browsers.enumerated() {
      TerminalUI.line("  \(TerminalUI.choiceNumber(index + 1)) \(browser.displayName)")
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
      TerminalUI.warning("Enter one of the listed numbers.")
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

  private static func standardEndpoints(for address: String) throws
    -> TransmissionEndpoints
  {
    do {
      return try TransmissionEndpointResolver.resolve(serverAddress: address)
    } catch {
      throw CLIError(
        "Enter only an HTTP or HTTPS server address, for example "
          + "https://transmission.example:9091. Use --advanced for custom paths."
      )
    }
  }

  private static func readSecret(_ prompt: String) -> String {
    guard let pointer = getpass(TerminalUI.secretPrompt(prompt)) else { return "" }
    return String(cString: pointer)
  }

  private static func printHelp() {
    TerminalUI.banner(version: version)
    TerminalUI.heading("Usage")
    TerminalUI.line(
      "  \(TerminalUI.command("magnetbridge configure")) \(TerminalUI.muted("[--advanced]"))"
    )
    TerminalUI.line("  \(TerminalUI.command("magnetbridge test"))")
    TerminalUI.line(
      "  \(TerminalUI.command("magnetbridge config show")) \(TerminalUI.muted("[--advanced]"))"
    )
    TerminalUI.line(
      "  \(TerminalUI.command("magnetbridge config set")) \(TerminalUI.muted("<key> <value>"))"
    )
    TerminalUI.line("  \(TerminalUI.command("magnetbridge config unset-password"))")
    TerminalUI.line("  \(TerminalUI.command("magnetbridge config reset"))")
    TerminalUI.line("  \(TerminalUI.command("magnetbridge version"))")
    TerminalUI.line("")
    TerminalUI.heading("Configuration keys")
    TerminalUI.line("  server, username, password, browser, timeout,")
    TerminalUI.line("  open-web-ui, start-mode, allow-http")
    TerminalUI.line("")
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
