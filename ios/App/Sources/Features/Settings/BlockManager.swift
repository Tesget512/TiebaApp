import Foundation

/// 内容屏蔽（对应 Android `utils/BlockManager.kt` + Room `block` 表的 iOS 版）。
/// 白名单命中 → 不屏蔽；黑名单命中 → 屏蔽。UserDefaults JSON 持久化。
final class BlockManager: ObservableObject {
    static let shared = BlockManager()

    struct Block: Codable, Identifiable {
        var id: Int
        var category: Int       // 10=黑名单 11=白名单（对齐 Android Block）
        var type: Int           // 0=关键词 1=用户
        var keywords: [String]?
        var username: String?
        var uid: String?
        var isRegex: Bool
    }

    static let categoryBlackList = 10
    static let categoryWhiteList = 11
    static let typeKeyword = 0
    static let typeUser = 1

    @Published private(set) var blocks: [Block] = []
    private let key = "tieba.blocklist"

    var blackList: [Block] { blocks.filter { $0.category == Self.categoryBlackList } }
    var whiteList: [Block] { blocks.filter { $0.category == Self.categoryWhiteList } }

    private init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Block].self, from: data) else { return }
        blocks = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(blocks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(category: Int, keywords: [String], isRegex: Bool) {
        let maxID = blocks.map(\.id).max() ?? 0
        blocks.append(Block(id: maxID + 1, category: category, type: Self.typeKeyword,
                            keywords: keywords, username: nil, uid: nil, isRegex: isRegex))
        save()
    }

    func addUser(category: Int, username: String, uid: String) {
        let maxID = blocks.map(\.id).max() ?? 0
        blocks.append(Block(id: maxID + 1, category: category, type: Self.typeUser,
                            keywords: nil, username: username, uid: uid, isRegex: false))
        save()
    }

    func remove(id: Int) {
        blocks.removeAll { $0.id == id }
        save()
    }

    /// 关键词匹配（Android shouldBlock(content)：白名单优先）
    func shouldBlock(content: String) -> Bool {
        guard !blocks.isEmpty, !content.isEmpty else { return false }
        for b in whiteList where b.type == Self.typeKeyword {
            for kw in b.keywords ?? [] where matches(kw, content: content, isRegex: b.isRegex) {
                return false
            }
        }
        for b in blackList where b.type == Self.typeKeyword {
            for kw in b.keywords ?? [] where matches(kw, content: content, isRegex: b.isRegex) {
                return true
            }
        }
        return false
    }

    /// 用户屏蔽（Android shouldBlock(uid, userName)：白名单优先，不做正则）
    func shouldBlock(userId: Int64, userName: String?) -> Bool {
        guard !blocks.isEmpty else { return false }
        for b in whiteList where b.type == Self.typeUser {
            if b.uid == "\(userId)" || b.username == userName { return false }
        }
        for b in blackList where b.type == Self.typeUser {
            if b.uid == "\(userId)" || b.username == userName { return true }
        }
        return false
    }

    /// 帖子组合判定（Android ThreadInfo.shouldBlock：标题/摘要 + 用户）
    func shouldBlockThread(title: String, abstract: String, authorId: Int64, authorName: String?) -> Bool {
        shouldBlock(content: title) || shouldBlock(content: abstract)
            || shouldBlock(userId: authorId, userName: authorName)
    }

    private func matches(_ kw: String, content: String, isRegex: Bool) -> Bool {
        if isRegex {
            return content.range(of: kw, options: .regularExpression) != nil
        }
        return content.contains(kw)
    }
}
