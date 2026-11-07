import SwiftUI

/// 内存位图缓存（RemoteImage 专用；磁盘层由共享 URLCache 承担）
final class RemoteImageCache {
    static let shared = RemoteImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 64 * 1024 * 1024
    }
    func image(for url: URL) -> UIImage? { cache.object(forKey: url.absoluteString as NSString) }
    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.absoluteString as NSString,
                        cost: image.pngData()?.count ?? 1)
    }
}

/// 网络图片：内存缓存 + URLCache 二级缓存 + 失败占位（对应 Android NetworkImage）
/// 不用 AsyncImage：它无内存缓存，列表滚动会反复重下并闪烁
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else if failed {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .task(id: url) {
            guard let url else { failed = true; return }
            if let cached = RemoteImageCache.shared.image(for: url) {
                image = cached
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = UIImage(data: data) {
                    RemoteImageCache.shared.store(img, for: url)
                    image = img
                    failed = false
                } else {
                    failed = true
                }
            } catch {
                failed = true
            }
        }
    }
}

/// 圆形头像
struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 36

    var body: some View {
        RemoteImage(url: url)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color(.systemGray5), lineWidth: 0.5))
    }
}

/// 帖子卡片：三段式（header / content / action），对应 Android FeedCard
struct FeedCard: View {
    let thread: Tieba_ThreadInfo
    /// 不感兴趣理由（推荐流有值时显示 ↓ 按钮，Android DislikeBtn 1:1）
    var dislikeReasons: [Tieba_DislikeReason] = []
    var onDislike: (() -> Void)?
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var dislikeClickTime: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            actionBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: 8) {
            AvatarView(url: thread.authorAvatarURL, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if thread.isTopThread {
                        Text("置顶")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.red)
                    }
                    Text(thread.displayAuthorName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if !thread.forumName.isEmpty {
                        Text(thread.forumName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    Text(thread.relativeTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !dislikeReasons.isEmpty {
                // 不感兴趣（Android DislikeBtn：↓ 图标 → 理由网格 → 提交）
                Menu {
                    ForEach(dislikeReasons, id: \.dislikeID) { reason in
                        Button {
                            Task { await submitDislike(reason) }
                        } label: {
                            Text(reason.dislikeReason.isEmpty ? "不感兴趣" : reason.dislikeReason)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
            }
        }
    }

    /// 提交不感兴趣（/c/c/excellent/submitDislike）并由列表移除该卡
    private func submitDislike(_ reason: Tieba_DislikeReason) async {
        if dislikeClickTime == 0 { dislikeClickTime = Int64(Date().timeIntervalSince1970 * 1000) }
        do {
            try await TiebaWriteEndpoints.submitDislike(
                threadId: thread.tid, forumId: thread.forumID,
                reasons: [(id: reason.dislikeID, extra: reason.extra)],
                clickTime: dislikeClickTime)
            onDislike?()
        } catch {
            onDislike?() // 提交失败也本地移除（对齐 Android Dislike.Success 语义）
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if thread.isNoTitle != 1 && !thread.title.isEmpty {
                    Text((thread.isGood == 1 ? "[精] " : "") + thread.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                if !thread.abstractText.isEmpty {
                    // Android FeedCard：abstractText.emoticonString（内联表情）
                    EmoticonText(text: thread.abstractText, font: .subheadline,
                                 pointSize: 15, color: .secondary, lineLimit: 3)
                }
                if thread.isPoll {
                    Label("投票", systemImage: "chart.bar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if thread.videoInfo.thumbnailURL.isNotEmpty {
                    Label("视频", systemImage: "play.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // 封面固定在卡片右侧（Spacer 撑开，无论文字长短都贴右边缘）
            Spacer(minLength: 8)
            coverView
        }
    }

    /// 右侧封面：多图成排（≤3 张，84x56）；单图 108x72；视频用封面图
    /// 「隐藏媒体」开关开启时不渲染（Android 收起贴子列表的图片和视频）
    @ViewBuilder
    private var coverView: some View {
        if prefs.hideMedia {
            EmptyView()
        } else {
            coverImage
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        let urls = thread.mediaURLs
        // 夜间模式压暗缩略图（Android night mode 缩略图压暗）
        let dim = colorScheme == .dark && prefs.imageDarkenWhenNightMode
        if urls.count > 1 {
            HStack(spacing: 4) {
                ForEach(Array(urls.prefix(3).enumerated()), id: \.offset) { _, u in
                    RemoteImage(url: u)
                        .frame(width: 84, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .brightness(dim ? 0.72 : 1)
                }
            }
        } else if let single = urls.first {
            RemoteImage(url: single)
                .frame(width: 108, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .brightness(dim ? 0.72 : 1)
        } else if let vThumb = thread.videoThumbnailURL {
            RemoteImage(url: vThumb)
                .frame(width: 108, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .brightness(dim ? 0.72 : 1)
        }
    }

    private var actionBar: some View {
        HStack {
            Label(shortNum(thread.shareNum), systemImage: "arrowshape.turn.up.right")
                .frame(maxWidth: .infinity)
            Label(shortNum(Int64(thread.replyNum)), systemImage: "bubble.right")
                .frame(maxWidth: .infinity)
            Label(shortNum(Int64(thread.agreeNum)), systemImage: "hand.thumbsup")
                .frame(maxWidth: .infinity)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// 帖子列表（发现页/吧页/搜索结果共用）。
/// 行内跳转用 `NavigationLink(value:)`——必须依赖所在栈已注册的
/// `navigationDestination(for: AppRoute.self)`，**不要**在 push 页里自建
/// 未绑定的 NavigationPath（那会导致点击完全无效）。
struct ThreadListView: View {
    let threads: [Tieba_ThreadInfo]
    var isLoadingMore: Bool = false
    /// 是否在末尾展示"加载更多"（由外部 `onLoadMore` 驱动）
    var onLoadMore: (() async -> Void)?
    /// 不感兴趣：tid → 理由列表（推荐流传入，其他页缺省）
    var dislikeProvider: ((Int64) -> [Tieba_DislikeReason])?
    var onDislike: ((Tieba_ThreadInfo) -> Void)?
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var blocker = BlockManager.shared

    /// 应用屏蔽（对应 Android ThreadInfo.shouldBlock + hideBlockedContent）
    /// + 屏蔽视频帖开关（Android 不看视频贴）
    private var visibleThreads: [Tieba_ThreadInfo] {
        var list = threads
        if prefs.blockVideo {
            list = list.filter { !$0.isVideo }
        }
        if !blocker.blocks.isEmpty {
            let filtered = list.filter { t in
                !blocker.shouldBlockThread(title: t.title, abstract: t.abstractText,
                                           authorId: t.author.id, authorName: t.author.name)
            }
            list = prefs.hideBlockedContent ? filtered : list
        }
        return list
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(visibleThreads, id: \.tid) { t in
                NavigationLink(value: AppRoute.thread(id: t.tid, title: t.title,
                                                      forumId: t.forumID)) {
                    FeedCard(thread: t,
                             dislikeReasons: dislikeProvider?(t.tid) ?? [],
                             onDislike: onDislike != nil ? { onDislike?(t) } : nil)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    // 记录浏览历史（对齐 Android HistoryUtil.recordThread）
                    HistoryStore.record(type: 2, id: "\(t.tid)",
                                        title: t.title.isEmpty ? t.abstractText : t.title,
                                        subtitle: t.forumName, avatar: t.author.portrait)
                })
                Divider().padding(.leading, 16)
            }
            if let onLoadMore {
                LoadMoreFooter(action: onLoadMore)
            }
        }
    }
}

/// 底部"加载更多"：进入可视区域即触发一次加载
struct LoadMoreFooter: View {
    let action: () async -> Void
    @State private var triggered = false

    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Text("加载中…").font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 16)
        .task {
            guard !triggered else { return }
            triggered = true
            await action()
        }
    }
}
