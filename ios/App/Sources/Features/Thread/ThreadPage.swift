import SwiftUI
import UIKit
import PhotosUI
import AVKit

/// PbContent 富文本渲染（对应 Android PbContentRender 的 iOS 版）：
/// type 0/9/27/35/40=文字、1=链接、2=表情、3/20=图片、4=@用户、5=视频、10=语音
struct PbContentView: View {
    let contents: [Tieba_PbContent]
    var fontSize: Font = .subheadline
    /// 沉浸阅读：不渲染图片/视频段
    var hideImages: Bool = false
    /// 点击图片回调（对齐 Android PbContentRender：点击进 PhotoViewActivity）
    /// 参数 = 本段全部图片条目（picId/展示/原图）+ 被点图片下标
    var onImageTap: (([PicViewItem], Int) -> Void)? = nil

    private enum Item {
        case text(String)
        case image(url: URL?, aspect: CGFloat)
        case link(String)
        /// 有直链 → 内联播放；无直链 → 网页打开（Android VideoContentRender 两种分支）
        case video(url: URL?, poster: URL?, aspect: CGFloat)
        case videoWeb(url: URL?)
        case voice(Int32)
    }

    private var items: [Item] {
        var result: [Item] = []
        var textBuffer = ""
        func flush() {
            if !textBuffer.isEmpty {
                result.append(.text(textBuffer))
                textBuffer = ""
            }
        }
        for c in contents {
            switch Int(c.type) {
            case 0, 9, 27, 35, 40:
                textBuffer += c.text
            case 1:
                flush()
                result.append(.link(c.text.isEmpty ? c.link : c.text))
            case 2:
                // Android：registerEmoticon(text, c) 后渲染 `#(c)`（text=id, c=名字）
                EmoticonManager.shared.register(id: c.text, name: c.c)
                textBuffer += "#(\(c.c))"
            case 3, 20:
                guard !hideImages else { break }
                flush()
                result.append(.image(url: Self.picURL(c), aspect: Self.aspect(c)))
            case 4:
                textBuffer += "@\(c.text) "
            case 5:
                guard !hideImages else { break }
                flush()
                if c.link.isEmpty {
                    // 无直链：text 为网页地址（Android 跳网页分支）
                    result.append(.videoWeb(url: c.text.isEmpty ? nil : URL(string: c.text)))
                } else {
                    result.append(.video(url: URL(string: c.link),
                                         poster: c.src.isEmpty ? nil : URL(string: c.src),
                                         aspect: Self.aspect(c)))
                }
            case 10:
                flush()
                result.append(.voice(Int32(c.duringTime)))
            default:
                break
            }
        }
        flush()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                switch item {
                case .text(let t):
                    EmoticonText(text: t, font: fontSize, pointSize: fontSizePointSize,
                                 color: .primary)
                case .image(let url, let aspect):
                    imageItem(url: url, aspect: aspect, ordinal: imageOrdinal(idx) ?? 0)
                case .link(let text):
                    Text(text).font(fontSize).foregroundStyle(.blue)
                case .video(let url, let poster, let aspect):
                    InlineVideoPlayer(videoURL: url, posterURL: poster, aspect: aspect)
                case .videoWeb(let url):
                    if let url {
                        Link(destination: url) {
                            Label("在浏览器中观看视频", systemImage: "play.rectangle")
                                .font(fontSize)
                        }
                    } else {
                        Label("视频内容", systemImage: "play.rectangle")
                            .font(fontSize).foregroundStyle(.secondary)
                    }
                case .voice(let sec):
                    Label("语音 \(sec)″", systemImage: "waveform")
                        .font(fontSize).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 贴吧图片 URL 归一化：服务端常返回 `//imgsrc.baidu.com/...` 协议相对地址
    /// （Android Glide 原生支持、URL(string:) 不支持）→ 补 https:；再百分号编码兜底
    static func normalizePicURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        else if !s.contains("://"), s.hasPrefix("imgsrc.") || s.hasPrefix("tb") {
            s = "https://" + s
        }
        return URL(string: s)
            ?? URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s)
    }

    /// 图片 URL：originSrc > bigCdnSrc > bigSrc > cdnSrc > src（Android ImageUtil.getUrl 顺序）；
    /// 全部原图模式 origin 优先、全部不加载返回 nil
    static func picURL(_ c: Tieba_PbContent) -> URL? {
        let mode = UserDefaults.standard.integer(forKey: "image_load_mode")
        guard mode != 2 else { return nil }
        let candidates = mode == 1
            ? [c.originSrc, c.bigCdnSrc, c.bigSrc, c.cdnSrc, c.src]
            : [c.bigCdnSrc, c.bigSrc, c.originSrc, c.cdnSrc, c.src]
        let s = candidates.first { !$0.isEmpty } ?? ""
        return Self.normalizePicURL(s)
    }

    /// 本段全部图片条目（点击查看大图用，顺序与渲染一致）；
    /// picId 从 url 文件名提取（Android ImageUtil.getPicId 对齐），供 picpage 定位
    var picViewItems: [PicViewItem] {
        contents.filter { [3, 20].contains(Int($0.type)) }
            .compactMap { c in
                guard let display = Self.picURL(c) else { return nil }
                let originRaw = c.originSrc.isEmpty ? c.bigSrc : c.originSrc
                let origin = Self.normalizePicURL(originRaw)?.absoluteString
                    ?? display.absoluteString
                return PicViewItem(id: tiebaPicId(from: display.absoluteString),
                                   url: display.absoluteString,
                                   originUrl: origin)
            }
    }

