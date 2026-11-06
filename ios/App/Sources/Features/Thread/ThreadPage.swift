import SwiftUI

/// PbContent 富文本渲染（对应 Android PbContentRender 的 iOS 版）：
/// type 0/9/27/35/40=文字、1=链接、2=表情(显示 [表情])、3/20=图片、4=@用户、5=视频、10=语音
struct PbContentView: View {
    let contents: [Tieba_PbContent]
    var fontSize: Font = .subheadline

    /// 渲染项（构造时把连续文本合并，对齐 Android appendText 逻辑）
    private enum Item {
        case text(String)
        case image(url: URL?, aspect: CGFloat)
        case link(String)
        case mention(String)
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
                result.append(.image(url: picURL(c), aspect: bsize(c)))
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
                case .image(let url, let aspect):
                    RemoteImage(url: url)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(aspect, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .link(let text):
                    Text(text).font(fontSize).foregroundStyle(.blue)
                case .mention(let text):
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
    private func picURL(_ c: Tieba_PbContent) -> URL? {
        let candidates = [c.originSrc, c.bigCdnSrc, c.bigSrc, c.cdnSrc, c.src]
        let s = candidates.first { !$0.isEmpty } ?? ""
        return s.isEmpty ? nil : URL(string: s)
    }

    private func bsize(_ c: Tieba_PbContent) -> CGFloat {
        let parts = c.bsize.split(separator: ",")
        guard parts.count == 2,
              let w = Double(parts[0]), w > 0,
              let h = Double(parts[1]), h > 0 else { return 4/3 }
        return CGFloat(w / h)
    }
}

/// 帖子页（对应 Android ThreadPage）：楼主贴 + 楼层列表
struct ThreadPage: View {
    let threadID: Int64
    let title: String

    @State private var posts: [Tieba_Post] = []
    @State private var forumName = ""
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var page = 1

    var body: some View {
        Group {
            if isLoading && posts.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText, posts.isEmpty {
                UnavailableView(title: "加载失败", systemImage: "wifi.exclamationmark", description: err)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(posts.enumerated()), id: \.offset) { idx, post in
                            postCard(post, floor: idx + 1)
                            Divider()
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle(title.isEmpty ? "帖子" : title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if posts.isEmpty { await load() } }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await TiebaEndpoints.pbPage(client: .shared, threadId: threadID, page: 1, rn: 30)
            posts = data.postList
            forumName = data.forum.name
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    @ViewBuilder
    private func postCard(_ post: Tieba_Post, floor: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(floor)楼")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if post.time > 0 {
                    Text(Date(timeIntervalSince1970: TimeInterval(post.time)), style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            PbContentView(contents: post.content)
            if post.subPostNumber > 0 {
                Text("共 \(post.subPostNumber) 条回复")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(16)
    }
}
