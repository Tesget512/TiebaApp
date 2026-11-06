import Foundation

/// 贴吧 JSON 通道通用客户端：复刻 Android `OFFICIAL_TIEBA_API` / `MINI_TIEBA_API` /
/// `NEW_TIEBA_API` 三个渠道的公共参数、header 与 `SortAndSignInterceptor` 的 FormBody 签名。
///
/// 三个渠道差异（已亲核 `RetrofitTiebaApi.kt`）：
/// | 渠道 | base | UA | 公共 query/form 参数 |
/// |---|---|---|---|
/// | official | http://c.tieba.baidu.com | bdtb for Android 12.52.1.0 | from=tieba |
/// | mini | http://c.tieba.baidu.com | bdtb for Android 7.2.0.0 | from=1021636m、subapp_type=mini、cuid、cuid_galaxy2、_client_version=7.2.0.0 |
/// | new | http://c.tieba.baidu.com | bdtb for Android 8.2.2 | cuid、from=baidu_appstore、_client_version=8.2.2 |
///
/// 公共请求头（CommonHeaderInterceptor）：`client_user_token`（登录 uid）、
/// `User-Agent`；mini/new 另加 `CUID`、`CLIENT_LOG_ID`。
enum TiebaJSONChannel {
    case official
    case mini
    case new

    var base: String { "http://c.tieba.baidu.com" }

    var userAgent: String {
        switch self {
        case .official: return "bdtb for Android \(ClientVersion.v12.rawValue)"
        case .mini: return "bdtb for Android 7.2.0.0"
        case .new: return "bdtb for Android 8.2.2"
        }
    }

    /// 渠道级公共参数（Android 拦截器自动注入，参与签名）
    func commonParams() -> [String: String] {
        switch self {
        case .official:
            return ["from": "tieba"]
        case .mini:
            return [
                "from": "1021636m",
                "subapp_type": "mini",
                "cuid": DeviceIdentity.shared.newCUID,
                "cuid_galaxy2": DeviceIdentity.shared.newCUID,
                "_client_version": "7.2.0.0",
            ]
        case .new:
            return [
                "cuid": DeviceIdentity.shared.finalCUID,
                "from": "baidu_appstore",
                "_client_version": "8.2.2",
            ]
        }
    }

    /// 三个 JSON 渠道共享的 `defaultCommonParamInterceptor` 参数
    /// （RetrofitTiebaApi.kt:78-86；FormBody 非空时追加，与渠道参数合并）。
    /// 注意：`_client_type` 才是 Android Param.CLIENT_TYPE 的 wire 名
    /// （`Param` 枚举见 api/Enums.kt：CLIENT_TYPE("_client_type")）。
    static func defaultCommonParams() -> [String: String] {        let device = DeviceIdentity.shared
        return [
            "BDUSS": TiebaJSONClient.shared.accountProvider()?.bduss ?? "",
            "client_id": ClientUtils.clientId,
            "_client_type": "2",
            "_os_version": "16.0",
            "model": device.deviceModel,
            "net_type": "1",
            "phone_imei": "000000000000000",
            "timestamp": "\(Int64(Date().timeIntervalSince1970 * 1000))",
        ]
    }
}

/// JSON 通道客户端
final class TiebaJSONClient {
    static let shared = TiebaJSONClient()

    var accountProvider: () -> Account? = { nil }

    private let session: URLSession
    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60
        session = URLSession(configuration: cfg)
    }

    /// POST form-urlencoded 请求
    /// - Parameters:
    ///   - path: 如 "/c/c/forum/sign"
    ///   - params: 业务参数（与渠道公共参数合并后签名）
    ///   - forceLogin: 缺 uid 时直接抛 notLoggedIn（Android FORCE_LOGIN header）
    func post(path: String,
              params: [String: String],
              channel: TiebaJSONChannel,
              forceLogin: Bool = false) async throws -> Data {
        let account = accountProvider()
        if forceLogin, account?.uid.isEmpty ?? true { throw TiebaAPIError.notLoggedIn }

        var all = channel.commonParams()
        for (k, v) in params { all[k] = v }
        // 注入登录态（Android StParamInterceptor + AccountUtil）
        if let account {
            if !account.uid.isEmpty { all["user_id"] = all["user_id"] ?? account.uid }
            if !account.tbs.isEmpty { all["tbs"] = all["tbs"] ?? account.tbs }
            if !account.stoken.isEmpty { all["stoken"] = all["stoken"] ?? account.stoken }
        }
        // Android defaultCommonParamInterceptor：仅补齐业务参数里没有的键
        for (k, v) in TiebaJSONChannel.defaultCommonParams() where (all[k] ?? "").isEmpty {
            all[k] = v
        }
        // 签名：仅当含 _client_version（FormBody 分支条件）
        all = Signer.signFormParams(all)

        guard let url = URL(string: "\(channel.base)\(path)") else { throw TiebaAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(channel.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(DeviceIdentity.shared.newCUID, forHTTPHeaderField: "CUID")
        req.setValue("\(CommonRequestBuilder.initTime)", forHTTPHeaderField: "CLIENT_LOG_ID")
        if let uid = account?.uid, !uid.isEmpty {
            req.setValue(uid, forHTTPHeaderField: "client_user_token")
        }
        req.httpBody = Data(Self.formEncode(all).utf8)

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TiebaAPIError.httpStatus(http.statusCode)
        }
        return data
    }

    /// form 编码（Android FormBody：字段按插入序，值用 URL 表单编码，空格为 +）
    static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return params.map { k, v in
            let enc = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(k)=\(enc)"
        }.joined(separator: "&")
    }

    /// 解 JSON 并抛出贴吧错误码（对应 Android `TiebaApiException`）
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let probe = try? JSONDecoder().decode(JSONErrorProbe.self, from: data),
           let code = Int(probe.error_code?.value ?? "0"), code != 0 {
            throw TiebaAPIError.apiError(code: code,
                                        message: TiebaAPIError.errorMessage(code: code,
                                                                            msg: probe.error_msg ?? "",
                                                                            userMsg: ""))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TiebaAPIError.decoding(error)
        }
    }
}

/// 贴吧 JSON 响应错误探测（`error_code` 可能是字符串或数字）
struct JSONErrorProbe: Decodable {
    let error_code: FlexibleString?
    let error_msg: String?
    let no_error: FlexibleString?
}

/// 贴吧 JSON 响应里数字/字符串混用的容错解码（如 error_code 可能是 "0" 或 0）
struct FlexibleString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = "\(i)" }
        else if let d = try? c.decode(Double.self) { value = "\(Int(d))" }
        else { value = "" }
    }
}
