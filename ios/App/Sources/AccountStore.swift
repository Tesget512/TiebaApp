import Foundation
import Security

/// 凭证持久化（iOS 对应 Android 端 Room Account 表）。
///
/// 双通道保证登录态不丢：
/// 1. **Keychain 主通道**（真机签名构建下最安全）；写入后立即回读校验
/// 2. **Application Support 文件兜底**：keychain 写入/读取失败（如未签名调试构建、
///    系统回收）时自动降级；文件带 `NSFileProtectionComplete` 保护
///
/// 多账号（对齐 Android AccountUtil：全部账号列表 + 当前账号 id）：
/// - 通道内容为 `[Account]` JSON 数组
/// - UserDefaults "tieba.currentUid" 保存当前账号 uid（对应 Android `accountData.now`）
final class AccountStore {
    static let saveFailureNotification = Notification.Name("tieba.accountStore.saveFailed")

    private let service = "com.tieba.ioslite.account"
    private let listKey = "accounts"
    private let currentUidKey = "tieba.currentUid"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// 兜底文件：Application Support/account_store.json
    private var fallbackURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("account_store.json")
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: listKey,
        ]
    }

    // MARK: - 读取

    private func readKeychain() -> [Account]? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                NSLog("[AccountStore] keychain read failed: \(status)")
            }
            return nil
        }
        return try? decoder.decode([Account].self, from: data)
    }

    private func readFallback() -> [Account]? {
        guard let data = try? Data(contentsOf: fallbackURL) else { return nil }
        return try? decoder.decode([Account].self, from: data)
    }

    // MARK: - 写入（回读校验 + 自动降级）

    private func writeList(_ list: [Account]) {
        guard let data = try? encoder.encode(list) else { return }

        // 1) Keychain：删除旧项 → 写入 → 回读校验
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess, readKeychain() != nil {
            NSLog("[AccountStore] keychain write ok (\(list.count) accounts)")
            return
        }
        NSLog("[AccountStore] keychain write failed (add=\(addStatus)), falling back to file")

        // 2) 兜底：Application Support 文件（完整文件保护）
        do {
            try data.write(to: fallbackURL, options: [.atomic, .completeFileProtection])
            // 回读校验兜底通道
            guard readFallback() != nil else {
                NSLog("[AccountStore] fallback write verify failed!")
                return
            }
            NSLog("[AccountStore] fallback file write ok (\(list.count) accounts)")
        } catch {
            NSLog("[AccountStore] fallback write error: \(error.localizedDescription)")
        }
    }

    private func readAll() -> [Account] {
        if let list = readKeychain(), !list.isEmpty { return list }
        if let list = readFallback(), !list.isEmpty { return list }
        return []
    }

    // MARK: - 对外接口

    func all() -> [Account] { readAll() }

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
        writeList(list)
        setCurrent(uid: account.uid)
    }

    /// 切换当前账号（对应 Android switchAccount）
    func setCurrent(uid: String) {
        UserDefaults.standard.set(uid, forKey: currentUidKey)
    }

    /// 退出登录：移除该账号；若有其他账号则自动切到剩余账号（对应 Android AccountUtil.exit）
    func remove(uid: String) {
        var list = readAll()
        list.removeAll { $0.uid == uid }
        if list.isEmpty {
            clear()
        } else {
            writeList(list)
            if currentUid() == uid {
                setCurrent(uid: list[0].uid)
            }
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        try? FileManager.default.removeItem(at: fallbackURL)
        UserDefaults.standard.removeObject(forKey: currentUidKey)
    }
}
