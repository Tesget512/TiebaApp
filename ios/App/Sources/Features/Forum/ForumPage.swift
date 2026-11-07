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
    /// 签到结果弹窗（对齐 Android ForumViewModel:100-112 经验/排名/连续天数）
    @State private var signResult: ForumSignResponse.UserInfo?
    @State private var showSignResult = false
    /// 关注确认取关弹窗
    @State private var showUnfollowConfirm = false
    @State private var isTogglingLike = false
    @State private var path = NavigationPath()
    @State private var toast: String?
    @State private var showNewPost = false
    @State private var forumDetailRoute = false
    @State private var generalTabRoute: GeneralTabListPage.TabInfo?
    @State private var generalTabs: [Tieba_FrsTabInfo] = []

    enum ForumTab: Hashable { case latest, good }

    var body: some View {
        VStack(spacing: 0) {
            // 层级顺序对齐 Android ForumPage.kt：吧信息头在上（840 行），Tab 行在下（872 行）
            forumHeader
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
        .bottomBarHidden()
        .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // 吧内搜索（Android ForumSearchPostPage）
                NavigationLink(value: AppRoute.forumSearch(name: forumName)) {
                    Image(systemName: "magnifyingglass")
                }
                if appState.isLoggedIn {
                    Button {
                        showNewPost = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                Menu {
                    if tab == .latest {
                        // Android 最新 tab 子菜单：按回复时间/按发帖时间排序
                        Picker("排序方式", selection: $latestSort) {
                            Text("按回复时间").tag(0)
                            Text("按发帖时间").tag(1)
                        }
                        .onChange(of: latestSort) { _ in Task { await reload() } }
                    }
                    if let forum {
                        Button {
                            forumDetailRoute = true
                        } label: {
                            Label("吧详情", systemImage: "info.circle")
                        }
                    }
                    if !generalTabs.isEmpty {
                        Menu {
                            ForEach(generalTabs, id: \.tabID) { t in
                                Button {
                                    generalTabRoute = GeneralTabListPage.TabInfo(id: t.tabID,
                                                                                 name: t.tabName,
                                                                                 type: t.tabType)
                                } label: {
                                    Text(t.tabName)
                                }
                            }
                        } label: {
                            Label("通用标签", systemImage: "list.bullet")
                        }
                    }
                    Button {
                        UIPasteboard.general.string = "https://tieba.baidu.com/f?kw=\(forumName)"
                        toast = "链接已复制"
                    } label: {
                        Label("复制链接", systemImage: "link")
                    }
                    ShareLink(item: URL(string: "https://tieba.baidu.com/f?kw=\(forumName)")!) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    // 取关（Android ForumPage.kt:655-663 菜单项，带确认弹窗）
                    if appState.isLoggedIn, forum?.isLike == 1 {
                        Divider()
                        Button(role: .destructive) {
                            showUnfollowConfirm = true
                        } label: {
                            Label("取消关注本吧", systemImage: "person.minus")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("签到成功", isPresented: $showSignResult) {
            Button("好的", role: .cancel) {}
        } message: {
            if let info = signResult {
                Text("""
                经验值 +\(info.sign_bonus_point?.value ?? 8)
                连续签到 \(info.cont_sign_num?.value ?? 1) 天
                本吧排名 第\(info.user_sign_rank?.value ?? 0) 名
                """)
            }
        }
        .alert("取消关注", isPresented: $showUnfollowConfirm) {
            Button("取消", role: .cancel) {}
            Button("取关", role: .destructive) {
                if let f = forum { Task { await toggleFollow(f, follow: false) } }
            }
        } message: {
            Text("确定不再关注 \(forumName) 吗？")
        }
        .navigationDestination(isPresented: $forumDetailRoute) {
            ForumDetailPage(forumId: forum?.id ?? 0, forumName: forumName)
        }
        .navigationDestination(isPresented: Binding(get: { generalTabRoute != nil },
                                                    set: { if !$0 { generalTabRoute = nil } })) {
            if let tab = generalTabRoute {
                GeneralTabListPage(forumId: forum?.id ?? 0, forumName: forumName, tab: tab)
            }
        }
        .sheet(isPresented: $showNewPost) {
            ReplySheet(threadId: 0, forumId: forum?.id ?? 0, forumName: forumName,
                       threadTitle: "")
        }
        .overlay(alignment: .bottomTrailing) {
            // FAB（对应 Android forumFabFunction 默认 post）；安全模式只读不显示
            if appState.isLoggedIn && !AppPreferences.shared.safeMode {
                Button {
                    showNewPost = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.blue, in: Circle())
                        .shadow(radius: 4, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
        .toast($toast)
        .task { if threads.isEmpty { await reload() } }
        .onChange(of: tab) { _ in Task { await reload() } }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && threads.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorText, threads.isEmpty {
            UnavailableView(title: "加载失败", systemImage: "wifi.exclamationmark",
                            description: err, retry: { Task { await reload() } })
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ThreadListView(threads: threads, isLoadingMore: isLoadingMore,
                                   onLoadMore: { await loadMore() })
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
                forumActionButton(forum)
            }
            .padding(16)
            Divider()
        }
    }

    /// 头部主按钮：对齐 Android ForumPage.kt:290-310 三态
    /// 未关注 → 「关注」（点击关注）；已关注未签 → 「签到」；已签 → 「已签 N 天」（置灰）
    @ViewBuilder
    private func forumActionButton(_ forum: Tieba_FrsPage_ForumInfo) -> some View {
        let liked = forum.isLike == 1
        let signed = forum.signInInfo.userInfo.isSignIn == 1
        Button {
            Task {
                if !liked {
                    await toggleFollow(forum, follow: true)
                } else if !signed {
                    await sign(forum)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if isSigning || isTogglingLike {
                    ProgressView().controlSize(.small)
                } else {
                    if liked && signed {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                    }
                    Text(buttonTitle(forum, liked: liked, signed: signed))
                        .font(.footnote.weight(.medium))
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isSigning || isTogglingLike || (liked && signed))
    }

    private func buttonTitle(_ forum: Tieba_FrsPage_ForumInfo, liked: Bool, signed: Bool) -> String {
        if !liked { return "关注" }
        if signed { return "已签 \(forum.signInInfo.userInfo.contSignNum) 天" }
        return signStatus ?? "签到"
    }

    /// 关注/取关（Android ForumUiIntent.Like / unlike；取关带确认弹窗）
    private func toggleFollow(_ forum: Tieba_FrsPage_ForumInfo, follow: Bool) async {
        guard appState.isLoggedIn else {
            errorText = "请先登录"
            return
        }
        if AppPreferences.shared.safeMode && !follow {
            toast = "安全模式已开启，写操作被拦截"
            return
        }
        isTogglingLike = true
        defer { isTogglingLike = false }
        do {
            if follow {
                _ = try await TiebaWriteEndpoints.likeForum(forumId: Int64(forum.id),
                                                            forumName: forumName)
                updateForumLocally { $0.isLike = 1 }  // Int32 协议字段
                toast = "已关注 \(forumName)"
            } else {
                _ = try await TiebaWriteEndpoints.unlikeForum(forumId: Int64(forum.id),
                                                              forumName: forumName)
                updateForumLocally { $0.isLike = 0 }
                toast = "已取消关注 \(forumName)"
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    /// 本地更新吧信息（struct 拷贝写回，按钮态即时变化，避免整页 reload 闪烁）
    private func updateForumLocally(_ mutate: (inout Tieba_FrsPage_ForumInfo) -> Void) {
        guard var f = forum else { return }
        mutate(&f)
        forum = f
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
            let resp = try await TiebaWriteEndpoints.forumSign(forumName: forumName,
                                                               forumId: Int64(forum.id))
            // 本地回显已签状态（is_sign_in=1 + 连续天数），并弹出结果
            if let info = resp.user_info {
                updateForumLocally { f in
                    var si = f.signInInfo
                    var ui = si.userInfo
                    ui.isSignIn = Int32(info.is_sign_in?.value ?? 1)
                    if let cont = info.cont_sign_num?.value { ui.contSignNum = Int32(cont) }
                    si.userInfo = ui
                    f.signInInfo = si
                }
                signResult = info
                showSignResult = true
            } else {
                signStatus = "已签到"
            }
        } catch {
            toast = error.localizedDescription
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
            threads.resolveAuthors(AuthorResolver.map(data.userList))
            hasMore = data.page.hasMore_p != 0
            errorText = nil
            generalTabs = data.navTabInfo.tab.filter { $0.isGeneralTab == 1 }
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
            var more = data.threadList.filter { !$0.isLive }
            more.resolveAuthors(AuthorResolver.map(data.userList))
            threads += more
            page = next
            hasMore = data.page.hasMore_p != 0
        } catch {
            errorText = error.localizedDescription
        }
    }
}
