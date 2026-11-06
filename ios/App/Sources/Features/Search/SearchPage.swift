import SwiftUI

/// 搜索页（对应 Android `SearchPage` + 三个结果子页）：
/// 帖子（hybrid `/mo/q/search/thread`）、吧（`/mo/q/search/forum`）、用户（`/mo/q/search/user`）；
/// 搜索联想走 proto `searchSug`。依赖外层 NavigationStack（由发现页 toolbar push 进入）。
struct SearchPage: View {
    @State private var keyword = ""
    @State private var scope: Scope = .thread
    @State private var suggestions: [String] = []
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var suggestTask: Task<Void, Never>?
    @State private var path = NavigationPath()

    // 三类结果
    @State private var threadResults: [WebSearchThreadResponse.Thread] = []
    @State private var forumResults: [WebSearchForumResponse.Forum] = []
    @State private var userResults: [WebSearchUserResponse.User] = []
    @State private var lastQuery = ""

    enum Scope: String, CaseIterable, Hashable {
        case thread = "帖子"
        case forum = "吧"
        case user = "用户"
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Picker("范围", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            content
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        .onChange(of: scope) { _ in
            // 切范围时若已有结果则立即重搜
            if !lastQuery.isEmpty { Task { await search() } }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索\(scope.rawValue)", text: $keyword)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { Task { await search() } }
                .onChange(of: keyword) { _ in scheduleSuggest() }
            if !keyword.isEmpty {
                Button { clearAll() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func clearAll() {
        keyword = ""
        threadResults = []
        forumResults = []
        userResults = []
        suggestions = []
        lastQuery = ""
        errorText = nil
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorText, resultsEmpty {
            UnavailableView(title: "搜索失败", systemImage: "magnifyingglass", description: err)
        } else if !suggestions.isEmpty && resultsEmpty {
            List(suggestions, id: \.self) { s in
                Button {
                    keyword = s
                    suggestions = []
                    Task { await search() }
                } label: {
                    Label(s, systemImage: "magnifyingglass").foregroundStyle(.primary)
                }
            }
            .listStyle(.plain)
        } else if resultsEmpty {
            UnavailableView(title: "输入关键词开始搜索", systemImage: "magnifyingglass",
                            description: "支持搜索帖子、吧与用户")
        } else {
            resultList
        }
    }

    private var resultsEmpty: Bool {
        switch scope {
        case .thread: return threadResults.isEmpty
        case .forum: return forumResults.isEmpty
        case .user: return userResults.isEmpty
        }
    }

    @ViewBuilder
    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch scope {
                case .thread:
                    ForEach(Array(threadResults.enumerated()), id: \.offset) { _, t in
                        Button {
                            path.append(AppRoute.thread(id: Int64(t.tid?.value ?? "0") ?? 0,
                                                        title: t.title ?? "",
                                                        forumId: Int64(t.forum_id?.value ?? "0") ?? 0))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.title ?? "").font(.subheadline.weight(.medium)).lineLimit(2)
                                if let c = t.content, !c.isEmpty {
                                    Text(c).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                HStack(spacing: 8) {
                                    if let f = t.forum_name, !f.isEmpty {
                                        Text(f).font(.caption2).foregroundStyle(.blue)
                                    }
                                    if let n = t.post_num?.value {
                                        Text("回复 \(n)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    if let l = t.like_num?.value {
                                        Text("赞 \(l)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                case .forum:
                    ForEach(Array(forumResults.enumerated()), id: \.offset) { _, f in
                        Button {
                            path.append(AppRoute.forum(f.forum_name ?? ""))
                        } label: {
                            HStack(spacing: 12) {
                                RemoteImage(url: URL(string: f.avatar ?? ""))
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.forum_name_show ?? f.forum_name ?? "")
                                        .font(.subheadline.weight(.medium))
                                    if let s = f.slogan, !s.isEmpty {
                                        Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    HStack(spacing: 8) {
                                        Text("关注 \(f.concern_num?.value ?? "0")")
                                        Text("帖子 \(f.post_num?.value ?? "0")")
                                    }
                                    .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                case .user:
                    ForEach(Array(userResults.enumerated()), id: \.offset) { _, u in
                        Button {
                            path.append(AppRoute.user(uid: Int64(u.id?.value ?? "0") ?? 0))
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: Tieba_ThreadInfo.portraitURL(u.portrait ?? ""), size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(u.show_nickname ?? u.user_nickname ?? u.name ?? "")
                                        .font(.subheadline.weight(.medium))
                                    if let i = u.intro, !i.isEmpty {
                                        Text(i).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    if let fans = u.fans_num?.value {
                                        Text("粉丝 \(fans)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .refreshable { await search() }
    }

    /// 搜索联想（去抖 300ms）
    private func scheduleSuggest() {
        suggestTask?.cancel()
        let word = keyword
        guard !word.isEmpty else { suggestions = []; return }
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                let data = try await TiebaEndpoints.searchSug(
                    client: .shared, keyword: word, isForum: scope == .forum)
                guard !Task.isCancelled else { return }
                await MainActor.run { suggestions = Array(data.list.prefix(10)) }
            } catch {
                // 联想失败静默（不影响主搜索）
            }
        }
    }

    private func search() async {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        suggestions = []
        lastQuery = word
        isSearching = true
        defer { isSearching = false }
        errorText = nil
        switch scope {
        case .thread:
            do {
                let resp = try await TiebaJSONClient.shared.searchThread(keyword: word, page: 1)
                threadResults = resp.data?.post_list ?? []
                if threadResults.isEmpty { errorText = "没有找到相关帖子" }
            } catch {
                errorText = error.localizedDescription
            }
        case .forum:
            do {
                let resp = try await TiebaJSONClient.shared.searchForum(keyword: word)
                forumResults = resp.forums
                if forumResults.isEmpty { errorText = "未找到相关贴吧" }
            } catch {
                errorText = error.localizedDescription
            }
        case .user:
            do {
                let resp = try await TiebaJSONClient.shared.searchUser(keyword: word)
                userResults = resp.users
                if userResults.isEmpty { errorText = "未找到相关用户" }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
