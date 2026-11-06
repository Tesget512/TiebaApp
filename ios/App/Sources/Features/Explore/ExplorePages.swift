import SwiftUI

// MARK: - 热榜页（对应 Android `HotPage`：/c/f/forum/hotThreadList?cmd=309661）

struct HotPage: View {
    @State private var threads: [Tieba_ThreadInfo] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && threads.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, threads.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "flame",
                                    description: err)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(threads.enumerated()), id: \.element.tid) { idx, t in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(idx + 1)")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(idx < 3 ? Color.red : Color.secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(t.title.isEmpty ? t.abstractText : t.title)
                                            .font(.subheadline)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        HStack(spacing: 8) {
                                            if !t.forumName.isEmpty {
                                                Text(t.forumName).font(.caption2).foregroundStyle(.blue)
                                            }
                                            Label(shortNum(Int64(t.agreeNum)), systemImage: "hand.thumbsup")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    // 封面固定右侧（对齐 Android 热榜卡片）
                                    if let cover = t.mediaURLs.first ?? t.videoThumbnailURL {
                                        RemoteImage(url: cover)
                                            .frame(width: 84, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    path.append(AppRoute.thread(id: t.tid, title: t.title, forumId: t.forumID))
                                }
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("热榜")
            .task { if threads.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await TiebaExtraEndpoints.hotThreadList(client: .shared)
            threads = data.threadInfo
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 关注动态页（对应 Android `ConcernPage`：/c/f/concern/userlike?cmd=309474）

struct ConcernPage: View {
    @State private var threads: [Tieba_ThreadInfo] = []
    @State private var pageTag = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var errorText: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && threads.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, threads.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "person.2",
                                    description: err)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ThreadListView(threads: threads, isLoadingMore: isLoadingMore) { t in
                                path.append(AppRoute.thread(id: t.tid, title: t.title, forumId: t.forumID))
                            } onLoadMore: {
                                await loadMore()
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("关注动态")
            .task { if threads.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await TiebaExtraEndpoints.userLike(client: .shared,
                                                              loadType: 1)
            threads = data.threadInfo.map(\.threadList)
            pageTag = data.pageTag
            hasMore = !data.threadInfo.isEmpty
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore, !pageTag.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let data = try await TiebaExtraEndpoints.userLike(client: .shared,
                                                              pageTag: pageTag, loadType: 2)
            threads += data.threadInfo.map(\.threadList)
            pageTag = data.pageTag
            hasMore = !data.threadInfo.isEmpty
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 进吧页（对应 Android `HomePage`：关注吧 + 浏览过的吧 + 推荐）

struct HomeFeedPage: View {
    @State private var likeForums: [Tieba_ForumRecommend_LikeForum] = []
    @State private var historyForums: [Tieba_HistoryForumInfo] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && likeForums.isEmpty && historyForums.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, likeForums.isEmpty && historyForums.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "list.bullet.rectangle",
                                    description: err)
                } else {
                    List {
                        if !historyForums.isEmpty {
                            Section("浏览过的吧") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(historyForums, id: \.forumID) { f in
                                            NavigationLink(value: AppRoute.forum(f.forumName)) {
                                                VStack(spacing: 6) {
                                                    RemoteImage(url: URL(string: f.avatar))
                                                        .frame(width: 56, height: 56)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                                    Text(f.forumName)
                                                        .font(.caption2)
                                                        .lineLimit(1)
                                                        .frame(width: 60)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        Section("关注的吧") {
                            if likeForums.isEmpty {
                                Text("暂无关注的吧，去搜索页发现感兴趣的贴吧吧")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            ForEach(likeForums, id: \.forumID) { f in
                                NavigationLink(value: AppRoute.forum(f.forumName)) {
                                    HStack(spacing: 12) {
                                        RemoteImage(url: URL(string: f.avatar))
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay {
                                                Image(systemName: "b.circle.fill")
                                                    .foregroundStyle(.blue)
                                                    .opacity(f.avatar.isEmpty ? 1 : 0)
                                            }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(f.forumName).font(.subheadline.weight(.medium))
                                            if !f.content.isEmpty {
                                                Text(f.content).font(.caption)
                                                    .foregroundStyle(.secondary).lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        if f.isSign != 0 {
                                            Text("已签")
                                                .font(.caption2).foregroundStyle(.green)
                                        } else {
                                            Text("\(f.levelID)级")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("进吧")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.search) {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .task { if likeForums.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // 浏览过的吧（需登录，未登录时静默为空）
        if let hist = try? await TiebaExtraEndpoints.historyForum(client: .shared) {
            historyForums = hist.historyForum
        }
        // 关注吧（签名通道）
        do {
            let data = try await TiebaExtraEndpoints.forumRecommend(client: .shared)
            likeForums = data.likeForum
            errorText = likeForums.isEmpty && historyForums.isEmpty
                ? "登录后可查看关注的吧（当前未登录）" : nil
        } catch {
            if historyForums.isEmpty { errorText = error.localizedDescription }
        }
    }
}

// MARK: - 收藏页（对应 Android `ThreadStorePage`：/c/f/post/threadstore）

struct ThreadStorePage: View {
    @State private var items: [ThreadStoreResponse.StoreInfo] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, items.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "star",
                                    description: err)
                } else if items.isEmpty {
                    UnavailableView(title: "还没有收藏", systemImage: "star",
                                    description: "在帖子页右上角可收藏喜欢的帖子")
                } else {
                    List {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            NavigationLink(value: AppRoute.thread(
                                id: item.tid?.value ?? 0,
                                title: item.title ?? "",
                                forumId: item.forum_id?.value ?? 0)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title ?? "").font(.subheadline).lineLimit(2)
                                    HStack(spacing: 8) {
                                        if let fname = item.fname, !fname.isEmpty {
                                            Text(fname).font(.caption2).foregroundStyle(.blue)
                                        }
                                        if let n = item.reply_num?.value {
                                            Text("回复 \(n)").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete { idx in
                            Task { await remove(at: idx) }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("我的收藏")
            .task { if items.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await TiebaWriteEndpoints.threadStore()
            items = resp.thread_store ?? []
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func remove(at offsets: IndexSet) async {
        for i in offsets {
            guard let tid = items[i].tid?.value else { continue }
            try? await TiebaWriteEndpoints.removeStore(threadId: tid)
        }
        items.remove(atOffsets: offsets)
    }
}

// MARK: - 浏览历史页（对应 Android `HistoryPage`，本地持久化）

struct HistoryPageView: View {
    @State private var items: [HistoryStore.Item] = []
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if items.isEmpty {
                    UnavailableView(title: "暂无浏览记录", systemImage: "clock.arrow.circlepath",
                                    description: "浏览过的帖子会显示在这里")
                } else {
                    List {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            row(item)
                        }
                        .onDelete { offsets in
                            for i in offsets { HistoryStore.remove(type: items[i].type, id: items[i].id) }
                            items.remove(atOffsets: offsets)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("浏览历史")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) {
                        HistoryStore.clear()
                        items = []
                    }
                }
            }
            .onAppear { items = HistoryStore.all() }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    @ViewBuilder
    private func row(_ item: HistoryStore.Item) -> some View {
        if item.type == 1 {
            NavigationLink(value: AppRoute.forum(item.id)) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? item.id : item.title).font(.subheadline)
                        Text(relativeTime(fromUnixSeconds: Int64(item.timestamp)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "b.circle").foregroundStyle(.blue)
                }
            }
        } else {
            NavigationLink(value: AppRoute.thread(id: Int64(item.id) ?? 0,
                                                  title: item.title, forumId: 0)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.isEmpty ? item.id : item.title).font(.subheadline).lineLimit(2)
                    HStack {
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle).font(.caption2).foregroundStyle(.blue)
                        }
                        Text(relativeTime(fromUnixSeconds: Int64(item.timestamp)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - 用户帖子列表页（对应 Android `UserPostListPage`：userpost?cmd=303002）

struct UserPostListPage: View {
    let uid: Int64
    let name: String
    let isThread: Bool

    @State private var posts: [Tieba_PostInfoList] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var page = 1
    @State private var hasMore = true
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && posts.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, posts.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "doc.text",
                                    description: err)
                } else {
                    List {
                        ForEach(Array(posts.enumerated()), id: \.offset) { _, post in
                            NavigationLink(value: AppRoute.thread(
                                id: Int64(bitPattern: post.threadID),
                                title: post.title,
                                forumId: Int64(bitPattern: post.forumID))) {
                                VStack(alignment: .leading, spacing: 4) {
                                    if post.isThread != 0, !post.title.isEmpty {
                                        Text(post.title).font(.subheadline).lineLimit(2)
                                    }
                                    if !post.contentThread.isEmpty {
                                        Text(post.contentThread).font(.caption)
                                            .foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    HStack(spacing: 8) {
                                        if !post.forumName.isEmpty {
                                            Text(post.forumName).font(.caption2).foregroundStyle(.blue)
                                        }
                                        Text(relativeTime(fromUnixSeconds: Int64(post.createTime)))
                                            .font(.caption2).foregroundStyle(.secondary)
                                        Text("回复 \(post.replyNum)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        if hasMore {
                            LoadMoreFooter { await loadMore() }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await load() }
                }
            }
            .navigationTitle(isThread ? "\(name)的主题贴" : "\(name)的回复")
            .navigationBarTitleDisplayMode(.inline)
            .task { if posts.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await TiebaExtraEndpoints.userPost(client: .shared, uid: uid,
                                                              page: 1, isThread: isThread)
            posts = data.postList
            page = 1
            hasMore = !data.postList.isEmpty
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = page + 1
            let data = try await TiebaExtraEndpoints.userPost(client: .shared, uid: uid,
                                                              page: next, isThread: isThread)
            posts += data.postList
            page = next
            hasMore = !data.postList.isEmpty
        } catch {
            errorText = error.localizedDescription
        }
    }
}
