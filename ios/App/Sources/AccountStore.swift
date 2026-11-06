import Foundation
import Security

/// BDUSS 等凭证的 Keychain 持久化（iOS 对应 Android 端 Room Account 表）。
///
/// 说明：`kSecAttrAccessibleAfterFirstUnlock` 允许 App 在后台/锁屏后继续读凭证
/// （默认的 `kSecAttrAccessibleWhenUnlocked` 在未解锁时会失败）。
final class AccountStore {
    private let service = "com.tieba.ioslite.account"
    private let accountKey = "current"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
        ]
    }

    func save(_ account: Account) {
        guard let data = try? encoder.encode(account) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    func load() -> Account? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? decoder.decode(Account.self, from: data)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
