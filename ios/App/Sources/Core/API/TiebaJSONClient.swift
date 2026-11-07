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
            // 1:1 对齐 Android OFFICIAL_TIEBA_API 渠道级 CommonParamInterceptor
            // （RetrofitTiebaApi.kt:185-228：default + 渠道专属约 25 个参数）
            let device = DeviceIdentity.shared
            let now = Date()
            let cal = Calendar(identifier: .gregorian)
            let eventDay = "\(cal.component(.year, from: now))\(cal.component(.month, from: now))\(cal.component(.day, from: now))"
            var p: [String: String] = [
                "from": "tieba",
                "_client_version": ClientVersion.v12.rawValue,
                "active_timestamp": "\(ClientUtils.activeTimestamp)",
                "android_id": Data(device.androidId.utf8).base64EncodedString(),
                "baiduid": ClientUtils.baiduId,
                "brand": "Apple",
                "cmode": "1",
                "cuid": device.newCUID,
                "cuid_galaxy2": device.newCUID,
                "cuid_gid": "",
                "cuid_galaxy3": device.c3Aid,
                "event_day": eventDay,
                "extra": "",
                "first_install_time": "\(ClientUtils.firstInstallTime)",
                "framework_ver": "3340042",
                "is_teenager": "0",
                "last_update_time": "\(ClientUtils.lastUpdateTime)",
                "mac": "02:00:00:00:00:00",
                "sdk_ver": "2.34.0",
                "start_scheme": "",
                "start_type": "1",
                "swan_game_ver": "1038000",
            ]
            if !ClientUtils.sampleId.isEmpty { p["sample_id"] = ClientUtils.sampleId }
            return p
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
            "_client_id": ClientUtils.clientId,
            "_client_type": "2",
            "_os_version": "16.0",
            "model": device.deviceModel,
            "net_type": "1",
            "_phone_imei": "000000000000000",
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

    /// hybrid Web GET 通用请求（对应 Android `AppHybridTiebaApi` 的三个搜索接口：
    /// NO_ST_PARAMS + NO_COMMON_PARAMS(BDUSS/STOKEN)，带 Referer 头）
    func webGet(path: String, query: [String: String],
                referer: String? = nil) async throws -> Data {
        var comps = URLComponents(string: "https://tieba.baidu.com\(path)")!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("tieba/12.35.1.0 skin/default", forHTTPHeaderField: "User-Agent")
        req.setValue("com.baidu.tieba", forHTTPHeaderField: "X-Requested-With")
        if let referer {
            req.setValue(referer, forHTTPHeaderField: "Referer")
        }
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TiebaAPIError.httpStatus(http.statusCode)
        }
        return data
    }

    /// 搜吧 `GET /mo/q/search/forum?word=`（对应 Android searchForumFlow）
    func searchForum(keyword: String) async throws -> WebSearchForumResponse {
        let data = try await webGet(path: "/mo/q/search/forum", query: ["word": keyword],
                                    referer: "https://tieba.baidu.com/mo/q/hybrid/search?keyword=\(keyword)")
        return try TiebaJSONClient.decode(WebSearchForumResponse.self, from: data)
    }

    /// 搜用户 `GET /mo/q/search/user?word=`（对应 Android searchUserFlow）
    func searchUser(keyword: String) async throws -> WebSearchUserResponse {
        let data = try await webGet(path: "/mo/q/search/user", query: ["word": keyword],
                                    referer: "https://tieba.baidu.com/mo/q/hybrid/search?keyword=\(keyword)")
        return try TiebaJSONClient.decode(WebSearchUserResponse.self, from: data)
    }

    /// 搜帖子 `GET /mo/q/search/thread?word=&pn=&st=...`（对应 Android searchThreadFlow）
    /// - sort: 0=最旧 / 2=相关 / 5=最新（Android SearchThreadSortType）
    /// - filterTT: tt 参数（1=仅主题 / 2=全部，ForumSearchPostFilterType）
    /// - forumName: 限定吧名（吧内搜索）
    func searchThread(keyword: String, page: Int, sort: Int = 0, filterTT: Int = 1,
                      forumName: String? = nil) async throws -> WebSearchThreadResponse {
        var query = ["word": keyword, "pn": "\(page)", "st": "\(sort)", "tt": "\(filterTT)",
                     "ct": "1", "is_use_zonghe": "1", "cv": "99.9.101"]
        if let forumName, !forumName.isEmpty { query["fname"] = forumName }
        let data = try await webGet(
            path: "/mo/q/search/thread",
            query: query,
            referer: "https://tieba.baidu.com/mo/q/hybrid/search?keyword=\(keyword)")
        return try TiebaJSONClient.decode(WebSearchThreadResponse.self, from: data)
    }

    /// 热议话题详情 `GET /mo/q/newtopic/topicDetail`（HYBRID 通道 https://tieba.baidu.com）
    /// 对应 Android `AppHybridTiebaApi.topicDetail`（query：topic_id/topic_name/is_new=1/
    /// is_share=1/pn/rn=10/offset/last_id/derivative_to_pic_id=""）
    func getTopicDetail(topicId: String, topicName: String,
                        page: Int, offset: Int, lastId: String) async throws -> TopicDetailResponse {
        var comps = URLComponents(string: "https://tieba.baidu.com/mo/q/newtopic/topicDetail")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "topic_id", value: topicId),
            URLQueryItem(name: "topic_name", value: topicName),
            URLQueryItem(name: "is_new", value: "1"),
            URLQueryItem(name: "is_share", value: "1"),
            URLQueryItem(name: "pn", value: "\(page)"),
            URLQueryItem(name: "rn", value: "10"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "last_id", value: lastId),
            URLQueryItem(name: "derivative_to_pic_id", value: ""),
        ]
        comps.queryItems = items
        _ = items.popLast()
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("tieba/12.35.1.0 skin/default", forHTTPHeaderField: "User-Agent")
        req.setValue("com.baidu.tieba", forHTTPHeaderField: "X-Requested-With")
        req.setValue(AccountUtil.cookieHeader(), forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TiebaAPIError.httpStatus(http.statusCode)
        }
        return try TiebaJSONClient.decode(TopicDetailResponse.self, from: data)
    }
}

