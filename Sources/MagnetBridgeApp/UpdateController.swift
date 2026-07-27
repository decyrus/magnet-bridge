import Observation
import Sparkle

@MainActor
@Observable
final class UpdateController {
  @ObservationIgnored
  private let controller: SPUStandardUpdaterController

  init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  var automaticallyChecksForUpdates: Bool {
    get { controller.updater.automaticallyChecksForUpdates }
    set { controller.updater.automaticallyChecksForUpdates = newValue }
  }

  var canCheckForUpdates: Bool {
    controller.updater.canCheckForUpdates
  }

  var lastUpdateCheckDate: Date? {
    controller.updater.lastUpdateCheckDate
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}
