import Foundation

/// 需要登录的 JSON 写操作与通知接口：复刻 Android `MixedTiebaApiImpl` 的
/// opAgree（MINI 通道）、sign/mSign（official/mini 通道）、通知三接口（NEW 通道）。
enum TiebaWriteEndpoints {

    // MARK: - 点赞

    /// 点赞/取消赞 `/c/c/agree/opAgree`（MINI 通道，objectType 3=帖子）
    /// - Parameters:
    ///   - opType: 0=点赞，1=取消赞
    ///   - threadId: 帖子 id（tid，即 Android 的 thread_id）
    ///   - postId: 楼层 id（pid）
    static func agree(threadId: Int64, postId: Int64, opType: Int = 0) async throws {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { throw TiebaAPIError.notLoggedIn }
        let params: [String: String] = [
            "post_id": "\(postId)",
            "thread_id": "\(threadId)",
            "_client_version": "8.0.8.0",
            "cuid_gid": "",
            "agree_type": "2",
            "obj_type": "3",
            "op_type": "\(opType)",
            "tbs": account.tbs,
            "stoken": account.stoken,
        ]
        let data = try await TiebaJSONClient.shared.post(path: "/c/c/agree/opAgree",
                                                        params: params, channel: .mini,
                                                        forceLogin: true)
        _ = try TiebaJSONClient.decode(SimpleErrorResponse.self, from: data)
    }

    // MARK: - 签到

    /// 单吧签到 `/c/c/forum/sign`（official 通道）
    static func forumSign(forumName: String, forumId: Int64 = 0) async throws {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { throw TiebaAPIError.notLoggedIn }
        let params: [String: String] = [
            "kw": forumName,
            "fid": "\(forumId)",
            "tbs": account.tbs,
            "from_widget": "0",
            "_client_version": ClientVersion.v12.rawValue,
            "stoken": account.stoken,
        ]
        let data = try await TiebaJSONClient.shared.post(path: "/c/c/forum/sign",
                                                        params: params, channel: .official,
                                                        forceLogin: true)
        _ = try TiebaJSONClient.decode(SimpleErrorResponse.self, from: data)
    }

    /// 一键签到 `/c/c/forum/msign`（official 通道）
    /// - Returns: 签到结果（含成功/失败的吧名列表）
    static func multiSign(forumIds: [Int64]) async throws -> MultiSignResponse {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { throw TiebaAPIError.notLoggedIn }
        let params: [String: String] = [
            "forum_ids": forumIds.map(String.init).joined(separator: ","),
            "tbs": account.tbs,
            "authsid": "null",
            "stoken": account.stoken,
            "user_id": account.uid,
            "_client_version": ClientVersion.v12.rawValue,
        ]
        let data = try await TiebaJSONClient.shared.post(path: "/c/c/forum/msign",
                                                        params: params, channel: .official,
                                                        forceLogin: true)
        return try TiebaJSONClient.decode(MultiSignResponse.self, from: data)
    }

    // MARK: - 通知

    /// 回复我的 `/c/u/feed/replyme`
    static func replyMe(page: Int = 0) async throws -> MessageListResponse {
        try await notify("/c/u/feed/replyme", page: page)
    }

    /// @我的 `/c/u/feed/atme`
    static func atMe(page: Int = 0) async throws -> MessageListResponse {
        try await notify("/c/u/feed/atme", page: page)
    }

    /// 赞我的 `/c/u/feed/agreeme`
    static func agreeMe(page: Int = 0) async throws -> MessageListResponse {
        try await notify("/c/u/feed/agreeme", page: page)
    }

    /// 未读消息数 `/c/s/msg`（NEW 通道，`bookmark=1`）
    static func unreadCount() async throws -> MsgResponse {
        let data = try await TiebaJSONClient.shared.post(path: "/c/s/msg",
                                                        params: ["bookmark": "1"],
                                                        channel: .new, forceLogin: true)
        return try TiebaJSONClient.decode(MsgResponse.self, from: data)
    }

    private static func notify(_ path: String, page: Int) async throws -> MessageListResponse {
        let data = try await TiebaJSONClient.shared.post(path: path, params: ["pn": "\(page)"],
                                                        channel: .new, forceLogin: true)
        return try TiebaJSONClient.decode(MessageListResponse.self, from: data)
    }

    // MARK: - 关注吧（MINI 通道 `/c/c/forum/like` / `/c/c/forum/unlike`）

