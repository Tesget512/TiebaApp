import SwiftUI

/// 根视图：底部导航 = 自定义底栏（CustomTabBar）+ 4 个常驻 Tab 页。
/// 系统底栏在各 tab 根视图统一隐藏（iOS 26 系统 tabBar 隐藏动画有 ~0.5s 闪现，
/// 用户验收不通过）；push 详情页通过 `bottomBarHidden()` 隐藏自定义底栏。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notifyBadge = NotifyBadge.shared
    @State private var selectedTab = 0
    /// 详情页是否要求隐藏底栏（PreferenceKey 汇总）
    @State private var bottomBarHidden = false
    /// 剪贴板链接等外部跳转（sheet 承载，含关闭按钮）
    @State private var externalRoute: ExternalRoute?

    struct ExternalRoute: Identifiable {
        let id = UUID()
        let route: AppRoute
    }

    init() {
        // 启动首选页（Android HabitSettings：首页/进吧/消息）
        _selectedTab = State(initialValue: min(max(AppPreferences.shared.startPage, 0), 2))
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
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                ExploreView()
                    .tabItem { Label("发现", systemImage: "safari") }
                    .tag(0)
                    .toolbar(.hidden, for: .tabBar) // 系统底栏全程隐藏，由 CustomTabBar 接管

                HomeFeedPage()
                    .tabItem { Label("进吧", systemImage: "square.grid.2x2") }
                    .tag(1)
                    .toolbar(.hidden, for: .tabBar)

                NotificationsView()
                    .tabItem { Label("通知", systemImage: "bell") }
                    .tag(2)
                    .toolbar(.hidden, for: .tabBar)

                ProfileView()
                    .tabItem { Label("我的", systemImage: "person.crop.circle") }
                    .tag(3)
                    .toolbar(.hidden, for: .tabBar)
            }
            .onPreferenceChange(BottomBarHiddenKey.self) { bottomBarHidden = $0 }
            // 自定义悬浮底栏（隐藏声明由 TabView 内页面通过 preference 汇总上来）。
            // 注意：悬浮底栏是 ZStack 覆盖；TabView 层的 safeAreaInset 无法可靠穿透到
            // tab 内容（用户验收：列表最后一项仍被挡），内容让位由 4 个 tab 根页各自
            // safeAreaPadding(.bottom, 70) 承担。
            CustomTabBar(selection: $selectedTab, isHidden: bottomBarHidden,
                         unreadCount: notifyBadge.count)
        }
        // 强制导航栏玻璃材质跟随应用内主题（修复 iOS 26 滚动后胶囊变浅色不跟随深色）
        .toolbarColorScheme(usesDarkTheme ? .dark : .light, for: .navigationBar)
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
        #if DEBUG
        // 模拟器验收辅助（仅 Debug 构建）：simctl launch … -openThread <tid> / -openPhoto <url>
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-openThread"), i + 1 < args.count,
               let tid = Int64(args[i + 1]) {
                externalRoute = ExternalRoute(route: .thread(id: tid, title: "帖子", forumId: 0))
            }
            if let i = args.firstIndex(of: "-openPhoto"), i + 1 < args.count {
                let url = args[i + 1]
                externalRoute = ExternalRoute(route: .photoView(
                    items: [PicViewItem(id: tiebaPicId(from: url), url: url, originUrl: url)],
                    index: 0))
            }
        }
        #endif
        // 外部路由全屏呈现（Android 全页对齐；卡片式 sheet 顶部会露出黑色背景带，
        // 用户验收指出「不沉浸」），保留关闭按钮供深链场景退出
        .fullScreenCover(item: $externalRoute) { item in
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
        // 深链（Android tblite:// scheme 对齐）：tblite://thread/{tid}、tblite://forum/{kw}
        .onOpenURL { url in
            guard url.scheme == "tblite" else { return }
            let host = url.host ?? ""
            let key = url.pathComponents.count > 1 ? url.pathComponents[1] : ""
            switch host {
            case "thread":
                if let tid = Int64(key) {
                    externalRoute = ExternalRoute(route: .thread(id: tid, title: "帖子", forumId: 0))
                }
            case "forum":
                if !key.isEmpty {
                    externalRoute = ExternalRoute(route: .forum(key))
                }
            case "history":
                externalRoute = ExternalRoute(route: .history)
            case "notifications":
                selectedTab = 2
            default:
                break
            }
        }
        .task {
            // 启动时请求通知权限并拉一次未读（对应 Android NotifyJobService 的轻量替代）
            _ = await NotifyScheduler.requestPermission()
            await NotifyScheduler.pollOnce()
            // 自动签到补执行（Android OKSignService 应用内替代）
            await appState.runAutoSignIfDue()
        }
        .onChange(of: scenePhase) { phase in
            // 回前台补执行（当天已签/未到时间由方法内部判定）
            if phase == .active {
                Task {
                    await NotifyScheduler.pollOnce()
                    await appState.runAutoSignIfDue()
                }
            }
        }
    }
}
