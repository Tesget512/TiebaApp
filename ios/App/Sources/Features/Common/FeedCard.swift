import SwiftUI

/// 网络图片：AsyncImage 封装 + 失败占位（对应 Android NetworkImage 的简化版）
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                Image(systemName: "photo").foregroundStyle(.secondary)
            default:
                Color(.systemGray5)
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
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if thread.isNoTitle != 1 && !thread.title.isEmpty {
                    Text((thread.isGood == 1 ? "[精] " : "") + thread.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                if !thread.abstractText.isEmpty {
                    Text(thread.abstractText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
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
            if let thumb = thread.mediaURLs.first {
                RemoteImage(url: thumb)
                    .frame(width: 108, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let vThumb = thread.videoThumbnailURL {
                RemoteImage(url: vThumb)
                    .frame(width: 108, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
            }
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

/// 帖子列表（发现页/吧页/搜索结果共用）
struct ThreadListView: View {
    let threads: [Tieba_ThreadInfo]
    var isLoadingMore: Bool = false
    var onOpenThread: (Tieba_ThreadInfo) -> Void
    /// 是否在末尾展示"加载更多"（由外部 `onLoadMore` 驱动）
    var onLoadMore: (() async -> Void)?

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(threads, id: \.tid) { t in
                Button { onOpenThread(t) } label: {
                    FeedCard(thread: t)
                }
                .buttonStyle(.plain)
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
