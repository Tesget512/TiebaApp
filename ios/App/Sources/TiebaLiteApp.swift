import SwiftUI

@main
struct TiebaLiteApp: App {
    @StateObject private var appState = AppState()

    init() {
        // 屏幕参数喂给 CommonRequest 的 scr_w/scr_h（对应 Android BaseActivity.getDeviceDensity）
        UIScreenCompat.pixelSize = UIScreen.main.nativeBounds.size
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}
