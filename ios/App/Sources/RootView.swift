import SwiftUI

/// 根视图：底部 Tab（发现/进吧/通知/我的），未登录时显示登录入口。
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ExploreView()
                .tabItem {
                    Image(systemName: "safari")
                    Text("发现")
                }
                .tag(0)

            MyForumsView()
                .tabItem {
                    Image(systemName: "square.grid.2x2")
                    Text("进吧")
                }
                .tag(1)

            NotificationsView()
                .tabItem {
                    Image(systemName: "bell")
                    Text("通知")
                }
                .tag(2)

            ProfileView()
                .tabItem {
                    Image(systemName: "person.crop.circle")
                    Text("我的")
                }
                .tag(3)
        }
        .sheet(isPresented: .constant(!appState.isLoggedIn)) {
            LoginView()
        }
    }
}

struct ExploreView: View {
    var body: some View {
        NavigationStack {
            Text("发现")
                .navigationTitle("发现")
        }
    }
}

struct MyForumsView: View {
    var body: some View {
        NavigationStack {
            Text("进吧")
                .navigationTitle("进吧")
        }
    }
}

struct NotificationsView: View {
    var body: some View {
        NavigationStack {
            Text("通知")
                .navigationTitle("通知")
        }
    }
}

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            Text("我的")
                .navigationTitle("我的")
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("登录百度账号")
                    .font(.title2.bold())
                Text("通过百度通行证页面登录，客户端仅获取 BDUSS/STOKEN Cookie。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("打开登录页") {
                    // TODO(P4): 打开 WKWebView 登录
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if appState.isLoggedIn {
                        Button("完成") { dismiss() }
                    }
                }
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}
