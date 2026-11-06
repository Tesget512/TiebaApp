import Foundation
import SwiftUI
import UserNotifications
import UIKit

// MARK: - 草稿（对应 Android Room `draft` 表 + ReplyPage 的 500ms 防抖保存）

enum DraftStore {
    static func hashKey(threadId: Int64, postId: Int64, subPostId: Int64) -> String {
        let raw = "\(threadId)_\(postId)_\(subPostId)"
        return Signer.md5Hex(raw)
    }

    static func get(_ hash: String) -> String? {
        UserDefaults.standard.string(forKey: "tieba.draft.\(hash)")
    }

    static func save(_ hash: String, _ content: String) {
        if content.isEmpty { UserDefaults.standard.removeObject(forKey: "tieba.draft.\(hash)") }
        else { UserDefaults.standard.set(content, forKey: "tieba.draft.\(hash)") }
    }

    static func delete(_ hash: String) {
        UserDefaults.standard.removeObject(forKey: "tieba.draft.\(hash)")
    }
}

// MARK: - 表情（对应 Android EmoticonManager：#(名字) 插入 + 网络图渲染）

enum EmoticonManager {
    /// Android 默认表情 id 集合（EmoticonManager 默认区间 1..50, 61..101, 125..137 精选）
    static let defaultEmoticons: [(name: String, id: String)] = [
        ("呵呵", "image_emoticon1"), ("嘿嘿", "image_emoticon2"), ("吐舌", "image_emoticon3"),
        ("啊", "image_emoticon4"), ("酷", "image_emoticon5"), ("怒", "image_emoticon6"),
        ("开心", "image_emoticon7"), ("汗", "image_emoticon8"), ("泪", "image_emoticon9"),
        ("黑线", "image_emoticon10"), ("鄙视", "image_emoticon11"), ("不高兴", "image_emoticon12"),
        ("真棒", "image_emoticon13"), ("钱", "image_emoticon14"), ("疑问", "image_emoticon15"),
        ("阴脸", "image_emoticon16"), ("吐", "image_emoticon17"), ("咦", "image_emoticon18"),
        ("委屈", "image_emoticon19"), ("花心", "image_emoticon20"), ("哼", "image_emoticon21"),
        ("可爱", "image_emoticon22"), ("怒骂", "image_emoticon23"), ("滑稽", "image_emoticon25"),
        ("惊讶", "image_emoticon28"), ("搂抱", "image_emoticon29"), ("抓狂", "image_emoticon30"),
        ("暴怒", "image_emoticon31"), ("熊猫", "image_emoticon32"), ("思考", "image_emoticon33"),
        ("吐槽", "image_emoticon34"), ("昏", "image_emoticon36"), ("显摆", "image_emoticon37"),
        ("狂笑", "image_emoticon38"), ("可爱", "image_emoticon40"), ("色", "image_emoticon41"),
        ("小乖", "image_emoticon42"), ("漂亮", "image_emoticon45"), ("吃瓜", "image_emoticon47"),
        ("OK", "image_emoticon50"), ("沙发", "image_emoticon61"), ("香蕉", "image_emoticon81"),
        ("药丸", "image_emoticon85"), ("红领巾", "image_emoticon86"), ("蜡烛", "image_emoticon87"),
    ]

    /// 表情图片 URL（Android fetchEmoticons: static.tieba.baidu.com/tb/editor/images/client/{id}.png）
    static func imageURL(_ id: String) -> URL? {
        URL(string: "http://static.tieba.baidu.com/tb/editor/images/client/\(id).png")
    }
}

/// 回复面板的表情网格（插入 "#(名字)"）
struct EmoticonPanel: View {
    let onPick: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 8) {
                ForEach(EmoticonManager.defaultEmoticons, id: \.id) { e in
                    Button {
                        onPick("#(\(e.name))")
                    } label: {
                        AsyncImage(url: EmoticonManager.imageURL(e.id)) { img in
                            img.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Color(.systemGray6)
                        }
                        .frame(width: 40, height: 40)
                    }
                }
            }
            .padding(12)
        }
        .frame(height: 220)
        .background(Color(.systemBackground))
    }
}

