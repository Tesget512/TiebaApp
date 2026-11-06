import Foundation

/// 一键签到（对应 Android `utils/OKSigner.kt` + `services/OKSignService.kt`）：
/// 1. getforumlist 拿 level 阈值 + msignStepNum 上限；forumGuide 拿全部关注的吧
/// 2. 未签到的吧中，等级 ≥ 阈值且未超上限的走 msign 批量签（from_widget 语义同样生效于单签）
/// 3. 其余逐吧 signFlow；失败按 `oksign_fail_auto_stop` 决定中止或继续
/// 4. 慢速模式每吧间隔 3500-8000ms，否则 2000ms
enum OKSigner {

    struct SignProgress {
        var total: Int
        var signedCount: Int = 0
        var successCount: Int = 0
        var currentForum: String = ""
        var finished: Bool = false
        var errorText: String?
    }

    /// 单吧签到（from_widget=1 模拟桌面小组件入口 = 双倍经验，Android OKSigner.signFlow:37）
    static func signSingle(forumName: String, forumId: Int64, tbs: String) async throws {
        try await TiebaWriteEndpoints.forumSign(forumName: forumName, forumId: forumId,
                                                fromWidget: "1", tbs: tbs)
    }

    /// 批量签到主流程。onProgress 在主线程回调。
    static func run(account: Account,
                    slowMode: Bool = true,
                    useMSign: Bool = true,
                    failAutoStop: Bool = true,
                    onProgress: @escaping @MainActor (SignProgress) -> Void) async -> Bool {
        let client = TiebaAPIClient.shared
        var progress = SignProgress(total: 0)

        // 1) 签到参数服务端配置 + 关注吧列表
        struct ForumListCfg: Decodable {
            let level: FlexibleString?
            let msign_step_num: FlexibleString?
            let msignStepNum: FlexibleString?
        }
        struct GuideForum: Decodable {
            let forum_id: FlexibleInt?
            let forum_name: String?
            let level_id: FlexibleInt?
            let is_sign: FlexibleInt?
        }
        struct GuideResp: Decodable {
            let error_code: FlexibleString?
            let like_forum: [GuideForum]?
        }

        do {
            let cfgData = try await TiebaJSONClient.shared.post(
                path: "/c/f/forum/getforumlist",
                params: ["_client_version": ClientVersion.v12.rawValue],
                channel: .official, forceLogin: true)
            let cfg = try? JSONDecoder().decode(ForumListCfg.self, from: cfgData)
            let mSignLevel = Int(cfg?.level?.value ?? "1") ?? 1
            let mSignMax = Int(cfg?.msign_step_num?.value ?? cfg?.msignStepNum?.value ?? "10") ?? 10

            let guideData = try await TiebaJSONClient.shared.post(
                path: "/c/f/forum/forumGuide",
                params: [
                    "sort_type": "0", "call_from": "0", "page_no": "1",
                    "res_num": "200", "top_forum_num": "0",
                    "tbs": account.tbs, "stoken": account.stoken,
                    "_client_version": ClientVersion.v12.rawValue,
                ],
                channel: .official, forceLogin: true)
            let guide = try TiebaJSONClient.decode(GuideResp.self, from: guideData)
            let forums = (guide.like_forum ?? []).filter { $0.is_sign?.value != 1 }

            progress.total = forums.count
            await onProgress(progress)
            guard !forums.isEmpty else {
                progress.finished = true
                await onProgress(progress)
                return true
            }

            // 2) msign 批量（等级达标且未超上限）
            var remaining = forums
            var msignInfoMap: [Int64: Bool] = [:]   // forumId -> signed
            if useMSign {
                let eligible = forums.filter {
                    ($0.level_id?.value ?? 0) >= mSignLevel &&
                    msignInfoMap.count < mSignMax
                }
                if !eligible.isEmpty {
                    let ids = eligible.compactMap { $0.forum_id?.value }
                    let joined = ids.map(String.init).joined(separator: ",")
                    do {
                        let resp = try await TiebaWriteEndpoints.multiSign(forumIds: ids)
                        let infos = resp.data?.signedForumInfo ?? resp.data?.signed_forum_info ?? []
                        for info in infos {
                            if let fid = info.forum_id?.value {
                                msignInfoMap[fid] = (info.is_signed?.value == 1) || (info.signed?.value == "1")
                            }
                        }
                        progress.successCount += msignInfoMap.values.filter { $0 }.count
                    } catch {
                        // msign 整批失败：全部走单签兜底
                        progress.errorText = error.localizedDescription
                    }
                    remaining = forums.filter { msignInfoMap[$0.forum_id?.value ?? 0] != true }
                }
            }

            // 3) 逐吧单签
            for (idx, f) in remaining.enumerated() {
                guard let name = f.forum_name, !name.isEmpty, let fid = f.forum_id?.value else { continue }
                progress.currentForum = name
                progress.signedCount = progress.total - remaining.count + idx
                await onProgress(progress)
                do {
                    try await signSingle(forumName: name, forumId: fid, tbs: account.tbs)
                    progress.successCount += 1
                } catch {
                    if failAutoStop {
                        progress.errorText = "\(name)吧: \(error.localizedDescription)"
                        progress.finished = true
                        await onProgress(progress)
                        return false
                    }
                    progress.errorText = "\(name)吧: \(error.localizedDescription)"
                }
                // 慢速模式 3500-7999ms 随机；否则 2000ms（Android OKSigner.getSignDelay）
                let delayMs = slowMode ? Int.random(in: 3500...7999) : 2000
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }

            progress.signedCount = progress.total
            progress.finished = true
            await onProgress(progress)
            return progress.successCount == progress.total
        } catch {
            progress.errorText = error.localizedDescription
            progress.finished = true
            await onProgress(progress)
            return false
        }
    }
}
