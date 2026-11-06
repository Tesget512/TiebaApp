import Foundation
import Combine

/// 全局登录/账号状态。BDUSS 来自 WKWebView 登录流程，持久化在 Keychain。
final class AppState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var account: Account?

    private let store = AccountStore()

    init() {
        account = store.load()
        isLoggedIn = account?.bduss != nil
        // 把登录态注入 API 客户端（CommonRequest 的 BDUSS/stoken 等）
        TiebaAPIClient.shared.accountProvider = { [weak self] in self?.account }
    }

    func updateAccount(_ newAccount: Account) {
        store.save(newAccount)
        account = newAccount
        isLoggedIn = true
    }

    func logout() {
        store.clear()
        account = nil
        isLoggedIn = false
    }
}
