import Foundation

/// protobuf 请求的 multipart 信封：1:1 复刻 Android `buildProtobufRequestBody`
/// + `MyMultipartBody` + `SortAndSignInterceptor` 的 multipart 分支所产生的线上字节。
///
/// 关键事实（已亲核 Android `api/ProtobufRequest.kt`、`retrofit/body/MyMultipartBody.kt`、
/// `retrofit/interceptors/SortAndSignInterceptor.kt`）：
/// - boundary 固定 `--------7da3d81520810*`，Content-Type `multipart/form-data; boundary=…`
/// - part 顺序：`stoken?` → `data`（filename="file"）
/// - **V12 / V12_POST / V22 不加 `_client_version` part** → 该分支下 SortAndSignInterceptor
///   的 multipart 条件不成立（条件要求 body 含 `_client_version`）→ 这类请求不签名
/// - 其余版本会在 `data` 之前加 `_client_version` part，并在排序后追加 `sign` part
/// - 所有 part 一律不带 Content-Type（MyMultipartBody.Part.create 禁止该头）
///
/// 注：V12 通道另有一个 `Param.OAID` 公共 query 参数，但它只加到 V11 通道
/// （`RetrofitTiebaApi.kt` 中 V12 的 query 只有 `no_param=1`），不影响签名判定。
enum ProtobufEnvelope {
    static let boundary = "--------7da3d81520810*"
    static let contentType = "multipart/form-data; boundary=\(boundary)"

    /// 构造与 Android MyMultipartBody 逐字节一致的请求体
    /// - Parameters:
    ///   - data: protobuf 编码后的消息字节
    ///   - sToken: 登录用户的 stoken（nil/空 则省略该 part；对应 needSToken=true）
    ///   - clientVersion: 信封版本（V12/V12_POST/V22 省略 `_client_version` part）
    ///   - commonParts: 公共参数 part（Android `CommonParamInterceptor` 注入到 multipart 的
    ///     内容，如 `OFFICIAL_PROTOBUF_TIEBA_API` 通道的 `_client_version=12.52.1.0` 等）。
    ///     一旦非空且含 `_client_version`，信封即满足签名条件 → 自动追加 `sign` part。
    ///
    /// Android 侧同一通道的请求体组装顺序（`CommonParamInterceptor` → `SortAndSignInterceptor`）：
    /// 1. 业务构造：`stoken?` → `data(file)`
    /// 2. CommonParamInterceptor 在**末尾**追加公共 part
    /// 3. SortAndSignInterceptor 把**非文件 part**（stoken + 公共 part）按名字排序后**重新拼接**
    ///    （先移除全部再按序添加），随后追加 sign，最后才追加文件 part `data`
    /// → 因此最终 part 顺序为：`sign` 之前的非文件 part（按 name 升序）→ `sign` → `data`(file)。
    static func build(data: Data, sToken: String?, clientVersion: ClientVersion = .v12,
                      commonParts: [(name: String, value: String)] = []) -> Data {
        var body = Data()
        func text(_ s: String) { body.append(Data(s.utf8)) }
        func part(name: String, filename: String? = nil, value: Data) {
            text("--\(boundary)\r\n")
            if let filename {
                text("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
            } else {
                text("Content-Disposition: form-data; name=\"\(name)\"\r\n")
            }
            text("\r\n")
            body.append(value)
            text("\r\n")
        }

        let omitClientVersion = (clientVersion == .v12 || clientVersion == .v12Post || clientVersion == .v22)
        var nonFileParts: [(name: String, value: String)] = []

        if !omitClientVersion {
            nonFileParts.append(("_client_version", clientVersion.rawValue))
        }
        if let st = sToken, !st.isEmpty {
            nonFileParts.append(("stoken", st))
        }
        // 公共参数 part（Android CommonParamInterceptor 注入）——放在 stoken 之后
        nonFileParts.append(contentsOf: commonParts)

        // 含 _client_version 时签名（SortAndSignInterceptor multipart 分支条件）
        let needsSign = nonFileParts.contains { $0.name == "_client_version" }
        // SortAndSignInterceptor：非文件 part 按 name 排序后重排，再追加 sign，最后追加文件 part
        let ordered = needsSign ? nonFileParts.sorted { $0.name < $1.name } : nonFileParts
        for (name, value) in ordered {
            part(name: name, value: Data(value.utf8))
        }
        if needsSign, let sign = Signer.signMultipart(nonFileParts: ordered) {
            part(name: "sign", value: Data(sign.utf8))
        }

        part(name: "data", filename: "file", value: data)
        text("--\(boundary)--\r\n")
        return body
    }
}
