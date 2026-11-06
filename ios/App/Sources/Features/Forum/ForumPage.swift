import SwiftUI

/// 吧页（对应 Android ForumPage）：吧信息 + 帖子列表（最新/精华）
struct ForumPage: View {
    let forumName: String

    @State private var forumAvatar = ""
    @State private var threads: [Tieba_ThreadInfo] = []
    @State private var isGood = false
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        VStack(spacing: 0) {
            // 最新 / 精华 tab
            Picker("排序", selection: $isGood) {
                Text("最新").tag(false)
                Text("精华").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

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
                .refreshable { await load() }
            }
        }
        .navigationTitle(forumName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ThreadRoute.self) { route in
            ThreadPage(threadID: route.threadID, title: route.title)
        }
        .task { if threads.isEmpty { await load() } }
        .onChange(of: isGood) { _ in Task { await load() } }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await TiebaEndpoints.frsPage(
                client: .shared, forumName: forumName, page: 1,
                sortType: isGood ? 0 : 2, isGood: isGood)
            threads = data.threadList.filter { $0.alaInfo.liveID == 0 }
            forumAvatar = data.forum.avatar
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
