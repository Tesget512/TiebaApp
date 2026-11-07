import SwiftUI

/// 发现页（对应 Android `ExplorePage`）：子 Tab 个性化推荐 / 关注动态 / 找人；
/// toolbar 右上角放大镜 → 全局搜索（Android 顶部 search icon）。
struct ExploreView: View {
    @State private var subTab: SubTab = .recommend
    @State private var path = NavigationPath()

    enum SubTab: String, CaseIterable, Hashable {
        case recommend = "推荐"
        case concern = "关注动态"
        case findUser = "找人"
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                switch subTab {
                case .recommend: RecommendFeedView(path: $path)
                case .concern: ConcernFeedView(path: $path)
                case .findUser: FindUserView(path: $path)
                }
            }
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.inline)
            // 频道选择器入导航栏 principal 位（原内嵌固定条滚动时形成不透明遮挡带）
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("频道", selection: $subTab) {
                        ForEach(SubTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        path.append(AppRoute.search)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    Menu {
                        Button { path.append(AppRoute.hot) } label: {
                            Label("热榜", systemImage: "flame")
                        }
                        Button { path.append(AppRoute.topicList) } label: {
                            Label("热议话题", systemImage: "flame.fill")
                        }
                        Button { path.append(AppRoute.store) } label: {
                            Label("我的收藏", systemImage: "star")
                        }
                        Button { path.append(AppRoute.history) } label: {
                            Label("浏览历史", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                RouteView(route: route)
            }
        }
    }
}

// MARK: - 推荐流（原 ExploreView 的个性化推荐，Android PersonalizedPage）

private struct RecommendFeedView: View {
    @Binding var path: NavigationPath
    @State private var threads: [Tieba_ThreadInfo] = []
    /// 不感兴趣理由（tid → dislikeResource，Android ThreadPersonalized 1:1）
    @State private var dislikeResources: [Int64: [Tieba_DislikeReason]] = [:]
    @State private var followedForumIds: Set<Int64> = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var page = 1
    @State private var hasMore = true
    @State private var errorText: String?
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        Group {
            if isLoading && threads.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText, threads.isEmpty {
                UnavailableView(title: "加载失败", systemImage: "wifi.exclamationmark",
                                description: err, retry: { Task { await load(refresh: true) } })
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let err = errorText, !threads.isEmpty {
                            // 刷新失败但已有内容：顶部横条提示（下次刷新成功自动消失）
                            Text("刷新失败：\(err)")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(6)
                                .background(Color(.systemGray6))
                        }
                        ThreadListView(threads: visibleThreads, isLoadingMore: isLoadingMore,
                                       onLoadMore: { await loadMore() },
                                       dislikeProvider: { tid in
                                           dislikeResources[tid] ?? []
                                       },
                                       onDislike: { t in
                                           threads.removeAll { $0.tid == t.tid }
                                           dislikeResources[t.tid] = nil
                                       })
                    }
                }
                .refreshable { await load(refresh: true) }
                // tab 根页内容让位悬浮底栏
                .tabRootScrollBottomInset()
            }
        }
        .task {
            if threads.isEmpty { await load(refresh: true) }
            if prefs.onlyRecommendFollowed, followedForumIds.isEmpty { await loadFollowedForums() }
        }
    }

    /// 只推荐已关注的吧开关生效的可见列表
    private var visibleThreads: [Tieba_ThreadInfo] {
        guard prefs.onlyRecommendFollowed, !followedForumIds.isEmpty else { return threads }
        return threads.filter { followedForumIds.contains($0.forumID) }
    }

    /// 用户关注的吧列表（getforumlist）
    private func loadFollowedForums() async {
        if let forums = try? await TiebaExtraEndpoints.historyForum(client: .shared) {
            followedForumIds = Set(forums.historyForum.map(\.forumID))
        }
    }

    private func load(refresh: Bool) async {
        if refresh { page = 1 } else { page += 1 }
        if refresh { isLoading = true }
        defer { isLoading = false; isLoadingMore = false }
        do {
            let data = try await TiebaEndpoints.personalized(
                client: .shared, loadType: refresh ? 1 : 2, page: page)
            let list = data.threadList.filter { !$0.isLive } // 过滤直播帖（对齐 Android）
            // 不感兴趣理由（Android threadPersonalized join by tid）
            if refresh { dislikeResources = [:] }
            for p in data.threadPersonalized where !p.dislikeResource.isEmpty {
                dislikeResources[Int64(bitPattern: p.tid)] = p.dislikeResource
            }
            threads = refresh ? list : threads + list
            hasMore = !list.isEmpty
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        await load(refresh: false)
    }
}

