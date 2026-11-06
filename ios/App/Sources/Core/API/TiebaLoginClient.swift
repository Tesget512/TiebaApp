import Foundation

/// JSON 通道 API（对应 Android `OFFICIAL_TIEBA_API` 的登录相关部分）。
/// POST http://c.tieba.baidu.com/c/s/login，form 参数 + sign（MD5 + "tiebaclient!!!"）。
///
/// 该通道 = `defaultCommonParamInterceptor`（8 参数）+ 扩展 `CommonParamInterceptor`（24 参数）
/// + `StParamInterceptor`（st 统计参数），见 RetrofitTiebaApi.kt:185-231。
///
/// Android 有两条 `/c/s/login` 路径（MixedTiebaApiImpl.kt:1010-1021），登录专属字段不同：
/// - **web 登录路径** `loginFlow(bduss, sToken)` → `loginFlow("$bduss|", sToken, null)`：
///   bdusstoken 竖线后为**空串**、user_id **强制 null（Retrofit 不发送）**、stoken=WebView 抓取值。
///   登录页（LoginView）使用该路径。
/// - **无参刷新路径** `loginFlow()` → 默认值 `bdusstoken="${BDUSS}|null"`：
///   bdusstoken 竖线后为字面量 `null`、stoken=已存账号 stoken、user_id=已存账号 uid。
///   启动时账号刷新（MainActivityV2.fetchAccount）使用该路径。
enum TiebaLoginClient {

    private static let session = URLSession.shared

    // MARK: - web 登录路径

    /// 用 WebView 抓取的 BDUSS/STOKEN 换账号信息（Android LoginPage → AccountUtil.fetchAccountFlow 1:1）
    static func fetchAccount(bduss: String, stoken: String) async throws -> Account {
        var params = commonParams()
        // 登录专属字段：bdusstoken 竖线后为空串（web 路径），user_id 不发送
        params["authsid"] = "null"
        params["bdusstoken"] = "\(bduss)|"
        params["channel_id"] = ""
        params["channel_uid"] = ""
        params["stoken"] = stoken
        return try await performLogin(params: params, bduss: bduss, stoken: stoken)
    }

    // MARK: - 无参刷新路径

    /// 已有账号的启动刷新（Android MainActivityV2.fetchAccount → loginFlow() 默认参数 1:1）
    static func refreshAccount(_ account: Account) async throws -> Account {
        var params = commonParams()
        params["authsid"] = "null"
        params["bdusstoken"] = "\(account.bduss)|null" // 字面量 null（无参刷新路径）
        params["channel_id"] = ""
        params["channel_uid"] = ""
        params["stoken"] = account.stoken
        params["user_id"] = account.uid
        return try await performLogin(params: params, bduss: account.bduss, stoken: account.stoken)
    }

    // MARK: - 通道公共参数

    /// OFFICIAL_TIEBA_API 全量公共参数（RetrofitTiebaApi.kt:66-74 + 199-226 + StParamInterceptor 1:1）。
    /// BDUSS 不在内（登录接口均有 `DROP_PARAMS: BDUSS`，需要时显式加字段）。
    private static func commonParams() -> [String: String] {
        let device = DeviceIdentity.shared
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        // event_day: SimpleDateFormat("yyyyMdd")，月/日不补零
        let eventDay = "\(cal.component(.year, from: now))\(cal.component(.month, from: now))\(cal.component(.day, from: now))"
        // StParamInterceptor：num∈[100,850)；不在 [100,120] 时（~97.6%）带完整统计字段
        let num = Int.random(in: 100..<850)
        var st: [String: String] = ["stErrorNums": "0"]
        if !(100...120).contains(num) {
            st["stMethod"] = "1"
            st["stMode"] = "1"
            st["stTimesNum"] = "1"
            st["stTime"] = String(num)
            st["stSize"] = String(Int((Double.random(in: 0.4..<8.4)) * Double(num)))
        }
        var params: [String: String] = [
            // defaultCommonParamInterceptor（BDUSS 被丢弃）
            "_client_id": ClientUtils.clientId,
            "_client_type": "2",
            "_os_version": "16.0",
            "model": device.deviceModel,
            "net_type": "1",
            "_phone_imei": "000000000000000",
            "timestamp": String(Int64(now.timeIntervalSince1970 * 1000)),
            // 扩展 CommonParamInterceptor（_client_version 已由登录字段提供时不重复，
            // 这里统一带上，交给字典去重；form 编码时同名只出现一次）
            "active_timestamp": String(ClientUtils.activeTimestamp),
            "android_id": Data(device.androidId.utf8).base64EncodedString(),
            "baiduid": ClientUtils.baiduId,
            "brand": "Apple",
            "cmode": "1",
            "cuid": device.newCUID,
            "cuid_galaxy2": device.newCUID,
            "cuid_gid": "",
            "c3_aid": device.c3Aid,
            "event_day": eventDay,
            "extra": "",
            "first_install_time": String(ClientUtils.firstInstallTime),
            "framework_ver": "3340042",
            "from": "tieba",
            "is_teenager": "0",
            "last_update_time": String(ClientUtils.lastUpdateTime),
            "mac": "02:00:00:00:00:00",
            "sample_id": ClientUtils.sampleId,
            "sdk_ver": "2.34.0",
            "start_scheme": "",
            "start_type": "1",
            "swan_game_ver": "1038000",
            "_client_version": ClientVersion.v12.rawValue,
            "oaid": "{\"v\":\"\(ClientUtils.encodedOAID)\",\"sc\":0,\"sup\":0,\"isTrackLimited\":0}",
        ]
        for (k, v) in st { params[k] = v }
        return params
    }

