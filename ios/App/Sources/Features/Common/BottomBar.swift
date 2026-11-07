import SwiftUI
import Combine

// MARK: - 自定义悬浮底栏（替代系统 TabView 底栏）
//
// 为什么不用系统底栏：iOS 26 Liquid Glass 浮动底栏配合
// `.toolbar(.hidden, for: .tabBar)` 在 push/pop 时有 ~0.5s 的延迟闪现动画
// （用户验收指出）。系统底栏全程隐藏（各 tab 根视图统一隐藏），由本组件
// 提供底部导航，显隐由页面通过 `bottomBarHidden()` 声明，无动画闪现。
//
// 样式对齐系统 Liquid Glass 悬浮胶囊（用户验收要求还原悬浮观感）：
// 圆角胶囊 + 材质底 + 阴影，左右留边悬浮于内容之上；
// 内容让位由 RootView 的 safeAreaInset 承担（最后一项不再被遮挡）。

/// 页面声明隐藏底栏的 PreferenceKey（push 详情页用）
struct BottomBarHiddenKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// 详情页调用：隐藏自定义底栏（替代系统 `.toolbar(.hidden, for: .tabBar)`）
    func bottomBarHidden(_ hidden: Bool = true) -> some View {
        preference(key: BottomBarHiddenKey.self, value: hidden)
    }

    /// 悬浮条底衬：iOS 26 用系统 Liquid Glass（glassEffect），旧系统材质+阴影兜底
    @ViewBuilder
    func floatingBarBackground<S: InsettableShape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
        }
    }
}

/// 底部导航条目
struct BottomBarItem: Identifiable {
    let id: Int
    let title: String
    let icon: String
}

/// 自定义悬浮底栏（对齐 Android MainPage 底栏：发现/进吧/通知/我的）
struct CustomTabBar: View {
    let items: [BottomBarItem]
    @Binding var selection: Int
    let isHidden: Bool
    /// 通知 tab 未读数（>0 显示红点角标，Android badge 对齐）
    var unreadCount: Int = 0

    init(selection: Binding<Int>, isHidden: Bool, unreadCount: Int = 0) {
        _selection = selection
        self.isHidden = isHidden
        self.unreadCount = unreadCount
        self.items = [
            BottomBarItem(id: 0, title: "发现", icon: "safari"),
            BottomBarItem(id: 1, title: "进吧", icon: "square.grid.2x2"),
            BottomBarItem(id: 2, title: "通知", icon: "bell"),
            BottomBarItem(id: 3, title: "我的", icon: "person.crop.circle"),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    selection = item.id
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: .medium))
                            .overlay(alignment: .topTrailing) {
                                if item.id == 2, unreadCount > 0 {
                                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1.5)
                                        .background(Color.red, in: Capsule())
                                        .offset(x: 10, y: -5)
                                }
                            }
                        Text(item.title).font(.caption2.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selection == item.id ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .floatingBarBackground(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .opacity(isHidden ? 0 : 1)
        .scaleEffect(isHidden ? 0.95 : 1, anchor: .bottom)
        .allowsHitTesting(!isHidden)
        .animation(.easeInOut(duration: 0.15), value: isHidden)
    }
}
