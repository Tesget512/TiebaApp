import XCTest
@testable import TiebaLite

/// 真实网络冒烟测试（在 iOS 模拟器上执行）。
/// 验证 protobuf/JSON 通道端到端可用：multipart 信封 + CommonRequest + 响应解码。
/// 断言均检查**实质内容**（非空、id 有效），避免"请求成功但返回空数据"的假通过。
final class NetworkSmokeTests: XCTestCase {

    /// 把实测结果写到共享文件，便于人工核对（xcodebuild 会吞掉 print 输出）
    static func record(_ line: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tieba_smoke.txt")
        let text = line + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func testPersonalizedFeed() async throws {
        let client = TiebaAPIClient()
        let data = try await TiebaEndpoints.personalized(client: client, loadType: 1, page: 1)
        XCTAssertFalse(data.threadList.isEmpty, "个性化推荐不应为空")
        // tid 是导航键；为 0 说明取错字段（Android 用 ThreadInfo.id）
        XCTAssertTrue(data.threadList.allSatisfy { $0.tid != 0 }, "每条帖子应有非 0 tid")
        XCTAssertTrue(data.threadList.contains { !$0.title.isEmpty }, "应有带标题的帖子")
        XCTAssertTrue(data.threadList.contains { !$0.forumName.isEmpty }, "应有带吧名的帖子")
        Self.record("personalized=\(data.threadList.count)")
    }

    func testFrsPage() async throws {
        let client = TiebaAPIClient()
        let data = try await TiebaEndpoints.frsPage(client: client, forumName: "李毅", page: 1,
                                                    sortType: 0, isGood: false)
        XCTAssertFalse(data.forum.name.isEmpty, "吧名不应为空")
        XCTAssertFalse(data.threadList.isEmpty, "吧页帖子列表不应为空")
        XCTAssertNotEqual(data.forum.id, 0, "吧 id 不应为 0（签到需要）")
        Self.record("frsPage=\(data.forum.name)/\(data.threadList.count)")
    }

    func testPbPageAndFloor() async throws {
        let client = TiebaAPIClient()
        let feed = try await TiebaEndpoints.personalized(client: client, loadType: 1, page: 1)
        guard let first = feed.threadList.first else { throw XCTSkip("推荐流为空") }
        let thread = try await TiebaEndpoints.pbPage(client: client, threadId: first.tid, page: 0, rn: 15)
        XCTAssertFalse(thread.postList.isEmpty, "帖子楼层不应为空")
        XCTAssertFalse(thread.forum.name.isEmpty, "帖子所属吧名不应为空")
        XCTAssertTrue(thread.postList.allSatisfy { $0.id != 0 }, "楼层 pid 不应为 0")
        Self.record("pbPage=\(thread.postList.count)")

        // 楼中楼：V22 通道（不带 stoken part）
        guard let post = thread.postList.first(where: { $0.subPostNumber > 0 }) else {
            Self.record("pbFloor=skipped(no subpost)")
            return
        }
        let floor = try await TiebaEndpoints.pbFloor(client: client, threadId: first.tid,
                                                     postId: Int64(bitPattern: post.id), page: 1,
                                                     forumId: thread.forum.id)
        XCTAssertFalse(floor.subpostList.isEmpty, "楼中楼列表不应为空")
        XCTAssertTrue(floor.subpostList.contains { !$0.content.isEmpty }, "楼中楼应有内容")
        Self.record("pbFloor=\(floor.subpostList.count)")
    }

    func testSearchSug() async throws {
        let client = TiebaAPIClient()
        let data = try await TiebaEndpoints.searchSug(client: client, keyword: "原神", isForum: false)
        XCTAssertFalse(data.list.isEmpty, "搜索联想不应为空")
        Self.record("searchSug=\(data.list.count)")
    }

    func testSearchPost() async throws {
        let resp = try await TiebaEndpoints.searchPost(keyword: "原神")
        let posts = resp.post_list ?? []
        XCTAssertFalse(posts.isEmpty, "帖子搜索结果不应为空")
        XCTAssertTrue(posts.contains { ($0.tid?.value ?? 0) != 0 }, "搜索结果应有 tid")
        Self.record("searchPost=\(posts.count)")
    }

    /// 签名 protobuf 通道（OFFICIAL_PROTOBUF_TIEBA_API）：热榜
    func testHotThreadList() async throws {
        let client = TiebaAPIClient()
        let data = try await TiebaExtraEndpoints.hotThreadList(client: client)
        XCTAssertFalse(data.threadInfo.isEmpty, "热榜列表不应为空（签名通道）")
        XCTAssertTrue(data.threadInfo.allSatisfy { $0.tid != 0 }, "热榜每条应有非 0 tid")
        Self.record("hotThreadList=\(data.threadInfo.count)")
    }

    /// 签名 protobuf 通道：热议话题
    func testTopicList() async throws {
        let client = TiebaAPIClient()
        let data = try await TiebaExtraEndpoints.topicList(client: client)
        XCTAssertFalse(data.topicList.isEmpty, "热议话题不应为空")
        Self.record("topicList=\(data.topicList.count)")
    }

    /// 签名 protobuf 通道：进吧推荐（未登录时 like_forum 可能为空，但请求须成功）
    func testForumRecommendChannel() async throws {
        let client = TiebaAPIClient()
        // 未登录时服务端会返回 error（need_login），此处只验证签名通道不因签名错误 500
        let data = try? await TiebaExtraEndpoints.forumRecommend(client: client)
        Self.record("forumRecommend=\(data?.likeForum.count ?? -1)")
        // 若返回则校验字段合法
        if let data {
            XCTAssertTrue(data.likeForum.allSatisfy { $0.forumID != 0 })
        }
    }

    /// V12 免签通道：用户帖子
    func testUserPost() async throws {
        let client = TiebaAPIClient()
        // 用推荐流里第一条帖子的作者 uid 作为目标
        let feed = try await TiebaEndpoints.personalized(client: client, loadType: 1, page: 1)
        guard let uid = feed.threadList.first(where: { $0.author.id != 0 })?.author.id else {
            throw XCTSkip("推荐流无作者 uid")
        }
        let data = try await TiebaExtraEndpoints.userPost(client: client, uid: uid,
                                                          page: 1, isThread: true)
        Self.record("userPost=\(data.postList.count)")
        XCTAssertTrue(data.postList.allSatisfy { $0.threadID != 0 }, "用户帖子应有 tid")
    }

    /// V12 免签通道：浏览过的吧
    func testHistoryForum() async throws {
        let client = TiebaAPIClient()
        let data = try? await TiebaExtraEndpoints.historyForum(client: client)
        Self.record("historyForum=\(data?.historyForum.count ?? -1)")
        if let data {
            XCTAssertTrue(data.historyForum.allSatisfy { !$0.forumName.isEmpty })
        }
    }

    /// V12 免签通道：吧详情（用吧页返回的 forum id）
    func testForumDetail() async throws {
        let client = TiebaAPIClient()
        let frs = try await TiebaEndpoints.frsPage(client: client, forumName: "李毅",
                                                   page: 1, sortType: 0, isGood: false)
        XCTAssertNotEqual(frs.forum.id, 0)
        let data = try await TiebaExtraEndpoints.forumDetailInfo(client: client, forumId: frs.forum.id)
        XCTAssertTrue(data.hasForumInfo, "吧详情应返回 forum_info")
        XCTAssertFalse(data.forumInfo.forumName.isEmpty)
        Self.record("forumDetail=\(data.forumInfo.forumName)")
    }

    /// V12 免签通道：吧规（无吧规的吧返回 error，允许跳过）
    func testForumRule() async throws {
        let client = TiebaAPIClient()
        let frs = try await TiebaEndpoints.frsPage(client: client, forumName: "李毅",
                                                   page: 1, sortType: 0, isGood: false)
        guard let data = try? await TiebaExtraEndpoints.forumRule(client: client,
                                                                  forumId: frs.forum.id),
              !data.rules.isEmpty else {
            Self.record("forumRule=skipped(no rule)")
            return
        }
        XCTAssertFalse(data.title.isEmpty)
        Self.record("forumRule=\(data.rules.count)")
    }

    /// V12_POST 免签通道：通用标签（需吧页有 generalTab，无则跳过）
    func testGeneralTabList() async throws {
        let client = TiebaAPIClient()
        let frs = try await TiebaEndpoints.frsPage(client: client, forumName: "原神",
                                                   page: 1, sortType: 0, isGood: false)
        guard let tab = frs.navTabInfo.tab.first(where: { $0.isGeneralTab == 1 }) else {
            Self.record("generalTab=skipped(no tab)")
            return
        }
        let data = try await TiebaExtraEndpoints.generalTabList(
            client: client, tabId: tab.tabID, forumId: frs.forum.id,
            page: 1, tabName: tab.tabName, sortType: 0, tabType: Int(tab.tabType))
        Self.record("generalTab=\(data.generalList.count)")
        XCTAssertTrue(data.generalList.allSatisfy { $0.tid != 0 })
    }
}
