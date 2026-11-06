import Foundation

/// ThreadInfo 的 UI 辅助扩展（对应 Android StringUtil/Extensions 的取值逻辑）
extension Tieba_ThreadInfo {
    var displayAuthorName: String {
        author.nameShow.isEmpty ? author.name : author.nameShow
    }

    /// 头像 URL：http://tb.himg.baidu.com/sys/portrait/item/{portrait}
    var authorAvatarURL: URL? {
        let p = author.portrait
        guard !p.isEmpty else { return nil }
        if p.hasPrefix("http://") || p.hasPrefix("https://") { return URL(string: p) }
        return URL(string: "http://tb.himg.baidu.com/sys/portrait/item/\(p)")
    }

    /// 相对时间（Android lastTimeInt 为 unix 秒）
    var relativeTime: String {
        guard lastTimeInt > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(lastTimeInt))
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    /// 摘要：richAbstract 里 type 0/40 文本（Android abstractText 逻辑的简化版）
    var abstractText: String {
        richAbstract.filter { [0, 9, 27, 35, 40].contains(Int($0.type)) }
            .map { $0.text }
            .joined(separator: " ")
            .replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
    }

    /// 缩略图列表（最多 3 张，对应 FeedCard ThreadMedia）
    var mediaURLs: [URL] {
        media.prefix(3).compactMap { m -> URL? in
            // Android ImageUtil.getUrl(isSmallPic=true)：originPic > bigPic > srcPic 第一个非空
            let candidates = [m.originPic, m.bigPic, m.srcPic]
            let urlStr = candidates.first { !$0.isEmpty } ?? ""
            return urlStr.isEmpty ? nil : URL(string: urlStr)
        }
    }

    var videoThumbnailURL: URL? {
        guard videoInfo.thumbnailURL.isNotEmpty else { return nil }
        return URL(string: videoInfo.thumbnailURL)
    }
}

extension String {
    var isNotEmpty: Bool { !isEmpty }
}

/// 数字缩写（Android getShortNumString：>9999 → x.xW）
func shortNum(_ n: Int64) -> String {
    if n >= 10000 {
        let v = Double(n) / 10000
        return String(format: "%.1fW", v)
    }
    return String(n)
}
