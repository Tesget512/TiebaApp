import Foundation

/// 全部贴吧接口：与 Android `MixedTiebaApiImpl.kt` 中对应方法的参数 1:1 对齐。
///
/// 说明：Android 的 protobuf 通道 query 里带一个无意义的 `no_param=1`
/// （`createProtobufApi` 的公共 query），对服务端语义无影响，iOS 省略。
enum TiebaEndpoints {

    // MARK: - 发现

    /// 首页推荐 `/c/f/excellent/personalized?cmd=309264`
    /// Android 参数：load_type 1=刷新/2=加载更多、pn、page_thread_count=11、q_type=1、屏幕参数
    static func personalized(client: TiebaAPIClient, loadType: Int, page: Int) async throws -> Tieba_PersonalizedResponseData {
        var data = Tieba_PersonalizedRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.loadType = UInt32(loadType)
        data.pn = UInt32(page)
        data.pageThreadCount = 11
        data.qType = 1
        data.needTags = 0
        data.preAdThreadCount = 0
        data.sugCount = 0
        data.tagCode = 0
        data.needForumlist = 0
        data.newNetType = 1
        data.newInstall = 0
        data.requestTimes = 0
        data.invokeSource = ""
        data.scrDip = UIScreenCompat.density
        data.scrH = Int32(UIScreenCompat.height)
        data.scrW = Int32(UIScreenCompat.width)
        var req = Tieba_PersonalizedRequest()
        req.data = data
        let resp: Tieba_PersonalizedResponse = try await client.request(
            path: "/c/f/excellent/personalized", cmd: 309264,
            requestData: req, responseType: Tieba_PersonalizedResponse.self)
        return resp.data
    }

    // MARK: - 吧

    /// 吧页 `/c/f/frs/page?cmd=301001`
    /// - Parameter sortType: 最新=0(回复时间)/1(发帖时间)；精华列表 Android 不发送 sort_type
    /// - Parameter goodClassifyId: 精华分类 id（精华 tab 传 0）
    static func frsPage(client: TiebaAPIClient, forumName: String,
                        page: Int, sortType: Int, isGood: Bool,
                        goodClassifyId: Int? = nil) async throws -> Tieba_FrsPage_FrsPageResponseData {
        var data = Tieba_FrsPage_FrsPageRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.kw = forumName
        data.pn = Int32(page)
        data.rn = 90
        data.rnNeed = 30
        data.qType = 2
        data.stType = "recom_flist"
        data.callFrom = 0
        data.categoryID = 0
        data.isDefaultNavtab = 0
        data.isSelection = 0
        data.loadType = isGood ? 0 : 1
        data.netError = 0
        data.stParam = 0
        data.withGroup = 1
        data.upSchema = ""
        data.yuelaouLocate = ""
        data.lastClickTid = 0
        data.hotThreadID = 0
        data.ctime = 0
        data.dataSize = 0
        data.scrDip = UIScreenCompat.density
        data.scrH = Int32(UIScreenCompat.height)
        data.scrW = Int32(UIScreenCompat.width)
        // Android：精华列表不发送 sort_type（proto3 optional 未 set）；最新列表发送
        if isGood {
            data.isGood = 1
            data.cid = Int32(goodClassifyId ?? 0)
        } else {
            data.isGood = 0
            data.sortType = Int32(sortType)
        }
        var req = Tieba_FrsPage_FrsPageRequest()
        req.data = data
        let resp: Tieba_FrsPage_FrsPageResponse = try await client.request(
            path: "/c/f/frs/page", cmd: 301001,
            requestData: req, responseType: Tieba_FrsPage_FrsPageResponse.self)
        return resp.data
    }

