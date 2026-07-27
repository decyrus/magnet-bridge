import MagnetBridgeCore
import SwiftUI

struct SettingsView: View {
  @Bindable var model: AppModel

  var body: some View {
    Form {
      Section("Transmission") {
        TextField("RPC URL", text: $model.settings.rpcURL)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("rpc-url")
        TextField("Web UI URL", text: $model.settings.webUIURL)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("web-ui-url")
        TextField("Username", text: $model.settings.username)
          .textFieldStyle(.roundedBorder)
        SecureField("Password", text: $model.password)
          .textFieldStyle(.roundedBorder)

        if usesInsecureHTTP {
          Toggle(
            "I understand that HTTP sends data without encryption",
            isOn: $model.settings.hasAcknowledgedInsecureHTTP
          )
          .foregroundStyle(.orange)
        }

        HStack {
          Button("Test Connection") {
            model.testConnection()
          }
          .disabled(model.connectionState == .testing)

          connectionStatus
        }
      }

      Section("Behavior") {
        Picker("Browser", selection: $model.settings.browser) {
          ForEach(model.browsers, id: \.self) { browser in
            Text(browser.displayName).tag(browser)
          }
        }
        .onAppear {
          model.refreshBrowsers()
        }

        Picker("Start New Torrents", selection: $model.settings.startMode) {
          Text("Immediately").tag(TorrentStartMode.immediately)
          Text("Paused").tag(TorrentStartMode.paused)
        }

        HStack {
          Text("Timeout")
          Slider(value: $model.settings.timeout, in: 3...60, step: 1)
          Text("\(Int(model.settings.timeout)) sec")
            .monospacedDigit()
            .frame(width: 58, alignment: .trailing)
        }

        Toggle("Open Web UI after adding a torrent", isOn: $model.settings.opensWebUI)
      }

      Section {
        HStack {
          Text("The password is stored only in macOS Keychain.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          if let message = model.saveMessage {
            Text(message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Button("Save") {
            model.saveSettings()
          }
          .keyboardShortcut(.defaultAction)
        }
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  @ViewBuilder
  private var connectionStatus: some View {
    switch model.connectionState {
    case .idle:
      EmptyView()
    case .testing:
      ProgressView()
        .controlSize(.small)
    case .success(let message):
      Label(message, systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.caption)
    case .failure(let message):
      Label(message, systemImage: "xmark.circle.fill")
        .foregroundStyle(.red)
        .font(.caption)
    }
  }

  private var usesInsecureHTTP: Bool {
    model.settings.rpcURL.lowercased().hasPrefix("http://")
  }
}
