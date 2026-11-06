import SwiftUI
import WebKit

/// 登录页：WKWebView 加载百度通行证（对应 Android `LoginPage`）。
/// 登录完成后从 WKHTTPCookieStore 抓 BDUSS/STOKEN，再调 `/c/s/login` 换账号信息。
struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var statusText = ""
    @State private var isExchanging = false
    /// +1 强制 LoginWebView 重建（清除网页登录状态后）
    @State private var webViewToken = 0

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
                .id(webViewToken) // token 变化时重建 WebView（清除 Cookie 后强制重新登录）
            }
            .navigationTitle("登录百度账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                statusText = "正在清除网页登录状态…"
                                await Self.clearBaiduCookies()
                                webViewToken += 1
                                statusText = "已清除，请重新登录"
                            }
                        } label: {
                            Label("清除网页登录状态", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    /// 清除 WKWebView 中所有百度域 Cookie（排查旧登录状态残留；仅手动触发）
    static func clearBaiduCookies() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        for c in cookies where c.domain.lowercased().contains("baidu.com") {
            await store.delete(c)
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

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            self.webView = webView
            decisionHandler(.allow)
        }

        /// 1:1 对齐 Android `LoginWebViewClient.onPageFinished` 的提交条件：
        /// - URL 落在 tieba.baidu.com / tiebac.baidu.com 的 `/index/tbwise/`（登录成功的落点）
        /// - 该 URL 下 BDUSS **和** STOKEN 同时存在（缺一不提交，等待轮询）
        /// 登录跳转常由 JS 完成（不触发 didFinish），所以注册 cookieStore 观察并每秒轮询。
        private func startPolling(_ webView: WKWebView) {
            self.webView = webView
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.add(self)
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                for _ in 0..<60 {
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
            // 提交条件 1：URL 必须已在贴吧个人中心（Android 同款判定）
            guard let current = webView.url, Self.isOnTiebaMine(current) else { return }
            let store = webView.configuration.websiteDataStore.httpCookieStore
            let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
                store.getAllCookies { cont.resume(returning: $0) }
            }
            // 提交条件 2：按当前 URL 域名过滤（模拟 CookieManager.getCookie(url)），
            // BDUSS 与 STOKEN 必须同时存在
            let matched = Self.cookies(for: current, from: cookies)
            var bduss = "", stoken = ""
            var pairs: [String] = []
            for c in matched {
                pairs.append("\(c.name)=\(c.value)")
                if c.name == "BDUSS" { bduss = c.value }
                if c.name == "STOKEN" { stoken = c.value }
            }
            guard !bduss.isEmpty, !stoken.isEmpty, bduss != lastSubmittedBduss else { return }
            lastSubmittedBduss = bduss
            // Android LoginPage：登录时保存 BAIDUID
            for c in matched where c.name == "BAIDUID" {
                ClientUtils.setBaiduId(c.value)
            }
            let header = pairs.joined(separator: "; ")
            await MainActor.run { self.parent.onCookies(bduss, stoken, header) }
        }

        /// Android 判定：`url.startsWith("https://tieba.baidu.com/index/tbwise/")`（含 tiebac）
        static func isOnTiebaMine(_ url: URL) -> Bool {
            let host = url.host?.lowercased() ?? ""
            guard host == "tieba.baidu.com" || host == "tiebac.baidu.com" else { return false }
            return url.path.hasPrefix("/index/tbwise")
        }

        /// 模拟 `CookieManager.getCookie(url)` 的域名匹配：
        /// cookie 域（去前导点后）等于 host，或是 host 的父域
        static func cookies(for url: URL, from all: [HTTPCookie]) -> [HTTPCookie] {
            let host = (url.host ?? "").lowercased()
            func matches(_ c: HTTPCookie) -> Bool {
                var d = c.domain.lowercased()
                if d.hasPrefix(".") { d.removeFirst() }
                if d.isEmpty { return false }
                return d == host || host.hasSuffix("." + d)
            }
            let filtered = all.filter(matches)
            // 同名 Cookie 冲突时：精确 host 优先于父域（CookieManager 的 host 优先语义）
            var best: [String: HTTPCookie] = [:]
            for c in filtered {
                let key = c.name
                if let old = best[key] {
                    let cExact = c.domain.lowercased() == host
                    let oldExact = old.domain.lowercased() == host
                    if cExact && !oldExact { best[key] = c }
                } else {
                    best[key] = c
                }
            }
            return Array(best.values)
        }
    }
}
