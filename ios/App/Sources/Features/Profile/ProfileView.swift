import SwiftUI

/// 我的页面（对应 Android `UserPage`）：登录态、头像、账号信息、登出
struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogin = false
    @State private var profile: Tieba_Profile_ProfileResponseData?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if let account = appState.account {
                    Section {
                        HStack(spacing: 12) {
                            AvatarView(url: account.avatarURL, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.name).font(.headline)
                                if let user = profile?.user {
                                    HStack(spacing: 14) {
                                        // 统计可点（对齐 Android UserPage：跳对应列表）
                                        NavigationLink {
                                            FollowListView(isFollow: true, uid: Int64(account.uid) ?? 0)
                                        } label: { statItem("关注", user.concernNum) }
                                            .buttonStyle(.plain)
                                        NavigationLink {
                                            FollowListView(isFollow: false, uid: Int64(account.uid) ?? 0)
                                        } label: { statItem("粉丝", user.fansNum) }
                                            .buttonStyle(.plain)
                                        NavigationLink {
                                            UserPostListPage(uid: Int64(account.uid) ?? 0,
                                                             name: account.name, isThread: false)
                                        } label: { statItem("发帖", user.postNum) }
                                            .buttonStyle(.plain)
                                    }
                                } else {
                                    Text("UID: \(account.uid)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        NavigationLink {
                            UserProfilePage(uid: Int64(account.uid) ?? 0)
                        } label: {
                            Label("我的主页", systemImage: "person.text.rectangle")
                        }
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
                } else {
                    Section {
                        Button {
                            showLogin = true
                        } label: {
                            Label("登录百度账号", systemImage: "person.crop.circle.badge.plus")
                        }
                    } footer: {
                        Text("通过百度通行证登录，客户端仅在本机 Keychain 保存 BDUSS/STOKEN 用于调用贴吧接口。")
                    }
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

/// 我的关注吧（对应 Android `UserLikeForumPage` 的精简版）
struct MyForumsView: View {
    @State private var forums: [Tieba_ForumInfo] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && forums.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if forums.isEmpty {
                UnavailableView(title: "暂无关注的吧", systemImage: "square.grid.2x2")
            } else {
                List(forums, id: \.forumID) { f in
                    NavigationLink {
                        ForumPage(forumName: f.forumName)
                    } label: {
                        HStack(spacing: 10) {
                            AvatarView(url: URL(string: f.avatar), size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.forumName).font(.subheadline.weight(.medium))
                                Text("关注 \(f.concernNum)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("我的关注吧")
        .task { await load() }
    }

    private func load() async {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await TiebaJSONClient.shared.post(
                path: "/c/u/feed/userlikeforum",
                params: ["uid": account.uid, "page": "1", "rn": "200"],
                channel: .official)
            struct Resp: Decodable {
                struct Forum: Decodable {
                    let forum_id: FlexibleInt?
                    let forum_name: String?
                    let avatar: String?
                    let level_id: FlexibleInt?
                }
                let error_code: FlexibleString?
                let like_forum: [Forum]?
            }
            let resp = try TiebaJSONClient.decode(Resp.self, from: data)
            forums = (resp.like_forum ?? []).map { f in
                var info = Tieba_ForumInfo()
                info.forumID = UInt32(f.forum_id?.value ?? 0)
                info.forumName = f.forum_name ?? ""
                info.avatar = f.avatar ?? ""
                return info
            }
        } catch {
            forums = []
        }
    }
}
