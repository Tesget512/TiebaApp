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
