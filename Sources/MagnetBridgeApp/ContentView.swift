import SwiftUI

struct ContentView: View {
  let model: AppModel

  var body: some View {
    VStack(spacing: 18) {
      Image(systemName: iconName)
        .font(.system(size: 44))
        .foregroundStyle(iconColor)
        .symbolEffect(.pulse, isActive: model.operationState == .processing)

      VStack(spacing: 6) {
        Text(title)
          .font(.title2.weight(.semibold))
        Text(detail)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
          .textSelection(.enabled)
      }

      HStack {
        SettingsLink {
          Label("Настройки", systemImage: "gear")
        }

        if case .failure = model.operationState {
          Button("Копировать ссылку") {
            model.copyLastURL()
          }
          .disabled(model.lastIncomingURL == nil)

          Button("Повторить") {
            model.retry()
          }
          .buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(28)
    .accessibilityElement(children: .contain)
  }

  private var iconName: String {
    switch model.operationState {
    case .idle: "link.badge.plus"
    case .processing: "arrow.triangle.2.circlepath"
    case .success: "checkmark.circle.fill"
    case .failure: "exclamationmark.triangle.fill"
    }
  }

  private var iconColor: Color {
    switch model.operationState {
    case .success: .green
    case .failure: .orange
    default: .accentColor
    }
  }

  private var title: String {
    switch model.operationState {
    case .idle: "Готов к magnet-ссылкам"
    case .processing: "Добавляю торрент…"
    case .success(let title, _): title
    case .failure: "Не удалось добавить торрент"
    }
  }

  private var detail: String {
    switch model.operationState {
    case .idle:
      "Нажмите magnet-ссылку в Safari, Chrome или другом приложении."
    case .processing:
      "Связываюсь с Transmission."
    case .success(_, let detail):
      detail
    case .failure(let message):
      message
    }
  }
}
