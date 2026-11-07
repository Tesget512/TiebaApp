import SwiftUI

/// iOS 16 兼容的占位视图（ContentUnavailableView 是 iOS 17+）
struct UnavailableView: View {
    let title: String
    let systemImage: String
    var description: String = ""
    /// 重试回调（提供后显示"重试"按钮，网络失败页用）
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            if !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let retry {
                Button {
                    retry()
                } label: {
                    Text("重试")
                        .font(.footnote.bold())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