    /// 关注吧 `/c/c/forum/like`（MINI，`from_widget=0`）
    @discardableResult
    static func likeForum(forumId: Int64, forumName: String) async throws -> Data {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { throw TiebaAPIError.notLoggedIn }
        let params: [String: String] = [
            "fid": "\(forumId)",
            "kw": forumName,
            "tbs": account.tbs,
            "_client_version": "8.0.8.0",
        ]
        return try await TiebaJSONClient.shared.post(path: "/c/c/forum/like",
                                                     params: params, channel: .mini, forceLogin: true)
    }

    /// 取关吧 `/c/c/forum/unlike`（MINI）
    @discardableResult
    static func unlikeForum(forumId: Int64, forumName: String) async throws -> Data {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { throw TiebaAPIError.notLoggedIn }
        let params: [String: String] = [
            "fid": "\(forumId)",
            "kw": forumName,
            "tbs": account.tbs,
            "_client_version": "8.0.8.0",
        ]
        return try await TiebaJSONClient.shared.post(path: "/c/c/forum/unlike",
                                                     params: params, channel: .mini, forceLogin: true)
    }

    // MARK: - 关注用户（official 通道 `/c/c/user/follow` / `/c/c/user/unfollow`）

    /// 关注用户 `/c/c/user/follow`（official，靠 portrait）
    @discardableResult
    static func followUser(portrait: String) async throws -> Data {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { throw TiebaAPIError.notLoggedIn }
        let params: [String: String] = [
            "portrait": portrait,
            "tbs": account.tbs,
            "_client_version": ClientVersion.v12.rawValue,
            "authsid": "null",
            "stoken": account.stoken,
            "from_type": "2",
            "in_live": "0",
        ]
        return try await TiebaJSONClient.shared.post(path: "/c/c/user/follow",
                                                     params: params, channel: .official, forceLogin: true)
    }

    /// 取关用户 `/c/c/user/unfollow`（official）
    @discardableResult
    static func unfollowUser(portrait: String) async throws -> Data {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { throw TiebaAPIError.notLoggedIn }
        let params: [String: String] = [
            "portrait": portrait,
            "tbs": account.tbs,
            "_client_version": ClientVersion.v12.rawValue,
            "authsid": "null",
            "stoken": account.stoken,
            "from_type": "2",
            "in_live": "0",
            "timestamp": "\(Int64(Date().timeIntervalSince1970 * 1000))",
        ]
        return try await TiebaJSONClient.shared.post(path: "/c/c/user/unfollow",
                                                     params: params, channel: .official, forceLogin: true)
    }

    // MARK: - 收藏（official 通道 `/c/c/post/addstore` / `/c/c/post/rmstore`）

    /// 收藏贴 `/c/c/post/addstore`
    /// - Parameter data: Android `NewCollectDataBean` 列表的 JSON：
    ///   `[{"tid":"…","pid":"0","status":1}]`
    static func addStore(threadId: Int64, postId: Int64, tbs: String) async throws {
        let json = "[{\"tid\":\"\(threadId)\",\"pid\":\"\(postId)\",\"status\":1}]"
        let params: [String: String] = ["data": json, "tbs": tbs]
        let data = try await TiebaJSONClient.shared.post(path: "/c/c/post/addstore",
                                                         params: params, channel: .official,
                                                         forceLogin: true)
        _ = try TiebaJSONClient.decode(SimpleErrorResponse.self, from: data)
    }

    /// 取消收藏 `/c/c/post/rmstore`
    static func removeStore(threadId: Int64) async throws {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { throw TiebaAPIError.notLoggedIn }
        let params: [String: String] = [
            "tid": "\(threadId)",
            "fid": "null",
            "tbs": account.tbs,
            "stoken": account.stoken,
            "user_id": account.uid,
            "client_user_token": account.uid,
        ]
        let data = try await TiebaJSONClient.shared.post(path: "/c/c/post/rmstore",
                                                         params: params, channel: .official,
                                                         forceLogin: true)
        _ = try TiebaJSONClient.decode(SimpleErrorResponse.self, from: data)
    }

    /// 收藏列表 `/c/f/post/threadstore`（official）
    static func threadStore(page: Int = 1, pageSize: Int = 20) async throws -> ThreadStoreResponse {
        guard let account = TiebaJSONClient.shared.accountProvider(),
              !account.uid.isEmpty else { throw TiebaAPIError.notLoggedIn }
        let offset = max(0, (page - 1) * pageSize)
        let params: [String: String] = [
            "rn": "\(pageSize)",
            "offset": "\(offset)",
            "user_id": account.uid,
            "stoken": account.stoken,
            "_client_version": ClientVersion.v12.rawValue,
        ]
        let data = try await TiebaJSONClient.shared.post(path: "/c/f/post/threadstore",
                                                         params: params, channel: .official,
                                                         forceLogin: true)
        return try TiebaJSONClient.decode(ThreadStoreResponse.self, from: data)
    }

