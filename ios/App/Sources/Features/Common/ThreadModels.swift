import Foundation

/// ThreadInfo 的 UI 辅助扩展（对应 Android `StringUtil` / `Extensions` 的取值逻辑）
extension Tieba_ThreadInfo {
    /// 帖子的**业务 id**（tid）。
    ///
    /// 注意：贴吧的 `ThreadInfo` 有两个 id 字段——
    /// - `id`（proto 字段 1）：主题帖的 tid，`/c/f/pb/page` 的 `kz` 要用它
    /// - `threadID`（proto 字段 2）：部分接口（如 store_thread）返回的记录 id
    ///
    /// Android 端导航统一用 `id`（见 `ThreadInfo.id` 的取值），iOS 必须一致，
    /// 否则帖子详情页会拉到错误内容或直接 404。
    var tid: Int64 { id != 0 ? id : threadID }

    var displayAuthorName: String {
        if !author.nameShow.isEmpty { return author.nameShow }
        return author.name
    }

    /// 头像 URL：`http://tb.himg.baidu.com/sys/portrait/item/{portrait}`
    var authorAvatarURL: URL? { Self.portraitURL(author.portrait) }

    static func portraitURL(_ portrait: String) -> URL? {
        guard !portrait.isEmpty else { return nil }
        if portrait.hasPrefix("http://") || portrait.hasPrefix("https://") { return URL(string: portrait) }
        return URL(string: "http://tb.himg.baidu.com/sys/portrait/item/\(portrait)")
    }

    /// 相对时间（Android `lastTimeInt` 为 unix 秒）
    var relativeTime: String {
        guard lastTimeInt > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(lastTimeInt))
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    /// 摘要：`richAbstract` 里 type 0/9/27/35/40 的文本（Android `abstractText` 逻辑）
    var abstractText: String {
        richAbstract.filter { [0, 9, 27, 35, 40].contains(Int($0.type)) }
            .map(\.text)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 缩略图列表（最多 3 张，对应 FeedCard ThreadMedia）
    var mediaURLs: [URL] {
        media.prefix(3).compactMap { m in
            // Android ImageUtil.getUrl(isSmallPic=true)：bigPic > srcPic > originPic 第一个非空
            let candidates = [m.bigPic, m.srcPic, m.originPic]
            let urlStr = candidates.first { !$0.isEmpty } ?? ""
            return urlStr.isEmpty ? nil : URL(string: urlStr)
        }
    }

    var videoThumbnailURL: URL? {
        videoInfo.thumbnailURL.isNotEmpty ? URL(string: videoInfo.thumbnailURL) : nil
    }

    /// 是否是投票帖（poll_info 存在且 options 非空即视为投票帖）
    var isPoll: Bool { hasPollInfo && !pollInfo.options.isEmpty }

    /// 是否直播帖（Android 列表过滤用）
    var isLive: Bool { alaInfo.liveID != 0 }

    /// 是否置顶（Android 会单独渲染）
    var isTopThread: Bool { isTop != 0 }
}

extension Tieba_Post {
    var displayAuthorName: String {
        if !author.nameShow.isEmpty { return author.nameShow }
        return author.name
    }
    var authorAvatarURL: URL? { Tieba_ThreadInfo.portraitURL(author.portrait) }
}

extension Tieba_SubPostList {
    var displayAuthorName: String {
        if !author.nameShow.isEmpty { return author.nameShow }
        return author.name
    }
    var authorAvatarURL: URL? { Tieba_ThreadInfo.portraitURL(author.portrait) }
}

extension String {
    var isNotEmpty: Bool { !isEmpty }
}

/// 数字缩写（Android getShortNumString：>=10000 → x.xW）
func shortNum(_ n: Int64) -> String {
    if n >= 10000 {
        return String(format: "%.1fW", Double(n) / 10000)
    }
    return String(n)
}

/// Unix 秒 → 相对时间描述
func relativeTime(fromUnixSeconds seconds: Int64) -> String {
    guard seconds > 0 else { return "" }
    let date = Date(timeIntervalSince1970: TimeInterval(seconds))
    let fmt = RelativeDateTimeFormatter()
    fmt.locale = Locale(identifier: "zh_CN")
    return fmt.localizedString(for: date, relativeTo: Date())
}

/// Unix 秒 → 绝对时间
func formattedTime(fromUnixSeconds seconds: Int64) -> String {
    guard seconds > 0 else { return "" }
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "zh_CN")
    fmt.dateFormat = "yyyy-MM-dd HH:mm"
    return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
}
