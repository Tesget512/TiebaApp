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

// MARK: - 表情（对应 Android EmoticonManager + EmoticonUtil：#(名字) 插入/渲染 + 网络图缓存）

/// 表情数据持久化（对应 Android `EmoticonCache`：ids + name→id mapping）
private struct EmoticonDataCache: Codable {
    var ids: [String] = []
    var mapping: [String: String] = [:]
}

/// 表情管理（Android EmoticonManager.kt 1:1）：
/// - id 区间 1..50 / 61..101 / 125..137（默认，可被持久化缓存覆盖）
/// - DEFAULT_EMOTICON_MAPPING 名字映射（重复键取最后值，与 Kotlin mapOf 一致）
/// - registerEmoticon：pb 内容 type=2（text=id, c=名字）动态注册
/// - 图片：Caches/emoticon/{id}.png 文件缓存，缺失时从 static.tieba.baidu.com 下载
/// 线程模型：NSLock 保护（注册会从数据层任意线程触发）；变更通知切主线程
final class EmoticonManager: ObservableObject {
    static let shared = EmoticonManager()

    /// `#\(([\u4e00-\u9fa5\w~]+)\)`（EmoticonUtil.REGEX 1:1；\w 在 Java/ICU 均为 ASCII 词字符）
    static let emoticonRegex = try! NSRegularExpression(pattern: #"#\(([\u4e00-\u9fa5\w~]+)\)"#)

    /// Android DEFAULT_EMOTICON_MAPPING（EmoticonManager.kt:61-121 1:1）
    private static let defaultMapping: [(name: String, id: String)] = [
        ("呵呵", "image_emoticon1"), ("哈哈", "image_emoticon2"), ("吐舌", "image_emoticon3"),
        ("啊", "image_emoticon4"), ("酷", "image_emoticon5"), ("怒", "image_emoticon6"),
        ("开心", "image_emoticon7"), ("汗", "image_emoticon8"), ("泪", "image_emoticon9"),
        ("黑线", "image_emoticon10"), ("鄙视", "image_emoticon11"), ("不高兴", "image_emoticon12"),
        ("真棒", "image_emoticon13"), ("钱", "image_emoticon14"), ("疑问", "image_emoticon15"),
        ("阴险", "image_emoticon16"), ("吐", "image_emoticon17"), ("咦", "image_emoticon18"),
        ("委屈", "image_emoticon19"), ("花心", "image_emoticon20"), ("呼~", "image_emoticon21"),
        ("笑眼", "image_emoticon22"), ("冷", "image_emoticon23"), ("太开心", "image_emoticon24"),
        ("滑稽", "image_emoticon25"), ("勉强", "image_emoticon26"), ("狂汗", "image_emoticon27"),
        ("乖", "image_emoticon28"), ("睡觉", "image_emoticon29"), ("惊哭", "image_emoticon30"),
        ("生气", "image_emoticon31"), ("惊讶", "image_emoticon32"), ("喷", "image_emoticon33"),
        ("爱心", "image_emoticon34"), ("心碎", "image_emoticon35"), ("玫瑰", "image_emoticon36"),
        ("礼物", "image_emoticon37"), ("彩虹", "image_emoticon38"), ("星星月亮", "image_emoticon39"),
        ("太阳", "image_emoticon40"), ("钱币", "image_emoticon41"), ("灯泡", "image_emoticon42"),
        ("茶杯", "image_emoticon43"), ("蛋糕", "image_emoticon44"), ("音乐", "image_emoticon45"),
        ("haha", "image_emoticon46"), ("胜利", "image_emoticon47"), ("大拇指", "image_emoticon48"),
        ("弱", "image_emoticon49"), ("OK", "image_emoticon50"),
        ("生气", "image_emoticon61"),
        ("沙发", "image_emoticon77"), ("手纸", "image_emoticon78"), ("香蕉", "image_emoticon79"),
        ("便便", "image_emoticon80"), ("药丸", "image_emoticon81"), ("红领巾", "image_emoticon82"),
        ("蜡烛", "image_emoticon83"), ("三道杠", "image_emoticon84"),
    ]

    private let lock = NSLock()
    private var _ids: [String] = []
    private var _mapping: [String: String] = [:]
    /// 内存位图缓存：key = "\(id)#\(pointSize)"
    private var imageCache: [String: UIImage] = [:]
    private var inFlight: Set<String> = []
    private let defaults = UserDefaults.standard
    private static let cacheKey = "tieba.emoticonCache"

    var emoticonIds: [String] {
        lock.lock(); defer { lock.unlock() }
        return _ids
    }

    var mapping: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return _mapping
    }

