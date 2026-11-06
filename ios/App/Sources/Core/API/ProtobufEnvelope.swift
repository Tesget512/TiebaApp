import Foundation

/// protobuf 请求的 multipart 信封：1:1 复刻 Android `buildProtobufRequestBody` +
/// `MyMultipartBody` 的线上字节格式。
///
/// 关键事实（已亲核 Android 源码）：
/// - boundary 固定 `--------7da3d81520810*`
/// - Content-Type: `multipart/form-data; boundary=<boundary>`
/// - part 顺序：`stoken`（登录且有 stoken 时）→ `data`（filename="file"）
/// - V12/V12_POST/V22 的信封**不含** `_client_version` part（版本在 CommonRequest 里）
///   → 这类请求不签名（SortAndSignInterceptor 的 multipart 分支要求 _client_version 存在）
/// - 所有 part 一律没有 Content-Type 头
/// - form-data part 的 Content-Disposition: `form-data; name="<name>"`，
///   文件 part 追加 `; filename="file"`
enum ProtobufEnvelope {
    static let boundary = "--------7da3d81520810*"

    /// 构造与 Android MyMultipartBody 逐字节一致的请求体
    /// - Parameters:
    ///   - data: protobuf 编码后的消息字节
    ///   - sToken: 登录用户的 stoken（nil 则省略该 part）
    static func build(data: Data, sToken: String?) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }

        if let st = sToken, !st.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"stoken\"\r\n")
            append("\r\n")
            append(st)
            append("\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"data\"; filename=\"file\"\r\n")
        append("\r\n")
        body.append(data)
        append("\r\n")
        append("--\(boundary)--\r\n")
        return body
    }

    static let contentType = "multipart/form-data; boundary=\(boundary)"
}
