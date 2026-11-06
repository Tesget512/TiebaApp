import SwiftUI
import UIKit

/// 吧页（对应 Android `ForumPage`）：吧信息 + 帖子列表（最新/精华）+ 签到
struct ForumPage: View {
    let forumName: String

    @EnvironmentObject private var appState: AppState
    @State private var forum: Tieba_FrsPage_ForumInfo?
    @State private var threads: [Tieba_ThreadInfo] = []
    @State private var tab: ForumTab = .latest
    @State private var latestSort = 0          // 0=回复时间 1=发帖时间（Android ForumSortType）
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var page = 1
    @State private var hasMore = true
    @State private var signStatus: String?
    @State private var isSigning = false
    @State private var path = NavigationPath()
    @State private var toast: String?

    enum ForumTab: Hashable { case latest, good }

    var body: some View {
        VStack(spacing: 0) {
            Picker("排序", selection: $tab) {
                Text("最新").tag(ForumTab.latest)
                Text("精华").tag(ForumTab.good)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            content
        }
        .navigationTitle(forumName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = "https://tieba.baidu.com/f?kw=\(forumName)"
                        toast = "链接已复制"
                    } label: {
                        Label("复制链接", systemImage: "link")
                    }
                    ShareLink(item: URL(string: "https://tieba.baidu.com/f?kw=\(forumName)")!) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        self.toast = nil
                    }
            }
        }
        .task { if threads.isEmpty { await reload() } }
        .onChange(of: tab) { _ in Task { await reload() } }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && threads.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorText, threads.isEmpty {
            UnavailableView(title: "加载失败", systemImage: "wifi.exclamationmark", description: err)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    forumHeader
                    ThreadListView(threads: threads, isLoadingMore: isLoadingMore) { t in
                        path.append(AppRoute.thread(id: t.tid, title: t.title, forumId: t.forumID))
                    } onLoadMore: {
                        await loadMore()
                    }
                }
            }
            .refreshable { await reload() }
        }
    }

    @ViewBuilder
    private var forumHeader: some View {
        if let forum {
            HStack(spacing: 12) {
                AvatarView(url: URL(string: forum.avatar), size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(forum.name).font(.headline)
                    Text("关注 \(shortNum(Int64(forum.memberNum))) · 帖子 \(shortNum(Int64(forum.postNum)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                signButton(forum)
            }
            .padding(16)
            Divider()
        }
    }

    @ViewBuilder
    private func signButton(_ forum: Tieba_FrsPage_ForumInfo) -> some View {
        Button {
            Task { await sign(forum) }
        } label: {
            if isSigning {
                ProgressView()
            } else {
                Text(signStatus ?? "签到")
                    .font(.footnote.weight(.medium))
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isSigning || signStatus != nil)
    }

    private func sign(_ forum: Tieba_FrsPage_ForumInfo) async {
        guard appState.isLoggedIn else {
            errorText = "请先登录后再签到"
            return
        }
        isSigning = true
        defer { isSigning = false }
        // 签到必须带 tbs；缺失时先刷新账号（Android 的 tbs 随账号持久化）
        await appState.refreshTbsIfNeeded()
        do {
            try await TiebaWriteEndpoints.forumSign(forumName: forumName, forumId: Int64(forum.id))
            signStatus = "已签到"
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func reload() async {
        isLoading = true
        page = 1
        hasMore = true
        defer { isLoading = false }
        do {
            let data = try await TiebaEndpoints.frsPage(
                client: .shared, forumName: forumName, page: 1,
                sortType: latestSort, isGood: tab == .good,
                goodClassifyId: tab == .good ? 0 : nil)
            forum = data.forum
            threads = data.threadList.filter { !$0.isLive }
            hasMore = data.page.hasMore_p != 0
            errorText = nil
            // 记录浏览历史（type 1=吧）
            HistoryStore.record(type: 1, id: forumName, title: forumName,
                                subtitle: "", avatar: data.forum.avatar)
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
            let data = try await TiebaEndpoints.frsPage(
                client: .shared, forumName: forumName, page: next,
                sortType: latestSort, isGood: tab == .good,
                goodClassifyId: tab == .good ? 0 : nil)
            threads += data.threadList.filter { !$0.isLive }
            page = next
            hasMore = data.page.hasMore_p != 0
        } catch {
            errorText = error.localizedDescription
        }
    }
}
