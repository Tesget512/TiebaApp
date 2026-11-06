import Foundation

enum TiebaAPIError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case apiError(code: Int, message: String)   // error_code != 0
    case notLoggedIn
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .httpStatus(let s): return "HTTP \(s)"
        case .apiError(_, let m): return m
        case .notLoggedIn: return "尚未登录"
        case .decoding(let e): return "解析失败: \(e.localizedDescription)"
        case .network(let e): return e.localizedDescription
        }
    }
}
