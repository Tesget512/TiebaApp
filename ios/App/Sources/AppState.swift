import Foundation
import Combine

/// 全局登录/账号状态（对应 Android `AccountUtil`）。
/// 多账号：Keychain 保存账号数组 + UserDefaults 保存当前 uid。
@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var account: Account?
    @Published var allAccounts: [Account] = []

    private let store = AccountStore()

    init() {
        account = store.load()
        allAccounts = store.all()
        isLoggedIn = account?.bduss.isEmpty == false
        // 把登录态注入两个 API 客户端（protobuf 的 BDUSS/stoken、JSON 通道的 uid/tbs）
        TiebaAPIClient.shared.accountProvider = { [weak self] in self?.account }
        TiebaJSONClient.shared.accountProvider = { [weak self] in self?.account }
        Task { await TiebaWriteEndpoints.sync() }
    }

    func updateAccount(_ newAccount: Account) {
        store.save(newAccount)
        account = newAccount
        allAccounts = store.all()
        isLoggedIn = !newAccount.bduss.isEmpty
    }

    /// 切换当前账号（对应 Android switchAccount： GlobalEvent.AccountSwitched 的等价处理）
    func switchAccount(uid: String) {
        store.setCurrent(uid: uid)
        account = store.load()
        allAccounts = store.all()
        isLoggedIn = account?.bduss.isEmpty == false
        Task { await TiebaWriteEndpoints.sync() }
    }

    /// 退出登录（移除该账号；多账号时自动切到剩余账号）
    func logout() {
        if let uid = account?.uid {
            store.remove(uid: uid)
        } else {
            store.clear()
        }
        account = store.load()
        allAccounts = store.all()
        isLoggedIn = account?.bduss.isEmpty == false
    }

    /// tbs 为空时刷新账号（签到/点赞等写操作前置）
    func refreshTbsIfNeeded() async {
        guard let account, account.tbs.isEmpty, !account.bduss.isEmpty else { return }
        if let refreshed = try? await TiebaLoginClient.fetchAccount(bduss: account.bduss,
                                                                   stoken: account.stoken) {
            updateAccount(refreshed)
        }
    }
}
