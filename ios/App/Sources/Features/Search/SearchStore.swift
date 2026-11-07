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

// 置顶吧已迁移至 AppPreferences.pinnedForums（Published 驱动即时重排，见 P18）
