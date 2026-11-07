import Foundation

/// 搜索历史（对应 Android SearchPage 搜索历史：去重置顶、上限 10、可清空/删除）
enum SearchStore {
    private static let key = "tieba.searchHistory"
    private static let limit = 10

    static func all() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    static func add(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        var list = all().filter { $0 != w }
        list.insert(w, at: 0)
        if list.count > limit { list = Array(list.prefix(limit)) }
        save(list)
    }

    static func remove(_ word: String) {
        save(all().filter { $0 != word })
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ list: [String]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// 置顶吧（Android HomePage 吧 item 长按「置顶」；UserDefaults 存吧名列表）
enum PinnedForumStore {
    private static let key = "tieba.pinnedForums"

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func isPinned(_ name: String) -> Bool { all().contains(name) }

    static func toggle(_ name: String) {
        var list = all()
        if let idx = list.firstIndex(of: name) {
            list.remove(at: idx)
        } else {
            list.insert(name, at: 0)
        }
        UserDefaults.standard.set(list, forKey: key)
    }
}
