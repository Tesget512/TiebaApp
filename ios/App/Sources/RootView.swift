import SwiftUI

/// 根视图：底部 Tab（发现/搜索/通知/我的），未登录可用（读接口无需登录）。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ExploreView()
                .tabItem { Label("发现", systemImage: "safari") }
                .tag(0)

            NavigationStack {
                SearchPage()
            }
            .tabItem { Label("搜索", systemImage: "magnifyingglass") }
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

#Preview {
    RootView()
        .environmentObject(AppState())
}
