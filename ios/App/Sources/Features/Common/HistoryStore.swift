import Foundation

/// 本地浏览历史（对应 Android Room `History` 表的轻量 iOS 版）。
/// UserDefaults JSON 持久化，上限 200 条，FIFO 淘汰。
enum HistoryStore {
    struct Item: Codable, Equatable {
        var type: Int          // 1=吧 2=贴
        var id: String         // 吧名或 tid
        var title: String
        var subtitle: String   // 吧名 / 摘要
        var avatar: String     // 头像 portrait 段（帖子作者）
        var timestamp: TimeInterval
    }

    private static let key = "tieba.history"
    private static let limit = 200

    static func all() -> [Item] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return list
    }

    /// 记录一条浏览（同一 id 去重后置顶）
    static func record(type: Int, id: String, title: String, subtitle: String, avatar: String) {
        guard !id.isEmpty else { return }
        var list = all().filter { !($0.type == type && $0.id == id) }
        list.insert(Item(type: type, id: id, title: title, subtitle: subtitle,
                         avatar: avatar, timestamp: Date().timeIntervalSince1970), at: 0)
        if list.count > limit { list = Array(list.prefix(limit)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func remove(type: Int, id: String) {
        var list = all()
        list.removeAll { $0.type == type && $0.id == id }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
