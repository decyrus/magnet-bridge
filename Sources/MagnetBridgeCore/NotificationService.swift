import Foundation
import UserNotifications

public protocol NotificationServing: Sendable {
  func requestAuthorization() async
  func show(title: String, body: String) async
}

public final class NotificationService: NotificationServing, @unchecked Sendable {
  private let center: UNUserNotificationCenter

  public init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  public func requestAuthorization() async {
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
  }

  public func show(title: String, body: String) async {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    try? await center.add(request)
  }
}
