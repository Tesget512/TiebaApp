import SwiftUI
import Combine

// MARK: - 自定义底栏（替代系统 TabView 底栏）
//
// 为什么不用系统底栏：iOS 26 Liquid Glass 浮动底栏配合
// `.toolbar(.hidden, for: .tabBar)` 在 push/pop 时有 ~0.5s 的延迟闪现动画
// （用户验收指出）。系统底栏全程隐藏（各 tab 根视图统一隐藏），由本组件
// 提供底部导航，显隐由页面通过 `bottomBarHidden()` 声明，无动画闪现。

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
}

/// 底部导航条目
struct BottomBarItem: Identifiable {
    let id: Int
    let title: String
    let icon: String
}

/// 自定义底部导航栏（对齐 Android MainPage 底栏：发现/进吧/通知/我的）
struct CustomTabBar: View {
    let items: [BottomBarItem]
    @Binding var selection: Int
    let isHidden: Bool

    init(selection: Binding<Int>, isHidden: Bool) {
        _selection = selection
        self.isHidden = isHidden
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
                    VStack(spacing: 2) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20))
                        Text(item.title).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selection == item.id ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .animation(.easeInOut(duration: 0.15), value: isHidden)
    }
}
