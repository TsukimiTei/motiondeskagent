import AppKit
import WebKit

/// Swift ↔ WebView 双向通信桥
class WebViewBridge: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private let claudeManager: ClaudeCLIManager
    private let configManager: ConfigManager
    private let chatHistoryManager: ChatHistoryManager

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

        // 设置 Claude 输出回调
        // stream-json 的 assistant 事件包含完整文本（非增量），所以发送为 replace 模式
        claudeManager.onToken = { [weak self] token in
            self?.sendToJS(type: "claudeReplace", payload: ["text": token])
        }
        claudeManager.onDone = { [weak self] in
            self?.sendToJS(type: "claudeDone", payload: [:])
        }
        claudeManager.onError = { [weak self] error in
            self?.sendToJS(type: "claudeError", payload: ["error": error])
        }
    }

    /// 处理从 JS 发来的消息
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

        case "stateChange":
            if let state = payload["state"] as? String {
                debugLog("[State] → \(state)")
                if let window = webView?.window as? DesktopWindow {
                    let interactive = ["transition-in", "listening", "thinking", "speaking"].contains(state)
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

    /// 打开文件选择对话框选择视频
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
