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
                                        if t.title.isEmpty {
                                            EmoticonText(text: t.abstractText, font: .subheadline,
                                                         pointSize: 15, color: .primary, lineLimit: 2)
                                        } else {
                                            Text(t.title)
                                                .font(.subheadline)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
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
                            ThreadListView(threads: threads, isLoadingMore: isLoadingMore,
                                           onLoadMore: { await loadMore() })
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
    @State private var toast: String?
    @ObservedObject private var prefs = AppPreferences.shared

    /// Android HomePage 排序：0 热度 / 1 发帖时间(按吧ID代理) / 2 等级 / 3 名称；
    /// 自定义置顶优先且保持置顶先后顺序（Published 驱动即时重排）
    private var sortedForums: [Tieba_ForumRecommend_LikeForum] {
        var list = likeForums
        switch prefs.homeForumSort {
        case 1: list.sort { ($0.forumID, $1.forumName) > ($1.forumID, $0.forumName) }
        case 2: list.sort { ($0.levelID, $1.forumName) > ($1.levelID, $0.forumName) }
        case 3: list.sort { $0.forumName < $1.forumName }
        default: break // 热度：保持服务端序
        }
        let pinned = prefs.pinnedForums
        var pinnedList: [Tieba_ForumRecommend_LikeForum] = []
        var rest: [Tieba_ForumRecommend_LikeForum] = []
        for f in list {
            if pinned.contains(f.forumName) { pinnedList.append(f) } else { rest.append(f) }
        }
        pinnedList.sort {
            (pinned.firstIndex(of: $0.forumName) ?? .max)
                < (pinned.firstIndex(of: $1.forumName) ?? .max)
        }
        return pinnedList + rest
    }

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
                        if prefs.showRecentForums, !historyForums.isEmpty {
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
                            if prefs.forumTwoColumn {
                                // 两列卡片（用户要求：开关切换两列显示）
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                                    GridItem(.flexible())], spacing: 10) {
                                    ForEach(sortedForums, id: \.forumID) { f in
                                        forumCard(f)
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .listRowBackground(Color.clear)
                            } else {
                                ForEach(sortedForums, id: \.forumID) { f in
                                    forumRow(f)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await load() }
                    // tab 根页内容让位悬浮底栏（RootView ZStack 覆盖，见 RootView 注释）
                    .tabRootScrollBottomInset()
                }
            }
            .navigationTitle("进吧")
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 16)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            self.toast = nil
                        }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.search) {
                        Image(systemName: "magnifyingglass")
                    }
                    Menu {
                        // 排序方式（Android HomePage 菜单）
                        Picker("排序方式", selection: $prefs.homeForumSort) {
                            Text("按热度").tag(0)
                            Text("按发帖时间").tag(1)
                            Text("按等级").tag(2)
                            Text("按名称").tag(3)
                        }
                        Toggle("两列显示", isOn: $prefs.forumTwoColumn)
                        Toggle("显示最近访问吧", isOn: $prefs.showRecentForums)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task { if likeForums.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    /// 吧行（单列）：行内跳转用 NavigationLink(value:)——依赖所在栈已注册的
    /// navigationDestination（P17 教训：页面自建 NavigationPath append 是死变更）
    private func forumRow(_ f: Tieba_ForumRecommend_LikeForum) -> some View {
        NavigationLink(value: AppRoute.forum(f.forumName)) {
            HStack(spacing: 12) {
                forumAvatar(f, side: 44, radius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if prefs.isPinnedForum(f.forumName) {
                            Image(systemName: "pin.fill")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                        Text(f.forumName).font(.subheadline.weight(.medium))
                    }
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
        .contextMenu { forumContextMenu(f) }
    }

    /// 吧卡片（两列）：紧凑版——头像 + 吧名 + 等级（用户反馈：砍掉热帖行/箭头，优化空间）
    private func forumCard(_ f: Tieba_ForumRecommend_LikeForum) -> some View {
        Button {
            path.append(AppRoute.forum(f.forumName))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                forumAvatar(f, side: 48, radius: 10)
                HStack(spacing: 4) {
                    if prefs.isPinnedForum(f.forumName) {
                        Image(systemName: "pin.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    Text(f.forumName)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                }
                if f.isSign != 0 {
                    Text("已签").font(.caption2).foregroundStyle(.green)
                } else {
                    Text("\(f.levelID)级").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { forumContextMenu(f) }
    }

    private func forumAvatar(_ f: Tieba_ForumRecommend_LikeForum,
                             side: CGFloat, radius: CGFloat) -> some View {
        RemoteImage(url: URL(string: f.avatar))
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                Image(systemName: "b.circle.fill")
                    .foregroundStyle(.blue)
                    .opacity(f.avatar.isEmpty ? 1 : 0)
            }
    }

    /// 吧行/卡片共用长按菜单（置顶即时重排）
    private func forumContextMenu(_ f: Tieba_ForumRecommend_LikeForum) -> some View {
        Group {
            Button {
                prefs.togglePinnedForum(f.forumName)
                toast = prefs.isPinnedForum(f.forumName) ? "已置顶 \(f.forumName)" : "已取消置顶"
            } label: {
                Label(prefs.isPinnedForum(f.forumName) ? "取消置顶" : "置顶",
                      systemImage: "pin")
            }
            Button {
                UIPasteboard.general.string = f.forumName
                toast = "吧名已复制"
            } label: {
                Label("复制吧名", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                Task { await unfollow(f) }
            } label: {
                Label("取消关注", systemImage: "person.minus")
            }
        }
    }

    /// 取关（确认由 contextMenu destructive 承担；成功后本地移除）
    private func unfollow(_ f: Tieba_ForumRecommend_LikeForum) async {
        guard AppPreferences.shared.safeMode == false else {
            toast = "安全模式已开启，写操作被拦截"
            return
        }
        do {
            _ = try await TiebaWriteEndpoints.unlikeForum(forumId: f.forumID,
                                                          forumName: f.forumName)
            likeForums.removeAll { $0.forumID == f.forumID }
            toast = "已取消关注 \(f.forumName)"
        } catch {
            toast = error.localizedDescription
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
                            // 收藏贴自动只看楼主/倒序（Android HabitSettings）
                            NavigationLink(value: AppRoute.thread(
                                id: Int64(item.thread_id?.value ?? "") ?? 0,
                                title: item.title ?? "",
                                forumId: 0,
                                onlyLz: AppPreferences.shared.storeAutoLz,
                                desc: AppPreferences.shared.storeAutoDesc)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        if item.is_deleted?.value == "1" {
                                            Text("已删除").font(.caption2).foregroundStyle(.red)
                                        }
                                        Text(item.title ?? "").font(.subheadline).lineLimit(2)
                                    }
                                    HStack(spacing: 8) {
                                        if let fname = item.forum_name, !fname.isEmpty {
                                            Text(fname).font(.caption2).foregroundStyle(.blue)
                                        }
                                        if let last = item.last_time?.value, !last.isEmpty {
                                            Text(last).font(.caption2).foregroundStyle(.secondary)
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
            .bottomBarHidden()
            .task { if items.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await TiebaWriteEndpoints.threadStore()
            items = resp.store_thread ?? []
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func remove(at offsets: IndexSet) async {
        for i in offsets {
            guard let tid = Int64(items[i].thread_id?.value ?? "") else { continue }
            try? await TiebaWriteEndpoints.removeStore(threadId: tid)
        }
        items.remove(atOffsets: offsets)
    }
}

// MARK: - 浏览历史页（对应 Android `HistoryPage`，本地持久化）

struct HistoryPageView: View {
    /// 双 tab（Android HistoryPage：贴子记录 / 经过贴吧）
    @State private var tab: Tab = .thread
    @State private var items: [HistoryStore.Item] = []
    @State private var path = NavigationPath()

    enum Tab: String, CaseIterable { case thread = "贴子记录"; case forum = "经过贴吧" }

    /// 按「今天 / 更早」分组（对齐 Android 分组头）
    private var grouped: [(header: String, items: [HistoryStore.Item])] {
        let filtered = items.filter { tab == .thread ? $0.type == 2 : $0.type == 1 }
        let cal = Calendar.current
        var today: [HistoryStore.Item] = []
        var earlier: [HistoryStore.Item] = []
        for item in filtered {
            if cal.isDateInToday(Date(timeIntervalSince1970: item.timestamp)) {
                today.append(item)
            } else {
                earlier.append(item)
            }
        }
        var groups: [(String, [HistoryStore.Item])] = []
        if !today.isEmpty { groups.append(("今天", today)) }
        if !earlier.isEmpty { groups.append(("更早", earlier)) }
        return groups
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if items.isEmpty {
                    UnavailableView(title: "暂无浏览记录", systemImage: "clock.arrow.circlepath",
                                    description: "浏览过的帖子与贴吧会显示在这里")
                } else {
                    VStack(spacing: 0) {
                        Picker("记录", selection: $tab) {
                            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        if grouped.isEmpty {
                            UnavailableView(title: "暂无记录", systemImage: "clock.arrow.circlepath")
                        } else {
                            List {
                                ForEach(grouped, id: \.header) { group in
                                    Section(group.header) {
                                        ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                                            row(item)
                                                .contextMenu {
                                                    Button(role: .destructive) {
                                                        HistoryStore.remove(type: item.type, id: item.id)
                                                        items = HistoryStore.all()
                                                    } label: {
                                                        Label("删除", systemImage: "trash")
                                                    }
                                                }
                                        }
                                        .onDelete { offsets in
                                            // 按当前 tab 的扁平索引删除
                                            let flat = items.filter { tab == .thread ? $0.type == 2 : $0.type == 1 }
                                            for i in offsets {
                                                let item = flat[i]
                                                HistoryStore.remove(type: item.type, id: item.id)
                                            }
                                            items = HistoryStore.all()
                                        }
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
                        }
                    }
                }
            }
            .navigationTitle("浏览历史")
            .bottomBarHidden()
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

struct UserPostListPage: View {
    let uid: Int64
    let name: String
    let isThread: Bool

    @State private var posts: [Tieba_PostInfoList] = []
    /// 官方回帖接口缺陷（is_thread=0 恒空，2026-09 起）→ eztb 只读镜像（Android 同策略）
    @State private var replies: [UserReplyItem] = []
    @State private var usingMirror = false
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var page = 1
    @State private var hasMore = true
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && posts.isEmpty && replies.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, posts.isEmpty && replies.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "doc.text",
                                    description: err)
                } else if usingMirror {
                    mirrorList
                } else {
                    officialList
                }
            }
            .navigationTitle(isThread ? "\(name)的主题贴" : "\(name)的回复")
            .navigationBarTitleDisplayMode(.inline)
            .bottomBarHidden()
            .task { if posts.isEmpty && replies.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    /// 主题贴/官方回帖行
    private var officialList: some View {
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

    /// 镜像回帖行（Android UserPostPage 结构：回复内容 + 时间 + 原帖标题卡片）
    private var mirrorList: some View {
        List {
            ForEach(Array(replies.enumerated()), id: \.offset) { _, reply in
                NavigationLink(value: AppRoute.thread(
                    id: Int64(reply.threadId ?? "") ?? 0,
                    title: reply.title ?? "",
                    forumId: reply.forumId ?? 0)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reply.content ?? "")
                            .font(.subheadline)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if let fname = reply.forumName, !fname.isEmpty {
                                Text(fname).font(.caption2).foregroundStyle(.blue)
                            }
                            Text(relativeTime(fromUnixSeconds: reply.createTime ?? 0))
                                .font(.caption2).foregroundStyle(.secondary)
                            if let to = reply.replyTo, !to.isEmpty {
                                Text("回复 @\(to)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if let t = reply.title, !t.isEmpty {
                            // 原帖标题卡片（Android floorCard 样式）
                            Text("原帖：\(t)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 6))
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if isThread {
            do {
                let data = try await TiebaExtraEndpoints.userPost(client: .shared, uid: uid,
                                                                  page: 1, isThread: true)
                posts = data.postList
                page = 1
                hasMore = !data.postList.isEmpty
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
            return
        }
        // 回帖：官方优先，空/失败时降级镜像（对齐 Android UserPostViewModel 降级策略：
        // 由「数据为空」触发而非异常触发；第 1 页镜像失败才显示错误页）
        var officialEmpty = false
        do {
            let data = try await TiebaExtraEndpoints.userPost(client: .shared, uid: uid,
                                                              page: 1, isThread: false)
            if data.postList.isEmpty {
                officialEmpty = true
            } else {
                posts = data.postList
                hasMore = true
                errorText = nil
                return
            }
        } catch {
            officialEmpty = true
        }
        if officialEmpty {
            do {
                replies = try await UserReplyMirror.fetch(uid: uid, page: 1)
                usingMirror = true
                page = 1
                hasMore = !replies.isEmpty
                errorText = nil
            } catch {
                errorText = "回帖数据源不可用：\(error.localizedDescription)"
            }
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        if usingMirror {
            // 镜像加载更多失败静默停止（对齐 Android：page>1 失败返回空）
            let next = page + 1
            guard let more = try? await UserReplyMirror.fetch(uid: uid, page: next),
                  !more.isEmpty else {
                hasMore = false
                return
            }
            replies += more
            page = next
        } else {
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
}
