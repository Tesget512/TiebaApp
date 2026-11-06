import SwiftUI

/// AsyncImage 封装：失败时占位（对应 Android NetworkImage 的简化版）
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentResizeMode = .fill

    enum ContentResizeMode { case fill, fit }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
            case .failure:
                Image(systemName: "photo").foregroundStyle(.secondary)
            default:
                Color(.systemGray5)
            }
        }
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
    }

    private var header: some View {
        HStack(spacing: 8) {
            RemoteImage(url: thread.authorAvatarURL)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.displayAuthorName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
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
                }
                if !thread.abstractText.isEmpty {
                    Text(thread.abstractText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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

/// 帖子列表（发现页/吧页共用）
struct ThreadListView: View {
    let threads: [Tieba_ThreadInfo]
    var onOpenThread: (Tieba_ThreadInfo) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(threads, id: \.threadID) { t in
                Button { onOpenThread(t) } label: {
                    FeedCard(thread: t)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
            }
        }
    }
}
