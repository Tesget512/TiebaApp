import SwiftUI

/// 全局导航路由：所有 push 目标都通过 `NavigationLink(value:)` + 本枚举路由。
///
/// 说明：iOS 16 没有 `navigationDestination(item:)`（那是 iOS 17+ API），
/// 因此统一用 `navigationDestination(for:)`。
enum AppRoute: Hashable {
    case forum(String)
    case thread(id: Int64, title: String, forumId: Int64,
                onlyLz: Bool = false, desc: Bool = false) // onlyLz/desc：收藏页自动只看楼主/倒序
    case user(uid: Int64)
    case hot          // 热榜（HotPage）
    case concern      // 关注动态（ConcernPage）
    case homeFeed     // 进吧（HomePage：关注吧+推荐）
    case store        // 我的收藏（ThreadStorePage）
    case history      // 浏览历史（HistoryPage）
    case userPosts(uid: Int64, name: String, isThread: Bool) // TA 的帖子
    case topicList    // 热议话题列表
    case topicDetail(id: String, name: String)               // 热议话题详情
    case forumDetail(id: Int64, name: String)                // 吧详情
    case analysis(uid: Int64, name: String)                  // 发言分析
    case photoView(urls: [String], index: Int)               // 图片查看器
    case search                                              // 全局搜索（发现页 toolbar 进入）
    case forumSearch(name: String)                           // 吧内搜索（ForumSearchPostPage）
}
