import SwiftUI
import UIKit

/// PbContent 富文本渲染（对应 Android PbContentRender 的 iOS 版）：
/// type 0/9/27/35/40=文字、1=链接、2=表情、3/20=图片、4=@用户、5=视频、10=语音
struct PbContentView: View {
    let contents: [Tieba_PbContent]
    var fontSize: Font = .subheadline

    private enum Item {
        case text(String)
        case image(url: URL?, aspect: CGFloat)
        case link(String)
        case video
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
                textBuffer += "[\(c.c)]"
            case 3, 20:
                flush()
                result.append(.image(url: Self.picURL(c), aspect: Self.aspect(c)))
            case 4:
                textBuffer += "@\(c.text) "
            case 5:
                flush()
                result.append(.video)
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
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .text(let t):
                    Text(t).font(fontSize).foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                case .image(let url, let aspect):
                    RemoteImage(url: url, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(aspect, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .link(let text):
                    Text(text).font(fontSize).foregroundStyle(.blue)
                case .video:
                    Label("视频内容", systemImage: "play.rectangle")
                        .font(fontSize).foregroundStyle(.secondary)
                case .voice(let sec):
                    Label("语音 \(sec)″", systemImage: "waveform")
                        .font(fontSize).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 图片 URL：originSrc > bigCdnSrc > bigSrc > cdnSrc > src（Android ImageUtil.getUrl 顺序）
    static func picURL(_ c: Tieba_PbContent) -> URL? {
        let candidates = [c.originSrc, c.bigCdnSrc, c.bigSrc, c.cdnSrc, c.src]
        let s = candidates.first { !$0.isEmpty } ?? ""
        return s.isEmpty ? nil : URL(string: s)
    }

    /// bsize "宽,高" → aspect ratio
    static func aspect(_ c: Tieba_PbContent) -> CGFloat {
        let parts = c.bsize.split(separator: ",")
        guard parts.count == 2,
              let w = Double(parts[0]), w > 0,
              let h = Double(parts[1]), h > 0 else { return 4.0 / 3.0 }
        return CGFloat(w / h)
    }
}

// MARK: - 帖子详情页

/// 帖子页（对应 Android `ThreadPage`）：楼层列表 + 分页 + 楼中楼入口
struct ThreadPage: View {
    let threadID: Int64
    let title: String
    var forumId: Int64 = 0

    @EnvironmentObject private var appState: AppState
    @State private var posts: [Tieba_Post] = []
    @State private var forumName = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var nextPage = 0
    @State private var hasMore = true
    @State private var seeLz = false
    /// 从响应里补全的 forum id（首页请求可能未带）
    @State private var resolvedForumId: Int64 = 0
    @State private var isStored = false
    @State private var toast: String?
    @State private var showReply = false
    /// 楼层列表首个楼层 pid（回复主题作者用）
    @State private var threadAuthorName = ""

    /// 楼中楼导航目标
    struct FloorSelection: Hashable {
        let postId: Int64
        let floor: Int
    }

    var body: some View {
        content
            .navigationTitle(title.isEmpty ? (forumName.isEmpty ? "帖子" : forumName) : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showReply = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    Menu {
                        Button {
                            seeLz.toggle()
                            Task { await reload() }
                        } label: {
                            Label(seeLz ? "看全部" : "只看楼主",
                                  systemImage: seeLz ? "person.3" : "person.crop.circle")
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: FloorSelection.self) { sel in
                FloorDetailPage(threadId: threadID, postId: sel.postId,
                                forumId: resolvedForumId, title: "\(sel.floor)楼评论")
            }
            .sheet(isPresented: $showReply) {
                ReplySheet(threadId: threadID, forumId: resolvedForumId,
                           forumName: forumName.isEmpty ? "" : forumName)
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            self.toast = nil
                        }
                }
            }
            .task {
                if resolvedForumId == 0, forumId != 0 { resolvedForumId = forumId }
                if posts.isEmpty { await reload() }
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

    @ViewBuilder
    private var content: some View {
        if isLoading && posts.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorText, posts.isEmpty {
            UnavailableView(title: "加载失败", systemImage: "wifi.exclamationmark", description: err)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(posts.enumerated()), id: \.offset) { idx, post in
                        postCard(post, floor: floorNumber(post, index: idx))
                        Divider()
                    }
                    if hasMore {
                        LoadMoreFooter { await loadMore() }
                    }
                }
            }
            .refreshable { await reload() }
        }
    }

    /// 楼层号：Android 用 Post.floor
    private func floorNumber(_ post: Tieba_Post, index: Int) -> Int {
        post.floor > 0 ? Int(post.floor) : index + 1
    }

    private func reload() async {
        isLoading = true
        nextPage = 0
        hasMore = true
        defer { isLoading = false }
        do {
            // Android 首页固定 pn=0
            let data = try await TiebaEndpoints.pbPage(
                client: .shared, threadId: threadID, page: 0, rn: 15,
                forumId: resolvedForumId, seeLz: seeLz)
            posts = data.postList
            forumName = data.forum.name
            if resolvedForumId == 0 {
                resolvedForumId = forumId != 0 ? forumId : data.forum.id
            }
            nextPage = Int(data.page.currentPage)
            hasMore = data.page.hasMore_p != 0
            errorText = nil
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
                forumId: resolvedForumId, seeLz: seeLz)
            posts += data.postList
            nextPage = Int(data.page.currentPage)
            hasMore = data.page.hasMore_p != 0
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
                    if post.time > 0 {
                        Text(formattedTime(fromUnixSeconds: Int64(post.time)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(floor)楼")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            PbContentView(contents: post.content)
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
        .padding(16)
    }
}

// MARK: - 楼中楼详情页

/// 楼中楼（对应 Android `SubPostsPage`）：V22 通道 `/c/f/pb/floor`
struct FloorDetailPage: View {
    let threadId: Int64
    let postId: Int64
    var forumId: Int64 = 0
    let title: String

    @State private var subPosts: [Tieba_SubPostList] = []
    @State private var hostPost: Tieba_Post?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var page = 1
    @State private var hasMore = false
    @State private var replyTarget: ReplyTarget?
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
                                PbContentView(contents: hostPost.content, fontSize: .footnote)
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
            PbContentView(contents: sub.content, fontSize: .footnote)
            HStack(spacing: 12) {
                Label(shortNum(Int64(sub.agree.agreeNum)), systemImage: "hand.thumbsup")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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

/// 回复/发帖面板（对应 Android `ReplyPage` 的 iOS 精简版）：
/// 走 proto `/c/c/post/add?cmd=309731`（V12_POST 通道）。
/// threadId 为 0 时表示发新主题贴（发主题还需吧名，当前仅支持回帖场景）。
struct ReplySheet: View {
    let threadId: Int64
    let forumId: Int64
    let forumName: String
    /// 回复目标楼层（0=直接回复主题）
    var postId: Int64 = 0
    var subPostId: Int64 = 0
    var replyUserId: Int64 = 0
    var quoteHint: String = ""

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .disabled(busy)
                } header: {
                    Text(quoteHint.isEmpty
                         ? (threadId == 0 ? "发新主题贴" : "回复")
                         : "回复 \(quoteHint)")
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
            .navigationTitle(threadId == 0 ? "发帖" : "回复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        guard appState.isLoggedIn, let account = appState.account else {
            errorText = "请先登录后再回复"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