    /// item 下标 → 第几张图（查看器初始定位用）
    private func imageOrdinal(_ itemIndex: Int) -> Int? {
        var n = 0
        for (i, item) in items.enumerated() {
            if case .image = item {
                if i == itemIndex { return n }
                n += 1
            }
        }
        return nil
    }

    /// 单张图片：有点击回调且 URL 有效时仅在图片自身热区挂手势
    /// （URL 为 nil 的占位块不可进查看器，避免打开空列表显示「无图片」）
    @ViewBuilder
    private func imageItem(url: URL?, aspect: CGFloat, ordinal: Int) -> some View {
        let img = RemoteImage(url: url, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        if let onImageTap, url != nil {
            img.contentShape(Rectangle())
                .onTapGesture { onImageTap(picViewItems, ordinal) }
        } else {
            img
        }
    }

    /// bsize "宽,高" → aspect ratio
    static func aspect(_ c: Tieba_PbContent) -> CGFloat {
        let parts = c.bsize.split(separator: ",")
        guard parts.count == 2,
              let w = Double(parts[0]), w > 0,
              let h = Double(parts[1]), h > 0 else { return 4.0 / 3.0 }
        return CGFloat(w / h)
    }

    /// SwiftUI Font → 近似点值（EmoticonText 行内图缩放用）
    var fontSizePointSize: CGFloat {
        if fontSize == .caption2 || fontSize == .caption { return 12 }
        if fontSize == .footnote { return 13 }
        if fontSize == .subheadline { return 15 }
        if fontSize == .callout { return 16 }
        if fontSize == .title3 || fontSize == .headline { return 20 }
        if fontSize == .title2 { return 22 }
        if fontSize == .title { return 28 }
        return 17 // .body 及其他
    }
}

/// 内联视频播放（对应 Android VideoPlayer widget：封面图 + 点击播放 → AVKit）
struct InlineVideoPlayer: View {
    let videoURL: URL?
    let posterURL: URL?
    var aspect: CGFloat = 16.0 / 9.0
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onDisappear { player.pause() }
            } else {
                ZStack {
                    RemoteImage(url: posterURL, contentMode: .fit)
                        .aspectRatio(aspect, contentMode: .fit)
                        .background(Color.black.opacity(0.85))
                    if videoURL != nil {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard let videoURL else { return }
                    let p = AVPlayer(url: videoURL)
                    player = p
                    p.play()
                }
            }
        }
    }
}

// MARK: - 帖子详情页

/// 帖子页（对应 Android `ThreadPage`）：楼层列表 + 分页 + 楼中楼入口
struct ThreadPage: View {
    let threadID: Int64
    let title: String
    var forumId: Int64 = 0
    /// 初始只看楼主/倒序（收藏页「自动只看楼主/倒序」设置传入）
    var initialOnlyLz = false
    var initialSortDesc = false

    @EnvironmentObject private var appState: AppState
    @State private var posts: [Tieba_Post] = []
    @State private var forumName = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var nextPage = 0
    @State private var hasMore = true
    @State private var seeLz = false
    /// 已加载的最低页（pn，正序时支持「加载上一页」）
    @State private var lowestPage = 0
    /// 沉浸阅读（Android immersiveMode：隐藏图片与楼中楼预览，纯文字阅读）
    @State private var immersive = false
    /// 从响应里补全的 forum id（首页请求可能未带）
    @State private var resolvedForumId: Int64 = 0
    @State private var isStored = false
    @State private var toast: String?
    @State private var showReply = false
    @State private var showPhoto = false
    @State private var photoItems: [PicViewItem] = []
    @State private var photoIndex = 0
    @State private var showReport = false
    @State private var reportURL: URL?
    @State private var sortDesc = false
    @State private var showJumpPage = false
    @State private var jumpPageInput = ""
    @State private var selectedPollOptions: Set<UInt64> = []
    @State private var pollVoted = false
    /// 主题贴的投票信息（PbPage 响应的 thread.poll_info）
    @State private var pollInfo: Tieba_PollInfo?
    /// 全帖点赞状态（PbPage 响应的 thread.agree，Android BottomBar 同源）
    @State private var threadAgree: Tieba_Agree?
    /// 楼层列表首个楼层 pid（回复主题作者用）
    @State private var threadAuthorName = ""
    /// 指定楼层回复（楼层 contextMenu「回复」）
    @State private var replyToFloor: Tieba_Post?
    /// 回复完成后滚动锚点
    @State private var scrollTarget: String?
    /// 仅当本次打开的回复 sheet 真的发送成功才刷新+滚动（关闭取消不该动列表）
    @State private var replyPosted = false

    /// 楼中楼导航目标
    struct FloorSelection: Hashable {
        let postId: Int64
        let floor: Int
    }

