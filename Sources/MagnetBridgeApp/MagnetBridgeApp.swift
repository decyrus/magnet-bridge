import AppKit
import Carbon.HIToolbox
import Foundation
import MagnetBridgeCore
import SwiftUI

@main
enum MagnetBridgeMain {
  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let executableName = URL(fileURLWithPath: CommandLine.arguments[0])
      .lastPathComponent
    let magnetURLs = arguments.compactMap { argument -> URL? in
      guard argument.lowercased().hasPrefix("magnet:") else { return nil }
      return URL(string: argument)
    }

    if magnetURLs.isEmpty, !arguments.isEmpty || executableName == "magnetbridge" {
      Task {
        let exitCode = await CLIApplication.run(arguments)
        exit(exitCode)
      }
      RunLoop.main.run()
    } else {
      GUIApplication.run(magnetURLs: magnetURLs)
    }
  }
}

private enum GUIApplication {
  @MainActor
  static func run(magnetURLs: [URL]) {
    let application = NSApplication.shared
    let delegate = ApplicationDelegate(launchMagnetURLs: magnetURLs)
    application.delegate = delegate
    withExtendedLifetime(delegate) {
      application.run()
    }
  }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let notificationService = NotificationService()
  private let updateController = UpdateController()
  private lazy var model = AppModel(notificationService: notificationService)
  private let launchMagnetURLs: [URL]
  private var window: NSWindow?
  private var statusItem: NSStatusItem?

  init(launchMagnetURLs: [URL]) {
    self.launchMagnetURLs = launchMagnetURLs
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
    model.onMenuBarPreferenceChanged = { [weak self] isEnabled in
      self?.applyPresentationMode(showsMenuBarIcon: isEnabled)
    }
    model.onHandlerStateChanged = { [weak self] in
      self?.rebuildStatusMenu()
    }
    configureMainMenu()
    createWindow()
    applyPresentationMode(showsMenuBarIcon: model.settings.showsMenuBarIcon)
    if let launchMagnetURL = launchMagnetURLs.first {
      model.receive(launchMagnetURL)
    }
    showWindow()

    Task {
      await notificationService.requestAuthorization()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    NSAppleEventManager.shared().removeEventHandler(
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    !model.settings.showsMenuBarIcon
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    showWindow()
    return true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    true
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
    model.receive(url)
    showWindow()
  }

  private func createWindow() {
    let contentView = MainView(model: model, updater: updateController)
    let hostingController = NSHostingController(rootView: contentView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "MagnetBridge"
    window.setContentSize(NSSize(width: 620, height: 700))
    window.minSize = NSSize(width: 570, height: 560)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.isMovableByWindowBackground = true
    window.center()
    window.delegate = self
    window.setFrameAutosaveName("MagnetBridge.MainWindow.v2")
    self.window = window
  }

  @objc
  private func showWindow() {
    guard let window else { return }
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  private func applyPresentationMode(showsMenuBarIcon: Bool) {
    if showsMenuBarIcon {
      NSApplication.shared.setActivationPolicy(.accessory)
      installStatusItem()
    } else {
      removeStatusItem()
      NSApplication.shared.setActivationPolicy(.regular)
      configureMainMenu()
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }

  private func installStatusItem() {
    guard statusItem == nil else {
      rebuildStatusMenu()
      return
    }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      button.image = NSImage(named: "MenuBarIcon")
      button.image?.isTemplate = true
      button.toolTip = "MagnetBridge"
      button.setAccessibilityLabel("MagnetBridge")
    }
    statusItem = item
    rebuildStatusMenu()
  }

  private func removeStatusItem() {
    guard let statusItem else { return }
    NSStatusBar.system.removeStatusItem(statusItem)
    self.statusItem = nil
  }

  private func rebuildStatusMenu() {
    let menu = NSMenu()
    menu.addItem(
      withTitle: "Open MagnetBridge…",
      action: #selector(showWindow),
      keyEquivalent: ""
    ).target = self

    let handlerItem = NSMenuItem(
      title: model.currentHandler.hasPrefix("MagnetBridge")
        ? "✓ Default magnet handler"
        : "Not the default magnet handler",
      action: nil,
      keyEquivalent: ""
    )
    handlerItem.isEnabled = false
    menu.addItem(handlerItem)
    menu.addItem(.separator())

    let testItem = menu.addItem(
      withTitle: "Test Connection",
      action: #selector(testConnection),
      keyEquivalent: ""
    )
    testItem.target = self

    let updateItem = menu.addItem(
      withTitle: "Check for Updates…",
      action: #selector(checkForUpdates),
      keyEquivalent: ""
    )
    updateItem.target = self

    let helpItem = menu.addItem(
      withTitle: "MagnetBridge Help",
      action: #selector(showHelp),
      keyEquivalent: ""
    )
    helpItem.target = self

    let defaultItem = menu.addItem(
      withTitle: "Make Default for Magnet Links",
      action: #selector(makeDefaultHandler),
      keyEquivalent: ""
    )
    defaultItem.target = self
    menu.addItem(.separator())

    let quitItem = menu.addItem(
      withTitle: "Quit MagnetBridge",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = NSApplication.shared
    statusItem?.menu = menu
  }

  private func configureMainMenu() {
    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem(
      title: "MagnetBridge",
      action: nil,
      keyEquivalent: ""
    )
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "About MagnetBridge",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    ).target = NSApplication.shared
    let updateItem = appMenu.addItem(
      withTitle: "Check for Updates…",
      action: #selector(checkForUpdates),
      keyEquivalent: ""
    )
    updateItem.target = self
    appMenu.addItem(.separator())
    let openItem = appMenu.addItem(
      withTitle: "Open MagnetBridge…",
      action: #selector(showWindow),
      keyEquivalent: ""
    )
    openItem.target = self
    let helpItem = appMenu.addItem(
      withTitle: "MagnetBridge Help",
      action: #selector(showHelp),
      keyEquivalent: "?"
    )
    helpItem.target = self
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Quit MagnetBridge",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    appMenuItem.submenu = appMenu
    NSApplication.shared.mainMenu = mainMenu
  }

  @objc
  private func testConnection() {
    showWindow()
    Task { await model.testConnection() }
  }

  @objc
  private func makeDefaultHandler() {
    showWindow()
    Task {
      await model.makeDefaultHandler()
      rebuildStatusMenu()
    }
  }

  @objc
  private func checkForUpdates() {
    updateController.checkForUpdates()
  }

  @objc
  private func showHelp() {
    showWindow()
    model.showsHelp = true
  }
}
