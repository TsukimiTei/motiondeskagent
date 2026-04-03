import AppKit
import WebKit

/// Swift ↔ WebView 双向通信桥
class WebViewBridge: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private let claudeManager: ClaudeCLIManager
    private let configManager: ConfigManager
    private let chatHistoryManager: ChatHistoryManager
    private var memoryManager: MemoryManager?

    init(webView: WKWebView,
         claudeManager: ClaudeCLIManager,
         configManager: ConfigManager,
         chatHistoryManager: ChatHistoryManager) {
        self.webView = webView
        self.claudeManager = claudeManager
        self.configManager = configManager
        self.chatHistoryManager = chatHistoryManager
        super.init()

        // 注册消息处理器
        webView.configuration.userContentController.add(self, name: "bridge")

        // 从配置读取 claude 路径
        let config = configManager.load()
        if let path = config["claudePath"] as? String, !path.isEmpty {
            claudeManager.setClaudePath(path)
        }

        // 设置 Claude 统一事件回调
        claudeManager.onEvent = { [weak self] event in
            self?.handleClaudeEvent(event)
        }
    }

    /// 设置记忆管理器（延迟注入，因为初始化顺序）
    func setMemoryManager(_ manager: MemoryManager) {
        self.memoryManager = manager
    }

    // MARK: - Claude 事件处理

    private func handleClaudeEvent(_ event: ClaudeStreamEvent) {
        switch event {
        case .sessionInit(let model, let tools):
            sendToJS(type: "claudeInit", payload: [
                "model": model,
                "tools": tools
            ])

        case .textDelta(let text):
            sendToJS(type: "claudeTextDelta", payload: ["text": text])

        case .textComplete(let text):
            // 向后兼容：claudeReplace 用于完整文本替换
            sendToJS(type: "claudeReplace", payload: ["text": text])

        case .toolUseStart(let id, let name, let input):
            sendToJS(type: "claudeToolStart", payload: [
                "id": id,
                "name": name,
                "input": input
            ])

        case .toolProgress(let name, let elapsed):
            sendToJS(type: "claudeToolProgress", payload: [
                "name": name,
                "elapsed": elapsed
            ])

        case .toolResult(let name, let summary):
            sendToJS(type: "claudeToolResult", payload: [
                "name": name,
                "summary": summary
            ])

        case .thinking(let text):
            sendToJS(type: "claudeThinking", payload: ["text": text])

        case .done(_, let cost, let duration):
            var payload: [String: Any] = [:]
            if let cost = cost { payload["cost"] = cost }
            if let duration = duration { payload["duration"] = duration }
            sendToJS(type: "claudeDone", payload: payload)

        case .error(let message, let isRetryable):
            sendToJS(type: "claudeError", payload: [
                "error": message,
                "retryable": isRetryable
            ])
        }
    }

    // MARK: - JS → Swift 消息处理

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        let payload = body["payload"] as? [String: Any] ?? [:]

        switch type {
        case "sendMessage":
            if let content = payload["content"] as? String {
                claudeManager.send(message: content)
            }

        case "getConfig":
            let config = configManager.load()
            sendToJS(type: "config", payload: config)

        case "saveConfig":
            configManager.save(payload)

        case "loadChatHistory":
            let history = chatHistoryManager.load()
            sendToJSRaw(type: "chatHistory", jsonArray: history)

        case "saveChatHistory":
            if let messages = payload["messages"] as? [[String: Any]] {
                chatHistoryManager.save(messages)
            }

        case "clearChatHistory":
            chatHistoryManager.clear()

        case "resetClaudeSession":
            claudeManager.resetSession()

        // MARK: 记忆系统消息
        case "addMemory":
            if let content = payload["content"] as? String,
               let typeStr = payload["type"] as? String {
                let memType = MemoryType(rawValue: typeStr) ?? .user
                if let entry = memoryManager?.add(type: memType, content: content) {
                    sendToJS(type: "memoryAdded", payload: [
                        "id": entry.id,
                        "type": entry.type.rawValue,
                        "content": entry.content
                    ])
                }
            }

        case "deleteMemory":
            if let id = payload["id"] as? String {
                let success = memoryManager?.delete(id: id) ?? false
                sendToJS(type: "memoryDeleted", payload: ["id": id, "success": success])
            }

        case "listMemories":
            let memories = memoryManager?.loadAll() ?? []
            let list = memories.map { entry -> [String: Any] in
                return [
                    "id": entry.id,
                    "type": entry.type.rawValue,
                    "content": entry.content,
                    "created": entry.created,
                    "updated": entry.updated
                ]
            }
            sendToJSRaw(type: "memoryList", jsonArray: list)

        case "searchMemories":
            if let query = payload["query"] as? String {
                let results = memoryManager?.search(query: query) ?? []
                let list = results.map { entry -> [String: Any] in
                    return [
                        "id": entry.id,
                        "type": entry.type.rawValue,
                        "content": entry.content
                    ]
                }
                sendToJSRaw(type: "memorySearchResults", jsonArray: list)
            }

        case "stateChange":
            if let state = payload["state"] as? String {
                debugLog("[State] → \(state)")
                if let window = webView?.window as? DesktopWindow {
                    let interactive = ["transition-in", "listening", "thinking",
                                       "speaking", "tool-executing"].contains(state)
                    if interactive {
                        window.enterInteractiveMode()
                    } else if state == "transition-out" {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                            window.exitInteractiveMode()
                        }
                    } else if state == "idle" {
                        window.exitInteractiveMode()
                    }
                }
            }

        case "pickVideoFile":
            if let stateName = payload["stateName"] as? String {
                pickVideoFile(for: stateName)
            }

        case "startHotkeyRecording":
            // TODO: 实现快捷键录制
            break

        default:
            print("[Bridge] Unknown message type: \(type)")
        }
    }

    // MARK: - Swift → JS

    /// 向 JS 发送消息
    func sendToJS(type: String, payload: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

        let escaped = jsonStr.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let js = "window.nativeBridge.receive('\(type)', JSON.parse('\(escaped)'))"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    /// 向 JS 发送原始 JSON 数组
    func sendToJSRaw(type: String, jsonArray: [[String: Any]]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonArray),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

        let escaped = jsonStr.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let js = "window.nativeBridge.receive('\(type)', JSON.parse('\(escaped)'))"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - 文件选择

    private func pickVideoFile(for stateName: String) {
        DispatchQueue.main.async { [weak self] in
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [
                .init(filenameExtension: "mp4")!,
                .init(filenameExtension: "mov")!,
                .init(filenameExtension: "webm")!,
                .init(filenameExtension: "m4v")!,
            ]
            panel.title = "选择视频文件 - \(stateName)"

            if panel.runModal() == .OK, let url = panel.url {
                self?.sendToJS(type: "videoFilePicked", payload: [
                    "stateName": stateName,
                    "path": url.path
                ])
            }
        }
    }
}