    /// 吧详情 `/c/f/forum/getforumdetail?cmd=309614&format=protobuf`
    /// 注意：Android 端此接口走 V11 通道（`CommonRequest` 为 V11 分支）
    static func forumDetail(client: TiebaAPIClient, forumId: Int64) async throws -> Tieba_GetForumDetail_GetForumDetailResponseData {
        var data = Tieba_GetForumDetail_GetForumDetailRequestData()
        data.common = CommonRequestBuilder.build(.v12, account: client.accountProvider())
        data.forumID = forumId
        var req = Tieba_GetForumDetail_GetForumDetailRequest()
        req.data = data
        let resp: Tieba_GetForumDetail_GetForumDetailResponse = try await client.request(
            path: "/c/f/forum/getforumdetail", cmd: 309614,
            requestData: req, responseType: Tieba_GetForumDetail_GetForumDetailResponse.self)
        return resp.data
    }

    // MARK: - 帖子

    /// 帖子内容 `/c/f/pb/page?cmd=302001&format=protobuf`
    /// - Parameters:
    ///   - page: 页码；Android 首页固定传 0
    ///   - seeLz: 只看楼主（lz=1）
    ///   - sortType: 排序（r）
    static func pbPage(client: TiebaAPIClient, threadId: Int64, page: Int,
                       rn: Int = 15, forumId: Int64 = 0, seeLz: Bool = false,
                       sortType: Int32 = 0, postId: Int64 = 0) async throws -> Tieba_PbPage_PbPageResponseData {
        var data = Tieba_PbPage_PbPageRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.kz = threadId
        data.pid = postId
        data.pn = Int32(page)
        data.r = sortType
        data.lz = seeLz ? 1 : 0
        data.forumID = forumId
        data.lastPid = 0
        data.back = 0
        data.banner = 0
        data.broadcastID = 0
        data.floorRn = 4
        data.floorSortType = 1
        data.fromPush = 0
        data.fromSmartFrs = 0
        data.isCommReverse = 0
        data.isFoldCommentReq = 0
        data.isJumpfloor = 0
        data.jumpfloorNum = 0
        data.needRepostRecommendForum = 0
        data.objLocate = ""
        data.objParam1 = "10"
        data.objSource = ""
        data.oriUgcType = 0
        data.pbRn = 0
        data.qType = 2
        data.requestTimes = 0
        data.rn = Int32(rn)
        data.sModel = 0
        data.scrDip = UIScreenCompat.density
        data.scrH = Int32(UIScreenCompat.height)
        data.scrW = Int32(UIScreenCompat.width)
        data.similarFrom = 0
        data.sourceType = 2
        data.stType = ""
        data.threadType = 0
        data.weipost = 0
        data.withFloor = 1
        var req = Tieba_PbPage_PbPageRequest()
        req.data = data
        let resp: Tieba_PbPage_PbPageResponse = try await client.request(
            path: "/c/f/pb/page", cmd: 302001,
            requestData: req, responseType: Tieba_PbPage_PbPageResponse.self)
        return resp.data
    }

    /// 楼中楼 `/c/f/pb/floor?cmd=302002&format=protobuf`（V22 通道，不发送 stoken part）
    static func pbFloor(client: TiebaAPIClient, threadId: Int64, postId: Int64,
                        subPostId: Int64 = 0, page: Int = 1,
                        forumId: Int64 = 0) async throws -> Tieba_PbFloor_PbFloorResponseData {
        var data = Tieba_PbFloor_PbFloorRequestData()
        data.common = CommonRequestBuilder.build(.v22, account: client.accountProvider())
        data.kz = threadId
        data.pid = postId
        data.spid = subPostId
        data.pn = Int32(page)
        data.isCommReverse = 0
        data.oriUgcType = 0
        data.forumID = forumId
        data.scrDip = UIScreenCompat.density
        data.scrH = Int32(UIScreenCompat.height)
        data.scrW = Int32(UIScreenCompat.width)
        var req = Tieba_PbFloor_PbFloorRequest()
        req.data = data
        let resp: Tieba_PbFloor_PbFloorResponse = try await client.request(
            path: "/c/f/pb/floor", cmd: 302002,
            requestData: req, responseType: Tieba_PbFloor_PbFloorResponse.self,
            channel: TiebaAPIClient.v22)
        return resp.data
    }

    // MARK: - 用户