// MARK: - 话题详情响应模型（对应 Android `TopicDetailBean`）

struct TopicDetailResponse: Decodable {
    struct ThreadItem: Decodable {
        let feed_id: FlexibleInt?
        let thread_info: ThreadInfo?
    }
    struct ThreadInfo: Decodable {
        let id: FlexibleInt?
        let title: String?
        let tid: FlexibleInt?
        let forum_id: FlexibleInt?
        let forum_name: String?
        let abstract: String?
        let agree_num: FlexibleInt?
        let reply_num: FlexibleInt?
        let user_id: FlexibleInt?
        let author: Author?
    }
    struct Author: Decodable {
        let id: FlexibleInt?
        let name: String?
        let name_show: String?
        let portrait: String?
    }
    struct TopicInfo: Decodable {
        let topic_id: String?
        let topic_name: String?
        let topic_desc: String?
        let discuss_num: FlexibleInt?
        let topic_image: String?
    }
    struct Data: Decodable {
        let topic_info: TopicInfo?
        struct RelateThread: Decodable { let thread_list: [ThreadItem]? }
        let relate_thread: RelateThread?
        let has_more: Bool?
    }
    let no: FlexibleInt?
    let error: String?
    let data: Data?
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

// MARK: - hybrid 搜索响应模型（对应 Android SearchForumBean / SearchUserBean / SearchThreadBean）

/// 搜吧：`{no, error, data:{has_more, pn, fuzzy_match:[forum], exact_match:forum}}`
struct WebSearchForumResponse: Decodable {
    struct Forum: Decodable {
        let forum_id: FlexibleInt?
        let forum_name: String?
        let forum_name_show: String?
        let avatar: String?
        let post_num: FlexibleString?
        let concern_num: FlexibleString?
        let has_concerned: FlexibleInt?
        let intro: String?
        let slogan: String?
    }
    struct Data: Decodable {
        let has_more: FlexibleInt?
        let pn: FlexibleInt?
        let fuzzy_match: [Forum]?
        let exact_match: Forum?
    }
    let no: FlexibleInt?
    let error: String?
    let data: Data?

    var forums: [Forum] {
        var list = data?.fuzzy_match ?? []
        if let exact = data?.exact_match {
            list.insert(exact, at: 0)
        }
        return list
    }
}

/// 搜用户：`{no, error, data:{exact_match:User, fuzzy_match:[User]}}`
struct WebSearchUserResponse: Decodable {
    struct User: Decodable {
        let id: FlexibleString?
        let name: String?
        let user_nickname: String?
        let show_nickname: String?
        let portrait: String?
        let fans_num: FlexibleString?
        let intro: String?
    }
    struct Data: Decodable {
        let exact_match: User?
        let fuzzy_match: [User]?
    }
    let no: FlexibleInt?
    let error: String?
    let data: Data?

    var users: [User] {
        var list = data?.fuzzy_match ?? []
        if let exact = data?.exact_match {
            list.insert(exact, at: 0)
        }
        return list
    }
}

/// 搜帖子：`{no, error, data:{has_more, current_page, post_list:[thread]}}`
struct WebSearchThreadResponse: Decodable {
    struct Thread: Decodable {
        let tid: FlexibleString?
        let pid: FlexibleString?
        let title: String?
        let content: String?
        let time: FlexibleString?
        let post_num: FlexibleString?
        let like_num: FlexibleString?
        let forum_id: FlexibleString?
        let forum_name: String?
        struct User: Decodable {
            let id: FlexibleString?
            let name: String?
            let portrait: String?
        }
        let user: User?
    }
    struct Data: Decodable {
        let has_more: FlexibleInt?
        let current_page: FlexibleInt?
        let post_list: [Thread]?
    }
    let no: FlexibleInt?
    let error: String?
    let data: Data?
}