    /// OFFICIAL_TIEBA_API 请求头（RetrofitTiebaApi.kt:188-198 1:1）。
    /// `httpShouldHandleCookies = false`：OkHttp 无 CookieJar 自动附带行为，
    /// 关闭 URLSession 自动合并 HTTPCookieStorage 里可能残留的旧百度 Cookie。
    private static func makeRequest(url: URL, params: [String: String]) -> URLRequest {
        let device = DeviceIdentity.shared
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpShouldHandleCookies = false
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("bdtb for Android \(ClientVersion.v12.rawValue)", forHTTPHeaderField: "User-Agent")
        req.setValue("CUID=\(device.newCUID);ka=open;TBBRAND=\(device.deviceModel);BAIDUID=\(ClientUtils.baiduId);",
                     forHTTPHeaderField: "Cookie")
        req.setValue(device.newCUID, forHTTPHeaderField: "cuid")
        req.setValue(device.newCUID, forHTTPHeaderField: "cuid_galaxy2")
        req.setValue("", forHTTPHeaderField: "cuid_gid")
        req.setValue(device.c3Aid, forHTTPHeaderField: "c3_aid")
        req.setValue("2", forHTTPHeaderField: "client_type")
        req.setValue("UTF-8", forHTTPHeaderField: "charset")
        req.setValue(String(CommonRequestBuilder.initTime), forHTTPHeaderField: "client_log_id")
        req.httpBody = Data(TiebaJSONClient.formEncode(Signer.signFormParams(params)).utf8)
        return req
    }

    // MARK: - 请求与解析

    private static func performLogin(params: [String: String], bduss: String,
                                     stoken: String) async throws -> Account {
        guard let url = URL(string: "http://c.tieba.baidu.com/c/s/login") else {
            throw TiebaAPIError.invalidURL
        }
        let req = makeRequest(url: url, params: params)
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
        return await completeLoginChain(account)
    }

    /// 登录后链路（Android `AccountUtil.fetchAccountFlow` 的 zip 顺序 1:1）：
    /// initNickname（结果不阻断）→ getuserinfo 补 nameShow/portrait。
    private static func completeLoginChain(_ account: Account) async -> Account {
        var acc = account
        // 1. /c/s/initNickname（Android loginFlow 与 initNickNameFlow 同步 zip 调用）
        await initNickname(bduss: acc.bduss, stoken: acc.stoken)
        // 2. 用户信息（Android getUserInfoFlow 刷新 nameShow/portrait；失败不阻断）
        let client = TiebaAPIClient()
        client.accountProvider = { acc }
        if let profile = try? await TiebaEndpoints.userProfile(
            client: client, uid: Int64(acc.uid) ?? 0,
            selfUid: Int64(acc.uid) ?? 0, isSelf: true) {
            if !profile.user.nameShow.isEmpty { acc.name = profile.user.nameShow }
            else if !profile.user.name.isEmpty { acc.name = profile.user.name }
            if !profile.user.portrait.isEmpty { acc.portrait = profile.user.portrait }
        }
        return acc
    }

    /// `/c/s/initNickname`（Android OfficialTiebaApi.initNickNameFlow 1:1：
    /// 显式 BDUSS/stoken 字段 + `NO_COMMON_PARAMS: BDUSS`；失败不影响登录）
    private static func initNickname(bduss: String, stoken: String) async {
        var params = commonParams()
        params["BDUSS"] = bduss
        params["stoken"] = stoken
        guard let url = URL(string: "http://c.tieba.baidu.com/c/s/initNickname") else { return }
        let req = makeRequest(url: url, params: params)
        _ = try? await session.data(for: req)
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