// MARK: - 本地通知调度（对应 Android NotifyJobService 的 iOS 等价实现）

/// iOS 无常驻 JobService；用 BGTask 不可靠，改为「前台/切后台时拉一次未读数，
/// 有新消息就发本地通知」+ 设置里的开关。对应 Android 30 分钟轮询的轻量替代。
enum NotifyScheduler {
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    /// 拉未读数并对 reply/at 发本地通知（对应 NotifyJobService.onStartJob 的字段逻辑）
    static func pollOnce() async {
        guard let _ = TiebaJSONClient.shared.accountProvider(), !AccountUtil.cookieHeader().isEmpty else { return }
        guard await currentlyAuthorized() else { return }
        guard let resp = try? await TiebaWriteEndpoints.unreadCount() else { return }
        let reply = resp.msg?.replyme?.value ?? 0
        let at = resp.msg?.atme?.value ?? 0
        if reply > 0 {
            notify(id: "reply", title: "回复我的",
                   body: "你有 \(reply) 条新回复")
        }
        if at > 0 {
            notify(id: "at", title: "提到我的",
                   body: "有 \(at) 人提到了你")
        }
    }

    private static func currentlyAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    private static func notify(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - 剪贴板链接检测（对应 Android ClipBoardLinkDetector）

enum ClipBoardLinkDetector {
    struct ParsedLink: Equatable {
        var url: String
        var threadId: Int64?
        var forumName: String?
    }

    /// 识别 tieba.baidu.com 的 /p/{tid}、/f?kw=、/mo/q/m?word= 链接
    /// （对齐 Android isTiebaDomain + parseLink）
    static func detect() -> ParsedLink? {
        guard let raw = UIPasteboard.general.string, !raw.isEmpty else { return nil }
        guard let match = raw.range(of: "https?://[^\\s\"<>]+", options: .regularExpression) else { return nil }
        let link = String(raw[match])
        guard let url = URL(string: link),
              let host = url.host else { return nil }
        let ok = host == "wapp.baidu.com" || host == "tieba.baidu.com" || host == "tiebac.baidu.com"
        guard ok else { return nil }

        let path = url.path
        var query: [String: String] = [:]
        if let q = url.query {
            for pair in q.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let value = kv.count > 1
                    ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
                query[key] = value
            }
        }

        var result = ParsedLink(url: link, threadId: nil, forumName: nil)
        if path.hasPrefix("/p/") {
            result.threadId = Int64(path.dropFirst(3))
        } else if path == "/f" || path == "/mo/q/m" {
            if let kw = query["kw"] { result.forumName = kw }
            else if let word = query["word"] { result.forumName = word }
            else if let kz = query["kz"] { result.threadId = Int64(kz) }
        }
        if result.threadId == nil && result.forumName == nil { return nil }
        return result
    }
}

/// 剪贴板链接弹窗（RootView 挂载；对应 MainActivity ClipBoardDetectDialog）
struct ClipBoardLinkDialog: ViewModifier {
    @State private var link: ClipBoardLinkDetector.ParsedLink?
    @State private var lastCheck: Date = .distantPast

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            // 10s 节流（对齐 Android lastTimestamp >= 10*1000）
            guard Date().timeIntervalSince(lastCheck) >= 10 else { return }
            lastCheck = Date()
            link = ClipBoardLinkDetector.detect()
        }
        .alert("发现贴吧链接", isPresented: Binding(
            get: { link != nil }, set: { if !$0 { link = nil } })) {
            Button("打开") {
                if let l = link {
                    if let tid = l.threadId {
                        LinkNavigator.open(threadId: tid)
                    } else if let kw = l.forumName {
                        LinkNavigator.open(forumName: kw)
                    }
                }
                link = nil
            }
            Button("关闭", role: .cancel) { link = nil }
        } message: {
            Text(link?.url ?? "")
        }
    }
}

/// 从弹窗打开链接的导航辅助（RootView 提供 path）
@MainActor
enum LinkNavigator {
    static var handler: ((Int64) -> Void)?
    static var forumHandler: ((String) -> Void)?

    static func open(threadId: Int64) { handler?(threadId) }
    static func open(forumName: String) { forumHandler?(forumName) }
}
