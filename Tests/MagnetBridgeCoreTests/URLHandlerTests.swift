import Foundation
import XCTest

@testable import MagnetBridgeCore

final class URLHandlerTests: XCTestCase {
  func testDuplicateIsSuccessAndOpensSelectedBrowser() async throws {
    let settings = configuredSettings
    let browser = RecordingBrowserLauncher()
    let notifications = RecordingNotificationService()
    let session = HandlerSession([
      .response(
        status: 409,
        headers: ["X-Transmission-Session-Id": "session"]
      ),
      .response(
        status: 200,
        body:
          #"{"result":"success","arguments":{"torrent-duplicate":{"id":3,"name":"Existing","hashString":"abc"}}}"#
      ),
    ])
    let handler = URLHandler(
      settingsStore: FixedSettingsStore(settings: settings),
      passwordStore: FixedPasswordStore(password: "secret"),
      browserLauncher: browser,
      notificationService: notifications,
      session: session
    )
    let magnet = try XCTUnwrap(
      URL(
        string:
          "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
      )
    )

    let result = await handler.handle(magnet)

    XCTAssertEqual(
      result,
      .duplicate(TorrentSummary(id: 3, name: "Existing", hash: "abc"))
    )
    let launch = browser.lastLaunch()
    XCTAssertEqual(launch?.url.absoluteString, settings.webUIURL)
    XCTAssertEqual(launch?.browser, settings.browser)
    let shownNotifications = await notifications.notifications
    XCTAssertTrue(shownNotifications.contains { $0.title == "Torrent Already Added" })
  }

  func testDisabledAuthenticationDoesNotReadPasswordOrSendHeader() async throws {
    var settings = configuredSettings
    settings.usesAuthentication = false
    settings.opensWebUI = false
    let passwordStore = RecordingPasswordStore(password: "retained-secret")
    let session = HandlerSession([
      .response(
        status: 200,
        body:
          #"{"result":"success","arguments":{"torrent-added":{"id":4,"name":"Added","hashString":"def"}}}"#
      )
    ])
    let handler = URLHandler(
      settingsStore: FixedSettingsStore(settings: settings),
      passwordStore: passwordStore,
      browserLauncher: RecordingBrowserLauncher(),
      notificationService: RecordingNotificationService(),
      session: session
    )

    _ = await handler.handle(try validMagnetURL())

    XCTAssertEqual(passwordStore.readCount, 0)
    let requests = await session.requests
    XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
  }

  func testEnabledAuthenticationReadsPasswordAndSendsHeader() async throws {
    var settings = configuredSettings
    settings.usesAuthentication = true
    settings.opensWebUI = false
    let passwordStore = RecordingPasswordStore(password: "secret")
    let session = HandlerSession([
      .response(
        status: 200,
        body:
          #"{"result":"success","arguments":{"torrent-added":{"id":4,"name":"Added","hashString":"def"}}}"#
      )
    ])
    let handler = URLHandler(
      settingsStore: FixedSettingsStore(settings: settings),
      passwordStore: passwordStore,
      browserLauncher: RecordingBrowserLauncher(),
      notificationService: RecordingNotificationService(),
      session: session
    )

    _ = await handler.handle(try validMagnetURL())

    XCTAssertEqual(passwordStore.readCount, 1)
    let requests = await session.requests
    XCTAssertEqual(
      requests.first?.value(forHTTPHeaderField: "Authorization"),
      "Basic \(Data("alice:secret".utf8).base64EncodedString())"
    )
  }

  func testInvalidMagnetNeverContactsServerOrBrowser() async throws {
    let browser = RecordingBrowserLauncher()
    let session = HandlerSession([])
    let handler = URLHandler(
      settingsStore: FixedSettingsStore(settings: configuredSettings),
      passwordStore: FixedPasswordStore(password: nil),
      browserLauncher: browser,
      notificationService: RecordingNotificationService(),
      session: session
    )
    let invalidURL = try XCTUnwrap(URL(string: "https://example.com/not-magnet"))

    let result = await handler.handle(invalidURL)

    guard case .failed(.invalidMagnet) = result else {
      return XCTFail("Expected invalid magnet, got \(result)")
    }
    XCTAssertNil(browser.lastLaunch())
    let requestCount = await session.requestCount
    XCTAssertEqual(requestCount, 0)
  }