    init() {
        // Android init：有缓存用缓存，否则默认区间 + 默认映射
        if let data = defaults.data(forKey: Self.cacheKey),
           let cache = try? JSONDecoder().decode(EmoticonDataCache.self, from: data),
           !cache.ids.isEmpty {
            _ids = cache.ids
            _mapping = cache.mapping
        } else {
            var ids: [String] = []
            for i in 1...50 { ids.append("image_emoticon\(i)") }
            for i in 61...101 { ids.append("image_emoticon\(i)") }
            for i in 125...137 { ids.append("image_emoticon\(i)") }
            _ids = ids
            var m: [String: String] = [:]
            for (name, id) in Self.defaultMapping { m[name] = id } // 重复键后者覆盖（Kotlin mapOf 语义）
            _mapping = m
            persist()
        }
        prefetchMissing()
    }

    // MARK: - 查询

    /// 面板表情（Android getAllEmoticon().filter { name.isNotEmpty() }）
    var panelEmoticons: [(id: String, name: String)] {
        let ids = emoticonIds
        let m = mapping
        return ids.compactMap { id in
            guard let name = m.first(where: { $0.value == id })?.key, !name.isEmpty else { return nil }
            return (id, name)
        }
    }

    func idByName(_ name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return _mapping[name]
    }

    // MARK: - 注册（pb type=2 内容动态注册）

