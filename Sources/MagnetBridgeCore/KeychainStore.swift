import Foundation
import Security

public protocol PasswordStoring: Sendable {
  func readPassword() throws -> String?
  func savePassword(_ password: String) throws
  func deletePassword() throws
}

public final class KeychainStore: PasswordStoring, @unchecked Sendable {
  private let service: String
  private let account: String

  public init(
    service: String = "org.magnetbridge.app",
    account: String = "transmission-rpc"
  ) {
    self.service = service
    self.account = account
  }

  public func readPassword() throws -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let data = result as? Data else {
      throw error(status)
    }
    return String(data: data, encoding: .utf8)
  }

  public func savePassword(_ password: String) throws {
    let data = Data(password.utf8)
    let status = SecItemUpdate(
      baseQuery as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if status == errSecItemNotFound {
      var query = baseQuery
      query[kSecValueData as String] = data
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw error(addStatus)
      }
    } else if status != errSecSuccess {
      throw error(status)
    }
  }

  public func deletePassword() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw error(status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
  }

  private func error(_ status: OSStatus) -> MagnetBridgeError {
    let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    return .keychain(message)
  }
}
