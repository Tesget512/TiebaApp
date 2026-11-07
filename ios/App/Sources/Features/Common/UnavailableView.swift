import SwiftUI

/// 占位视图：iOS 17 系统 ContentUnavailableView（成熟系统组件，
/// 替换此前 iOS 16 兼容期手写副本）。对外参数不变，33 处调用点零改动；
/// 提供 retry 时显示系统样式"重试"按钮。

/// 全局轻提示（消除各页面重复复制的 overlay 胶囊）
private struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            self.message = nil
                        }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: message)
    }
}

extension View {
    /// 轻提示：`.toast($toast)`（2s 自动消失）
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

/// 占位视图（系统 ContentUnavailableView 包装）
struct UnavailableView: View {
    let title: String
    let systemImage: String
    var description: String = ""
    /// 重试回调（提供后显示"重试"按钮，网络失败页用）
    var retry: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if !description.isEmpty {
                Text(description)
            }
        } actions: {
            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