    /// Android registerEmoticon(id, name) 1:1；"image_emoticon" 规范化为 image_emoticon1
    func register(id: String, name: String) {
        let realId = id == "image_emoticon" ? "image_emoticon1" : id
        var changed = false
        lock.lock()
        if !_ids.contains(realId) {
            _ids.append(realId)
            changed = true
        }
        if !name.isEmpty, _mapping[name] == nil {
            _mapping[name] = realId
            changed = true
        }
        lock.unlock()
        if changed {
            if let data = try? JSONEncoder().encode(EmoticonDataCache(ids: emoticonIds, mapping: mapping)) {
                defaults.set(data, forKey: Self.cacheKey)
            }
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    // MARK: - 图片

    private var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("emoticon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(_ id: String) -> URL { cacheDir.appendingPathComponent("\(id).png") }

    /// 展示 URL（面板用）：优先本地文件缓存，否则网络地址
    func displayURL(_ id: String) -> URL {
        let f = fileURL(id)
        if FileManager.default.fileExists(atPath: f.path) { return f }
        return URL(string: "http://static.tieba.baidu.com/tb/editor/images/client/\(id).png")
            ?? f
    }

    /// 内联渲染用位图（EmoticonText 用）：未就绪返回 nil 并触发异步加载，
    /// 加载完成后 objectWillChange 驱动视图重算
    func image(id: String, pointSize: CGFloat) -> UIImage? {
        let key = "\(id)#\(Int(pointSize))"
        lock.lock()
        if let img = imageCache[key] {
            lock.unlock()
            return img
        }
        lock.unlock()
        let f = fileURL(id)
        if let source = UIImage(contentsOfFile: f.path) {
            let img = resized(source, pointSize: pointSize)
            lock.lock()
            imageCache[key] = img
            lock.unlock()
            return img
        }
        downloadIfNeeded(id)
        return nil
    }

    private func resized(_ source: UIImage, pointSize: CGFloat) -> UIImage {
        let target = max(12, pointSize * 1.2)
        if abs(source.size.width - target) < 0.5 { return source }
        let scale = target / max(1, source.size.width)
        let size = CGSize(width: target, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func downloadIfNeeded(_ id: String) {
        lock.lock()
        let busy = inFlight.contains(id)
        if !busy { inFlight.insert(id) }
        lock.unlock()
        guard !busy else { return }
        let dest = fileURL(id)
        let remote = URL(string: "http://static.tieba.baidu.com/tb/editor/images/client/\(id).png")
        Task { [weak self] in
            defer {
                if let self {
                    self.lock.lock()
                    self.inFlight.remove(id)
                    self.lock.unlock()
                }
            }
            guard let remote,
                  let (data, resp) = try? await URLSession.shared.data(from: remote),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  !data.isEmpty else { return }
            try? data.write(to: dest, options: .atomic)
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    /// 预下载全部缺失表情（Android fetchEmoticons 1:1；串行避免瞬时 76 请求）
    private func prefetchMissing() {
        let missing = emoticonIds.filter { !FileManager.default.fileExists(atPath: fileURL($0).path) }
        Task { [weak self] in
            for id in missing {
                guard let self else { return }
                let dest = self.fileURL(id)
                guard !FileManager.default.fileExists(atPath: dest.path),
                      let remote = URL(string: "http://static.tieba.baidu.com/tb/editor/images/client/\(id).png"),
                      let (data, resp) = try? await URLSession.shared.data(from: remote),
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      !data.isEmpty else { continue }
                try? data.write(to: dest, options: .atomic)
            }
        }
    }

    private func persist() {
        lock.lock()
        let snapshot = EmoticonDataCache(ids: _ids, mapping: _mapping)
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.cacheKey)
        }
    }

    /// 清空内存位图缓存 + 表情文件缓存（设置「清除图片缓存」调用；下次渲染自动重下）
    func clearImageCache() {
        lock.lock()
        imageCache.removeAll()
        inFlight.removeAll()
        lock.unlock()
        try? FileManager.default.removeItem(at: cacheDir)
        DispatchQueue.main.async { self.objectWillChange.send() }
    }
}

/// 内联表情文本渲染（对应 Android `String.emoticonString` + EmoticonText）：
/// `#(名字)` 匹配段替换为行内图片；未知名/未加载时保留原文本
struct EmoticonText: View {
    let text: String
    var font: Font = .body
    var pointSize: CGFloat = 17
    var color: Color = .primary
    var lineLimit: Int? = nil

    @ObservedObject private var mgr = EmoticonManager.shared

    private enum Seg {
        case plain(String)
        case emoticon(raw: String, name: String, id: String?)
    }

    private var segments: [Seg] {
        let ns = text as NSString
        let matches = EmoticonManager.emoticonRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [.plain(text)] }
        var result: [Seg] = []
        var cursor = 0
        for m in matches {
            if m.range.location > cursor {
                result.append(.plain(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))))
            }
            let name = ns.substring(with: m.range(at: 1))
            result.append(.emoticon(raw: ns.substring(with: m.range), name: name, id: mgr.idByName(name)))
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            result.append(.plain(ns.substring(from: cursor)))
        }
        return result
    }

    var body: some View {
        let composed = segments.reduce(Text("")) { acc, seg in
            switch seg {
            case .plain(let s):
                return acc + Text(s)
            case .emoticon(let raw, _, let id):
                if let id, let img = mgr.image(id: id, pointSize: pointSize) {
                    return acc + Text(Image(uiImage: img))
                }
                return acc + Text(raw)
            }
        }
        composed
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
    }
}

/// 回复面板的表情网格（Android ReplyPage.EmoticonPanel 1:1：仅显示有名字的表情，
/// 自适应 48pt 网格，插入 "#(名字)"）
struct EmoticonPanel: View {
    let onPick: (String) -> Void
    @ObservedObject private var mgr = EmoticonManager.shared

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 0) {
                ForEach(mgr.panelEmoticons, id: \.id) { e in
                    Button {
                        onPick("#(\(e.name))")
                    } label: {
                        AsyncImage(url: mgr.displayURL(e.id)) { img in
                            img.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Color(.systemGray6)
                        }
                        .frame(width: 32, height: 32)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)
        }
        .frame(height: 220)
        .background(Color(.systemBackground))
    }
}

// MARK: - 本地通知调度（对应 Android NotifyJobService 的 iOS 等价实现）

/// 通知未读数状态（Android MainPage 底栏 badge=messageCount 对齐）
@MainActor
final class NotifyBadge: ObservableObject {
    static let shared = NotifyBadge()
    @Published var count: Int = 0
}

/// iOS 无常驻 JobService；用 BGTask 不可靠，改为「前台/切后台时拉一次未读数，
/// 有新消息就发本地通知」+ 设置里的开关。对应 Android 30 分钟轮询的轻量替代。
enum NotifyScheduler {
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    /// 拉未读数：更新底栏角标（不依赖通知授权）+ 对 reply/at 发本地通知（需授权）
    static func pollOnce() async {
        guard let _ = TiebaJSONClient.shared.accountProvider(), !AccountUtil.cookieHeader().isEmpty else { return }
        guard let resp = try? await TiebaWriteEndpoints.unreadCount() else { return }
        let reply = resp.msg?.replyme?.value ?? 0
        let at = resp.msg?.atme?.value ?? 0
        await MainActor.run { NotifyBadge.shared.count = Int(reply + at) }
        guard await currentlyAuthorized() else { return }
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
//
// iOS 不能像 Android 那样随便读剪贴板：直接读 `UIPasteboard.general.string`
// 会触发系统「允许粘贴」横幅，每次回前台都弹（用户反馈"反反复复提示"）。
// 改用 iOS 16+ `detectValues(.probableWebURL)`：系统侧识别 URL，不弹横幅、
// 不需要粘贴授权；拿到 URL 即可解析跳转，全程零读取。

enum ClipBoardLinkDetector {
    struct ParsedLink: Equatable {
        var url: String
        var threadId: Int64?
        var forumName: String?
    }

    /// 无横幅检测：仅当剪贴板里能识别出 Web URL 时返回
    /// （SDK 仅提供 completionHandler 版本，此处包一层 continuation）
    static func detectAsync() async -> ParsedLink? {
        guard UIPasteboard.general.hasStrings else { return nil }
        let values: [UIPasteboard.DetectionPattern: Any]? = await withCheckedContinuation { cont in
            UIPasteboard.general.detectValues(for: [.probableWebURL]) { result in
                switch result {
                case .success(let v): cont.resume(returning: v)
                case .failure: cont.resume(returning: nil)
                }
            }
        }
        guard let url = values?[.probableWebURL] as? URL else { return nil }
        return parse(url: url)
    }

    /// 识别 tieba.baidu.com 的 /p/{tid}、/f?kw=、/mo/q/m?word= 链接
    /// （对齐 Android isTiebaDomain + parseLink）
    static func parse(url: URL) -> ParsedLink? {
        guard let host = url.host?.lowercased() else { return nil }
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

        var result = ParsedLink(url: url.absoluteString, threadId: nil, forumName: nil)
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
/// 同一链接只提示一次（防反复打扰）；检测全程不触发系统粘贴横幅
struct ClipBoardLinkDialog: ViewModifier {
    @State private var link: ClipBoardLinkDetector.ParsedLink?
    @State private var lastOffered = ""

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                guard let l = await ClipBoardLinkDetector.detectAsync() else { return }
                guard l.url != lastOffered else { return }
                lastOffered = l.url
                link = l
            }
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
