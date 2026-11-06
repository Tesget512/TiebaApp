import Foundation

/// 账号模型：与 Android 端 Account 实体（models/database/Account.kt）字段对齐。
struct Account: Codable, Equatable {
    var uid: String
    var name: String
    var portrait: String
    var bduss: String
    var stoken: String
    var tbs: String
    var zid: String
    var cookie: String

    var avatarURL: URL? {
        guard !portrait.isEmpty else { return nil }
        if portrait.hasPrefix("http://") || portrait.hasPrefix("https://") {
            return URL(string: portrait)
        }
        return URL(string: "http://tb.himg.baidu.com/sys/portrait/item/\(portrait)")
    }
}

/// Web/JSON 通道的 Cookie 头工具（对应 Android `AccountUtil` 的 cookie 构造）
enum AccountUtil {
    /// 当前账号的 web cookie：`BDUSS=...; STOKEN=...`（无账号则返回空）
    static func cookieHeader() -> String {
        guard let a = TiebaJSONClient.shared.accountProvider() else { return "" }
        var parts: [String] = []
        if !a.bduss.isEmpty { parts.append("BDUSS=\(a.bduss)") }
        if !a.stoken.isEmpty { parts.append("STOKEN=\(a.stoken)") }
        return parts.joined(separator: "; ")
    }
}
