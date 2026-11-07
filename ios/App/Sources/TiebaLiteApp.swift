import SwiftUI

@main
struct TiebaLiteApp: App {
    @StateObject private var appState = AppState()

    init() {
        // 屏幕参数喂给 CommonRequest 的 scr_w/scr_h（对应 Android BaseActivity.getDeviceDensity）
        UIScreenCompat.pixelSize = UIScreen.main.nativeBounds.size
        // 图片缓存扩容（默认 URLCache 太小导致列表图片反复重下；Android 用 Fresco/OkHttp 大缓存）
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024,
                                   diskPath: "tieba_url_cache")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}
