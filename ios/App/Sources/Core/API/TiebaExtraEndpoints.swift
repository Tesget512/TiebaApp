import Foundation

/// 第二批端点（对齐 Android 主分支功能面）：
/// 热榜、关注动态、热议话题、进吧推荐、用户帖子 —— 全部走
/// `OFFICIAL_PROTOBUF_TIEBA_API`（带公共参数 part + 签名）或 V12 免签通道。
enum TiebaExtraEndpoints {

    // MARK: - 热榜（`/c/f/forum/hotThreadList?cmd=309661`，签名通道）

    /// - Parameter tabCode: 热榜 tab（Android HotViewModel 默认传首页 tab 的 code，
    ///   无 tab 信息时传 "1"）
    static func hotThreadList(client: TiebaAPIClient, tabCode: String = "1") async throws -> Tieba_HotThreadList_HotThreadListResponseData {
        var data = Tieba_HotThreadList_HotThreadListRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.tabCode = tabCode
        data.tabID = "1"
        var req = Tieba_HotThreadList_HotThreadListRequest()
        req.data = data
        let resp: Tieba_HotThreadList_HotThreadListResponse = try await client.request(
            path: "/c/f/forum/hotThreadList", cmd: 309661,
            requestData: req, responseType: Tieba_HotThreadList_HotThreadListResponse.self,
            channel: TiebaAPIClient.signedV12)
        return resp.data
    }

    // MARK: - 关注动态（`/c/f/concern/userlike?cmd=309474`，签名通道）

    /// - Parameters:
    ///   - pageTag: 上一页响应返回的游标（首页传 ""）
    ///   - lastRequestUnix: 上次请求的 unix 秒（首页 0）
    ///   - loadType: 1=刷新 2=加载更多
    static func userLike(client: TiebaAPIClient, pageTag: String = "",
                         lastRequestUnix: UInt64 = 0, loadType: Int = 1) async throws -> Tieba_UserLike_UserLikeResponseData {
        var data = Tieba_UserLike_UserLikeRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.pageTag = pageTag
        data.lastRequestUnix = lastRequestUnix
        data.followType = 1
        data.loadType = Int32(loadType)
        var req = Tieba_UserLike_UserLikeRequest()
        req.data = data
        let resp: Tieba_UserLike_UserLikeResponse = try await client.request(
            path: "/c/f/concern/userlike", cmd: 309474,
            requestData: req, responseType: Tieba_UserLike_UserLikeResponse.self,
            channel: TiebaAPIClient.signedV12)
        return resp.data
    }

    // MARK: - 热议话题（`/c/f/recommend/topicList?cmd=309289`，签名通道）

    static func topicList(client: TiebaAPIClient) async throws -> Tieba_TopicList_TopicListResponseData {
        var data = Tieba_TopicList_TopicListRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.callFrom = "newbang"
        data.listType = "all"
        data.needTabList = "0"
        data.fid = 0
        var req = Tieba_TopicList_TopicListRequest()
        req.data = data
        let resp: Tieba_TopicList_TopicListResponse = try await client.request(
            path: "/c/f/recommend/topicList", cmd: 309289,
            requestData: req, responseType: Tieba_TopicList_TopicListResponse.self,
            channel: TiebaAPIClient.signedV12)
        return resp.data
    }

    // MARK: - 进吧推荐（`/c/f/forum/forumrecommend?cmd=303011`，签名通道）

    /// 关注吧列表 + 推荐（Android HomePage「进吧」页数据源）
    static func forumRecommend(client: TiebaAPIClient, sortType: Int = 0) async throws -> Tieba_ForumRecommend_ForumRecommendResponseData {
        var data = Tieba_ForumRecommend_ForumRecommendRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.likeForum = 1
        data.recommend = 1
        data.sortType = Int32(sortType)
        data.topic = 0
        var req = Tieba_ForumRecommend_ForumRecommendRequest()
        req.data = data
        let resp: Tieba_ForumRecommend_ForumRecommendResponse = try await client.request(
            path: "/c/f/forum/forumrecommend", cmd: 303011,
            requestData: req, responseType: Tieba_ForumRecommend_ForumRecommendResponse.self,
            channel: TiebaAPIClient.signedV12)
        return resp.data
    }

