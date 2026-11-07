import SwiftUI

/// 用户主页（对应 Android `ui/page/user/UserProfilePage`）
/// 接口：`/c/u/user/profile?cmd=303012`（V12 通道）
struct UserProfilePage: View {
    let uid: Int64

    @EnvironmentObject private var appState: AppState
    @State private var data: Tieba_Profile_ProfileResponseData?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var toast: String?
    @State private var showReplyDisabled = false

    var body: some View {
        Group {
            if isLoading && data == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText, data == nil {
                UnavailableView(title: "加载失败", systemImage: "person.crop.circle.badge.exclamationmark",
                                description: err)
            } else if let data {
                content(data)
            }
        }
        .navigationTitle(data?.user.nameShow.isEmpty == false ? data!.user.nameShow
                         : (data?.user.name ?? "用户主页"))
        .navigationBarTitleDisplayMode(.inline)
        .bottomBarHidden()
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
        .alert("拉黑范围", isPresented: $showBlackDialog) {
            Button("保存") { Task { await saveBlackInfo() } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("禁止 TA 关注 / 互动 / 私信（perm_list 将提交到 setUserBlack）")
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ data: Tieba_Profile_ProfileResponseData) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AvatarView(url: Tieba_ThreadInfo.portraitURL(data.user.portrait), size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(data.user.nameShow.isEmpty ? data.user.name : data.user.nameShow)
                            .font(.headline)
                        if !data.user.intro.isEmpty {
                            Text(data.user.intro).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text("ID: \(data.user.id)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    stat("关注", data.user.concernNum)
                    Divider()
                    stat("粉丝", data.user.fansNum)
                    Divider()
                    stat("发帖", data.user.postNum)
                }
                .frame(maxWidth: .infinity)
            }

            // 操作区（对齐 Android：关注/取关、TA的帖子、互动分析）
            Section {
                NavigationLink {
                    UserPostListPage(uid: uid, name: displayName(data), isThread: true)
                } label: {
                    Label("TA 的主题贴", systemImage: "doc.text")
                }
                NavigationLink {
                    UserPostListPage(uid: uid, name: displayName(data), isThread: false)
                } label: {
                    Label("TA 的回复", systemImage: "bubble.right")
                }
                NavigationLink {
                    FollowListView(isFollow: true, uid: uid)
                } label: {
                    Label("关注 \(shortNum(Int64(data.user.concernNum)))", systemImage: "person.badge.plus")
                }
                NavigationLink {
                    FollowListView(isFollow: false, uid: uid)
                } label: {
                    Label("粉丝 \(shortNum(Int64(data.user.fansNum)))", systemImage: "person.2")
                }
                NavigationLink {
                    UserLikeForumListPage(uid: uid)
                } label: {
                    Label("TA 关注的吧", systemImage: "square.grid.2x2")
                }
                NavigationLink {
                    PostAnalysisPage(uid: uid, name: displayName(data))
                } label: {
                    Label("发言分析", systemImage: "chart.bar")
                }
                if !isSelfProfile {
                    Button {
                        Task { await loadBlackInfo() }
                    } label: {
                        Label("禁止互动范围", systemImage: "nosign")
                    }
                }
            }

            if !data.postList.isEmpty {
                Section("最近发帖") {
                    ForEach(Array(data.postList.enumerated()), id: \.offset) { _, post in
                        NavigationLink {
                            ThreadPage(threadID: Int64(bitPattern: post.threadID),
                                       title: post.title,
                                       forumId: Int64(bitPattern: post.forumID))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(post.title).font(.subheadline).lineLimit(2)
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
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            // 非自己主页时显示关注/取关（对应 Android followFlow/unfollowFlow）
            if !isSelfProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleFollow(data) }
                    } label: {
                        Label(isFollowing ? "取关" : "关注",
                              systemImage: isFollowing ? "person.badge.minus" : "person.badge.plus")
                            .font(.footnote)
                    }
                }
            }
        }
    }

    private var selfUid: Int64 { Int64(appState.account?.uid ?? "") ?? 0 }
    private var isSelfProfile: Bool { uid == selfUid }
    /// Android User.has_concerned = 1 表示已关注
    private var isFollowing: Bool { data?.user.hasConcerned_p == 1 }

    // MARK: 拉黑（对应 Android PermissionSettingDialog + setUserBlack）

    @State private var showBlackDialog = false
    @State private var perm = PermissionList()
    @State private var permLoaded = false

    private func loadBlackInfo() async {
        guard appState.isLoggedIn else { toast = "请先登录"; return }
        do {
            perm = try await TiebaWriteEndpoints.getUserBlackInfo(blackUid: uid)
            permLoaded = true
            showBlackDialog = true
        } catch {
            toast = error.localizedDescription
        }
    }

    private func saveBlackInfo() async {
        guard let account = appState.account else { return }
        if AppPreferences.shared.safeMode { toast = "安全模式已开启，写操作被拦截"; return }
        do {
            try await TiebaWriteEndpoints.setUserBlack(blackUid: uid, tbs: account.tbs, perm: perm)
            toast = "已保存拉黑范围"
        } catch {
            toast = error.localizedDescription
        }
    }

    private func displayName(_ data: Tieba_Profile_ProfileResponseData) -> String {
        data.user.nameShow.isEmpty ? data.user.name : data.user.nameShow
    }

    private func toggleFollow(_ data: Tieba_Profile_ProfileResponseData) async {
        guard appState.isLoggedIn else { toast = "请先登录"; return }
        let portrait = data.user.portrait
        guard !portrait.isEmpty else { toast = "无法获取用户标识"; return }
        do {
            if isFollowing {
                try await TiebaWriteEndpoints.unfollowUser(portrait: portrait)
                toast = "已取消关注"
            } else {
                try await TiebaWriteEndpoints.followUser(portrait: portrait)
                toast = "关注成功"
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    private func stat(_ title: String, _ value: Int32) -> some View {
        VStack(spacing: 2) {
            Text(shortNum(Int64(value))).font(.subheadline.weight(.semibold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let selfUid = appState.account.flatMap { Int64($0.uid) } ?? 0
        do {
            data = try await TiebaEndpoints.userProfile(
                client: .shared, uid: uid, selfUid: selfUid, isSelf: uid == selfUid)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
