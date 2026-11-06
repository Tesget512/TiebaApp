import SwiftUI

/// 发现页：个性化推荐（对应 Android `PersonalizedPage`）
struct ExploreView: View {
    @State private var threads: [Tieba_ThreadInfo] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var page = 1
    @State private var hasMore = true
    @State private var errorText: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && threads.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, threads.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "wifi.exclamationmark", description: err)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ThreadListView(threads: threads, isLoadingMore: isLoadingMore) { t in
                                openThread(t)
                            } onLoadMore: {
                                await loadMore()
                            }
                        }
                    }
                    .refreshable { await load(refresh: true) }
                }
            }
            .navigationTitle("发现")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button { path.append(AppRoute.hot) } label: {
                            Label("热榜", systemImage: "flame")
                        }
                        Button { path.append(AppRoute.concern) } label: {
                            Label("关注动态", systemImage: "person.2")
                        }
                        Button { path.append(AppRoute.homeFeed) } label: {
                            Label("进吧", systemImage: "list.bullet.rectangle")
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
            .task { if threads.isEmpty { await load(refresh: true) } }
            .navigationDestination(for: AppRoute.self) { route in
                RouteView(route: route)
            }
        }
    }

    private func openThread(_ t: Tieba_ThreadInfo) {
        HistoryStore.record(type: 2, id: "\(t.tid)", title: t.title.isEmpty ? t.abstractText : t.title,
                            subtitle: t.forumName, avatar: t.author.portrait)
        path.append(AppRoute.thread(id: t.tid, title: t.title, forumId: t.forumID))
    }

    private func load(refresh: Bool) async {
        if refresh { page = 1 } else { page += 1 }
        if refresh { isLoading = true }
        defer { isLoading = false; isLoadingMore = false }
        do {
            let data = try await TiebaEndpoints.personalized(
                client: .shared, loadType: refresh ? 1 : 2, page: page)
            let list = data.threadList.filter { !$0.isLive } // 过滤直播帖（对齐 Android）
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

/// 统一的路由分发（避免每个页面重复 navigationDestination）
struct RouteView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .forum(let name):
            ForumPage(forumName: name)
        case .thread(let id, let title, let forumId):
            ThreadPage(threadID: id, title: title, forumId: forumId)
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
        }
    }
}
