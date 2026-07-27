import Darwin
import Foundation

enum TerminalUI {
  private enum ANSI {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let cyan = "\u{001B}[36m"
  }

  static var usesColor: Bool {
    let environment = ProcessInfo.processInfo.environment
    if environment["NO_COLOR"] != nil
      || environment["CLICOLOR"] == "0"
      || environment["TERM"] == "dumb"
    {
      return false
    }
    if environment["CLICOLOR_FORCE"] == "1" || environment["FORCE_COLOR"] == "1" {
      return true
    }
    return isatty(STDOUT_FILENO) != 0
  }

  static func banner(version: String) {
    line("")
    line("  🧲 \(styled("MagnetBridge", ANSI.bold + ANSI.cyan)) \(muted("v\(version)"))")
    line("  \(muted("Send magnet links to Transmission"))")
    line("")
  }

  static func section(_ icon: String, _ title: String) {
    line("")
    line("\(icon)  \(styled(title, ANSI.bold))")
    line(muted("────────────────────────────────────────"))
  }

  static func heading(_ title: String) {
    line(styled(title.uppercased(), ANSI.bold + ANSI.cyan))
  }

  static func note(_ message: String) {
    line("\(muted("›")) \(muted(message))")
  }

  static func info(_ message: String) {
    line("🔄 \(message)")
  }

  static func success(_ message: String) {
    line("✅ \(styled(message, ANSI.green))")
  }

  static func warning(_ message: String) {
    line("⚠️  \(styled(message, ANSI.yellow))")
  }

  static func failure(_ message: String) {
    errorLine("❌ \(styled(message, ANSI.red))")
  }

  static func keyValue(_ key: String, _ value: String) {
    let paddedKey = key.padding(toLength: 14, withPad: " ", startingAt: 0)
    line("  \(styled(paddedKey, ANSI.cyan)) \(value)")
  }

  static func command(_ value: String) -> String {
    styled(value, ANSI.cyan)
  }

  static func prompt(_ label: String, default defaultValue: String) -> String {
    "\(styled(label, ANSI.bold)) \(muted("[\(defaultValue)]")) \(styled("›", ANSI.cyan)) "
  }

  static func secretPrompt(_ label: String) -> String {
    "\(styled(label, ANSI.bold)) \(styled("›", ANSI.cyan)) "
  }

  static func choiceNumber(_ number: Int) -> String {
    styled("\(number).", ANSI.cyan)
  }

  static func muted(_ value: String) -> String {
    styled(value, ANSI.dim)
  }

  static func line(_ value: String) {
    FileHandle.standardOutput.write(Data("\(value)\n".utf8))
  }

  static func write(_ value: String) {
    FileHandle.standardOutput.write(Data(value.utf8))
  }

  private static func errorLine(_ value: String) {
    FileHandle.standardError.write(Data("\(value)\n".utf8))
  }

  private static func styled(_ value: String, _ style: String) -> String {
    guard usesColor else { return value }
    return "\(style)\(value)\(ANSI.reset)"
  }
}
