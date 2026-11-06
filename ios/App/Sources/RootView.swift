import SwiftUI

/// 根视图：底部 Tab（发现/进吧/通知/我的）——对齐 Android `MainPage` 的 4 Tab 结构。
/// 搜索是发现页 toolbar 的放大镜入口（Android ExplorePage 顶部 search icon）。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ExploreView()
                .tabItem { Label("发现", systemImage: "safari") }
                .tag(0)

            HomeFeedPage()
                .tabItem { Label("进吧", systemImage: "square.grid.2x2") }
                .tag(1)

            NotificationsView()
                .tabItem { Label("通知", systemImage: "bell") }
                .tag(2)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .modifier(ClipBoardLinkDialog())
        .task {
            // 启动时请求通知权限并拉一次未读（对应 Android NotifyJobService 的轻量替代）
            _ = await NotifyScheduler.requestPermission()
            await NotifyScheduler.pollOnce()
        }
    }
}
