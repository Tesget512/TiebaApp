import Foundation
import Combine

/// 全局登录/账号状态。BDUSS 来自 WKWebView 登录流程，持久化在 Keychain。
@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var account: Account?

    private let store = AccountStore()

    init() {
        account = store.load()
        isLoggedIn = account?.bduss.isEmpty == false
        // 把登录态注入两个 API 客户端（protobuf 的 BDUSS/stoken、JSON 通道的 uid/tbs）
        TiebaAPIClient.shared.accountProvider = { [weak self] in self?.account }
        TiebaJSONClient.shared.accountProvider = { [weak self] in self?.account }
        Task { await TiebaWriteEndpoints.sync() }
    }

    func updateAccount(_ newAccount: Account) {
        store.save(newAccount)
        account = newAccount
        isLoggedIn = !newAccount.bduss.isEmpty
    }

    func logout() {
        store.clear()
        account = nil
        isLoggedIn = false
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