    // MARK: - 用户帖子（`/c/u/feed/userpost?cmd=303002&format=protobuf`，V12 免签通道）

    /// - Parameter isThread: true=主题贴（subtype 0），false=回复
    static func userPost(client: TiebaAPIClient, uid: Int64, page: Int,
                         isThread: Bool) async throws -> Tieba_UserPost_UserPostResponseData {
        var data = Tieba_UserPost_UserPostRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.uid = uid
        data.rn = 20
        data.isThread = isThread ? 1 : 0
        data.needContent = 1
        data.pn = UInt32(page)
        data.scrDip = UIScreenCompat.density
        data.scrH = Int32(UIScreenCompat.height)
        data.scrW = Int32(UIScreenCompat.width)
        data.qType = 1
        data.isViewCard = isThread ? 1 : 0
        var req = Tieba_UserPost_UserPostRequest()
        req.data = data
        let resp: Tieba_UserPost_UserPostResponse = try await client.request(
            path: "/c/u/feed/userpost", cmd: 303002,
            requestData: req, responseType: Tieba_UserPost_UserPostResponse.self)
        return resp.data
    }

    // MARK: - 浏览过的吧（`/c/f/forum/gethistoryforum?cmd=309601`，V12 免签通道）

    /// Android getHistoryForumFlow：HomePage「浏览过的吧」
    static func historyForum(client: TiebaAPIClient) async throws -> Tieba_GetHistoryForum_GetHistoryForumResponseData {
        var data = Tieba_GetHistoryForum_GetHistoryForumRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        var req = Tieba_GetHistoryForum_GetHistoryForumRequest()
        req.data = data
        let resp: Tieba_GetHistoryForum_GetHistoryForumResponse = try await client.request(
            path: "/c/f/forum/gethistoryforum", cmd: 309601,
            requestData: req, responseType: Tieba_GetHistoryForum_GetHistoryForumResponse.self)
        return resp.data
    }

    // MARK: - 吧详情（`/c/f/forum/getforumdetail?cmd=303021`，V12 免签通道）

    static func forumDetailInfo(client: TiebaAPIClient, forumId: Int64) async throws -> Tieba_GetForumDetail_GetForumDetailResponseData {
        var data = Tieba_GetForumDetail_GetForumDetailRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.forumID = forumId
        var req = Tieba_GetForumDetail_GetForumDetailRequest()
        req.data = data
        let resp: Tieba_GetForumDetail_GetForumDetailResponse = try await client.request(
            path: "/c/f/forum/getforumdetail", cmd: 303021,
            requestData: req, responseType: Tieba_GetForumDetail_GetForumDetailResponse.self)
        return resp.data
    }

    // MARK: - 吧规（`/c/f/forum/forumRuleDetail?cmd=309690`，V12 免签通道）

    static func forumRule(client: TiebaAPIClient, forumId: Int64) async throws -> Tieba_ForumRuleDetail_ForumRuleDetailResponseData {
        var data = Tieba_ForumRuleDetail_ForumRuleDetailRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.forumID = forumId
        var req = Tieba_ForumRuleDetail_ForumRuleDetailRequest()
        req.data = data
        let resp: Tieba_ForumRuleDetail_ForumRuleDetailResponse = try await client.request(
            path: "/c/f/forum/forumRuleDetail", cmd: 309690,
            requestData: req, responseType: Tieba_ForumRuleDetail_ForumRuleDetailResponse.self)
        return resp.data
    }

    // MARK: - 通用标签（`/c/f/frs/generalTabList?cmd=309622`，V12_POST 免签通道）

