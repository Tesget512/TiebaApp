import SwiftUI
import Combine

/// 应用设置（对应 Android `AppPreferencesUtils` 的 iOS 版）。
/// UserDefaults 持久化；键名尽量与 Android 对齐，便于对照。
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private let d = UserDefaults.standard

    // MARK: - 主题
    @Published var theme: String { didSet { d.set(theme, forKey: "theme") } }
    @Published var darkTheme: String { didSet { d.set(darkTheme, forKey: "dark_theme") } }
    @Published var followSystemNight: Bool { didSet { d.set(followSystemNight, forKey: "follow_system_night") } }
    @Published var customPrimaryColor: String { didSet { d.set(customPrimaryColor, forKey: "custom_primary_color") } }

    // MARK: - 外观/阅读
    @Published var fontScale: Double { didSet { d.set(fontScale, forKey: "fontScale") } }
    @Published var hideMedia: Bool { didSet { d.set(hideMedia, forKey: "hideMedia") } }
    @Published var imageDarkenWhenNightMode: Bool { didSet { d.set(imageDarkenWhenNightMode, forKey: "imageDarkenWhenNightMode") } }
    @Published var listSingle: Bool { didSet { d.set(listSingle, forKey: "listSingle") } }

    // MARK: - 行为
    @Published var safeMode: Bool { didSet { d.set(safeMode, forKey: "safeMode") } }
    @Published var incognitoMode: Bool { didSet { d.set(incognitoMode, forKey: "incognitoMode") } }
    @Published var hideBlockedContent: Bool { didSet { d.set(hideBlockedContent, forKey: "hideBlockedContent") } }
    @Published var blockVideo: Bool { didSet { d.set(blockVideo, forKey: "blockVideo") } }
    @Published var showExperimentalFeatures: Bool { didSet { d.set(showExperimentalFeatures, forKey: "showExperimentalFeatures") } }
    @Published var littleTail: String { didSet { d.set(littleTail, forKey: "little_tail") } }

    // MARK: - 一键签到
    @Published var autoSign: Bool { didSet { d.set(autoSign, forKey: "auto_sign") } }
    @Published var autoSignTime: String { didSet { d.set(autoSignTime, forKey: "auto_sign_time") } }
    @Published var oksignSlowMode: Bool { didSet { d.set(oksignSlowMode, forKey: "oksign_slow_mode") } }
    @Published var oksignUseOfficialOksign: Bool { didSet { d.set(oksignUseOfficialOksign, forKey: "oksign_use_official_oksign") } }
    @Published var oksignFailAutoStop: Bool { didSet { d.set(oksignFailAutoStop, forKey: "oksign_fail_auto_stop") } }
    @Published var signDay: Int { didSet { d.set(signDay, forKey: "sign_day") } }

    // MARK: - 使用习惯（对齐 Android HabitSettingsPage）
    /// 图片加载：0 智能加载 / 1 全部原图 / 2 全部不加载
    @Published var imageLoadMode: Int { didSet { d.set(imageLoadMode, forKey: "image_load_mode") } }
    /// 图片水印：0 无 / 1 用户名 / 2 吧名
    @Published var watermarkType: Int { didSet { d.set(watermarkType, forKey: "watermark_type") } }
    /// 进吧页吧列表排序：0 热度 / 1 发帖时间 / 2 等级 / 3 名称
    @Published var homeForumSort: Int { didSet { d.set(homeForumSort, forKey: "home_forum_sort") } }
    @Published var showRecentForums: Bool { didSet { d.set(showRecentForums, forKey: "show_recent_forums") } }
    /// 启动首选页：0 发现 / 1 进吧 / 2 通知
    @Published var startPage: Int { didSet { d.set(startPage, forKey: "start_page") } }
    @Published var storeAutoLz: Bool { didSet { d.set(storeAutoLz, forKey: "store_auto_lz") } }
    @Published var storeAutoDesc: Bool { didSet { d.set(storeAutoDesc, forKey: "store_auto_desc") } }
    /// 只推荐已关注的吧（推荐流过滤）
    @Published var onlyRecommendFollowed: Bool { didSet { d.set(onlyRecommendFollowed, forKey: "only_recommend_followed") } }

    private init() {
        theme = d.string(forKey: "theme") ?? "tieba"
        darkTheme = d.string(forKey: "dark_theme") ?? "grey_dark"
        followSystemNight = d.object(forKey: "follow_system_night") as? Bool ?? true
        customPrimaryColor = d.string(forKey: "custom_primary_color") ?? ""
        fontScale = d.object(forKey: "fontScale") as? Double ?? 1.0
        hideMedia = d.object(forKey: "hideMedia") as? Bool ?? false
        imageDarkenWhenNightMode = d.object(forKey: "imageDarkenWhenNightMode") as? Bool ?? true
        listSingle = d.object(forKey: "listSingle") as? Bool ?? false
        safeMode = d.object(forKey: "safeMode") as? Bool ?? true
        incognitoMode = d.object(forKey: "incognitoMode") as? Bool ?? false
        hideBlockedContent = d.object(forKey: "hideBlockedContent") as? Bool ?? false
        blockVideo = d.object(forKey: "blockVideo") as? Bool ?? false
        showExperimentalFeatures = d.object(forKey: "showExperimentalFeatures") as? Bool ?? false
        littleTail = d.string(forKey: "little_tail") ?? ""
        autoSign = d.object(forKey: "auto_sign") as? Bool ?? false
        autoSignTime = d.string(forKey: "auto_sign_time") ?? "09:00"
        oksignSlowMode = d.object(forKey: "oksign_slow_mode") as? Bool ?? true
        oksignUseOfficialOksign = d.object(forKey: "oksign_use_official_oksign") as? Bool ?? true
        oksignFailAutoStop = d.object(forKey: "oksign_fail_auto_stop") as? Bool ?? true
        signDay = d.object(forKey: "sign_day") as? Int ?? -1
        imageLoadMode = d.object(forKey: "image_load_mode") as? Int ?? 0
        watermarkType = d.object(forKey: "watermark_type") as? Int ?? 0
        homeForumSort = d.object(forKey: "home_forum_sort") as? Int ?? 0
        showRecentForums = d.object(forKey: "show_recent_forums") as? Bool ?? true
        startPage = d.object(forKey: "start_page") as? Int ?? 0
        storeAutoLz = d.object(forKey: "store_auto_lz") as? Bool ?? false
        storeAutoDesc = d.object(forKey: "store_auto_desc") as? Bool ?? false
        onlyRecommendFollowed = d.object(forKey: "only_recommend_followed") as? Bool ?? false
    }
}

