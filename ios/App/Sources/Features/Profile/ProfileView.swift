import SwiftUI

/// 我的页面（对应 Android `UserPage`）：登录态、头像、账号信息、登出
/// 头部卡片在 List 之外（List 同一行放多个 NavigationLink 会同时激活——
/// 之前"点卡片一次弹出回复/粉丝/关注"即此 bug；navigationDestination(item:)
/// 在 iOS 26 上还会推出空白页，一并移除）
struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogin = false
    @State private var profile: Tieba_Profile_ProfileResponseData?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let account = appState.account {
                    // 头部卡片（List 外：NavigationLink 在普通布局中行为可靠）
                    VStack(spacing: 12) {
                        NavigationLink {
                            UserProfilePage(uid: Int64(account.uid) ?? 0)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: account.avatarURL, size: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.name).font(.headline)
                                    Text("UID: \(account.uid) · 查看主页")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        if let user = profile?.user {
                            HStack(spacing: 0) {
                                // 统计可点（对齐 Android UserPage：跳对应列表）
                                NavigationLink {
                                    FollowListView(isFollow: true, uid: Int64(account.uid) ?? 0)
                                } label: { statItem("关注", user.concernNum) }
                                    .buttonStyle(.plain)
                                Divider().frame(height: 24)
                                NavigationLink {
                                    FollowListView(isFollow: false, uid: Int64(account.uid) ?? 0)
                                } label: { statItem("粉丝", user.fansNum) }
                                    .buttonStyle(.plain)
                                Divider().frame(height: 24)
                                NavigationLink {
                                    UserPostListPage(uid: Int64(account.uid) ?? 0,
                                                     name: account.name, isThread: true)
                                } label: { statItem("发帖", user.postNum) }
                                    .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    List {
                        Section {
                            NavigationLink {
                                UserPostListPage(uid: Int64(account.uid) ?? 0, name: account.name,
                                                 isThread: true)
                            } label: {
                                Label("我的发帖", systemImage: "doc.text")
                            }
                            NavigationLink {
                                UserPostListPage(uid: Int64(account.uid) ?? 0, name: account.name,
                                                 isThread: false)
                            } label: {
                                Label("我的回帖", systemImage: "bubble.right")
                            }
                            NavigationLink {
                                MyForumsView()
                            } label: {
                                Label("我的关注吧", systemImage: "square.grid.2x2")
                            }
                            NavigationLink {
                                FollowListView(isFollow: true, uid: Int64(account.uid) ?? 0)
                            } label: {
                                Label("关注列表", systemImage: "person.2")
                            }
                            NavigationLink {
                                FollowListView(isFollow: false, uid: Int64(account.uid) ?? 0)
                            } label: {
                                Label("粉丝列表", systemImage: "person.2.wave.2")
                            }
                            NavigationLink {
                                EditProfilePage()
                            } label: {
                                Label("修改资料", systemImage: "pencil.line")
                            }
                            NavigationLink {
                                ThreadStorePage()
                            } label: {
                                Label("我的收藏", systemImage: "star")
                            }
                            NavigationLink {
                                HistoryPageView()
                            } label: {
                                Label("浏览历史", systemImage: "clock.arrow.circlepath")
                            }
                        }

                        Section {
                            NavigationLink {
                                SettingsView()
                            } label: {
                                Label("设置", systemImage: "gearshape")
                            }
                            // 服务中心（Android UserPage 菜单：WebView）
                            NavigationLink {
                                WebViewPage(url: URL(string: "https://tieba.baidu.com/mo/q/service/pages/index")!)
                            } label: {
                                Label("服务中心", systemImage: "headphones")
                            }
                            NavigationLink {
                                AboutView()
                            } label: {
                                Label("关于", systemImage: "info.circle")
                            }
                        }

                        Section {
                            Button("退出登录", role: .destructive) { appState.logout() }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .tabRootScrollBottomInset()
                } else {
                    VStack(spacing: 12) {
                        Button {
                            showLogin = true
                        } label: {
                            Label("登录百度账号", systemImage: "person.crop.circle.badge.plus")
                                .font(.headline)
                        }
                        Text("通过百度通行证登录，客户端仅在本机 Keychain 保存 BDUSS/STOKEN 用于调用贴吧接口。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showLogin) { LoginView() }
            .task(id: appState.account?.uid) { await loadProfile() }
        }
    }

    private func statItem(_ title: String, _ value: Int32) -> some View {
        VStack(spacing: 1) {
            Text(shortNum(Int64(value))).font(.footnote.weight(.semibold))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func loadProfile() async {
        guard let account = appState.account, let uid = Int64(account.uid), uid != 0 else {
            profile = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        profile = try? await TiebaEndpoints.userProfile(
            client: .shared, uid: uid, selfUid: uid, isSelf: true)
    }
}

/// 我的关注吧（对齐 Android `UserLikeForumPage`：
/// `/c/f/forum/like` official 通道，page_no/page_size/uid；
/// 此前误用 /c/u/feed/userlikeforum + like_forum 解析 → 恒空）
struct MyForumsView: View {
    struct LikeForum: Identifiable {
        let id: String
        let name: String
        let levelId: String
        let avatar: String
    }

    @State private var forums: [LikeForum] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if isLoading && forums.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText, forums.isEmpty {
                UnavailableView(title: "加载失败", systemImage: "square.grid.2x2",
                                description: err,
                                retry: { Task { await load() } })
            } else if forums.isEmpty {
                UnavailableView(title: "暂无关注的吧", systemImage: "square.grid.2x2")
            } else {
                List(forums) { f in
                    NavigationLink {
                        ForumPage(forumName: f.name)
                    } label: {
                        HStack(spacing: 10) {
                            AvatarView(url: tiebaImageURL(f.avatar), size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).font(.subheadline.weight(.medium))
                                Text("\(f.levelId)级").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .navigationTitle("我的关注吧")
        .bottomBarHidden()
        .task { if forums.isEmpty { await load() } }
    }

    private func load() async {
        guard TiebaJSONClient.shared.accountProvider() != nil else {
            errorText = "请先登录"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            forums = try await Self.fetchLikeForums(uid: nil)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            forums = []
        }
    }

    /// 拉取关注吧列表（uid=nil 查自己；uid=他人时走 friend_uid/is_guest，
    /// 对齐 Android MixedTiebaApiImpl.userLikeForumFlow:1566）
    static func fetchLikeForums(uid: Int64?) async throws -> [LikeForum] {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { throw TiebaAPIError.notLoggedIn }
        let myUid = Int64(account.uid) ?? 0
        let isSelf = uid == nil || uid == myUid
        var params = ["page_no": "1", "page_size": "50", "uid": account.uid]
        if !isSelf, let uid {
            params["friend_uid"] = "\(uid)"
            params["is_guest"] = "1"
        }
        let data = try await TiebaJSONClient.shared.post(
            path: "/c/f/forum/like", params: params,
            channel: .official, forceLogin: true)
        struct Resp: Decodable {
            struct ForumList: Decodable {
                let forumList: [Forum]?
                /// 服务端键名 "non-gconforum"（含连字符，自定义 CodingKeys）
                let nonGconforum: [Forum]?
                enum CodingKeys: String, CodingKey {
                    case forumList = "forum_list"
                    case nonGconforum = "non-gconforum"
                }
            }
            struct Forum: Decodable {
                let id: FlexibleString?
                let name: String?
                let level_id: FlexibleString?
                let avatar: String?
            }
            let error_code: FlexibleString?
            let error: ForumError?
            let forum_list: ForumList?
            let common_forum_list: ForumList?
            struct ForumError: Decodable {
                let errno: FlexibleString?
                let errmsg: String?
            }
        }
        let resp = try TiebaJSONClient.decode(Resp.self, from: data)
        if let code = resp.error_code?.value, code != "0" {
            throw TiebaAPIError.apiError(code: Int(code) ?? -1,
                                         message: resp.error?.errmsg ?? "获取关注吧失败")
        }
        var list: [LikeForum] = []
        let seen = NSMutableSet()
        for f in (resp.forum_list?.nonGconforum ?? [])
            + (resp.forum_list?.forumList ?? [])
            + (resp.common_forum_list?.nonGconforum ?? []) {
            let id = f.id?.value ?? ""
            guard !id.isEmpty, !seen.contains(id) else { continue }
            seen.add(id)
            list.append(LikeForum(id: id, name: f.name ?? "",
                                  levelId: f.level_id?.value ?? "0",
                                  avatar: f.avatar ?? ""))
        }
        return list
    }
}