    // MARK: - 客户端初始化

    /// `/c/s/sync`：换取真实 client_id 与 sample_id（Android `ClientUtils.sync`）
    /// 失败不影响使用（Android 用 catch 吞掉异常）
    static func sync() async {
        struct SyncResponse: Decodable {
            struct Client: Decodable { let client_id: FlexibleString?; let clientId: FlexibleString? }
            struct WlConfig: Decodable { let sample_id: FlexibleString?; let sampleId: FlexibleString? }
            let client: Client?
            let wl_config: WlConfig?
            let wlConfig: WlConfig?
        }
        var params: [String: String] = ["_client_version": ClientVersion.v12.rawValue]
        if let account = TiebaJSONClient.shared.accountProvider() {
            if !account.uid.isEmpty { params["user_id"] = account.uid }
            if !account.stoken.isEmpty { params["stoken"] = account.stoken }
        }
        guard let data = try? await TiebaJSONClient.shared.post(path: "/c/s/sync", params: params,
                                                               channel: .official) else { return }
        guard let resp = try? JSONDecoder().decode(SyncResponse.self, from: data) else { return }
        if let cid = resp.client?.client_id?.value ?? resp.client?.clientId?.value, !cid.isEmpty {
            ClientUtils.setClientId(cid)
        }
        if let sid = (resp.wl_config ?? resp.wlConfig)?.sample_id?.value
            ?? (resp.wl_config ?? resp.wlConfig)?.sampleId?.value, !sid.isEmpty {
            ClientUtils.setSampleId(sid)
        }
    }
}

// MARK: - JSON 响应模型

/// 只有 error_code / error_msg 的简单响应
struct SimpleErrorResponse: Decodable {
    let error_code: FlexibleString?
    let error_msg: String?
    let error: SimpleErrorResponse.Inner?
    struct Inner: Decodable {
        let error_code: FlexibleString?
        let error_msg: String?
    }
}

/// `/c/c/forum/msign` 响应
struct MultiSignResponse: Decodable {
    struct Data: Decodable {
        struct SignInfo: Decodable {
            let forum_name: String?
            let forum_id: FlexibleInt?
            let is_signed: FlexibleInt?
        }
        let signedForumInfo: [SignInfo]?
        let signed_forum_info: [SignInfo]?
        let unsignedForumInfo: [SignInfo]?
        let unsigned_forum_info: [SignInfo]?
    }
    let error_code: FlexibleString?
    let error_msg: String?
    let data: Data?
}

/// 通知列表响应（对应 Android `MessageListBean`）
struct MessageListResponse: Decodable {
    struct MessageInfo: Decodable {
        let title: String?
        let content: String?
        let quote_content: String?
        let thread_id: FlexibleInt?
        let post_id: FlexibleInt?
        let time: FlexibleInt?
        let fname: String?
        let unread: FlexibleInt?
        let is_floor: FlexibleInt?
        let replyer: Replyer?
        let quote_user: Replyer?
    }
    struct Replyer: Decodable {
        let id: FlexibleInt?
        let name: String?
        let name_show: String?
        let portrait: String?
    }
    struct Message: Decodable {
        let replyme: FlexibleInt?
        let atme: FlexibleInt?
        let fans: FlexibleInt?
    }
    let error_code: FlexibleString?
    let error_msg: String?
    let reply_list: [MessageInfo]?
    let at_list: [MessageInfo]?
    let message: Message?
}

/// `/c/s/msg` 响应（对应 Android `MsgBean`：未读计数）
struct MsgResponse: Decodable {
    struct Msg: Decodable {
        let replyme: FlexibleInt?
        let atme: FlexibleInt?
        let fans: FlexibleInt?
    }
    let error_code: FlexibleString?
    let error_msg: String?
    let no_error: FlexibleString?
    let msg: Msg?
}

/// `/c/f/post/threadstore` 响应（对应 Android `ThreadStoreBean`）
struct ThreadStoreResponse: Decodable {
    struct StoreInfo: Decodable {
        let tid: FlexibleInt?
        let pid: FlexibleInt?
        let title: String?
        let fname: String?
        let forum_id: FlexibleInt?
        let reply_num: FlexibleInt?
        let author: StoreAuthor?
        let create_time: FlexibleInt?
    }
    struct StoreAuthor: Decodable {
        let id: FlexibleInt?
        let name: String?
        let name_show: String?
        let portrait: String?
    }
    struct Page: Decodable {
        let current_page: FlexibleInt?
        let has_more: FlexibleInt?
    }
    let error_code: FlexibleString?
    let error_msg: String?
    let thread_store: [StoreInfo]?
    let page: Page?
}
