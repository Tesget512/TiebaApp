import Foundation
import Security

/// BDUSS 等凭证的 Keychain 持久化（iOS 对应 Android 端 Room Account 表）。
final class AccountStore {
    private let service = "com.tieba.ioslite.account"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func save(_ account: Account) {
        if let data = try? encoder.encode(account) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecValueData as String: data,
            ]
            SecItemDelete(query as CFDictionary)
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func load() -> Account? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? decoder.decode(Account.self, from: data)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
