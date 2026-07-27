import AppKit
import Carbon.HIToolbox
import Foundation
import MagnetBridgeCore

@main
enum MagnetBridgeMain {
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let executableName = URL(fileURLWithPath: CommandLine.arguments[0])
      .lastPathComponent
    if !arguments.isEmpty || executableName == "magnetbridge" {
      Task {
        let exitCode = await CLIApplication.run(arguments)
        exit(exitCode)
      }
      RunLoop.main.run()
    } else {
      HeadlessApplication.run()
    }
  }
}

private enum HeadlessApplication {
  @MainActor
  static func run() {
    let application = NSApplication.shared
    let delegate = ApplicationDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    withExtendedLifetime(delegate) {
      application.run()
    }
  }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
  private let notificationService = NotificationService()
  private let handler: URLHandler
  private var receivedURL = false
  private var activeRequests = 0

  override init() {
    let settingsStore = SettingsStore()
    let passwordStore = KeychainStore()
    let browserLauncher = BrowserLauncher()
    self.handler = URLHandler(
      settingsStore: settingsStore,
      passwordStore: passwordStore,
      browserLauncher: browserLauncher,
      notificationService: notificationService
    )
    super.init()
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    Task {
      await notificationService.requestAuthorization()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self, !receivedURL, activeRequests == 0 else { return }
      NSApplication.shared.terminate(nil)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    NSAppleEventManager.shared().removeEventHandler(
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  @objc
  private func handleGetURLEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent replyEvent: NSAppleEventDescriptor
  ) {
    guard
      let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let url = URL(string: rawURL)
    else {
      return
    }

    receivedURL = true
    activeRequests += 1
    Task {
      _ = await handler.handle(url)
      activeRequests -= 1
      if activeRequests == 0 {
        NSApplication.shared.terminate(nil)
      }
    }
  }
}
