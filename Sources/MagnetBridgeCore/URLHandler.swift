import Foundation

public enum URLHandlingResult: Equatable, Sendable {
  case added(TorrentSummary)
  case duplicate(TorrentSummary)
  case failed(MagnetBridgeError)
}

public actor URLHandler {
  private let validator: MagnetValidator
  private let settingsStore: any SettingsStoring
  private let passwordStore: any PasswordStoring
  private let browserLauncher: any BrowserLaunching
  private let notificationService: any NotificationServing
  private let session: any NetworkSession

  public init(
    validator: MagnetValidator = MagnetValidator(),
    settingsStore: any SettingsStoring,
    passwordStore: any PasswordStoring,
    browserLauncher: any BrowserLaunching,
    notificationService: any NotificationServing,
    session: any NetworkSession = URLSessionNetworkSession()
  ) {
    self.validator = validator
    self.settingsStore = settingsStore
    self.passwordStore = passwordStore
    self.browserLauncher = browserLauncher
    self.notificationService = notificationService
    self.session = session
  }

  public func handle(_ url: URL) async -> URLHandlingResult {
    do {
      let magnet = try validator.validate(url)
      let settings = settingsStore.load()
      guard let rpcURL = URL(string: settings.rpcURL) else {
        throw MagnetBridgeError.invalidRPCURL
      }
      let password = try passwordStore.readPassword()
      let client = TransmissionClient(
        configuration: TransmissionConfiguration(
          rpcURL: rpcURL,
          username: settings.username,
          password: password,
          timeout: settings.timeout,
          allowsInsecureHTTP: settings.hasAcknowledgedInsecureHTTP
        ),
        session: session
      )
      let outcome = try await client.add(
        magnetURL: magnet.url,
        paused: settings.startMode == .paused
      )

      let result: URLHandlingResult
      switch outcome {
      case .added(let torrent):
        result = .added(torrent)
        await notificationService.show(
          title: "Торрент добавлен",
          body: torrent.name
        )
      case .duplicate(let torrent):
        result = .duplicate(torrent)
        await notificationService.show(
          title: "Торрент уже добавлен",
          body: torrent.name
        )
      }

      if settings.opensWebUI, let webURL = URL(string: settings.webUIURL) {
        do {
          let launch = try await browserLauncher.open(
            webURL,
            using: settings.browser
          )
          if launch.usedFallback {
            await notificationService.show(
              title: "Браузер не найден",
              body: "Web UI открыт в системном браузере."
            )
          }
        } catch {
          await notificationService.show(
            title: "Не удалось открыть Web UI",
            body: error.localizedDescription
          )
        }
      }
      return result
    } catch let error as MagnetBridgeError {
      await notificationService.show(
        title: "Не удалось добавить торрент",
        body: error.localizedDescription
      )
      return .failed(error)
    } catch {
      let mapped = MagnetBridgeError.rpcError(error.localizedDescription)
      await notificationService.show(
        title: "Не удалось добавить торрент",
        body: mapped.localizedDescription
      )
      return .failed(mapped)
    }
  }
}