    /// 用户信息 `/c/u/user/profile?cmd=303012&format=protobuf`
    /// - Parameter uid: 目标用户；自己传 0（Android isSelf 判定）
    static func userProfile(client: TiebaAPIClient, uid: Int64, selfUid: Int64, isSelf: Bool) async throws -> Tieba_Profile_ProfileResponseData {
        var data = Tieba_Profile_ProfileRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.uid = selfUid
        if !isSelf { data.friendUid = uid }
        data.friendUidPortrait = ""
        data.hasPlist_p = 1
        data.isFromUsercenter = 1
        data.isGuest = isSelf ? 0 : 1
        data.needPostCount = 1
        data.page = 1
        data.pn = 1
        data.qType = 0
        data.rn = 20
        data.scrDip = UIScreenCompat.density
        data.scrH = UInt32(UIScreenCompat.height)
        data.scrW = UInt32(UIScreenCompat.width)
        var req = Tieba_Profile_ProfileRequest()
        req.data = data
        let resp: Tieba_Profile_ProfileResponse = try await client.request(
            path: "/c/u/user/profile", cmd: 303012,
            requestData: req, responseType: Tieba_Profile_ProfileResponse.self)
        return resp.data
    }

    // MARK: - 搜索

    /// 搜索联想 `/c/s/searchSug?cmd=309438&format=protobuf`
    static func searchSug(client: TiebaAPIClient, keyword: String, isForum: Bool) async throws -> Tieba_SearchSug_SearchSugResponseData {
        var data = Tieba_SearchSug_SearchSugRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.word = keyword
        data.isforum = isForum ? "1" : "0"
        var req = Tieba_SearchSug_SearchSugRequest()
        req.data = data
        let resp: Tieba_SearchSug_SearchSugResponse = try await client.request(
            path: "/c/s/searchSug", cmd: 309438,
            requestData: req, responseType: Tieba_SearchSug_SearchSugResponse.self)
        return resp.data
    }

    /// 搜索帖子（JSON，`MINI_TIEBA_API` `/c/s/searchpost`）
    /// - Parameters: kw 限定吧名（可空）、onlyThread 只看主题帖、sm 排序方式（1=相关度）
    static func searchPost(keyword: String, forumName: String = "", page: Int = 1,
                           rn: Int = 30, onlyThread: Bool = false, sm: Int = 1) async throws -> SearchPostResponse {
        var params: [String: String] = [
            "word": keyword,
            "kw": forumName,
            "pn": "\(page)",
            "rn": "\(rn)",
            "only_thread": onlyThread ? "1" : "0",
            "sm": "\(sm)",
        ]
        if let account = TiebaJSONClient.shared.accountProvider() {
            if !account.uid.isEmpty { params["user_id"] = account.uid }
            if !account.stoken.isEmpty { params["stoken"] = account.stoken }
        }
        let data = try await TiebaJSONClient.shared.post(path: "/c/s/searchpost", params: params,
                                                         channel: .mini)
        return try TiebaJSONClient.decode(SearchPostResponse.self, from: data)
    }
}

// MARK: - JSON 响应模型

/// `/c/s/searchpost` 响应（对应 Android `SearchPostBean`）
struct SearchPostResponse: Decodable {
    struct Post: Decodable {
        let tid: FlexibleInt?
        let pid: FlexibleInt?
        let title: String?
        let content: String?
        let time: FlexibleInt?
        let reply_num: FlexibleInt?
        let forum_name: String?
        let author: Author?
    }
    struct Author: Decodable {
        let id: FlexibleInt?
        let name: String?
        let name_show: String?
        let portrait: String?
    }
    let error_code: FlexibleString?
    let error_msg: String?
    let post_list: [Post]?
    let page: Page?
    struct Page: Decodable {
        let current_page: FlexibleInt?
        let has_more: FlexibleInt?
    }
}

/// 数字字段容错（JSON 里可能是数字也可能是字符串）
struct FlexibleInt: Decodable {
    let value: Int64
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int64.self) { value = i }
        else if let s = try? c.decode(String.self) { value = Int64(s) ?? 0 }
        else if let d = try? c.decode(Double.self) { value = Int64(d) }
        else { value = 0 }
    }
    var int: Int { Int(value) }
}
