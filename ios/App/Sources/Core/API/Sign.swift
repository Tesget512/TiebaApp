import Foundation
import CryptoKit

/// 请求签名：MD5(参数按名字排序后 name=value 无分隔符拼接 + "tiebaclient!!!")
/// 复刻 Android `SortAndSignInterceptor`。注意三种分支：
/// - Query 带 BDUSS：query 段排序后**无分隔符**拼接，sign 追加到 query
/// - FormBody 含 _client_version：排序 name=value 拼接，sign 追加为最后一个字段
/// - Multipart 含 _client_version part：非文件 part 按 name 排序拼接；文件 part 放最后
enum Signer {
    static let secret = "tiebaclient!!!"

    static func md5Hex(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Array(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// JSON/Form 请求的 form 签名：参数字典 → 排序拼接 → sign 字段
    static func signFormParams(_ params: [String: String]) -> [String: String] {
        var p = params
        guard p["_client_version"] != nil, p["sign"] == nil else { return p }
        let sortedRaw = p.keys.sorted().map { "\($0)=\(p[$0] ?? "")" }.joined()
        p["sign"] = md5Hex(sortedRaw + secret)
        return p
    }

    /// Multipart 请求签名（仅当含 _client_version part 时触发；V12 系列不含 → 不签名）
    /// - nonFileParts: name → 值（UTF-8 文本 part）
    /// 返回 sign 值（nil 表示无需签名）
    static func signMultipart(nonFileParts: [(name: String, value: String)]) -> String? {
        let names = nonFileParts.map(\.name)
        guard names.contains("_client_version"), !names.contains("sign") else { return nil }
        let sorted = nonFileParts.sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }.joined()
        return md5Hex(sorted + secret)
    }
}
