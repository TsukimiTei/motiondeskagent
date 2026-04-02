import Foundation

/// 对话历史持久化管理
class ChatHistoryManager {
    private let historyURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MotionDeskAgent")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        historyURL = appDir.appendingPathComponent("chat_history.json")
    }

    /// 加载对话历史
    func load() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: historyURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    /// 保存对话历史
    func save(_ messages: [[String: Any]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: messages, options: .prettyPrinted) else {
            return
        }
        try? data.write(to: historyURL)
    }

    /// 清除历史
    func clear() {
        try? FileManager.default.removeItem(at: historyURL)
    }
}
