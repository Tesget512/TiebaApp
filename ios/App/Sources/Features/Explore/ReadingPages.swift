import SwiftUI

// MARK: - 吧详情（对应 Android ForumDetailPage）

struct ForumDetailPage: View {
    let forumId: Int64
    let forumName: String

    @State private var info: Tieba_RecommendForumInfo?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if isLoading && info == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText, info == nil {
                UnavailableView(title: "加载失败", systemImage: "info.circle", description: err)
            } else if let info {
                List {
                    Section {
                        HStack(spacing: 14) {
                            RemoteImage(url: URL(string: info.avatar))
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.forumName).font(.headline)
                                if !info.slogan.isEmpty {
                                    Text(info.slogan).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        HStack {
                            stat("关注", info.memberCount)
                            Divider()
                            stat("帖子", info.threadCount)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if !info.content.isEmpty {
                        Section("吧简介") {
                            PbContentView(contents: info.content, fontSize: .footnote)
                        }
                    }
                    Section {
                        NavigationLink {
                            ForumRulePage(forumId: forumId)
                        } label: {
                            Label("吧规", systemImage: "doc.text")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(forumName.isEmpty ? "吧详情" : forumName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
    }

    private func stat(_ title: String, _ value: UInt32) -> some View {
        VStack(spacing: 4) {
            Text(shortNum(Int64(value))).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await TiebaExtraEndpoints.forumDetailInfo(client: .shared, forumId: forumId)
            info = data.hasForumInfo ? data.forumInfo : nil
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 吧规（对应 Android ForumRuleDetailPage）

struct ForumRulePage: View {
    let forumId: Int64

    @State private var data: Tieba_ForumRuleDetail_ForumRuleDetailResponseData?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if isLoading && data == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText, data == nil {
                UnavailableView(title: "加载失败", systemImage: "doc.text", description: err)
            } else if let data {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(data.title).font(.title3.bold())
                        HStack {
                            if !data.publishTime.isEmpty {
                                Text("发布于 \(data.publishTime)")
                            }
                            if data.hasBazhu {
                                Text("· 吧主 \(data.bazhu.nameShow.isEmpty ? data.bazhu.userName : data.bazhu.nameShow)")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)

                        if !data.preface.isEmpty {
                            Text(data.preface).font(.subheadline)
                        }

                        ForEach(Array(data.rules.enumerated()), id: \.offset) { idx, rule in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(idx + 1). \(rule.title)").font(.subheadline.weight(.semibold))
                                PbContentView(contents: rule.content, fontSize: .footnote)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("吧规")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            data = try await TiebaExtraEndpoints.forumRule(client: .shared, forumId: forumId)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 热议话题列表（对应 Android HotTopicListPage）

struct TopicListPage: View {
    @State private var topics: [Tieba_TopicList_NewTopicList] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && topics.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, topics.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "flame", description: err)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(topics.enumerated()), id: \.offset) { idx, t in
                                topicRow(t, index: idx)
                            }
                        }
                        .padding(16)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("热议话题")
            .toolbar(.hidden, for: .tabBar)
            .task { if topics.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    @ViewBuilder
    private func topicRow(_ t: Tieba_TopicList_NewTopicList, index: Int) -> some View {
        Button {
            path.append(AppRoute.topicDetail(id: "\(t.topicID)", name: t.topicName))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if !t.topicImage.isEmpty {
                    RemoteImage(url: URL(string: t.topicImage))
                        .frame(width: index < 3 ? 72 : 56, height: index < 3 ? 72 : 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if index < 3 {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(index == 0 ? Color.red : (index == 1 ? .orange : .yellow),
                                            in: RoundedRectangle(cornerRadius: 4))
                        }
                        if t.topicTag == 2 {
                            Text("热").font(.caption2).padding(.horizontal, 4)
                                .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.red)
                        } else if t.topicTag == 1 {
                            Text("新").font(.caption2).padding(.horizontal, 4)
                                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.orange)
                        }
                        Text(t.topicName).font(.subheadline.weight(.medium)).lineLimit(1)
                    }
                    if !t.topicDesc.isEmpty {
                        Text(t.topicDesc).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(index < 3 ? 3 : 1)
                    }
                    Text("\(shortNum(t.discussNum)) 讨论").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await TiebaExtraEndpoints.topicList(client: .shared)
            topics = data.topicList
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 热议话题详情（对应 Android TopicDetailPage，HYBRID 通道）

struct TopicDetailPage: View {
    let topicId: String
    let topicName: String

    @State private var data: TopicDetailResponse?
    @State private var threads: [TopicDetailResponse.ThreadItem] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var lastId = ""
    @State private var hasMore = true
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && threads.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, threads.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "flame", description: err)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            header
                            ForEach(Array(threads.enumerated()), id: \.offset) { _, item in
                                threadRow(item)
                                Divider()
                            }
                            if hasMore {
                                LoadMoreFooter { await loadMore() }
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle(topicName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task { if threads.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    @ViewBuilder
    private var header: some View {
        if let info = data?.data?.topic_info {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if let img = info.topic_image, !img.isEmpty {
                        RemoteImage(url: URL(string: img))
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.topic_name ?? topicName).font(.headline)
                        Text("\(shortNum(Int64(info.discuss_num?.value ?? 0))) 讨论")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let desc = info.topic_desc, !desc.isEmpty {
                    Text(desc).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
        }
    }

    private func threadRow(_ item: TopicDetailResponse.ThreadItem) -> some View {
        Button {
            path.append(AppRoute.thread(id: Int64(item.thread_info?.tid?.value ?? 0),
                                        title: item.thread_info?.title ?? "",
                                        forumId: Int64(item.thread_info?.forum_id?.value ?? 0)))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.thread_info?.title ?? "").font(.subheadline.weight(.medium)).lineLimit(2)
                if let abs = item.thread_info?.abstract, !abs.isEmpty {
                    Text(abs).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 10) {
                    if let f = item.thread_info?.forum_name, !f.isEmpty {
                        Text(f).font(.caption2).foregroundStyle(.blue)
                    }
                    if let r = item.thread_info?.reply_num {
                        Text("回复 \(r)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let a = item.thread_info?.agree_num {
                        Text("赞 \(a)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        lastId = ""
        defer { isLoading = false }
        do {
            let resp = try await TiebaJSONClient.shared.getTopicDetail(
                topicId: topicId, topicName: topicName, page: 1, offset: 0, lastId: "")
            data = resp
            threads = resp.data?.relate_thread?.thread_list ?? []
            hasMore = resp.data?.has_more ?? false
            lastId = "\(threads.last?.feed_id?.value ?? 0)"
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        let page = threads.count / 10 + 1
        do {
            let resp = try await TiebaJSONClient.shared.getTopicDetail(
                topicId: topicId, topicName: topicName, page: page,
                offset: (page - 1) * 10, lastId: lastId)
            let more = resp.data?.relate_thread?.thread_list ?? []
            threads += more
            hasMore = resp.data?.has_more ?? false
            lastId = "\(threads.last?.feed_id?.value ?? 0)"
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 关注/粉丝列表（对应 Android FollowListPage / FansListPage）

struct FollowListView: View {
    /// true=关注列表 false=粉丝列表
    let isFollow: Bool
    let uid: Int64

    @State private var users: [FollowUser] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var page = 1
    @State private var hasMore = true
    @State private var path = NavigationPath()

    struct FollowUser: Decodable {
        let id: FlexibleInt?
        let name: String?
        let name_show: String?
        let portrait: String?
        let intro: String?
        let has_concerned: FlexibleInt?
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && users.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, users.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "person.2", description: err)
                } else if users.isEmpty {
                    UnavailableView(title: isFollow ? "还没有关注的人" : "还没有粉丝",
                                    systemImage: "person.2")
                } else {
                    List {
                        ForEach(Array(users.enumerated()), id: \.offset) { _, u in
                            NavigationLink(value: AppRoute.user(uid: u.id?.value ?? 0)) {
                                userRow(u)
                            }
                        }
                        if hasMore {
                            LoadMoreFooter { await loadMore() }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle(isFollow ? "关注" : "粉丝")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task { if users.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    private func userRow(_ u: FollowUser) -> some View {
        HStack(spacing: 12) {
            AvatarView(url: Tieba_ThreadInfo.portraitURL(u.portrait ?? ""), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text((u.name_show?.isEmpty == false) ? u.name_show! : (u.name ?? ""))
                    .font(.subheadline.weight(.medium))
                if let intro = u.intro, !intro.isEmpty {
                    Text(intro).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        isLoading = true
        page = 1
        defer { isLoading = false }
        do {
            users = try await fetch(page: 1)
            hasMore = users.count >= 20
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = page + 1
            let more = try await fetch(page: next)
            users += more
            page = next
            hasMore = !more.isEmpty
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func fetch(page: Int) async throws -> [FollowUser] {
        struct Resp: Decodable {
            let error_code: FlexibleString?
            let follow_list: [FollowUser]?
            let user_list: [FollowUser]?
            let has_more: FlexibleInt?
            let page: PageInfo?
            struct PageInfo: Decodable { let has_more: FlexibleInt? }
        }
        let path = isFollow ? "/c/u/follow/followList" : "/c/u/fans/page"
        var params: [String: String] = ["pn": "\(page)", "_client_version": ClientVersion.v12.rawValue]
        if uid != 0 { params["uid"] = "\(uid)" }
        let data = try await TiebaJSONClient.shared.post(path: path, params: params,
                                                         channel: .official, forceLogin: true)
        let resp = try TiebaJSONClient.decode(Resp.self, from: data)
        return resp.follow_list ?? resp.user_list ?? []
    }
}

// MARK: - 关注吧列表（他人可见，对应 Android UserLikeForumPage）

struct UserLikeForumListPage: View {
    let uid: Int64

    @State private var forums: [ForumItem] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var path = NavigationPath()

    struct ForumItem: Decodable {
        let id: String?
        let name: String?
        let avatar: String?
        let slogan: String?
        let level_id: FlexibleString?
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading && forums.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if forums.isEmpty {
                    UnavailableView(title: "暂无关注的吧", systemImage: "square.grid.2x2")
                } else {
                    List(forums, id: \.id) { f in
                        NavigationLink(value: AppRoute.forum(f.name ?? "")) {
                            HStack(spacing: 12) {
                                RemoteImage(url: URL(string: f.avatar ?? ""))
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name ?? "").font(.subheadline.weight(.medium))
                                    if let s = f.slogan, !s.isEmpty {
                                        Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("关注的吧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task { if forums.isEmpty { await load() } }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            struct Resp: Decodable {
                struct ForumList: Decodable {
                    let nonGconforum: [ForumItem]?
                    enum CodingKeys: String, CodingKey {
                        case nonGconforum = "non-gconforum"
                    }
                }
                let error_code: FlexibleString?
                let forum_list: ForumList?
            }
            var params: [String: String] = [
                "page_no": "1", "page_size": "50",
                "_client_version": ClientVersion.v12.rawValue,
            ]
            let myUid = TiebaJSONClient.shared.accountProvider()?.uid ?? ""
            if !uid.description.isEmpty, "\(uid)" != myUid {
                params["friend_uid"] = "\(uid)"
                params["is_guest"] = "1"
            } else {
                params["uid"] = myUid
            }
            let data = try await TiebaJSONClient.shared.post(path: "/c/f/forum/like",
                                                             params: params, channel: .official,
                                                             forceLogin: true)
            let resp = try TiebaJSONClient.decode(Resp.self, from: data)
            forums = resp.forum_list?.nonGconforum ?? []
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
