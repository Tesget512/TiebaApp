import SwiftUI

/// 通知页：回复我的 / @我的 / 赞我的
/// 对应 Android `ui/page/main/...` 的消息列表（NEW 通道 `/c/u/feed/*`）
struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var tab: Tab = .reply
    @State private var items: [MessageListResponse.MessageInfo] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var path = NavigationPath()

    enum Tab: String, CaseIterable, Hashable {
        case reply = "回复我的"
        case at = "@我的"
        case agree = "赞我的"
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !appState.isLoggedIn {
                    loginPrompt
                } else if isLoading && items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = errorText, items.isEmpty {
                    UnavailableView(title: "加载失败", systemImage: "wifi.exclamationmark", description: err)
                } else if items.isEmpty {
                    UnavailableView(title: "暂无消息", systemImage: "bell", description: "下拉可刷新")
                } else {
                    List(items, id: \.offsetKey) { item in
                        messageRow(item)
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            // 分类选择器放导航栏 principal 位（原 safeAreaInset 顶部叠加大段空隙，用户反馈 ???）
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if appState.isLoggedIn {
                        Picker("类型", selection: $tab) {
                            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // 搜索入口（Android NotificationsPage.kt:139-145）
                    NavigationLink(value: AppRoute.search) {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .navigationDestination(for: AppRoute.self) { RouteView(route: $0) }
            .task { if appState.isLoggedIn { await load() } }
            .onChange(of: tab) { _ in Task { await load() } }
            .onAppear { NotifyBadge.shared.count = 0 } // 进入通知页视为已读
            .tabRootScrollBottomInset() // tab 根页：滚过底栏+边缘淡出
        }
    }

    private var loginPrompt: some View {
        UnavailableView(title: "未登录", systemImage: "person.crop.circle.badge.exclamationmark",
                        description: "登录后可查看回复、@ 与点赞消息")
    }

    @ViewBuilder
    private func messageRow(_ item: MessageListResponse.MessageInfo) -> some View {
        Button {
            if let tid = item.thread_id?.value, tid != 0 {
                path.append(AppRoute.thread(id: tid,
                                            title: item.title ?? item.fname ?? "帖子",
                                            forumId: 0))
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(url: portraitURL(item.replyer?.portrait), size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.replyer?.name_show ?? item.replyer?.name ?? "某用户")
                            .font(.subheadline.weight(.medium))
                        if let fname = item.fname, !fname.isEmpty {
                            Text(fname)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                        Spacer()
                        Text(relativeTime(fromUnixSeconds: item.time?.value ?? 0))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let title = item.title, !title.isEmpty {
                        Text(title).font(.footnote).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let content = item.content, !content.isEmpty {
                        Text(content).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func portraitURL(_ portrait: String?) -> URL? {
        guard let portrait, !portrait.isEmpty else { return nil }
        return Tieba_ThreadInfo.portraitURL(portrait)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp: MessageListResponse
            switch tab {
            case .reply: resp = try await TiebaWriteEndpoints.replyMe()
            case .at: resp = try await TiebaWriteEndpoints.atMe()
            case .agree: resp = try await TiebaWriteEndpoints.agreeMe()
            }
            items = resp.reply_list ?? resp.at_list ?? []
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private extension MessageListResponse.MessageInfo {
    /// List 需要稳定 id：用 thread_id+post_id+time 拼一个
    var offsetKey: String {
        "\(thread_id?.value ?? 0)-\(post_id?.value ?? 0)-\(time?.value ?? 0)"
    }
}
