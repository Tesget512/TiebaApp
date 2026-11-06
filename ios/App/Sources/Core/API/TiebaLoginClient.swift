import Foundation

/// JSON 通道 API（对应 Android OFFICIAL_TIEBA_API 的登录部分）。
/// POST http://c.tieba.baidu.com/c/s/login，form 参数 + sign（MD5 + tiebaclient!!!）。
enum TiebaLoginClient {

    /// 用 BDUSS 换账号信息（Android fetchAccountFlow 的 /c/s/login 步骤）
    static func fetchAccount(bduss: String, stoken: String) async throws -> Account {
        var params: [String: String] = [
            "_client_id": CommonRequestBuilder.clientId,
            "_client_type": "2",
            "_client_version": CommonRequestBuilder.clientVersionV12,
            "_phone_imei": "000000000000000",
            "bdusstoken": "\(bduss)|",
            "channel_id": "",
            "channel_uid": "",
            "from": "tieba",
            "model": CommonRequestBuilder.deviceModel,
            "net_type": "1",
            "stoken": stoken,
            "timestamp": String(Int64(Date().timeIntervalSince1970 * 1000)),
        ]
        params = Signer.signFormParams(params)

        guard let url = URL(string: "http://c.tieba.baidu.com/c/s/login") else {
            throw TiebaAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("bdtb for Android \(CommonRequestBuilder.clientVersionV12)", forHTTPHeaderField: "User-Agent")
        let bodyString = params.sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Self.urlEncode($0.value))" }
            .joined(separator: "&")
        req.httpBody = Data(bodyString.utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TiebaAPIError.httpStatus(http.statusCode)
        }

        // 解析 LoginBean（对应 Android api/models/LoginBean 的核心字段）
        struct LoginResponse: Decodable {
            struct Anti: Decodable { let tbs: String? }
            struct User: Decodable {
                let id: String?
                let name: String?
                let nameShow: String?
                let portrait: String?
            }
            struct ErrorInfo: Decodable { let error_code: String?; let error_msg: String? }
            let error_code: String?
            let error_msg: String?
            let anti: Anti?
            let user: User?
        }

        let login: LoginResponse
        do {
            login = try JSONDecoder().decode(LoginResponse.self, from: data)
        } catch {
            throw TiebaAPIError.decoding(error)
        }
        if let code = Int(login.error_code ?? "0"), code != 0 {
            throw TiebaAPIError.apiError(code: code, message: login.error_msg ?? "登录失败")
        }

        var account = Account(
            uid: login.user?.id ?? "",
            name: login.user?.nameShow ?? login.user?.name ?? "",
            portrait: login.user?.portrait ?? "",
            bduss: bduss,
            stoken: stoken,
            tbs: login.anti?.tbs ?? "",
            zid: "",
            cookie: "BDUSS=\(bduss); STOKEN=\(stoken)")
        if account.name.isEmpty { account.name = "百度用户" }
        return account
    }

    private static func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
