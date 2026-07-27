import SwiftUI

@main
struct MagnetBridgeApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    Window("MagnetBridge", id: "main") {
      ContentView(model: model)
        .frame(minWidth: 430, minHeight: 230)
        .onOpenURL { url in
          model.handleIncomingURL(url)
        }
        .task {
          model.start()
        }
    }
    .windowResizability(.contentSize)
    .defaultPosition(.center)

    Settings {
      SettingsView(model: model)
        .frame(width: 580, height: 540)
    }
  }
}