    var body: some View {
        content
            .navigationTitle(title.isEmpty ? (forumName.isEmpty ? "帖子" : forumName) : title)
            .navigationBarTitleDisplayMode(.inline)
            // 导航栏中央吧名：点击进对应贴吧（Android 顶栏吧名可点对齐）
            .toolbar {
                if !forumName.isEmpty {
                    ToolbarItem(placement: .principal) {
                        NavigationLink {
                            ForumPage(forumName: forumName)
                        } label: {
                            HStack(spacing: 4) {
                                Text(forumName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .bottomBarHidden()
            // 底部回复栏（对齐 Android ThreadPage BottomBar 2021-2060：回复输入框 + 全帖点赞）；
            // 悬浮胶囊 + Liquid Glass（与主底栏一致）；安全模式（只读）不显示（用户验收）
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if posts.isEmpty || immersive || AppPreferences.shared.safeMode {
                    Color.clear.frame(height: 0)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            showReply = true
                        } label: {
                            Text("回复")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                        LikeButton(threadId: threadID,
                                   postId: Int64(bitPattern: posts.first?.id ?? 0),
                                   isLiked: threadAgree?.hasAgree_p == 1,
                                   count: threadAgree?.agreeNum ?? 0)
                            .font(.body)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .floatingBarBackground(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // 回帖入口在底部回复栏（Android BottomBar 对齐）
                    Menu {
                        Button {
                            seeLz.toggle()
                            Task { await reload() }
                        } label: {
                            Label(seeLz ? "看全部" : "只看楼主",
                                  systemImage: seeLz ? "person.3" : "person.crop.circle")
                        }
                        Button {
                            sortDesc.toggle()
                            Task { await reload() }
                        } label: {
                            Label(sortDesc ? "切回正序" : "倒序查看",
                                  systemImage: sortDesc ? "arrow.up" : "arrow.down")
                        }
                        Button {
                            immersive.toggle()
                        } label: {
                            Label(immersive ? "退出沉浸阅读" : "沉浸阅读",
                                  systemImage: immersive ? "text.page" : "book")
                        }
                        Button {
                            showJumpPage = true
                        } label: {
                            Label("跳页", systemImage: "arrow.right.to.line")
                        }
                        Button {
                            Task { await toggleStore() }
                        } label: {
                            Label(isStored ? "取消收藏" : "收藏", systemImage: isStored ? "star.fill" : "star")
                        }
                        Button {
                            UIPasteboard.general.string = "https://tieba.baidu.com/p/\(threadID)"
                            toast = "链接已复制"
                        } label: {
                            Label("复制链接", systemImage: "link")
                        }
                        ShareLink(item: URL(string: "https://tieba.baidu.com/p/\(threadID)")!) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        if appState.isLoggedIn {
                            Divider()
                            Button {
                                Task { await reportThread() }
                            } label: {
                                Label("举报主题贴", systemImage: "exclamationmark.bubble")
                            }
                            Button(role: .destructive) {
                                Task { await deleteThread() }
                            } label: {
                                Label("删除主题贴", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: FloorSelection.self) { sel in
                FloorDetailPage(threadId: threadID, postId: sel.postId,
                                forumId: resolvedForumId, forumName: forumName,
                                title: "\(sel.floor)楼的回复")
            }
            .fullScreenCover(isPresented: $showPhoto) {
                SKPhotoBrowserHost(initialItems: photoItems, initialIndex: photoIndex,
                                   context: PicPageContext(forumId: resolvedForumId,
                                                           forumName: forumName,
                                                           threadId: threadID,
                                                           seeLz: seeLz,
                                                           objType: "pb"))
            }
            .sheet(isPresented: $showReport) {
                if let reportURL {
                    NavigationStack { WebViewPage(url: reportURL) }
                }
            }
            .alert("跳页", isPresented: $showJumpPage) {
                TextField("页码（1 起）", text: $jumpPageInput)
                    .keyboardType(.numberPad)
                Button("跳转") {
                    guard let target = Int(jumpPageInput), target > 0 else { return }
                    jumpToPage(target - 1)  // pbPage 的 pn 从 0 计
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("当前第 \(max(1, nextPage + 1)) 页")
            }
            .sheet(isPresented: $showReply) {
                ReplySheet(threadId: threadID, forumId: resolvedForumId,
                           forumName: forumName.isEmpty ? "" : forumName,
                           postId: Int64(bitPattern: replyToFloor?.id ?? 0),
                           quoteHint: replyToFloor.map { "回复 @\($0.displayAuthorName)" } ?? "",
                           onReplied: { replyPosted = true })
            }
            .onChange(of: showReply) { showing in
                // 仅回复成功后刷新并滚到自己楼层；直接关闭 sheet 不动列表（用户反馈：关闭即回滚底部）
                if !showing {
                    defer { replyToFloor = nil }
                    guard replyPosted else { return }
                    replyPosted = false
                    Task {
                        await reload()
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        withAnimation { scrollTarget = "threadBottom" }
                    }
                }
            }
            .toast($toast)
            .task {
                if resolvedForumId == 0, forumId != 0 { resolvedForumId = forumId }
                if posts.isEmpty {
                    // 收藏页「自动只看楼主/倒序」设置（对齐 Android HabitSettings）
                    seeLz = initialOnlyLz
                    sortDesc = initialSortDesc
                    await reload()
                }
            }
    }

    private func toggleStore() async {
        guard appState.isLoggedIn else { toast = "请先登录"; return }
        guard let account = appState.account else { return }
        do {
            if isStored {
                try await TiebaWriteEndpoints.removeStore(threadId: threadID)
                isStored = false
                toast = "已取消收藏"
            } else {
                try await TiebaWriteEndpoints.addStore(threadId: threadID, postId: 0,
                                                       tbs: account.tbs)
                isStored = true
                toast = "收藏成功"
            }
            HistoryStore.record(type: 2, id: "\(threadID)", title: title,
                                subtitle: forumName, avatar: "")
        } catch {
            toast = error.localizedDescription
        }
    }

    /// 是否自己的楼层（对应 Android isSelfPost：author_id == user.id）
    private func isMyPost(_ post: Tieba_Post) -> Bool {
        guard let uidStr = appState.account?.uid, let uid = Int64(uidStr) else { return false }
        return post.author.id == uid
    }

    /// 举报楼层（对应 Android reportPost：checkjubao 拿 URL → 内置 WebView）
    private func report(_ post: Tieba_Post) async {
        guard appState.isLoggedIn else { toast = "请先登录"; return }
        do {
            let url = try await TiebaWriteEndpoints.checkReport(postId: "\(post.id)")
            if !url.isEmpty, let u = URL(string: url) {
                reportURL = u
                showReport = true
            } else {
                toast = "举报页地址获取失败"
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    /// 删除回复（对应 Android DeletePost）
    private func deletePost(_ post: Tieba_Post) async {
        guard appState.isLoggedIn, let account = appState.account else { return }
        if AppPreferences.shared.safeMode { toast = "安全模式已开启，写操作被拦截"; return }
        do {
            try await TiebaWriteEndpoints.delPost(
                forumId: resolvedForumId, forumName: forumName,
                threadId: threadID, postId: Int64(bitPattern: post.id),
                tbs: account.tbs, delMyPost: isMyPost(post))
            posts.removeAll { $0.id == post.id }
            toast = "已删除"
        } catch {
            toast = error.localizedDescription
        }
    }

    private func openPhoto(_ items: [PicViewItem], _ index: Int) {
        // 空列表不打开查看器（防御：永不出现「无图片」占位页）
        guard !items.isEmpty else { return }
        photoItems = items
        photoIndex = index
        showPhoto = true
    }

    /// 举报主题贴（用首楼 pid）
    private func reportThread() async {
        guard let first = posts.first else { return }
        await report(first)
    }

    /// 删除主题贴（对应 Android delThreadFlow；delete_my_thread 由是否楼主决定）
    private func deleteThread() async {
        guard appState.isLoggedIn, let account = appState.account else { return }
        if AppPreferences.shared.safeMode { toast = "安全模式已开启，写操作被拦截"; return }
        let isMine = isMyPost(posts.first ?? Tieba_Post())
        do {
            try await TiebaWriteEndpoints.delThread(
                forumId: resolvedForumId, forumName: forumName, threadId: threadID,
                tbs: account.tbs, delMyThread: isMine)
            toast = "已删除主题贴"
        } catch {
            toast = error.localizedDescription
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && posts.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorText, posts.isEmpty {
            UnavailableView(title: "加载失败", systemImage: "wifi.exclamationmark",
                                description: err, retry: { Task { await reload() } })
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // 投票组件（对应 Android PollWidget，置于楼层列表顶部）
                        if let poll = pollInfo {
                            pollSection(poll)
                            Divider()
                        }
                        // 正序时支持向上补齐更早页（Android「加载上一页」）
                        if !sortDesc, lowestPage > 0 {
                            Button {
                                Task { await loadPrev() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if isLoadingMore { ProgressView() }
                                    Text("加载上一页（第 \(lowestPage) 页）")
                                        .font(.footnote).foregroundStyle(.blue)
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(Array(posts.enumerated()), id: \.offset) { idx, post in
                            postCard(post, floor: floorNumber(post, index: idx))
                            Divider()
                        }
                        if hasMore {
                            LoadMoreFooter { await loadMore() }
                        }
                        Color.clear.frame(height: 1).id("threadBottom")
                    }
                }
                .refreshable { await reload() }
                .onChange(of: scrollTarget) { target in
                    guard let target else { return }
                    proxy.scrollTo(target, anchor: .bottom)
                    self.scrollTarget = nil
                }
            }
        }
    }

    /// 楼层号：Android 用 Post.floor
    private func floorNumber(_ post: Tieba_Post, index: Int) -> Int {
        post.floor > 0 ? Int(post.floor) : index + 1
    }

    // MARK: 投票（对应 Android PollWidget + ThreadUiIntent.PollThread）

    @ViewBuilder
    private func pollSection(_ poll: Tieba_PollInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !poll.title.isEmpty {
                Text(poll.title).font(.subheadline.weight(.semibold))
            }
            let total = poll.options.reduce(0) { $0 + $1.num }
            ForEach(Array(poll.options.enumerated()), id: \.element.id) { _, opt in
                Button {
                    guard appState.isLoggedIn, !pollVoted else { return }
                    if selectedPollOptions.contains(UInt64(opt.id)) {
                        selectedPollOptions.remove(UInt64(opt.id))
                    } else {
                        selectedPollOptions.insert(UInt64(opt.id))
                    }
                } label: {
                    HStack {
                        Image(systemName: selectedPollOptions.contains(UInt64(opt.id))
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedPollOptions.contains(UInt64(opt.id)) ? .blue : .secondary)
                        Text(opt.text).font(.footnote)
                        Spacer()
                        if pollVoted {
                            Text("\(shortNum(opt.num))票")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Button {
                Task { await vote() }
            } label: {
                Text(pollVoted ? "已投票" : "投票")
                    .frame(maxWidth: .infinity)
                    .font(.footnote.bold())
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedPollOptions.isEmpty || pollVoted || !appState.isLoggedIn)
            if total > 0 {
                Text("共 \(shortNum(total)) 人投票")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func vote() async {
        guard let poll = pollInfo else { return }
        guard appState.isLoggedIn, let account = appState.account else { return }
        if AppPreferences.shared.safeMode { toast = "安全模式已开启，写操作被拦截"; return }
        let options = selectedPollOptions.map(String.init).joined(separator: ",")
        do {
            try await TiebaExtraEndpoints.addPollPost(client: .shared, forumId: resolvedForumId,
                                                      threadId: threadID, options: options)
            pollVoted = true
            toast = "投票成功"
            await reload()
        } catch {
            toast = error.localizedDescription
        }
    }

    /// 跳页（对应 Android jumpToPage：直接请求指定 pn 的楼层）
    private func jumpToPage(_ pn: Int) {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let data = try await TiebaEndpoints.pbPage(
                    client: .shared, threadId: threadID, page: pn, rn: 15,
                    forumId: resolvedForumId, seeLz: seeLz, sortType: sortDesc ? 1 : 0)
                posts = data.postList
                posts.resolveAuthors(AuthorResolver.map(data.userList))
                nextPage = Int(data.page.currentPage)
                hasMore = data.page.hasMore_p != 0
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func reload() async {
        isLoading = true
        nextPage = 0
        lowestPage = 0
        hasMore = true
        defer { isLoading = false }
        do {
            // Android 首页固定 pn=0
            let data = try await TiebaEndpoints.pbPage(
                client: .shared, threadId: threadID, page: 0, rn: 15,
                forumId: resolvedForumId, seeLz: seeLz, sortType: sortDesc ? 1 : 0)
            posts = data.postList
            posts.resolveAuthors(AuthorResolver.map(data.userList))
            forumName = data.forum.name
            threadAgree = data.thread.agree
            if resolvedForumId == 0 {
                resolvedForumId = forumId != 0 ? forumId : data.forum.id
            }
            nextPage = Int(data.page.currentPage)
            hasMore = data.page.hasMore_p != 0
            errorText = nil
            // 投票信息（Android resolvePollInfo：options 非空即视为投票帖）
            let poll = data.thread.pollInfo
            pollInfo = (!poll.options.isEmpty || !poll.title.isEmpty) ? poll : nil
            // 记录浏览历史（对齐 Android HistoryUtil.recordThread）
            HistoryStore.record(type: 2, id: "\(threadID)", title: title,
                                subtitle: forumName, avatar: "")
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let data = try await TiebaEndpoints.pbPage(
                client: .shared, threadId: threadID, page: nextPage, rn: 15,
                forumId: resolvedForumId, seeLz: seeLz, sortType: sortDesc ? 1 : 0)
            var more = data.postList
            more.resolveAuthors(AuthorResolver.map(data.userList))
            posts += more
            nextPage = Int(data.page.currentPage)
            hasMore = data.page.hasMore_p != 0
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// 加载上一页（Android「加载上一页」：正序时向上补齐更早的楼层页）
    private func loadPrev() async {
        guard !isLoadingMore, !sortDesc, lowestPage > 0 else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let data = try await TiebaEndpoints.pbPage(
                client: .shared, threadId: threadID, page: lowestPage - 1, rn: 15,
                forumId: resolvedForumId, seeLz: seeLz, sortType: 0)
            var earlier = data.postList
            earlier.resolveAuthors(AuthorResolver.map(data.userList))
            posts = earlier + posts
            lowestPage -= 1
        } catch {
            errorText = error.localizedDescription
        }
    }

    @ViewBuilder
    private func postCard(_ post: Tieba_Post, floor: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 作者行
            HStack(spacing: 8) {
                AvatarView(url: post.authorAvatarURL, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.displayAuthorName)
                        .font(.footnote.weight(.medium))
                    HStack(spacing: 6) {
                        if post.time > 0 {
                            Text(formattedTime(fromUnixSeconds: Int64(post.time)))
                        }
                        if !post.author.ipAddress.isEmpty {
                            Text("IP \(post.author.ipAddress)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(floor)楼")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Menu {
                    floorMenuItems(post, floor: floor)
                } label: {
                    Image(systemName: "ellipsis").font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            // 图片点击进查看器：手势挂在每张图片自身（Android PbContentRender 对齐），
            // 不再用整层透明 overlay（会拦截文字点击且与渲染条件不一致）
            PbContentView(contents: post.content, hideImages: immersive,
                          onImageTap: { urls, index in
                              guard !immersive else { return }
                              openPhoto(urls, index)
                          })
            if !immersive {
                // 楼中楼预览（对齐 Android ThreadPage.kt:2305：sub_post_number>0 时楼层内直接渲染子回复）
                let subs = post.subPostList.subPostList.prefix(3)
                if !subs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                            NavigationLink(value: FloorSelection(postId: Int64(bitPattern: post.id),
                                                                 floor: floor)) {
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(sub.displayAuthorName)：")
                                        .font(.caption).foregroundStyle(.blue)
                                    EmoticonText(text: sub.content.map(\.text).joined(),
                                                 font: .caption, pointSize: 12,
                                                 color: .primary)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if post.subPostNumber > 3 {
                            NavigationLink(value: FloorSelection(postId: Int64(bitPattern: post.id),
                                                                 floor: floor)) {
                                Text("查看全部 \(post.subPostNumber) 条回复")
                                    .font(.caption).foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 8))
                }
                HStack(spacing: 16) {
                    LikeButton(threadId: threadID, postId: Int64(bitPattern: post.id),
                               isLiked: post.agree.hasAgree_p == 1,
                               count: post.agree.agreeNum)
                    if post.subPostNumber > 0 {
                        NavigationLink(value: FloorSelection(postId: Int64(bitPattern: post.id), floor: floor)) {
                            Label("\(post.subPostNumber) 条回复", systemImage: "bubble.right")
                                .font(.caption)
                        }
                    } else {
                        NavigationLink(value: FloorSelection(postId: Int64(bitPattern: post.id), floor: floor)) {
                            Label("回复", systemImage: "bubble.right")
                                .font(.caption)
                        }
                    }
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        // 楼层长按菜单（对齐 Android LongClickMenu：复制/回复/收藏到此楼/举报/删除）
        .contextMenu { floorMenuItems(post, floor: floor) }
    }

    /// 楼层菜单项（Menu 与 contextMenu 共用）
    @ViewBuilder
    private func floorMenuItems(_ post: Tieba_Post, floor: Int) -> some View {
        Button {
            UIPasteboard.general.string = post.content.map(\.text).joined()
            toast = "已复制楼层内容"
        } label: {
            Label("复制内容", systemImage: "doc.on.doc")
        }
        Button {
            replyToFloor = post
            showReply = true
        } label: {
            Label("回复", systemImage: "arrowshape.turn.up.left")
        }
        Button {
            Task { await storeFloor(post) }
        } label: {
            Label("收藏到此楼", systemImage: "star")
        }
        Button {
            Task { await report(post) }
        } label: {
            Label("举报", systemImage: "exclamationmark.bubble")
        }
        if isMyPost(post) {
            Button(role: .destructive) {
                Task { await deletePost(post) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// 收藏到此楼（Android addStore with pid）
    private func storeFloor(_ post: Tieba_Post) async {
        guard appState.isLoggedIn, let account = appState.account else { toast = "请先登录"; return }
        if AppPreferences.shared.safeMode { toast = "安全模式已开启，写操作被拦截"; return }
        do {
            try await TiebaWriteEndpoints.addStore(threadId: threadID,
                                                   postId: Int64(bitPattern: post.id),
                                                   tbs: account.tbs)
            toast = post.floor > 0 ? "已收藏到 \(Int(post.floor))楼" : "已收藏到此楼"
        } catch {
            toast = error.localizedDescription
        }
    }
}

// MARK: - 楼中楼详情页

/// 楼中楼（对应 Android `SubPostsPage`）：V22 通道 `/c/f/pb/floor`
struct FloorDetailPage: View {
    let threadId: Int64
    let postId: Int64
    var forumId: Int64 = 0
    var forumName: String = ""
    let title: String

    @State private var subPosts: [Tieba_SubPostList] = []
    @State private var hostPost: Tieba_Post?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var page = 1
    @State private var hasMore = false
    @State private var replyTarget: ReplyTarget?
    @State private var showSubReport = false
    @State private var subReportURL: URL?
    /// 楼中楼图片查看器（对齐 Android 楼中楼看图）
    @State private var showPhoto = false
    @State private var photoItems: [PicViewItem] = []
    @State private var photoIndex = 0
    @EnvironmentObject private var appState: AppState

    /// 楼中楼回复目标
    struct ReplyTarget: Identifiable, Hashable {
        var id: String { "\(postId)-\(subPostId)-\(hint)" }
        let postId: Int64
        let subPostId: Int64
        let hint: String
    }

    var body: some View {
        Group {
            if isLoading && subPosts.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText, subPosts.isEmpty {
                UnavailableView(title: "加载失败", systemImage: "wifi.exclamationmark", description: err)
            } else {
                List {
                    if let hostPost {
                        Section("原帖") {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    AvatarView(url: hostPost.authorAvatarURL, size: 28)
                                    Text(hostPost.displayAuthorName).font(.footnote.weight(.medium))
                                    Spacer()
                                    Text("\(hostPost.floor)楼").font(.caption2).foregroundStyle(.secondary)
                                }
                                PbContentView(contents: hostPost.content, fontSize: .footnote,
                                              onImageTap: { items, index in
                                                  guard !items.isEmpty else { return }
                                                  photoItems = items; photoIndex = index
                                                  showPhoto = true
                                              })
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Section("评论 \(subPosts.count)") {
                        ForEach(Array(subPosts.enumerated()), id: \.offset) { _, sub in
                            subPostRow(sub)
                                .onTapGesture {
                                    guard appState.isLoggedIn else { return }
                                    replyTarget = ReplyTarget(postId: postId, subPostId: Int64(bitPattern: sub.id),
                                                              hint: sub.displayAuthorName)
                                }
                        }
                        if hasMore {
                            LoadMoreFooter { await loadMore() }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await reload() }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            guard appState.isLoggedIn else { return }
                            replyTarget = ReplyTarget(postId: postId, subPostId: 0,
                                                      hint: hostPost?.displayAuthorName ?? "")
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
                .fullScreenCover(isPresented: $showPhoto) {
                    SKPhotoBrowserHost(initialItems: photoItems, initialIndex: photoIndex,
                                       context: PicPageContext(forumId: forumId,
                                                               forumName: forumName,
                                                               threadId: threadId,
                                                               seeLz: false,
                                                               objType: "pb"))
                }
                .sheet(item: $replyTarget) { target in
                    ReplySheet(threadId: threadId, forumId: forumId,
                               forumName: forumNameOfHost,
                               postId: target.postId,
                               subPostId: target.subPostId,
                               quoteHint: target.hint)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .bottomBarHidden()
        .sheet(isPresented: $showSubReport) {
            if let subReportURL {
                NavigationStack { WebViewPage(url: subReportURL) }
            }
        }
        .task { if subPosts.isEmpty { await reload() } }
    }

    /// 楼中楼回复走 addPost 时 kw 需要：用原帖所属吧名（hostPost 无吧名时留空由服务端补）
    private var forumNameOfHost: String { "" }

    private func subPostRow(_ sub: Tieba_SubPostList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AvatarView(url: sub.authorAvatarURL, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sub.displayAuthorName).font(.footnote.weight(.medium))
                    Text(relativeTime(fromUnixSeconds: Int64(sub.time)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            PbContentView(contents: sub.content, fontSize: .footnote,
                          onImageTap: { items, index in
                              guard !items.isEmpty else { return }
                              photoItems = items; photoIndex = index; showPhoto = true
                          })
            HStack(spacing: 12) {
                // 楼中楼点赞（对齐 Android SubPostItem 点赞可点）
                LikeButton(threadId: threadId, postId: Int64(sub.id),
                           isLiked: sub.agree.hasAgree_p == 1,
                           count: sub.agree.agreeNum)
            }
        }
        .padding(.vertical, 4)
        // 楼中楼长按菜单（对齐 Android SubPostItem LongClickMenu：复制/回复/举报/删除）
        .contextMenu {
            Button {
                UIPasteboard.general.string = sub.content.map(\.text).joined()
            } label: {
                Label("复制内容", systemImage: "doc.on.doc")
            }
            Button {
                replyTarget = FloorDetailPage.ReplyTarget(
                    postId: postId, subPostId: Int64(bitPattern: sub.id),
                    hint: "回复 @\(sub.displayAuthorName)")
            } label: {
                Label("回复", systemImage: "arrowshape.turn.up.left")
            }
            Button {
                Task { await reportSub(sub) }
            } label: {
                Label("举报", systemImage: "exclamationmark.bubble")
            }
            Button(role: .destructive) {
                Task { await deleteSub(sub) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// 举报楼中楼（checkjubao）
    private func reportSub(_ sub: Tieba_SubPostList) async {
        guard appState.isLoggedIn else { return }
        do {
            let url = try await TiebaWriteEndpoints.checkReport(postId: "\(bitPatternCompat(sub.id))")
            if !url.isEmpty, let u = URL(string: url) {
                subReportURL = u
                showSubReport = true
            }
        } catch { }
    }

    /// 删除楼中楼（层主或楼主）
    private func deleteSub(_ sub: Tieba_SubPostList) async {
        guard appState.isLoggedIn, let account = appState.account else { return }
        if AppPreferences.shared.safeMode { return }
        do {
            try await TiebaWriteEndpoints.delPost(
                forumId: forumId, forumName: "",
                threadId: threadId, postId: bitPatternCompat(sub.id),
                tbs: account.tbs, delMyPost: isMySub(sub))
            subPosts.removeAll { $0.id == sub.id }
        } catch { }
    }

    private func isMySub(_ sub: Tieba_SubPostList) -> Bool {
        guard let uidStr = appState.account?.uid, let uid = Int64(uidStr) else { return false }
        return sub.author.id == uid
    }

    /// SubPostList.id 是 UInt64 → Int64（位模式保持）
    private func bitPatternCompat(_ v: UInt64) -> Int64 {
        Int64(bitPattern: v)
    }

    private func reload() async {
        isLoading = true
        page = 1
        defer { isLoading = false }
        do {
            let data = try await TiebaEndpoints.pbFloor(
                client: .shared, threadId: threadId, postId: postId,
                page: 1, forumId: forumId)
            hostPost = data.hasPost ? data.post : nil
            subPosts = data.subpostList
            hasMore = data.hasPage && data.page.hasMore_p != 0
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard hasMore else { return }
        do {
            let next = page + 1
            let data = try await TiebaEndpoints.pbFloor(
                client: .shared, threadId: threadId, postId: postId,
                page: next, forumId: forumId)
            subPosts += data.subpostList
            page = next
            hasMore = data.hasPage && data.page.hasMore_p != 0
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 回复面板

/// 回复/发帖面板（对应 Android `ReplyPage`）：
/// 走 proto `/c/c/post/add?cmd=309731`（V12_POST 通道）。
/// 含草稿自动保存（500ms 防抖对齐 Android）、表情面板（#(名字)）、小尾巴、安全模式拦截。
struct ReplySheet: View {
    let threadId: Int64
    let forumId: Int64
    let forumName: String
    /// 回复目标楼层（0=直接回复主题）
    var postId: Int64 = 0
    var subPostId: Int64 = 0
    var replyUserId: Int64 = 0
    var quoteHint: String = ""
    /// 发新主题贴的标题（threadId==0 时使用）
    var threadTitle: String = ""
    /// 发送成功回调（调用方据此刷新列表；取消关闭不触发）
    var onReplied: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var title = ""
    @State private var showEmoticon = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var pickerItem: PhotosPickerItem?
    @State private var uploading = false

    private var draftKey: String {
        DraftStore.hashKey(threadId: threadId, postId: postId, subPostId: subPostId)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    if threadId == 0 {
                        // Android 发主题帖：标题限 31 字（ReplyPage.kt 标题输入）
                        Section("标题") {
                            TextField("输入标题（最多 31 字）", text: $title)
                                .onChange(of: title) { newValue in
                                    if newValue.count > 31 {
                                        title = String(newValue.prefix(31))
                                    }
                                }
                        }
                    }
                    Section {
                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .disabled(busy)
                            .onChange(of: text) { newValue in
                                scheduleDraftSave(newValue)
                            }
                    } header: {
                        Text(quoteHint.isEmpty
                             ? (threadId == 0 ? "发新主题贴" : "回复")
                             : "回复 \(quoteHint)")
                    } footer: {
                        if !prefs.littleTail.isEmpty {
                            Text("将附加小尾巴：\(prefs.littleTail)")
                        }
                    }
                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            if busy {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("发送").frame(maxWidth: .infinity).bold()
                            }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                    }
                    if let errorText {
                        Section {
                            Text(errorText).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
                if showEmoticon {
                    EmoticonPanel { code in
                        text += code
                    }
                }
            }
            .navigationTitle(threadId == 0 ? "发帖" : "回复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo")
                    }
                    Button {
                        showEmoticon.toggle()
                    } label: {
                        Image(systemName: showEmoticon ? "keyboard" : "face.smiling")
                    }
                }
            }
            .onChange(of: pickerItem) { item in
                Task { await uploadPicked(item) }
            }
            .onAppear {
                // 恢复草稿（对应 Android LaunchedEffect getDraft）
                if let draft = DraftStore.get(draftKey), !draft.isEmpty {
                    text = draft
                }
            }
            .onDisappear {
                draftSaveTask?.cancel()
            }
        }
    }

    /// 草稿防抖保存（对齐 Android curTextFlow.sample(500)）
    private func scheduleDraftSave(_ content: String) {
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            DraftStore.save(draftKey, content)
        }
    }

    /// 图片上传：PhotosPicker → 水印 → 压缩 JPEG → uploadPicture → 插入 #(pic,id,w,h)
    /// （对应 Android ImageUploader + ReplyPage.kt:328 的插入格式）
    private func uploadPicked(_ item: PhotosPickerItem?) async {
        guard let item, !uploading else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let original = UIImage(data: data) else {
            errorText = "图片读取失败"
            return
        }
        // 图片水印（Android HabitSettings：无/用户名/吧名）
        let uiImage = applyWatermark(original)
        // 压缩到 512KB 以内（Android DEFAULT_CHUNK_SIZE=512000）
        var jpeg = uiImage.jpegData(compressionQuality: 0.9)
        var quality: CGFloat = 0.9
        while (jpeg?.count ?? 0) > 500_000 && quality > 0.2 {
            quality -= 0.15
            jpeg = uiImage.jpegData(compressionQuality: quality)
        }
        guard let finalData = jpeg, (finalData.count) <= 500_000 else {
            errorText = "图片过大（>500KB）无法上传"
            return
        }
        uploading = true
        defer { uploading = false }
        do {
            let result = try await ImageUploader.upload(
                imageData: finalData,
                width: Int(uiImage.size.width * uiImage.scale),
                height: Int(uiImage.size.height * uiImage.scale))
            text += result.contentCode
        } catch {
            errorText = "上传失败: \(error.localizedDescription)"
        }
    }

    /// 图片水印（Android 图片添加水印：0 无 / 1 用户名 / 2 吧名）
    private func applyWatermark(_ image: UIImage) -> UIImage {
        let prefs = AppPreferences.shared
        var text = ""
        switch prefs.watermarkType {
        case 1: text = appState.account?.name ?? ""
        case 2: text = forumName.isEmpty ? "百度贴吧" : forumName
        default: return image
        }
        guard !text.isEmpty else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.5)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = CGSize(width: 1, height: 1)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(14, image.size.width / 24),
                                         weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55),
                .shadow: shadow,
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let origin = CGPoint(x: image.size.width - size.width - 12,
                                 y: image.size.height - size.height - 12)
            (text as NSString).draw(at: origin, withAttributes: attrs)
        }
    }

    private func submit() async {
        guard appState.isLoggedIn, let account = appState.account else {
            errorText = "请先登录后再回复"
            return
        }
        // 安全模式拦截（对应 Android SafeModeInterceptor：写操作全部阻止）
        if prefs.safeMode {
            errorText = "安全模式已开启：为保护账号，客户端处于只读状态。可在设置中关闭安全模式。"
            return
        }
        busy = true
        defer { busy = false }
        do {
            var content = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // 小尾巴（Android little_tail：自由文本附加）
            if !prefs.littleTail.isEmpty, !content.contains(prefs.littleTail) {
                content += "\n\(prefs.littleTail)"
            }
            if threadId == 0 {
                // 发新主题贴（JSON `/c/c/thread/add`，MINI 通道）
                let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await TiebaWriteEndpoints.addThread(
                    content: content, forumId: "\(forumId)", forumName: forumName,
                    title: finalTitle, isHide: 1, isTitle: finalTitle.isEmpty ? 1 : 0)
            } else {
                _ = try await TiebaExtraEndpoints.addPost(
                    client: .shared,
                    content: content,
                    forumId: "\(forumId)",
                    forumName: forumName,
                    threadId: "\(threadId)",
                    tbs: account.tbs,
                    nameShow: account.name,
                    postId: postId != 0 ? "\(postId)" : nil,
                    subPostId: subPostId != 0 ? "\(subPostId)" : nil,
                    replyUserId: replyUserId != 0 ? "\(replyUserId)" : nil)
            }
            DraftStore.delete(draftKey)
            onReplied?()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 点赞按钮

/// 点赞按钮：调用 MINI 通道 `/c/c/agree/opAgree`（需登录）
struct LikeButton: View {
    let threadId: Int64
    let postId: Int64
    var isLiked: Bool
    var count: Int64

    @EnvironmentObject private var appState: AppState
    @State private var liked: Bool
    @State private var num: Int64
    @State private var busy = false
    @State private var alertText: String?

    init(threadId: Int64, postId: Int64, isLiked: Bool, count: Int64) {
        self.threadId = threadId
        self.postId = postId
        self.isLiked = isLiked
        self.count = count
        _liked = State(initialValue: isLiked)
        _num = State(initialValue: count)
    }

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Label(shortNum(num), systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.caption)
                .foregroundStyle(liked ? .blue : .secondary)
        }
        .disabled(busy)
        .alert("提示", isPresented: Binding(get: { alertText != nil },
                                          set: { if !$0 { alertText = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertText ?? "")
        }
    }

    private func toggle() async {
        guard appState.isLoggedIn else {
            alertText = "请先登录后再点赞"
            return
        }
        busy = true
        defer { busy = false }
        let target = !liked
        do {
            try await TiebaWriteEndpoints.agree(threadId: threadId, postId: postId,
                                                opType: target ? 0 : 1)
            liked = target
            num += target ? 1 : -1
            if num < 0 { num = 0 }
        } catch {
            alertText = error.localizedDescription
        }
    }
}
