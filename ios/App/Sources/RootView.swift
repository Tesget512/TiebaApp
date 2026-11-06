import SwiftUI

/// 根视图：底部 Tab（发现/进吧/通知/我的）——对齐 Android `MainPage` 的 4 Tab 结构。
/// 搜索是发现页 toolbar 的放大镜入口（Android ExplorePage 顶部 search icon）。
/// 全局外观：主题色 tint + 夜间主题色板 + 字体缩放（对齐 Android 主题/字体全局生效）。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var selectedTab = 0
    /// 剪贴板链接等外部跳转（sheet 承载，含关闭按钮）
    @State private var externalRoute: ExternalRoute?

    struct ExternalRoute: Identifiable {
        let id = UUID()
        let route: AppRoute
    }

    /// 夜间主题：跟随系统时取系统色板，否则按用户选择的深色主题判定
    private var usesDarkTheme: Bool {
        if prefs.followSystemNight { return systemColorScheme == .dark }
        return (AppTheme(rawValue: prefs.darkTheme) ?? .greyDark).isDark
    }

    /// 全局 tint：自定义主色优先，否则当前主题主色（Android colorPrimary）
    private var tintColor: Color {
        if !prefs.customPrimaryColor.isEmpty {
            return Color(hexString: prefs.customPrimaryColor)
        }
        return (AppTheme(rawValue: prefs.darkTheme) ?? .tieba).primary
    }

    /// 字体缩放 → DynamicTypeSize（8 档映射，标准=large 基准档）
    private var dynamicSize: DynamicTypeSize {
        let s = prefs.fontScale
        if s < 0.83 { return .xSmall }
        if s < 0.88 { return .small }
        if s < 0.93 { return .medium }
        if s < 0.98 { return .large }        // iOS 默认基准
        if s < 1.03 { return .large }
        if s < 1.08 { return .xLarge }
        if s < 1.13 { return .xxLarge }
        if s < 1.20 { return .xxxLarge }
        return .accessibility1
    }

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
        .tint(tintColor)
        .preferredColorScheme(prefs.followSystemNight ? nil : (usesDarkTheme ? .dark : .light))
        .dynamicTypeSize(dynamicSize)
        .modifier(ClipBoardLinkDialog())
        // 剪贴板链接「打开」的真实跳转（对齐 Android 深链：/p/{tid} → 帖子，/f?kw= → 吧）
        .onAppear {
            guard LinkNavigator.handler == nil else { return }
            LinkNavigator.handler = { tid in
                externalRoute = ExternalRoute(route: .thread(id: tid, title: "帖子", forumId: 0))
            }
            LinkNavigator.forumHandler = { kw in
                externalRoute = ExternalRoute(route: .forum(kw))
            }
        }
        .sheet(item: $externalRoute) { item in
            NavigationStack {
                RouteView(route: item.route)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { externalRoute = nil }
                        }
                    }
            }
            .tint(tintColor)
        }
        .task {
            // 启动时请求通知权限并拉一次未读（对应 Android NotifyJobService 的轻量替代）
            _ = await NotifyScheduler.requestPermission()
            await NotifyScheduler.pollOnce()
        }
    }
}
