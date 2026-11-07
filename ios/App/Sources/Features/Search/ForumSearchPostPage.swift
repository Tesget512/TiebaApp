import SwiftUI

/// 词流布局：标签式搜索历史（点击搜索、长按删除）
struct FlowWordList: View {
    let words: [String]
    var onTap: (String) -> Void
    var onDelete: ((String) -> Void)?

    var body: some View {
        var width: CGFloat = 0
        var height: CGFloat = 0
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(words, id: \.self) { word in
                    Text(word)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6), in: Capsule())
                        .onTapGesture { onTap(word) }
                        .contextMenu {
                            if let onDelete {
                                Button(role: .destructive) {
                                    onDelete(word)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                        .alignmentGuide(.leading) { d in
                            if abs(width - d.width) > geo.size.width {
                                width = 0
                                height -= d.height + 8
                            }
                            let result = width
                            if word == words.last {
                                width = 0
                            } else {
                                width -= d.width + 8
                            }
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if word == words.last { height = 0 }
                            return result
                        }
                }
            }
        }
        .frame(height: CGFloat((words.count / 4 + 1)) * 36)
        .padding(.horizontal, 16)
    }
}

/// 吧内搜索（对应 Android `ForumSearchPostPage`）：
/// hybrid `/mo/q/search/thread` + fname 限定吧名；
/// 筛选（全部/仅主题 → tt 2/1）+ 排序（按时间=1 / 按相关=2）+ 搜索历史
struct ForumSearchPostPage: View {
    let forumName: String

    @State private var keyword = ""
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var results: [WebSearchThreadResponse.Thread] = []
    @State private var history: [String] = []
    /// Android ForumSearchPostFilterType：ALL=2 / ONLY_THREAD=1
    @State private var filterType = 2
    /// Android sortType：1=时间倒序 / 2=相关
    @State private var sortType = 1
    @State private var page = 1
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var searched = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterBar
            content
        }
        .navigationTitle("\(forumName) 吧内搜索")
        .navigationBarTitleDisplayMode(.inline)
        .bottomBarHidden()
        .onAppear { history = SearchStore.all() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("在 \(forumName) 吧内搜索", text: $keyword)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { Task { await search(reset: true) } }
            if !keyword.isEmpty {
                Button { keyword = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("筛选", selection: $filterType) {
                    Text("全部").tag(2)
                    Text("仅主题").tag(1)
                }
                .onChange(of: filterType) { _ in
                    if searched { Task { await search(reset: true) } }
                }
            } label: {
                Label(filterType == 2 ? "全部" : "仅主题", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.footnote)
            }
            Menu {
                Picker("排序", selection: $sortType) {
                    Text("按时间").tag(1)
                    Text("按相关").tag(2)
                }
                .onChange(of: sortType) { _ in
                    if searched { Task { await search(reset: true) } }
                }
            } label: {
                Label(sortType == 1 ? "按时间" : "按相关", systemImage: "arrow.up.arrow.down")
                    .font(.footnote)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        if isSearching && results.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorText, results.isEmpty {
            VStack(spacing: 0) {
                historySection
                UnavailableView(title: "搜索失败", systemImage: "magnifyingglass", description: err)
            }
        } else if results.isEmpty {
            ScrollView {
                historySection
                if searched {
                    UnavailableView(title: "没有找到相关帖子", systemImage: "magnifyingglass")
                } else {
                    UnavailableView(title: "搜索本吧帖子", systemImage: "text.magnifyingglass",
                                    description: "输入关键词在 \(forumName) 吧内搜索")
                }
            }
        } else {
            resultListView
        }
    }

    private var resultListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.offset) { idx, t in
                    NavigationLink(value: AppRoute.thread(
                        id: Int64(t.tid?.value ?? "0") ?? 0,
                        title: t.title ?? "",
                        forumId: Int64(t.forum_id?.value ?? "0") ?? 0)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.title ?? "").font(.subheadline.weight(.medium)).lineLimit(2)
                            if let c = t.content, !c.isEmpty {
                                Text(c).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            HStack(spacing: 8) {
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
                    .onAppear {
                        if idx == results.count - 2, hasMore, !isLoadingMore {
                            Task { await loadMore() }
                        }
                    }
                    Divider().padding(.leading, 16)
                }
                if isLoadingMore {
                    ProgressView().padding(.vertical, 12)
                }
            }
        }
        .refreshable { await search(reset: true) }
    }

    @ViewBuilder
    private var historySection: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("搜索历史").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        SearchStore.clear()
                        history = []
                    } label: {
                        Image(systemName: "trash").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                FlowWordList(words: history) { word in
                    keyword = word
                    Task { await search(reset: true) }
                } onDelete: { word in
                    SearchStore.remove(word)
                    history = SearchStore.all()
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func search(reset: Bool) async {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        SearchStore.add(word)
        history = SearchStore.all()
        page = 1
        searched = true
        isSearching = true
        defer { isSearching = false }
        errorText = nil
        do {
            let resp = try await TiebaJSONClient.shared.searchThread(
                keyword: word, page: 1, sort: sortType, filterTT: filterType,
                forumName: forumName)
            results = resp.data?.post_list ?? []
            hasMore = results.count >= 20
            if results.isEmpty { errorText = "没有找到相关帖子" }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let resp = try await TiebaJSONClient.shared.searchThread(
                keyword: keyword, page: page + 1, sort: sortType, filterTT: filterType,
                forumName: forumName)
            let more = resp.data?.post_list ?? []
            results += more
            page += 1
            hasMore = more.count >= 20
        } catch {
            // 分页失败静默
        }
    }
}
