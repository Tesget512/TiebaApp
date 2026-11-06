import Foundation
import Security

/// 凭证的 Keychain 持久化（iOS 对应 Android 端 Room Account 表）。
///
/// 多账号（对齐 Android AccountUtil：全部账号列表 + 当前账号 id）：
/// - Keychain item "accounts" 保存 `[Account]` JSON 数组
/// - UserDefaults "tieba.currentUid" 保存当前账号 uid（对应 Android `accountData.now`）
///
/// 说明：`kSecAttrAccessibleAfterFirstUnlock` 允许 App 在后台/锁屏后继续读凭证
/// （默认的 `kSecAttrAccessibleWhenUnlocked` 在未解锁时会失败）。
final class AccountStore {
    private let service = "com.tieba.ioslite.account"
    private let listKey = "accounts"
    private let currentUidKey = "tieba.currentUid"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: listKey,
        ]
    }

    // MARK: - 多账号

    func all() -> [Account] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let list = try? decoder.decode([Account].self, from: data) else { return [] }
        return list
    }

    func currentUid() -> String {
        UserDefaults.standard.string(forKey: currentUidKey) ?? ""
    }

    func load() -> Account? {
        let list = all()
        if list.isEmpty { return nil }
        let uid = currentUid()
        return list.first { $0.uid == uid } ?? list.first
    }

    /// 保存并设为当前（登录/刷新）
    func save(_ account: Account) {
        var list = all().filter { $0.uid != account.uid }
        list.append(account)
        saveList(list)
        setCurrent(uid: account.uid)
    }

    /// 切换当前账号（对应 Android switchAccount）
    func setCurrent(uid: String) {
        UserDefaults.standard.set(uid, forKey: currentUidKey)
    }

    /// 退出登录：移除该账号；若有其他账号则自动切到剩余账号（对应 Android AccountUtil.exit）
    func remove(uid: String) {
        var list = all()
        list.removeAll { $0.uid == uid }
        if list.isEmpty {
            clear()
        } else {
            saveList(list)
            if currentUid() == uid {
                setCurrent(uid: list[0].uid)
            }
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: currentUidKey)
    }

    private func saveList(_ list: [Account]) {
        guard let data = try? encoder.encode(list) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }
}
