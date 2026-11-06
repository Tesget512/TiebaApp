import SwiftUI
import WebKit

/// 登录页：WKWebView 加载百度通行证（对应 Android LoginPage）。
/// 登录完成后从 WKHTTPCookieStore 抓 BDUSS/STOKEN，再调 /c/s/login 换账号信息。
struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var statusText = ""

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
                }
                LoginWebView(url: Self.loginURL) { bduss, stoken in
                    Task { await exchangeAccount(bduss: bduss, stoken: stoken) }
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
        .interactiveDismissDisabled(true)
    }

    /// 用 BDUSS 换取账号信息（对应 Android AccountUtil.fetchAccountFlow 的核心步骤）
    private func exchangeAccount(bduss: String, stoken: String) async {
        statusText = "获取账号信息…"
        do {
            let account = try await TiebaLoginClient.fetchAccount(bduss: bduss, stoken: stoken)
            await MainActor.run {
                appState.updateAccount(account)
                statusText = ""
                dismiss()
            }
        } catch {
            await MainActor.run { statusText = "获取账号失败: \(error.localizedDescription)" }
        }
    }
}

struct LoginWebView: UIViewRepresentable {
    let url: URL
    let onCookies: (_ bduss: String, _ stoken: String) -> Void

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

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LoginWebView
        /// 避免每次导航都检查；登录完成跳转到 tbwise 页面时抓 cookie
        private var captured = false

        init(_ parent: LoginWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !captured else { return }
            let url = webView.url?.absoluteString ?? ""
            guard url.contains("tieba.baidu.com/index/tbwise") else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                var bduss = "", stoken = ""
                for c in cookies {
                    if c.name == "BDUSS" { bduss = c.value }
                    if c.name == "STOKEN" { stoken = c.value }
                }
                if !bduss.isEmpty {
                    self.captured = true
                    self.parent.onCookies(bduss, stoken)
                }
            }
        }
    }
}
