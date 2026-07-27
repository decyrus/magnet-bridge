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
        TextField("Имя пользователя", text: $model.settings.username)
          .textFieldStyle(.roundedBorder)
        SecureField("Пароль", text: $model.password)
          .textFieldStyle(.roundedBorder)

        if usesInsecureHTTP {
          Toggle(
            "Я понимаю, что HTTP передаёт данные без шифрования",
            isOn: $model.settings.hasAcknowledgedInsecureHTTP
          )
          .foregroundStyle(.orange)
        }

        HStack {
          Button("Проверить соединение") {
            model.testConnection()
          }
          .disabled(model.connectionState == .testing)

          connectionStatus
        }
      }

      Section("Поведение") {
        Picker("Браузер", selection: $model.settings.browser) {
          ForEach(model.browsers, id: \.self) { browser in
            Text(browser.displayName).tag(browser)
          }
        }
        .onAppear {
          model.refreshBrowsers()
        }

        Picker("Запуск торрента", selection: $model.settings.startMode) {
          Text("Сразу").tag(TorrentStartMode.immediately)
          Text("Приостановлен").tag(TorrentStartMode.paused)
        }

        HStack {
          Text("Тайм-аут")
          Slider(value: $model.settings.timeout, in: 3...60, step: 1)
          Text("\(Int(model.settings.timeout)) с")
            .monospacedDigit()
            .frame(width: 40, alignment: .trailing)
        }

        Toggle("Открывать Web UI после добавления", isOn: $model.settings.opensWebUI)
      }

      Section {
        HStack {
          Text("Пароль хранится только в macOS Keychain.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          if let message = model.saveMessage {
            Text(message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Button("Сохранить") {
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
