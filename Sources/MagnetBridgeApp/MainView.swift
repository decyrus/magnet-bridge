import AppKit
import MagnetBridgeCore
import SwiftUI

struct MainView: View {
  @Bindable var model: AppModel
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
          hasPendingLink: model.pendingMagnetURL != nil,
          returnToLink: { showsSettingsForPendingLink = false }
        )
      }
    }
    .frame(minWidth: 560, idealWidth: 600, maxWidth: 680, minHeight: 520)
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: model.pendingMagnetURL?.absoluteString) {
      showsSettingsForPendingLink = false
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "link.badge.plus")
        .font(.system(size: 25, weight: .semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.tint)
        .frame(width: 38, height: 38)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

      VStack(alignment: .leading, spacing: 2) {
        Text("MagnetBridge")
          .font(.headline)
        Text("Magnet links → Transmission")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

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
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
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
  @State private var showsAdvancedEndpoints = false
  let hasPendingLink: Bool
  let returnToLink: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 14) {
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
        .padding(20)
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
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
    .onAppear {
      showsAdvancedEndpoints = model.usesCustomEndpoints
    }
  }

  private var connectionSection: some View {
    SettingsCard(title: "Transmission Server", systemImage: "server.rack") {
      VStack(alignment: .leading, spacing: 12) {
        LabeledContent("Server") {
          TextField("https://server.example:9091", text: $model.serverAddress)
            .textFieldStyle(.roundedBorder)
            .frame(width: 320)
        }
        Text(
          model.usesCustomEndpoints
            ? "The advanced endpoint URLs below override this address."
            : "Standard Transmission RPC and Web UI paths are added automatically."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Divider()

        LabeledContent("Username") {
          TextField("Optional", text: $model.settings.username)
            .textFieldStyle(.roundedBorder)
            .frame(width: 230)
        }
        LabeledContent("Password") {
          HStack(spacing: 8) {
            SecureField(
              model.hasStoredPassword ? "Stored in Keychain" : "Optional",
              text: $model.passwordInput
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 230)
            if model.hasStoredPassword {
              Button("Remove") {
                model.removeStoredPassword()
              }
              .buttonStyle(.borderless)
            }
          }
        }

        DisclosureGroup("Advanced", isExpanded: $showsAdvancedEndpoints) {
          VStack(alignment: .leading, spacing: 10) {
            Toggle(
              "Override standard endpoint URLs",
              isOn: $model.usesCustomEndpoints
            )
            if model.usesCustomEndpoints {
              LabeledContent("RPC URL") {
                TextField(
                  "https://server.example/transmission/rpc",
                  text: $model.settings.rpcURL
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
              }
              LabeledContent("Web UI URL") {
                TextField(
                  "https://server.example/transmission/web/",
                  text: $model.settings.webUIURL
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
              }
              Text(
                "Use custom URLs only when a reverse proxy changes Transmission’s standard paths."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
          .padding(.top, 8)
        }
        .font(.callout)

        if model.isUsingInsecureHTTP {
          Toggle(
            "Allow unencrypted HTTP connection",
            isOn: $model.settings.hasAcknowledgedInsecureHTTP
          )
          .tint(.orange)
          Text("Basic Authentication credentials are visible to the network over HTTP.")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
    }
  }

  private var behaviorSection: some View {
    SettingsCard(title: "Behavior", systemImage: "slider.horizontal.3") {
      VStack(spacing: 12) {
        LabeledContent("Start torrents") {
          Picker("", selection: $model.settings.startMode) {
            Text("Immediately").tag(TorrentStartMode.immediately)
            Text("Paused").tag(TorrentStartMode.paused)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 230)
        }
        Toggle("Open Transmission Web UI after adding", isOn: $model.settings.opensWebUI)
        if model.settings.opensWebUI {
          LabeledContent("Browser") {
            Picker("", selection: $model.settings.browser) {
              ForEach(model.browsers, id: \.self) { browser in
                Text(browser.displayName).tag(browser)
              }
            }
            .labelsHidden()
            .frame(width: 230)
          }
        }
        LabeledContent("Connection timeout") {
          Stepper(
            "\(Int(model.settings.timeout)) seconds",
            value: $model.settings.timeout,
            in: 3...60,
            step: 1
          )
          .frame(width: 230)
        }
      }
    }
  }

  private var integrationSection: some View {
    SettingsCard(title: "macOS Integration", systemImage: "macwindow") {
      VStack(alignment: .leading, spacing: 12) {
        Toggle(
          "Keep MagnetBridge in the menu bar",
          isOn: Binding(
            get: { model.showsMenuBarIcon },
            set: { model.showsMenuBarIcon = $0 }
          )
        )
        Text(
          model.showsMenuBarIcon
            ? "Closing the window keeps MagnetBridge available in the menu bar."
            : "MagnetBridge appears in the Dock and quits when its window closes."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Divider()

        LabeledContent("Current magnet handler") {
          Text(model.currentHandler)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        HStack {
          Button("Make Default") {
            Task { await model.makeDefaultHandler() }
          }
          .disabled(model.isBusy || model.currentHandler.hasPrefix("MagnetBridge"))

          Button("Restore \(model.restoreTarget)") {
            Task { await model.restorePreviousHandler() }
          }
          .disabled(model.isBusy || model.restoreTarget == "not available")
        }
      }
    }
  }
}

private struct SettingsCard<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: systemImage)
        .font(.headline)
        .foregroundStyle(.primary)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
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
      Text(notice.message)
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(11)
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