    static func generalTabList(client: TiebaAPIClient, tabId: Int32, forumId: Int64,
                               page: Int, tabName: String, sortType: Int,
                               tabType: Int, lastThreadId: Int64 = 0) async throws -> Tieba_GeneralTabList_GeneralTabListResponseData {
        var data = Tieba_GeneralTabList_GeneralTabListRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.tabID = tabId
        data.forumID = forumId
        data.pn = Int32(page)
        data.rn = 30
        data.scrW = Int32(UIScreenCompat.width)
        data.scrH = Int32(UIScreenCompat.height)
        data.scrDip = Int32(UIScreenCompat.density)
        data.lastThreadID = lastThreadId
        data.isDefaultNavtab = 0
        data.tabName = tabName
        data.isGeneralTab = 1
        data.sortType = Int32(sortType)
        data.tabType = Int32(tabType)
        data.adExtParams = ""
        data.adBearContext = ""
        data.hasAdBear_p = 0
        data.adBearSid = ""
        data.adBearSidPrice = 0
        data.requestTimes = 0
        data.frsCommonInfo = ""
        data.isNewfrs = 1
        data.isVideoDoublerow = 0
        var req = Tieba_GeneralTabList_GeneralTabListRequest()
        req.data = data
        let resp: Tieba_GeneralTabList_GeneralTabListResponse = try await client.request(
            path: "/c/f/frs/generalTabList", cmd: 309622,
            requestData: req, responseType: Tieba_GeneralTabList_GeneralTabListResponse.self,
            channel: TiebaAPIClient.v12Post)
        return resp.data
    }

    // MARK: - 回复 / 发帖（`/c/c/post/add?cmd=309731&format=protobuf`，V12_POST 免签通道）

    /// 回复楼层 / 楼中楼 / 发主题贴。
    /// - Parameters:
    ///   - content: 内容文本
    ///   - forumId/forumName: 目标吧（fid/kw）
    ///   - threadId: 主题贴 tid（发新主题贴时传 "0"）
    ///   - postId: 引用的楼层 pid（回帖时可空）
    ///   - subPostId: 楼中楼回复的目标楼中楼 id（楼中楼回复时传）
    ///   - replyUserId: 回复的目标用户 uid（`@` 某人时）
    static func addPost(client: TiebaAPIClient,
                        content: String,
                        forumId: String,
                        forumName: String,
                        threadId: String,
                        tbs: String,
                        nameShow: String? = nil,
                        postId: String? = nil,
                        subPostId: String? = nil,
                        replyUserId: String? = nil) async throws -> Tieba_AddPost_AddPostResponseData {
        var data = Tieba_AddPost_AddPostRequestData()
        data.common = CommonRequestBuilder.build(.v12Post, account: client.accountProvider(), tbs: tbs)
        data.anonymous = "1"
        data.canNoForum = "0"
        data.content = content
        data.entranceType = "0"
        data.fid = forumId
        data.floorNum = "0"
        data.kw = forumName
        data.isAd = "0"
        data.isAddition = "0"
        data.isBarrage = "0"
        data.isFeedback = "0"
        data.isGiftpost = "0"
        data.isPictxt = "0"
        data.isShowBless = 0
        data.isTwzhiboThread = "0"
        data.postFrom = ""
        data.realLat = ""
        data.realLng = ""
        data.showCustomFigure = 0
        data.stParam = ""
        data.stType = "tb_client_android"
        data.tbs = tbs
        data.vFid = ""
        data.vFname = ""
        data.vcode = ""
        data.vcodeTag = ""
        data.vcodeType = ""
        data.duringTime = "0"
        if postId == nil || postId!.isEmpty { data.barrageTime = "0" }
        data.nameShow = nameShow ?? ""
        data.tid = threadId
        if let postId, !postId.isEmpty { data.quoteID = postId }
        if let subPostId, !subPostId.isEmpty { data.subPostID = subPostId }
        if let replyUserId, !replyUserId.isEmpty { data.replyUid = replyUserId }
        var req = Tieba_AddPost_AddPostRequest()
        req.data = data
        let resp: Tieba_AddPost_AddPostResponse = try await client.request(
            path: "/c/c/post/add", cmd: 309731,
            requestData: req, responseType: Tieba_AddPost_AddPostResponse.self,
            channel: TiebaAPIClient.v12Post)
        return resp.data
    }
}
