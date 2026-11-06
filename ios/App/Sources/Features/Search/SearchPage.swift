import SwiftUI

/// 搜索页：搜索联想（proto `/c/s/searchSug`）+ 帖子搜索（JSON `/c/s/searchpost`）
/// 对应 Android `ui/page/search/SearchPage`
struct SearchPage: View {
    @State private var keyword = ""
    @State private var scope: Scope = .thread
    @State private var suggestions: [String] = []
    @State private var results: [Tieba_ThreadInfo] = []
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var suggestTask: Task<Void, Never>?
    @State private var path = NavigationPath()

    enum Scope: String, CaseIterable, Hashable {
        case thread = "帖子"
        case forum = "吧"
    }

    var body: some View {
        NavigationStack(path: $path) {
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
        .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(scope == .thread ? "搜索帖子" : "搜索贴吧", text: $keyword)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { Task { await search() } }
                .onChange(of: keyword) { _ in scheduleSuggest() }
            if !keyword.isEmpty {
                Button { keyword = ""; results = []; suggestions = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorText, results.isEmpty {
            UnavailableView(title: "搜索失败", systemImage: "magnifyingglass", description: err)
        } else if !suggestions.isEmpty && results.isEmpty {
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
        } else if results.isEmpty {
            UnavailableView(title: "输入关键词开始搜索", systemImage: "magnifyingglass",
                            description: "支持搜索帖子标题与内容")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ThreadListView(threads: results) { t in
                        path.append(AppRoute.thread(id: t.tid, title: t.title, forumId: t.forumID))
                    }
                }
            }
        }
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
        isSearching = true
        defer { isSearching = false }
        if scope == .forum {
            // 吧搜索：用联想接口的 forum_list
            do {
                let data = try await TiebaEndpoints.searchSug(
                    client: .shared, keyword: word, isForum: true)
                results = []
                errorText = data.forumList.isEmpty ? "未找到相关贴吧" : nil
                suggestions = data.forumList.map(\.forumName)
            } catch {
                errorText = error.localizedDescription
            }
            return
        }
        do {
            let resp = try await TiebaEndpoints.searchPost(keyword: word)
            results = (resp.post_list ?? []).compactMap { p -> Tieba_ThreadInfo? in
                guard let tid = p.tid?.value, tid != 0 else { return nil }
                var t = Tieba_ThreadInfo()
                t.id = tid
                t.title = p.title ?? ""
                t.forumName = p.forum_name ?? ""
                t.replyNum = Int32(p.reply_num?.value ?? 0)
                t.lastTimeInt = Int32(p.time?.value ?? 0)
                var a = Tieba_User()
                a.id = p.author?.id?.value ?? 0
                a.name = p.author?.name ?? ""
                a.nameShow = p.author?.name_show ?? ""
                a.portrait = p.author?.portrait ?? ""
                t.author = a
                var content = Tieba_PbContent()
                content.type = 0
                content.text = p.content ?? ""
                t.richAbstract = [content]
                return t
            }
            errorText = results.isEmpty ? "没有找到相关帖子" : nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
