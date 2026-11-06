import XCTest
@testable import TiebaLite

/// 真实网络冒烟测试（在 iOS 模拟器上执行）。
/// 验证 protobuf 通道端到端可用：multipart 信封 + CommonRequest + 响应解码。
/// 这些测试依赖外网可达，失败时输出具体 error_code 供诊断。
final class NetworkSmokeTests: XCTestCase {

    func testPersonalizedFeed() async throws {
        let client = TiebaAPIClient()
        let resp = try await TiebaEndpoints.personalized(client: client, loadType: 1, page: 1)
        let threads = resp.data.threadList
        print("SMOKE: personalized 返回 \(threads.count) 条")
        for t in threads.prefix(3) {
            print("SMOKE:   \(t.title)  by \(t.author.nameShow.isEmpty ? t.author.name : t.author.nameShow)")
        }
        XCTAssertFalse(threads.isEmpty, "个性化推荐不应为空")
    }

    func testFrsPage() async throws {
        let client = TiebaAPIClient()
        let data = try await TiebaEndpoints.frsPage(client: client, forumName: "李毅", page: 1, sortType: 0, isGood: false)
        print("SMOKE: frsPage 吧名=\(data.forum.name) 帖子=\(data.threadList.count) threads")
        XCTAssertFalse(data.forum.name.isEmpty, "吧名不应为空")
    }
}
