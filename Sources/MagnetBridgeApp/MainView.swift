import AppKit
import MagnetBridgeCore
import SwiftUI

struct MainView: View {
  @Bindable var model: AppModel
  @Bindable var updater: UpdateController
  @State private var showsSettingsForPendingLink = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      if model.pendingMagnetURL != nil, !showsSettingsForPendingLink {
        MagnetChoiceView(
          model: model,
          showSettings: { showsSettingsForPendingLink = true }
        )
      } else {
        SettingsView(
          model: model,
          updater: updater,
          hasPendingLink: model.pendingMagnetURL != nil,
          returnToLink: { showsSettingsForPendingLink = false }
        )
      }
    }
    .frame(minWidth: 570, idealWidth: 620, maxWidth: 700, minHeight: 560)
    .background(Color(nsColor: .windowBackgroundColor))
    .sheet(isPresented: $model.showsHelp) {
      HelpView(updater: updater)
    }
    .onChange(of: model.pendingMagnetURL?.absoluteString) {
      showsSettingsForPendingLink = false
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text("MagnetBridge")
          .font(.headline)
        Text("Magnet links → Transmission")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button {
        model.showsHelp = true
      } label: {
        Image(systemName: "questionmark.circle")
          .font(.system(size: 16, weight: .medium))
      }
      .buttonStyle(.plain)
      .help("MagnetBridge Help")
      .accessibilityLabel("MagnetBridge Help")

      HStack(spacing: 6) {
        Circle()
          .fill(model.currentHandler.hasPrefix("MagnetBridge") ? Color.green : Color.orange)
          .frame(width: 7, height: 7)
        Text(
          model.currentHandler.hasPrefix("MagnetBridge")
            ? "Default handler"
            : "Not the default"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(.quaternary, in: Capsule())
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 9)
  }
}

private struct MagnetChoiceView: View {
  @Bindable var model: AppModel
  let showSettings: () -> Void

  var body: some View {
    VStack(spacing: 18) {
      Spacer(minLength: 18)

      Image(systemName: "arrow.triangle.branch")
        .font(.system(size: 34, weight: .medium))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.tint)

      VStack(spacing: 5) {
        Text("Where should this link open?")
          .font(.title2.weight(.semibold))
        Text(model.pendingMagnetName)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }

      VStack(spacing: 10) {
        Button {
          Task { await model.sendPendingMagnetToServer() }
        } label: {
          Label("Send to Transmission Server", systemImage: "server.rack")
            .frame(maxWidth: .infinity)
            .frame(height: 28)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isBusy)

        if !model.handlerApplications.isEmpty {
          Text("OR OPEN LOCALLY")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 3)

          ForEach(model.handlerApplications) { application in
            Button {
              Task { await model.openPendingMagnet(with: application) }
            } label: {
              HStack(spacing: 10) {
                Image(nsImage: application.icon)
                  .resizable()
                  .frame(width: 24, height: 24)
                  .accessibilityHidden(true)
                Text(application.name)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                  .foregroundStyle(.secondary)
              }
              .contentShape(Rectangle())
              .padding(.horizontal, 10)
              .frame(height: 38)
            }
            .buttonStyle(.plain)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            .disabled(model.isBusy)
          }
        }
      }
      .frame(maxWidth: 390)

      if let notice = model.notice {
        NoticeBanner(notice: notice)
          .frame(maxWidth: 430)
      }

      HStack {
        Button("Cancel", role: .cancel) {
          model.cancelPendingMagnet()
        }
        Spacer()
        Button("Copy Link") {
          model.copyPendingMagnet()
        }
        Button("Settings…") {
          showSettings()
        }
      }
      .buttonStyle(.borderless)
      .font(.callout)
      .disabled(model.isBusy)

      Spacer(minLength: 12)
    }
    .padding(.horizontal, 28)
    .padding(.bottom, 18)
  }
}

