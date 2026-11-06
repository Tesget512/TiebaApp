import SwiftUI

/// 我的页面（对应 Android UserPage）：登录态、头像、登出
struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            List {
                if let account = appState.account {
                    Section {
                        HStack(spacing: 12) {
                            RemoteImage(url: account.avatarURL)
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.name).font(.headline)
                                if !account.tbs.isEmpty {
                                    Text("UID: \(account.uid)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Section {
                        Button("退出登录", role: .destructive) { appState.logout() }
                    }
                } else {
                    Section {
                        Button {
                            showLogin = true
                        } label: {
                            Label("登录百度账号", systemImage: "person.crop.circle.badge.plus")
                        }
                    } footer: {
                        Text("通过百度通行证登录，客户端仅保存 BDUSS/STOKEN 用于调用贴吧接口。")
                    }
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showLogin) { LoginView() }
        }
    }
}
