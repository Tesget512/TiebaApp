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
        // 启动刷新账号（Android MainActivityV2.fetchAccount 1:1：已登录时刷新 tbs 等登录态，失败仅忽略）
        if account?.bduss.isEmpty == false {
            Task { [weak self] in
                guard let self, let acc = self.account else { return }
                if let refreshed = try? await TiebaLoginClient.refreshAccount(acc) {
                    self.updateAccount(refreshed)
                }
            }
        }
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

    /// tbs 为空时刷新账号（签到/点赞等写操作前置；走无参刷新路径）
    func refreshTbsIfNeeded() async {
        guard let account, account.tbs.isEmpty, !account.bduss.isEmpty else { return }
        if let refreshed = try? await TiebaLoginClient.refreshAccount(account) {
            updateAccount(refreshed)
        }
    }

    /// 自动签到补执行（Android OKSignService 的应用内替代：
    /// 启动/回前台时若已到设定时间且当天未签，则静默执行一轮一键签到）
    private var autoSignRunning = false
    private let prefs = AppPreferences.shared

    func runAutoSignIfDue() async {
        guard prefs.autoSign, let account, !account.bduss.isEmpty else { return }
        let cal = Calendar.current
        guard prefs.signDay != cal.component(.day, from: Date()) else { return } // 当天已签
        let parts = prefs.autoSignTime.split(separator: ":").compactMap { Int($0) }
        guard let due = cal.date(bySettingHour: parts.first ?? 9,
                                 minute: parts.count > 1 ? parts[1] : 0,
                                 second: 0, of: Date()),
              Date() >= due else { return } // 未到设定时间
        guard !autoSignRunning else { return }
        autoSignRunning = true
        defer { autoSignRunning = false }
        await refreshTbsIfNeeded()
        let ok = await OKSigner.run(
            account: account,
            slowMode: prefs.oksignSlowMode,
            useMSign: prefs.oksignUseOfficialOksign,
            failAutoStop: prefs.oksignFailAutoStop) { _ in }
        if ok { prefs.signDay = cal.component(.day, from: Date()) }
    }
}