private struct SettingsView: View {
  @Bindable var model: AppModel
  @Bindable var updater: UpdateController
  let hasPendingLink: Bool
  let returnToLink: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 8) {
          if hasPendingLink {
            Button {
              returnToLink()
            } label: {
              Label("Return to magnet link", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          connectionSection
          behaviorSection
          integrationSection

          if let notice = model.notice {
            NoticeBanner(notice: notice)
          }
        }
        .padding(10)
      }

      Divider()
      HStack {
        Button {
          Task { await model.testConnection() }
        } label: {
          Label("Test Connection", systemImage: "wave.3.right")
        }
        .disabled(model.isBusy)

        Spacer()

        if model.isBusy {
          ProgressView()
            .controlSize(.small)
        }

        Button {
          Task { await model.save() }
        } label: {
          Text("Save & Make Default")
            .frame(minWidth: 124)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(model.isBusy)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
    }
  }

  private var connectionSection: some View {
    SettingsCard(title: "Transmission Server", systemImage: "server.rack") {
      VStack(alignment: .leading, spacing: 8) {
        LabeledContent("Server") {
          TextField("https://server.example:9091", text: $model.serverAddress)
            .textFieldStyle(.roundedBorder)
            .frame(width: 380)
        }
        Text(
          model.usesCustomEndpoints
            ? "The custom URLs below override the standard Transmission paths."
            : "Standard Transmission RPC and Web UI paths are added automatically."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Toggle(
          "Use custom endpoint URLs",
          isOn: $model.usesCustomEndpoints
        )
        .toggleStyle(.checkbox)

        if model.usesCustomEndpoints {
          LabeledContent("RPC URL") {
            TextField(
              "https://server.example/transmission/rpc",
              text: $model.settings.rpcURL
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 380)
          }
          LabeledContent("Web UI URL") {
            TextField(
              "https://server.example/transmission/web/",
              text: $model.settings.webUIURL
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 380)
          }
        }

        Divider()

        Toggle(
          "Use Basic Authentication",
          isOn: Binding(
            get: { model.settings.usesAuthentication },
            set: { model.setAuthenticationEnabled($0) }
          )
        )
        .toggleStyle(.checkbox)

        if model.settings.usesAuthentication {
          HStack(spacing: 8) {
            Text("Username")
              .frame(width: 64, alignment: .leading)
            TextField("Transmission username", text: $model.settings.username)
              .textFieldStyle(.roundedBorder)
              .frame(width: 150)
              .accessibilityLabel("Username")
            Text("Password")
              .frame(width: 62, alignment: .leading)
            SecureField(
              model.hasStoredPassword ? "Stored in Keychain" : "Transmission password",
              text: $model.passwordInput
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
            .accessibilityLabel("Password")
            if model.hasStoredPassword {
              Button {
                model.removeStoredPassword()
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.borderless)
              .help("Remove saved password from Keychain")
              .accessibilityLabel("Remove saved password from Keychain")
            }
          }
        }

        if model.isUsingInsecureHTTP {
          HStack(spacing: 10) {
            Toggle(
              "Allow unencrypted HTTP connection",
              isOn: $model.settings.hasAcknowledgedInsecureHTTP
            )
            .tint(.orange)
            .toggleStyle(.checkbox)
            Text(
              model.settings.usesAuthentication
                ? "Credentials are exposed over HTTP."
                : "Traffic is exposed over HTTP."
            )
            .font(.caption)
            .foregroundStyle(.orange)
          }
        }
      }
    }
  }

  private var behaviorSection: some View {
    SettingsCard(title: "Behavior", systemImage: "slider.horizontal.3") {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 12) {
          Text("Start torrents")
            .frame(width: 132, alignment: .leading)
          Picker("", selection: $model.settings.startMode) {
            Text("Immediately").tag(TorrentStartMode.immediately)
            Text("Paused").tag(TorrentStartMode.paused)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 240)
          .accessibilityLabel("Start torrents")
        }

        Toggle("Open Transmission Web UI after adding", isOn: $model.settings.opensWebUI)
          .toggleStyle(.checkbox)

        if model.settings.opensWebUI {
          HStack(spacing: 12) {
            Text("Browser")
              .frame(width: 132, alignment: .leading)
            Picker("", selection: $model.settings.browser) {
              ForEach(model.browserOptions) { option in
                HStack(spacing: 6) {
                  Image(nsImage: option.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                  Text(option.selection.displayName)
                }
                .tag(option.selection)
              }
            }
            .labelsHidden()
            .frame(width: 240)
            .accessibilityLabel("Browser")
          }
        }

        HStack(spacing: 12) {
          Text("Connection timeout")
            .frame(width: 132, alignment: .leading)
          Stepper(
            "\(Int(model.settings.timeout)) seconds",
            value: $model.settings.timeout,
            in: SettingsValidator.allowedTimeouts,
            step: 1
          )
          .frame(width: 160, alignment: .leading)
          .accessibilityLabel("Connection timeout")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var integrationSection: some View {
    SettingsCard(title: "macOS Integration", systemImage: "macwindow") {
      VStack(alignment: .leading, spacing: 6) {
        Toggle(
          "Keep MagnetBridge in the menu bar",
          isOn: Binding(
            get: { model.showsMenuBarIcon },
            set: { model.showsMenuBarIcon = $0 }
          )
        )
        .toggleStyle(.checkbox)
        Text(
          model.showsMenuBarIcon
            ? "Closing the window keeps MagnetBridge available in the menu bar."
            : "MagnetBridge appears in the Dock and quits when its window closes."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Divider()

        HStack(spacing: 12) {
          Text("Magnet handler")
            .frame(width: 132, alignment: .leading)
          Text(model.currentHandler)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(model.currentHandler)
          Spacer()
          Button("Make Default") {
            Task { await model.makeDefaultHandler() }
          }
          .disabled(model.isBusy || model.currentHandler.hasPrefix("MagnetBridge"))

          Button("Restore Previous") {
            Task { await model.restorePreviousHandler() }
          }
          .disabled(model.isBusy || model.restoreTarget == "not available")
          .help("Restore \(model.restoreTarget) as the default magnet handler")
        }

        Divider()

        HStack(spacing: 12) {
          Toggle(
            "Automatically check for updates",
            isOn: Binding(
              get: { updater.automaticallyChecksForUpdates },
              set: { updater.automaticallyChecksForUpdates = $0 }
            )
          )
          .toggleStyle(.checkbox)
          Spacer()
          Button("Check Now") {
            updater.checkForUpdates()
          }
        }
      }
    }
  }
}

private struct HelpView: View {
  @Bindable var updater: UpdateController
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .interpolation(.high)
          .frame(width: 50, height: 50)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("MagnetBridge Help")
            .font(.title2.weight(.semibold))
          Text("Send magnet links from your Mac to a Transmission server.")
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 11) {
        HelpStep(
          number: 1,
          title: "Connect",
          detail:
            "Enter the Transmission server address. Enable custom endpoints "
            + "or Basic Authentication only when your server needs them."
        )
        HelpStep(
          number: 2,
          title: "Verify",
          detail:
            "Use Test Connection, then Save & Make Default so macOS routes "
            + "magnet links to MagnetBridge."
        )
        HelpStep(
          number: 3,
          title: "Open a magnet link",
          detail:
            "Choose the Transmission server or one of the other installed "
            + "handlers. Downloads always run on the server."
        )
      }

      Text(
        "Tip: menu-bar mode keeps MagnetBridge ready after its window is closed. Turn it off to use the app only from the Dock."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))

      HStack(spacing: 14) {
        Link(
          "Transmission",
          destination: URL(string: "https://transmissionbt.com/")!
        )
        Link(
          "User Guide",
          destination: URL(string: "https://github.com/decyrus/magnet-bridge#readme")!
        )
        Link(
          "Report an Issue",
          destination: URL(string: "https://github.com/decyrus/magnet-bridge/issues/new/choose")!
        )
        Spacer()
        Button("Check for Updates…") {
          updater.checkForUpdates()
        }
      }

      Divider()

      HStack {
        Text(AppVersion.displayString)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Done") {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 540)
  }
}

private struct HelpStep: View {
  let number: Int
  let title: String
  let detail: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text("\(number)")
        .font(.caption.weight(.bold))
        .foregroundStyle(.white)
        .frame(width: 22, height: 22)
        .background(.tint, in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct SettingsCard<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: systemImage)
        .font(.headline)
        .foregroundStyle(.primary)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(11)
    .background(
      Color(nsColor: .controlBackgroundColor),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(.separator.opacity(0.55), lineWidth: 0.5)
    )
  }
}

private struct NoticeBanner: View {
  let notice: AppModel.Notice

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: iconName)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      Text(notice.message)
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(9)
    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
  }

  private var iconName: String {
    switch notice {
    case .progress: "arrow.triangle.2.circlepath"
    case .success: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .failure: "xmark.circle.fill"
    }
  }

  private var tint: Color {
    switch notice {
    case .progress: .accentColor
    case .success: .green
    case .warning: .orange
    case .failure: .red
    }
  }
}
