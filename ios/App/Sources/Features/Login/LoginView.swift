import SwiftUI
import WebKit

/// 登录页：WKWebView 加载百度通行证（对应 Android `LoginPage`）。
/// 登录完成后从 WKHTTPCookieStore 抓 BDUSS/STOKEN，再调 `/c/s/login` 换账号信息。
struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var statusText = ""
    @State private var isExchanging = false

    /// 登录后百度会跳到贴吧个人中心，用该地址判定登录完成
    static let loginURL = URL(string:
        "https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
                LoginWebView(url: Self.loginURL) { bduss, stoken, cookieHeader in
                    guard !isExchanging else { return }
                    isExchanging = true
                    Task { await exchangeAccount(bduss: bduss, stoken: stoken,
                                                 cookieHeader: cookieHeader) }
                }
            }
            .navigationTitle("登录百度账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    /// 用 BDUSS 换取账号信息（对应 Android `AccountUtil.fetchAccountFlow` 的核心步骤）
    private func exchangeAccount(bduss: String, stoken: String, cookieHeader: String) async {
        statusText = "获取账号信息…"
        do {
            var account = try await TiebaLoginClient.fetchAccount(bduss: bduss, stoken: stoken)
            if !cookieHeader.isEmpty { account.cookie = cookieHeader }
            await MainActor.run {
                appState.updateAccount(account)
                statusText = ""
                dismiss()
            }
            await TiebaWriteEndpoints.sync()
        } catch {
            await MainActor.run {
                statusText = "获取账号失败：\(error.localizedDescription)（可关闭后重试）"
                isExchanging = false
            }
        }
    }
}

/// WKWebView 登录壳：监听导航，落到贴吧个人中心后读取 Cookie
struct LoginWebView: UIViewRepresentable {
    let url: URL
    let onCookies: (_ bduss: String, _ stoken: String, _ cookieHeader: String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var parent: LoginWebView
        weak var webView: WKWebView?
        /// 上一次已提交换取的 BDUSS；新 BDUSS 出现会再次回调（失败后自动重试）
        private var lastSubmittedBduss = ""
        private var pollTask: Task<Void, Never>?

        init(_ parent: LoginWebView) {
            self.parent = parent
            super.init()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            startPolling(webView)
        }

        /// 登录成功时百度可能通过 JS 跳转，兜底在决策阶段也检查一次
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        /// 登录跳转常由 JS 完成（不触发 didFinish），所以：
        /// 1. 注册 cookieStore 变更观察（含 HttpOnly cookie）
        /// 2. 每秒轮询一次，最长 30s；BDUSS 出现或**变化**都会提交换取
        private func startPolling(_ webView: WKWebView) {
            self.webView = webView
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.add(self)
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                for _ in 0..<30 {
                    guard let self else { return }
                    await self.checkCookies()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }

        /// cookie 变化（含 JS/HttpOnly 设置）立即检查——失败重试的关键路径
        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { [weak self] in
                await self?.checkCookies()
            }
        }

        private func checkCookies() async {
            guard let webView else { return }
            let store = webView.configuration.websiteDataStore.httpCookieStore
            let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
                store.getAllCookies { cont.resume(returning: $0) }
            }
            var bduss = "", stoken = ""
            var pairs: [String] = []
            for c in cookies where c.domain.contains("baidu.com") {
                pairs.append("\(c.name)=\(c.value)")
                if c.name == "BDUSS" { bduss = c.value }
                if c.name == "STOKEN" { stoken = c.value }
            }
            // 空值跳过；同一 BDUSS 不重复提交；新 BDUSS（重新登录/换号）自动重试
            guard !bduss.isEmpty, bduss != lastSubmittedBduss else { return }
            lastSubmittedBduss = bduss
            let header = pairs.joined(separator: "; ")
            await MainActor.run { self.parent.onCookies(bduss, stoken, header) }
        }
    }
}
