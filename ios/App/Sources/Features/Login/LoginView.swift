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
        private var captured = false

        init(_ parent: LoginWebView) {
            self.parent = parent
            super.init()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            check(webView)
        }

        /// 登录成功时百度可能通过 JS 跳转，兜底在决策阶段也检查一次
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        private func check(_ webView: WKWebView) {
            guard !captured else { return }
            let current = webView.url?.absoluteString ?? ""
            // 登录成功后跳到 tieba.baidu.com 下的页面（个人中心）
            guard current.contains("tieba.baidu.com") else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                var bduss = "", stoken = ""
                var pairs: [String] = []
                for c in cookies where c.domain.contains("baidu.com") {
                    pairs.append("\(c.name)=\(c.value)")
                    if c.name == "BDUSS" { bduss = c.value }
                    if c.name == "STOKEN" { stoken = c.value }
                }
                guard !bduss.isEmpty else { return }
                self.captured = true
                let header = pairs.joined(separator: "; ")
                DispatchQueue.main.async { self.parent.onCookies(bduss, stoken, header) }
            }
        }
    }
}