/// 主题枚举（对应 Android `ThemeUtil` 的 theme 字符串集合 + arrays.xml）
enum AppTheme: String, CaseIterable, Identifiable {
    case tieba, blue, black, pink, red, purple
    case blueDark = "blue_dark"
    case greyDark = "grey_dark"
    case amoledDark = "amoled_dark"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .tieba: return "深海蓝"
        case .blue: return "清新蓝"
        case .black: return "高级黑"
        case .pink: return "少女粉"
        case .red: return "新年红"
        case .purple: return "星空紫"
        case .blueDark: return "静谧蓝"
        case .greyDark: return "深邃灰"
        case .amoledDark: return "纯黑"
        }
    }
    var isDark: Bool { rawValue.contains("dark") }
    /// 主色（用于展示圆点；深色主题给近似色）
    var primary: Color {
        switch self {
        case .tieba: return Color(red: 0.18, green: 0.38, blue: 0.69)
        case .blue: return Color(red: 0.16, green: 0.53, blue: 0.87)
        case .black: return Color(red: 0.15, green: 0.15, blue: 0.17)
        case .pink: return Color(red: 0.91, green: 0.45, blue: 0.62)
        case .red: return Color(red: 0.85, green: 0.24, blue: 0.24)
        case .purple: return Color(red: 0.55, green: 0.36, blue: 0.78)
        case .blueDark: return Color(red: 0.24, green: 0.42, blue: 0.66)
        case .greyDark: return Color(red: 0.35, green: 0.35, blue: 0.38)
        case .amoledDark: return Color(red: 0.10, green: 0.10, blue: 0.10)
        }
    }
}

/// 字体档位（对应 Android `AppFontSizeActivity` 的 6 档）
enum FontScaleOption {
    static let scales: [Double] = [0.80, 0.85, 0.90, 0.95, 1.00, 1.05, 1.10, 1.15, 1.20, 1.25, 1.30]
    static let labels = ["小", "较小", "标准", "较大", "大", "特大"]

    static func label(for scale: Double) -> String {
        if scale < 0.88 { return labels[0] }
        if scale < 0.98 { return labels[1] }
        if scale <= 1.02 { return labels[2] }
        if scale < 1.13 { return labels[3] }
        if scale < 1.23 { return labels[4] }
        return labels[5]
    }
}
