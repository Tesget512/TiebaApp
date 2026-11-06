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

    /// 组合 Tieba `Error` 的文案（Android CommonResponse 的 message 逻辑）
    static func message(from error: Tieba_Error) -> String {
        errorMessage(code: Int(error.errorCode), msg: error.errorMsg, userMsg: error.userMsg)
    }

    static func errorMessage(code: Int, msg: String, userMsg: String) -> String {
        var parts: [String] = []
        if !msg.isEmpty { parts.append(msg) }
        if !userMsg.isEmpty { parts.append(userMsg) }
        return parts.isEmpty ? "错误码 \(code)" : parts.joined(separator: " / ")
    }
}
