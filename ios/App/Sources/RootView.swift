import SwiftUI

/// 根视图：底部 Tab（发现/进吧/通知/我的），未登录可用（读接口无需登录）。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ExploreView()
                .tabItem { Label("发现", systemImage: "safari") }
                .tag(0)

            MyForumsView()
                .tabItem { Label("进吧", systemImage: "square.grid.2x2") }
                .tag(1)

            NotificationsView()
                .tabItem { Label("通知", systemImage: "bell") }
                .tag(2)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(3)
        }
    }
}

/// 进吧：常用吧入口 + 搜索（v1 提供固定入口列表）
struct MyForumsView: View {
    @State private var navigationPath = NavigationPath()
    static let commonForums = ["李毅", "孙笑川", "原神", "抗压背锅怪", "魔兽世界", "戒赌吧"]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section("常用吧") {
                    ForEach(Self.commonForums, id: \.self) { name in
                        Button {
                            navigationPath.append(ForumRoute(forumName: name))
                        } label: {
                            Label(name, systemImage: "bubble.left.and.bubble.left.and.bubble.right")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("进吧")
            .navigationDestination(for: ForumRoute.self) { route in
                ForumPage(forumName: route.forumName)
            }
        }
    }
}

/// 通知：需要登录 + JSON 通道（P5 后续实现）
struct NotificationsView: View {
    var body: some View {
        NavigationStack {
            UnavailableView(title: "暂未开放", systemImage: "bell.slash",
                                description: "通知功能需要登录后使用，将在后续版本提供。")
                .navigationTitle("通知")
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}
