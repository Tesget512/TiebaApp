import Foundation
import SwiftProtobuf

/// 贴吧 protobuf API 客户端：复刻 Android 的
/// `OFFICIAL_PROTOBUF_TIEBA_V12_API` / `OFFICIAL_PROTOBUF_TIEBA_V22_API` 通道。
///
/// 请求格式（已亲核 Android `RetrofitTiebaApi.kt` + 拦截器链）：
/// - POST https://tiebac.baidu.com<path>?cmd=<cmd>
/// - Headers：Charset: UTF-8、Client-Type: 2、Client-Log-Id: <initTime>、
///   Client-User-Token: <uid>、Cookie: "ka:open; CUID:<cuid>; TBBRAND:<model>"（冒号分隔！）、
///   CUID/CUID_GALAXY2/CUID_GID/CUID_GALAXY3、User-Agent（WebView UA + " tieba/<ver>"）、
///   X-BD-Data-Type: protobuf
/// - Body：ProtobufEnvelope（V12/V22 无 _client_version part → 不签名）
/// - 响应：protobuf 字节；错误由 `ProtoCommonResponse`（`Error error = 1`）探测，
///   与 Android `ProtoFailureResponseInterceptor` 一致
final class TiebaAPIClient {
    static let shared = TiebaAPIClient()

    /// 通道配置（V12 = 读接口；V22 = 楼中楼；V12_POST = 发帖/回帖）
    struct Channel {
        var host = "https://tiebac.baidu.com"
        var clientVersion: ClientVersion = .v12
        /// 是否把公共参数注入为 multipart part（→ 触发签名）。对应 Android `OFFICIAL_PROTOBUF_TIEBA_API`
        var signed = false

        init(host: String = "https://tiebac.baidu.com", clientVersion: ClientVersion = .v12, signed: Bool = false) {
            self.host = host
            self.clientVersion = clientVersion
            self.signed = signed
        }
    }

    static let v12 = Channel()
    static let v22 = Channel(clientVersion: .v22)
    static let v12Post = Channel(clientVersion: .v12Post)

    /// 带公共参数+签名的通道（对应 Android `OFFICIAL_PROTOBUF_TIEBA_API`，
    /// 用于 userLike/hotThreadList/topicList/forumRecommend/forumGuide）。
    static let signedV12 = Channel(signed: true)

    /// 该通道注入的公共参数 part（1:1 复刻 RetrofitTiebaApi.kt:235-262 的 CommonParamInterceptor）
    static func signedChannelParts(account: Account?) -> [(name: String, value: String)] {
        let device = DeviceIdentity.shared
        let oaidJson = "{\"v\":\"\(ClientUtils.encodedOAID)\",\"sc\":0,\"sup\":0,\"isTrackLimited\":0}"
        return [
            ("_client_version", ClientVersion.v12.rawValue),
            ("_os_version", "16.0"),
            ("BDUSS", account?.bduss ?? ""),
            ("_client_id", ClientUtils.clientId),
            ("_client_type", "2"),
            ("model", device.deviceModel),
            ("net_type", "1"),
            ("_phone_imei", "000000000000000"),
            ("timestamp", "\(Int64(Date().timeIntervalSince1970 * 1000))"),
            ("cuid", device.newCUID),
            ("cuid_galaxy2", device.newCUID),
            ("cuid_gid", ""),
            ("from", "tieba"),
            ("cuid_galaxy3", device.c3Aid),
            ("oaid", oaidJson),
        ]
    }

    let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        // 15s：弱网/请求悬挂时尽快暴露错误（60s 会让"下拉刷新"转圈一分钟）
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    var accountProvider: () -> Account? = { nil }

    func request<Req: SwiftProtobuf.Message, Resp: SwiftProtobuf.Message>(
        path: String,
        cmd: Int,
        requestData: Req,
        responseType: Resp.Type,
        channel: Channel = TiebaAPIClient.v12
    ) async throws -> Resp {
        let data = try await send(path: path, cmd: cmd,
                                  body: try requestData.serializedData(), channel: channel)
        do {
            return try Resp(serializedBytes: data)
        } catch {
            throw TiebaAPIError.decoding(error)
        }
    }

    /// 底层发送：构造信封 + headers，返回校验过错误码的原始响应字节
    func send(path: String, cmd: Int, body payload: Data,
              channel: Channel = TiebaAPIClient.v12) async throws -> Data {
        guard let url = URL(string: "\(channel.host)\(path)?cmd=\(cmd)") else {
            throw TiebaAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let account = accountProvider()
        let device = DeviceIdentity.shared

        var headers: [String: String] = [
            "Charset": "UTF-8",
            "Client-Type": "2",
            "Client-Log-Id": "\(CommonRequestBuilder.initTime)",
            "User-Agent": CommonRequestBuilder.userAgent("tieba/\(channel.clientVersion.rawValue)"),
            "X-BD-Data-Type": "protobuf",
            "Content-Type": ProtobufEnvelope.contentType,
            // Android getCookie 用 "name:value" 冒号分隔（不是分号）
            "Cookie": "ka:open; CUID:\(device.newCUID); TBBRAND:\(device.deviceModel)",
            "CUID": device.newCUID,
            "CUID_GALAXY2": device.newCUID,
            "CUID_GID": "",
            "CUID_GALAXY3": device.c3Aid,
        ]
        if let uid = account?.uid, !uid.isEmpty {
            headers["Client-User-Token"] = uid
        }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        req.httpBody = ProtobufEnvelope.build(
            data: payload, sToken: account?.stoken,
            clientVersion: channel.clientVersion,
            commonParts: channel.signed ? Self.signedChannelParts(account: account) : [])

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TiebaAPIError.httpStatus(http.statusCode)
        }
        // 复刻 ProtoFailureResponseInterceptor：解析失败即视为非错误响应（归还原始 body）
        if let common = try? Tieba_ProtoCommonResponse(serializedBytes: data),
           common.hasError, common.error.errorCode != 0 {
            throw TiebaAPIError.apiError(code: Int(common.error.errorCode),
                                        message: TiebaAPIError.message(from: common.error))
        }
        return data
    }
}
