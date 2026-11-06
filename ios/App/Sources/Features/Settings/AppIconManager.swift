import UIKit
import SwiftUI

/// App 图标切换（对应 Android `AppIconUtil` + activity-alias 的 iOS 等价实现：
/// `UIApplication.setAlternateIconName` + `CFBundleAlternateIcons`）。
/// 选项与 Android `LauncherIcons` 对齐：新版（默认）/ 反色 / 旧版。
enum AppIcon: String, CaseIterable, Identifiable {
    case new = "AppIcon"          // 默认（新版"贴"字）
    case invert = "AppIconInvert" // 反色
    case old = "AppIconOld"       // 旧版对话气泡

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .new: return "新版"
        case .invert: return "反色"
        case .old: return "旧版"
        }
    }

    static var current: AppIcon {
        if let name = UIApplication.shared.alternateIconName,
           let icon = AppIcon(rawValue: name) {
            return icon
        }
        return .new
    }

    /// 切换图标。iOS 会弹系统确认框（无法绕过）；传 nil 恢复默认。
    static func set(_ icon: AppIcon) {
        let name = icon == .new ? nil : icon.rawValue
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                NSLog("切换图标失败: \(error.localizedDescription)")
            }
        }
    }
}

/// 图标选择器行（设置页用）
struct AppIconPicker: View {
    @State private var current = AppIcon.current

    var body: some View {
        Picker("App 图标", selection: Binding(
            get: { current },
            set: { newValue in
                guard newValue != current else { return }
                AppIcon.set(newValue)
                current = newValue
            })) {
            ForEach(AppIcon.allCases) { icon in
                Text(icon.displayName).tag(icon)
            }
        }
    }
}
