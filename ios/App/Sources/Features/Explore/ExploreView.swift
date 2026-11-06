import SwiftUI

/// 发现页：个性化推荐（对应 Android PersonalizedPage）
struct ExploreView: View {
    @State private var threads: [Tieba_ThreadInfo] = []
    @State private var isLoading = false
    @State private var page = 1
    @State private var errorText: String?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if isLoading && threads.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, threads.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "wifi.exclamationmark", description: err)
                } else {
                    ScrollView {
                        ThreadListView(threads: threads) { t in
                            navigationPath.append(ThreadRoute(threadID: t.threadID, title: t.title))
                        }
                    }
                    .refreshable { await load(refresh: true) }
                }
            }
            .navigationTitle("发现")
            .task { if threads.isEmpty { await load(refresh: true) } }
            .navigationDestination(for: ThreadRoute.self) { route in
                ThreadPage(threadID: route.threadID, title: route.title)
            }
            .navigationDestination(for: ForumRoute.self) { route in
                ForumPage(forumName: route.forumName)
            }
        }
    }

    private func load(refresh: Bool) async {
        if refresh { page = 1 } else { page += 1 }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await TiebaEndpoints.personalized(
                client: .shared, loadType: refresh ? 1 : 2, page: page)
            let list = resp.data.threadList.filter { $0.alaInfo.liveID == 0 } // 过滤直播帖（对齐 Android）
            threads = refresh ? list : threads + list
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct ThreadRoute: Hashable {
    let threadID: Int64
    let title: String
}

struct ForumRoute: Hashable {
    let forumName: String
}