// MARK: - 关注动态（内嵌，Android ConcernPage）

private struct ConcernFeedView: View {
    @Binding var path: NavigationPath
    @State private var threads: [Tieba_ThreadInfo] = []
    @State private var pageTag = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if isLoading && threads.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText, threads.isEmpty {
                UnavailableView(title: "加载失败", systemImage: "person.2",
                                description: appStateHint(err))
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
        .task { if threads.isEmpty { await load() } }
    }

    private func appStateHint(_ err: String) -> String {
        err.contains("logged") || err.contains("登录") ? "需要登录后查看关注动态" : err
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await TiebaExtraEndpoints.userLike(client: .shared, loadType: 1)
            threads = data.threadInfo.map(\.threadList)
            pageTag = data.pageTag
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, !pageTag.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let data = try await TiebaExtraEndpoints.userLike(client: .shared,
                                                              pageTag: pageTag, loadType: 2)
            threads += data.threadInfo.map(\.threadList)
            pageTag = data.pageTag
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 找人（Android SearchUserTabPage：UID 直达个人主页）

private struct FindUserView: View {
    @Binding var path: NavigationPath
    @State private var input = ""
    @State private var searching = false
    @State private var result: Tieba_Profile_ProfileResponseData?
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("通过 UID 找人") {
                TextField("输入用户 UID（纯数字）", text: $input)
                    .keyboardType(.numberPad)
                Button {
                    Task { await search() }
                } label: {
                    if searching {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("查找").frame(maxWidth: .infinity)
                    }
                }
                .disabled(Int64(input) == nil || searching)
            }
            if let err = errorText {
                Section { Text(err).font(.footnote).foregroundStyle(.secondary) }
            }
            if let r = result {
                Section("结果") {
                    NavigationLink(value: AppRoute.user(uid: uid)) {
                        HStack(spacing: 12) {
                            AvatarView(url: Tieba_ThreadInfo.portraitURL(r.user.portrait), size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.user.nameShow.isEmpty ? r.user.name : r.user.nameShow)
                                    .font(.subheadline.weight(.medium))
                                if !r.user.intro.isEmpty {
                                    Text(r.user.intro).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
    }

    private var uid: Int64 { Int64(input) ?? 0 }

    private func search() async {
        searching = true
        result = nil
        errorText = nil
        defer { searching = false }
        do {
            result = try await TiebaEndpoints.userProfile(
                client: .shared, uid: uid, selfUid: 0, isSelf: false)
        } catch {
            errorText = "未找到该用户：\(error.localizedDescription)"
        }
    }
}

// MARK: - 统一路由分发（避免每个页面重复 navigationDestination）

struct RouteView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .forum(let name):
            ForumPage(forumName: name)
        case .thread(let id, let title, let forumId, let onlyLz, let desc):
            ThreadPage(threadID: id, title: title, forumId: forumId,
                       initialOnlyLz: onlyLz, initialSortDesc: desc)
        case .user(let uid):
            UserProfilePage(uid: uid)
        case .hot:
            HotPage()
        case .concern:
            ConcernPage()
        case .homeFeed:
            HomeFeedPage()
        case .store:
            ThreadStorePage()
        case .history:
            HistoryPageView()
        case .userPosts(let uid, let name, let isThread):
            UserPostListPage(uid: uid, name: name, isThread: isThread)
        case .topicList:
            TopicListPage()
        case .topicDetail(let id, let name):
            TopicDetailPage(topicId: id, topicName: name)
        case .forumDetail(let id, let name):
            ForumDetailPage(forumId: id, forumName: name)
        case .analysis(let uid, let name):
            PostAnalysisPage(uid: uid, name: name)
        case .photoView(let items, let index):
            SKPhotoBrowserHost(initialItems: items, initialIndex: index)
        case .search:
            SearchPage()
        case .forumSearch(let name):
            ForumSearchPostPage(forumName: name)
        }
    }
}
