import Foundation

/// JSON 通道 API（对应 Android `OFFICIAL_TIEBA_API` 的登录相关部分）。
/// POST http://c.tieba.baidu.com/c/s/login，form 参数 + sign（MD5 + "tiebaclient!!!"）。
enum TiebaLoginClient {

    private static let session = URLSession.shared

    /// 用 BDUSS/STOKEN 换账号信息（Android `OfficialTiebaApi.loginFlow` 1:1 对齐）
    static func fetchAccount(bduss: String, stoken: String) async throws -> Account {
        // Android 字面量：bdusstoken = "${BDUSS}|null"（竖线后是字面量 null，不是 stoken！）
        // 参数集 = defaultCommonParamInterceptor（drop BDUSS）+ login 专属字段
        var params: [String: String] = [
            "_client_id": ClientUtils.clientId,
            "_client_type": "2",
            "_client_version": ClientVersion.v12.rawValue,
            "_os_version": "16.0",
            "_phone_imei": "000000000000000",
            "bdusstoken": "\(bduss)|null",
            "channel_id": "",
            "channel_uid": "",
            "from": "tieba",
            "model": DeviceIdentity.shared.deviceModel,
            "net_type": "1",
            "timestamp": String(Int64(Date().timeIntervalSince1970 * 1000)),
            "authsid": "null",
        ]
        // Android: @Field("user_id") = AccountUtil.getUid()，首次登录为 null → Retrofit 不发送该字段
        if let uid = TiebaJSONClient.shared.accountProvider()?.uid, !uid.isEmpty {
            params["user_id"] = uid
        }
        // Android: @Field("stoken") sToken = AccountUtil.getSToken()!!（登录前为空串，照发）
        params["stoken"] = stoken
        params = Signer.signFormParams(params)

        guard let url = URL(string: "http://c.tieba.baidu.com/c/s/login") else {
            throw TiebaAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("bdtb for Android \(ClientVersion.v12.rawValue)", forHTTPHeaderField: "User-Agent")
        req.httpBody = Data(TiebaJSONClient.formEncode(params).utf8)

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TiebaAPIError.httpStatus(http.statusCode)
        }

        struct LoginResponse: Decodable {
            struct Anti: Decodable { let tbs: FlexibleString?; let tbs_string: String? }
            struct User: Decodable {
                let id: FlexibleString?
                let name: String?
                let nameShow: String?
                let name_show: String?
                let portrait: String?
            }
            let error_code: FlexibleString?
            let error_msg: String?
            let anti: Anti?
            let user: User?
            /// 反垃圾/风控校验提示
            let anti_tbs: String?
        }

        let login: LoginResponse
        do {
            login = try JSONDecoder().decode(LoginResponse.self, from: data)
        } catch {
            throw TiebaAPIError.decoding(error)
        }
        let code = Int(login.error_code?.value ?? "0") ?? 0
        if code != 0 {
            // 带上错误码便于排查（如 300004=BDUSS 无效）
            throw TiebaAPIError.apiError(code: code,
                                         message: "[code \(code)] \(login.error_msg ?? "登录失败")")
        }

        var account = Account(
            uid: login.user?.id?.value ?? "",
            name: login.user?.nameShow ?? login.user?.name_show ?? login.user?.name ?? "",
            portrait: login.user?.portrait ?? "",
            bduss: bduss,
            stoken: stoken,
            tbs: login.anti?.tbs?.value ?? login.anti?.tbs_string ?? "",
            zid: "",
            cookie: "BDUSS=\(bduss); STOKEN=\(stoken)")
        if account.name.isEmpty { account.name = "百度用户" }
        return account
    }

    /// 从 Cookie 串解析 BDUSS/STOKEN（WKWebView 抓取后调用）
    static func parseCookies(_ cookieHeader: String) -> (bduss: String, stoken: String) {
        var bduss = "", stoken = ""
        for pair in cookieHeader.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let k = kv[0].trimmingCharacters(in: .whitespaces)
            let v = kv[1].trimmingCharacters(in: .whitespaces)
            if k == "BDUSS" { bduss = v }
            if k == "STOKEN" { stoken = v }
        }
        return (bduss, stoken)
    }
}
