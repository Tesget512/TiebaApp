import Foundation
import SwiftProtobuf

/// 贴吧 protobuf API 客户端：复刻 Android `OFFICIAL_PROTOBUF_TIEBA_V12_API` 通道。
///
/// 请求格式（已亲核 Android 端拦截器链）：
/// - POST https://tiebac.baidu.com/<path>?cmd=<cmd>
/// - Headers: X-BD-Data-Type: protobuf, User-Agent: "Mozilla/... tieba/12.52.1.0",
///   Cookie: "ka=open; CUID=<cuid>; TBBRAND=<model>", CUID/CUID_GALAXY2/CUID_GID/CUID_GALAXY3,
///   CHARSET: UTF-8, CLIENT_TYPE: 2
/// - Body: ProtobufEnvelope（stoken? + data），无 sign（V12 信封无 _client_version part）
/// - 响应：protobuf 字节 → ProtoCommonResponse 探测 error_code → 目标消息解码
final class TiebaAPIClient {
    static let shared = TiebaAPIClient()

    private let session: URLSession
    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60
        cfg.httpAdditionalHeaders = [:] // 每请求单独设置
        session = URLSession(configuration: cfg)
    }

    var accountProvider: () -> Account? = { nil }

    private var userAgent: String {
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/135.0.0.0 Mobile Safari/537.36 tieba/\(CommonRequestBuilder.clientVersionV12)"
    }

    /// 通用 protobuf 请求
    /// - Parameters:
    ///   - path: 如 "/c/f/frs/page"
    ///   - cmd: 如 301001
    ///   - requestData: 已填充 common 与业务字段的 RequestData
    func request<Req: SwiftProtobuf.Message, Resp: SwiftProtobuf.Message>(
        path: String, cmd: Int, requestData: Req, responseType: Resp.Type
    ) async throws -> Resp {
        guard let url = URL(string: "https://tiebac.baidu.com\(path)?cmd=\(cmd)") else {
            throw TiebaAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let account = accountProvider()

        var headers: [String: String] = [
            "Charset": "UTF-8",
            "Client-Type": "2",
            "User-Agent": userAgent,
            "X-BD-Data-Type": "protobuf",
            "Content-Type": ProtobufEnvelope.contentType,
            "Cookie": "ka=open; CUID=\(DeviceIdentity().newCUID); TBBRAND=\(CommonRequestBuilder.deviceModel)",
            "CUID": DeviceIdentity().newCUID,
            "CUID_GALAXY2": DeviceIdentity().newCUID,
            "CUID_GID": "",
            "CUID_GALAXY3": DeviceIdentity().c3Aid,
        ]
        if let uid = account?.uid, !uid.isEmpty {
            headers["Client-User-Token"] = uid
        }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let body = ProtobufEnvelope.build(data: try requestData.serializedData(), sToken: account?.stoken)
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TiebaAPIError.httpStatus(http.statusCode)
        }

        // 先用 ProtoCommonResponse 探测错误（复刻 ProtoFailureResponseInterceptor）
        if let common = try? Tieba_ProtoCommonResponse(serializedBytes: data),
           common.hasError, common.error.errorCode != 0 {
            throw TiebaAPIError.apiError(code: Int(common.error.errorCode), message: errorMessage(common.error))
        }

        do {
            return try Resp(serializedBytes: data)
        } catch {
            throw TiebaAPIError.decoding(error)
        }
    }

    private func errorMessage(_ err: Tieba_Error) -> String {
        var parts: [String] = []
        if !err.errorMsg.isEmpty { parts.append(err.errorMsg) }
        if !err.userMsg.isEmpty { parts.append(err.userMsg) }
        return parts.isEmpty ? "错误码 \(err.errorCode)" : parts.joined(separator: " / ")
    }
}
