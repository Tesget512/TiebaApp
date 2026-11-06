import SwiftUI
import WebKit
import PhotosUI

// MARK: - WebView 内嵌页（对应 Android WebViewPage）

struct WebViewPage: View {
    let url: URL

    @State private var title = ""
    @State private var reloadToken = 0

    var body: some View {
        WebView(url: url, title: $title, reloadToken: reloadToken)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title.isEmpty ? url.host ?? "网页" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = url.absoluteString
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    if url.scheme?.hasPrefix("http") == true {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    Button {
                        reloadToken += 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var title: String
    var reloadToken: Int

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        // 注入登录 cookie（对应 Android injectCookies）
        let cookie = AccountUtil.cookieHeader()
        if !cookie.isEmpty {
            for part in cookie.split(separator: "; ") {
                let kv = part.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let c = HTTPCookie(properties: [
                    .domain: ".baidu.com",
                    .path: "/",
                    .name: String(kv[0]),
                    .value: String(kv[1]),
                ])
                if let c { wv.configuration.websiteDataStore.httpCookieStore.setCookie(c) }
            }
        }
        context.coordinator.loaded = false
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        if reloadToken != context.coordinator.lastReloadToken {
            context.coordinator.lastReloadToken = reloadToken
            wv.reload()
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        var loaded = false
        var lastReloadToken = 0

        init(_ parent: WebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.title = webView.title ?? ""
        }
    }
}

// MARK: - 修改资料（对应 Android EditProfileActivity / profileModify）

struct EditProfilePage: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var nickName = ""
    @State private var intro = ""
    @State private var sex = 1
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("昵称") {
                    TextField("昵称", text: $nickName)
                }
                Section("简介") {
                    TextField("简介（最多 500 字）", text: $intro, axis: .vertical)
                        .lineLimit(3...6)
                    if intro.count > 500 {
                        Text("简介超过 500 字限制").font(.caption).foregroundStyle(.red)
                    }
                }
                Section("性别") {
                    Picker("性别", selection: $sex) {
                        Text("男").tag(1)
                        Text("女").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if busy {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("保存").frame(maxWidth: .infinity).bold()
                        }
                    }
                    .disabled(nickName.isEmpty || intro.count > 500 || busy)
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("生日字段跟随服务端默认（birthday_time 传 0），昵称不可为空。")
                }
            }
            .navigationTitle("修改资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if let user = appState.account {
                    nickName = user.name
                }
            }
        }
    }

    private func submit() async {
        if AppPreferences.shared.safeMode {
            message = "安全模式已开启，写操作被拦截"
            return
        }
        busy = true
        defer { busy = false }
        do {
            _ = try await TiebaWriteEndpoints.profileModify(
                nickName: nickName, intro: intro, sex: sex,
                birthdayTime: 0, birthdayShowStatus: false)
            message = "保存成功"
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - 通用标签帖子流（对应 Android GeneralTabListPage，V12_POST 通道）

struct GeneralTabListPage: View {
    let forumId: Int64
    let forumName: String
    let tab: TabInfo

    struct TabInfo: Hashable, Identifiable {
        let id: Int32
        let name: String
        let type: Int32

        var tabID: Int32 { id }
        var tabName: String { name }
        var tabType: Int32 { type }
    }

    @State private var threads: [Tieba_ThreadInfo] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var page = 1
    @State private var hasMore = true
    @State private var lastThreadId: Int64 = 0
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && threads.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, threads.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "list.bullet", description: err)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ThreadListView(threads: threads) { t in
                                path.append(AppRoute.thread(id: t.tid, title: t.title, forumId: t.forumID))
                            } onLoadMore: {
                                await loadMore()
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle(tab.name.isEmpty ? forumName : tab.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task { if threads.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    private func load() async {
        isLoading = true
        page = 1
        lastThreadId = 0
        defer { isLoading = false }
        do {
            let data = try await TiebaExtraEndpoints.generalTabList(
                client: .shared, tabId: tab.id, forumId: forumId,
                page: 1, tabName: tab.name, sortType: 0, tabType: Int(tab.type))
            threads = data.generalList.filter { !$0.isLive }
            lastThreadId = threads.last?.id ?? 0
            hasMore = data.hasMore_p != 0
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = page + 1
            let data = try await TiebaExtraEndpoints.generalTabList(
                client: .shared, tabId: tab.id, forumId: forumId,
                page: next, tabName: tab.name, sortType: 0, tabType: Int(tab.type),
                lastThreadId: lastThreadId)
            let more = data.generalList.filter { !$0.isLive }
            threads += more
            lastThreadId = threads.last?.id ?? lastThreadId
            page = next
            hasMore = data.hasMore_p != 0
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 图片上传（对应 Android ImageUploader：/c/s/uploadPicture 单分片版）

enum ImageUploader {
    struct UploadResult {
        var picId: String
        var width: Int
        var height: Int
        var contentCode: String { "#(pic,\(picId),\(width),\(height))" } // ReplyPage.kt:328
    }

    /// 单分片上传（< 512KB；Android DEFAULT_CHUNK_SIZE=512000，大图分片逻辑 iOS 版不实现）
    static func upload(imageData: Data, width: Int, height: Int) async throws -> UploadResult {
        guard let account = TiebaJSONClient.shared.accountProvider(), !account.uid.isEmpty else {
            throw TiebaAPIError.notLoggedIn
        }
        guard imageData.count <= 512_000 else {
            throw TiebaAPIError.apiError(code: -1, message: "图片超过 500KB，请压缩后重试")
        }
        let boundary = "--------7da3d81520810*"
        let fileMd5 = Signer.md5Hex(String(decoding: imageData.prefix(64), as: UTF8.self)) + "\(imageData.count)"

        var body = Data()
        func part(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }
        part("alt", "json")
        part("chunkNo", "1")
        part("groupId", "1")
        part("height", "\(height)")
        part("isFinish", "true")
        part("is_bjh", "0")
        part("pic_water_type", "2")
        part("resourceId", fileMd5)
        part("saveOrigin", "true")
        part("size", "\(imageData.count)")
        part("width", "\(width)")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"chunk\"; filename=\"file\"\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: URL(string: "http://c.tieba.baidu.com/c/s/uploadPicture")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("bdtb for Android \(ClientVersion.v12.rawValue)", forHTTPHeaderField: "User-Agent")
        req.setValue(account.uid, forHTTPHeaderField: "client_user_token")
        req.setValue("ka=open", forHTTPHeaderField: "Cookie")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TiebaAPIError.httpStatus(http.statusCode)
        }
        struct Resp: Decodable {
            struct PicInfo: Decodable {
                struct Item: Decodable {
                    let width: FlexibleInt?
                    let height: FlexibleInt?
                    let picUrl: String?
                }
                let originPic: Item?
                let bigPic: Item?
            }
            struct Info: Decodable {
                let width: FlexibleInt?
                let height: FlexibleInt?
            }
            let error_code: FlexibleString?
            let error_msg: String?
            let picId: String?
            let picInfo: PicInfo?
            // 顶层 width/height（部分响应结构）
            let width: FlexibleInt?
            let height: FlexibleInt?
        }
        let resp = try TiebaJSONClient.decode(Resp.self, from: data)
        guard resp.error_code?.value == "0" || resp.error_code?.value == "" || resp.error_code == nil,
              let picId = resp.picId else {
            throw TiebaAPIError.apiError(code: Int(resp.error_code?.value ?? "-1") ?? -1,
                                         message: resp.error_msg ?? "上传失败")
        }
        let w = resp.picInfo?.originPic?.width?.value ?? resp.width?.value ?? Int64(width)
        let h = resp.picInfo?.originPic?.height?.value ?? resp.height?.value ?? Int64(height)
        return UploadResult(picId: picId, width: Int(w), height: Int(h))
    }
}

// MARK: - 投票（对应 Android ThreadUiIntent.PollThread：/c/c/post/addPollPost?cmd=309006）

extension TiebaExtraEndpoints {
    /// 投票（options 为选中项 id 逗号分隔，ThreadPage.kt:1700 selectedIds.joinToString(",")）
    static func addPollPost(client: TiebaAPIClient, forumId: Int64,
                            threadId: Int64, options: String) async throws {
        var data = Tieba_AddPollPost_AddPollPostRequestDate()
        data.forumID = UInt64(max(0, forumId))
        data.threadID = UInt64(max(0, threadId))
        data.options = options
        var req = Tieba_AddPollPost_AddPollPostRequest()
        req.data = data
        _ = try await client.request(
            path: "/c/c/post/addPollPost", cmd: 309006,
            requestData: req, responseType: Tieba_AddPollPost_AddPollPostReponse.self,
            channel: TiebaAPIClient.v12Post)
    }
}
