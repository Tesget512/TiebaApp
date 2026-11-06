import Foundation

/// 核心读接口：与 Android MixedTiebaApiImpl 中对应方法的参数 1:1 对齐。
enum TiebaEndpoints {

    /// 首页推荐 `/c/f/excellent/personalized?cmd=309264`
    /// Android 参数：load_type 1=刷新/2=加载更多、pn、page_thread_count=11、q_type=1、屏幕参数
    static func personalized(client: TiebaAPIClient, loadType: Int, page: Int) async throws -> Tieba_PersonalizedResponse {
        var data = Tieba_PersonalizedRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.loadType = UInt32(loadType)
        data.pn = UInt32(page)
        data.pageThreadCount = 11
        data.qType = 1
        data.scrW = Int32(UIScreenCompat.width)
        data.scrH = Int32(UIScreenCompat.height)
        var req = Tieba_PersonalizedRequest()
        req.data = data
        return try await client.request(path: "/c/f/excellent/personalized", cmd: 309264,
                                        requestData: req, responseType: Tieba_PersonalizedResponse.self)
    }

    /// 吧页 `/c/f/frs/page?cmd=301001`
    static func frsPage(client: TiebaAPIClient, forumName: String, page: Int, sortType: Int, isGood: Bool) async throws -> Tieba_FrsPage_FrsPageResponseData {
        var data = Tieba_FrsPage_FrsPageRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.kw = forumName
        data.pn = Int32(page)
        data.rn = 90
        data.rnNeed = 30
        data.sortType = Int32(sortType)
        data.qType = 2
        data.stType = "recom_flist"
        data.isGood = Int32(isGood ? 1 : 0)
        var req = Tieba_FrsPage_FrsPageRequest()
        req.data = data
        let resp: Tieba_FrsPage_FrsPageResponse = try await client.request(
            path: "/c/f/frs/page", cmd: 301001, requestData: req, responseType: Tieba_FrsPage_FrsPageResponse.self)
        return resp.data
    }

    /// 帖子内容 `/c/f/pb/page?cmd=302001`
    static func pbPage(client: TiebaAPIClient, threadId: Int64, page: Int, rn: Int) async throws -> Tieba_PbPage_PbPageResponseData {
        var data = Tieba_PbPage_PbPageRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.kz = threadId
        data.pn = Int32(page)
        data.rn = Int32(rn)
        data.withFloor = 1
        data.floorRn = 4
        data.qType = 2
        var req = Tieba_PbPage_PbPageRequest()
        req.data = data
        let resp: Tieba_PbPage_PbPageResponse = try await client.request(
            path: "/c/f/pb/page", cmd: 302001, requestData: req, responseType: Tieba_PbPage_PbPageResponse.self)
        return resp.data
    }

    /// 用户信息 `/c/u/user/profile?cmd=303012`
    static func userProfile(client: TiebaAPIClient, uid: Int64) async throws -> Tieba_Profile_ProfileResponseData {
        var data = Tieba_Profile_ProfileRequestData()
        data.common = CommonRequestBuilder.buildV12(account: client.accountProvider())
        data.uid = uid
        var req = Tieba_Profile_ProfileRequest()
        req.data = data
        let resp: Tieba_Profile_ProfileResponse = try await client.request(
            path: "/c/u/user/profile", cmd: 303012, requestData: req, responseType: Tieba_Profile_ProfileResponse.self)
        return resp.data
    }
}