  func testBrowserFailureDoesNotTurnSuccessfulAddIntoFailure() async throws {
    let browser = RecordingBrowserLauncher(error: .browserUnavailable("Missing"))
    let session = HandlerSession([
      .response(
        status: 200,
        body:
          #"{"result":"success","arguments":{"torrent-added":{"id":4,"name":"Added","hashString":"def"}}}"#
      )
    ])
    let handler = URLHandler(
      settingsStore: FixedSettingsStore(settings: configuredSettings),
      passwordStore: FixedPasswordStore(password: nil),
      browserLauncher: browser,
      notificationService: RecordingNotificationService(),
      session: session
    )
    let magnet = try XCTUnwrap(
      URL(
        string:
          "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
      )
    )

    let result = await handler.handle(magnet)

    XCTAssertEqual(
      result,
      .added(TorrentSummary(id: 4, name: "Added", hash: "def"))
    )
  }

  private var configuredSettings: AppSettings {
    AppSettings(
      rpcURL: "http://transmission.example/rpc",
      webUIURL: "https://transmission.example/web/",
      username: "alice",
      browser: BrowserSelection(
        bundleIdentifier: "com.example.Browser",
        displayName: "Example Browser"
      ),
      timeout: 5,
      opensWebUI: true,
      startMode: .paused,
      hasAcknowledgedInsecureHTTP: true
    )
  }

  private func validMagnetURL() throws -> URL {
    try XCTUnwrap(
      URL(
        string:
          "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
      )
    )
  }
}

private struct FixedSettingsStore: SettingsStoring {
  let settings: AppSettings

  func load() -> AppSettings {
    settings
  }

  func save(_ settings: AppSettings) throws {}
}

private struct FixedPasswordStore: PasswordStoring {
  let password: String?

  func readPassword() throws -> String? {
    password
  }

  func savePassword(_ password: String) throws {}
  func deletePassword() throws {}
}

private final class RecordingPasswordStore: PasswordStoring, @unchecked Sendable {
  private let lock = NSLock()
  private let password: String?
  private var reads = 0

  init(password: String?) {
    self.password = password
  }

  var readCount: Int {
    lock.withLock { reads }
  }

  func readPassword() throws -> String? {
    lock.withLock {
      reads += 1
      return password
    }
  }

  func savePassword(_ password: String) throws {}
  func deletePassword() throws {}
}

private final class RecordingBrowserLauncher: BrowserLaunching, @unchecked Sendable {
  struct Launch {
    let url: URL
    let browser: BrowserSelection
  }

  private let lock = NSLock()
  private var launch: Launch?
  private let error: MagnetBridgeError?

  init(error: MagnetBridgeError? = nil) {
    self.error = error
  }

  func installedBrowsers() -> [BrowserSelection] {
    [.systemDefault]
  }

  func open(
    _ url: URL,
    using browser: BrowserSelection
  ) async throws -> BrowserLaunchResult {
    if let error {
      throw error
    }
    lock.withLock {
      launch = Launch(url: url, browser: browser)
    }
    return BrowserLaunchResult(usedFallback: false)
  }

  func lastLaunch() -> Launch? {
    lock.withLock { launch }
  }
}

private actor RecordingNotificationService: NotificationServing {
  struct Notification: Sendable {
    let title: String
    let body: String
  }

  private(set) var notifications: [Notification] = []

  func requestAuthorization() async {}

  func show(title: String, body: String) async {
    notifications.append(Notification(title: title, body: body))
  }
}

private actor HandlerSession: NetworkSession {
  enum Item: Sendable {
    case response(status: Int, body: String = "", headers: [String: String] = [:])
  }

  private var items: [Item]
  private(set) var requestCount = 0
  private(set) var requests: [URLRequest] = []

  init(_ items: [Item]) {
    self.items = items
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requestCount += 1
    requests.append(request)
    guard !items.isEmpty else {
      throw URLError(.badServerResponse)
    }
    switch items.removeFirst() {
    case .response(let status, let body, let headers):
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
      )!
      return (Data(body.utf8), response)
    }
  }
}
