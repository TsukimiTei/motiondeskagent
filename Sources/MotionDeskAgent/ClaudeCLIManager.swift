import Foundation

// MARK: - 事件类型

/// Claude CLI stream-json 事件，统一的事件模型
enum ClaudeStreamEvent {
    /// 会话初始化：模型名称、可用工具列表
    case sessionInit(model: String, tools: [String])
    /// 增量文本（来自 stream_event content_block_delta）
    case textDelta(text: String)
    /// 完整文本块（来自 assistant 事件的 text content block）
    case textComplete(text: String)
    /// 工具调用开始
    case toolUseStart(id: String, name: String, input: String)
    /// 工具执行进度
    case toolProgress(name: String, elapsed: Double)
    /// 工具执行完成摘要
    case toolResult(name: String, summary: String)
    /// 思考过程（extended thinking）
    case thinking(text: String)
    /// 回复完成
    case done(sessionId: String?, cost: Double?, duration: Double?)
    /// 错误
    case error(message: String, isRetryable: Bool)
}

// MARK: - Manager

/// 管理 Claude CLI 调用：每条消息启动一次 `claude -p`，用 --resume 保持会话
class ClaudeCLIManager {
    private var currentProcess: Process?
    private var sessionId: String?
    private var claudePath: String?

    /// 系统提示词（注入 agent 人格 + 记忆上下文）
    var systemPrompt: String?

    /// 统一事件回调
    var onEvent: ((ClaudeStreamEvent) -> Void)?

    // 重试配置
    private let maxRetries = 2
    private let retryDelay: TimeInterval = 1.5
    private var retryCount = 0
    private var lastMessage: String?

    // 超时配置
    private var timeoutTimer: DispatchSourceTimer?
    private let timeoutInterval: TimeInterval = 120  // 秒
    private var lastActivityTime = Date()

    init() {}

    /// 设置 claude 可执行文件路径
    func setClaudePath(_ path: String) {
        self.claudePath = path
    }

    /// 发送消息给 Claude
    func send(message: String) {
        // 取消之前的请求
        stop()
        lastMessage = message

        let path = claudePath ?? findClaudeBinary()
        guard FileManager.default.isExecutableFile(atPath: path) else {
            emitEvent(.error(message: "找不到 Claude CLI: \(path)", isRetryable: false))
            return
        }

        let proc = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.executableURL = URL(fileURLWithPath: path)

        var args = ["-p", message, "--output-format", "stream-json", "--verbose"]
        // 如果有 session，用 --resume 继续对话
        if let sid = sessionId {
            args += ["--resume", sid]
        }
        // 系统提示词
        if let prompt = systemPrompt, !prompt.isEmpty {
            args += ["--system-prompt", prompt]
        }
        proc.arguments = args

        // 环境变量
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin",
                          "\(NSHomeDirectory())/.local/bin"]
        if let existing = env["PATH"] {
            env["PATH"] = extraPaths.joined(separator: ":") + ":" + existing
        }
        proc.environment = env
        proc.standardOutput = stdout
        proc.standardError = stderr

        // 逐行读取 stdout，解析 stream-json 事件
        var accumulated = ""
        lastActivityTime = Date()
        startTimeoutMonitor()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }

            self?.lastActivityTime = Date()

            // stream-json 每行一个 JSON 对象
            accumulated += chunk
            while let newlineRange = accumulated.range(of: "\n") {
                let line = String(accumulated[accumulated.startIndex..<newlineRange.lowerBound])
                accumulated = String(accumulated[newlineRange.upperBound...])

                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = json["type"] as? String else { continue }

                self?.handleStreamEvent(type: type, json: json)
            }
        }

        proc.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            self?.stopTimeoutMonitor()

            // 处理剩余的 accumulated
            if !accumulated.isEmpty,
               let lineData = accumulated.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let type = json["type"] as? String {
                self?.handleStreamEvent(type: type, json: json)
            }

            if proc.terminationStatus != 0 {
                // 读 stderr
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? "未知错误"
                let trimmed = errStr.trimmingCharacters(in: .whitespacesAndNewlines)

                if !trimmed.isEmpty {
                    // 尝试重试
                    if let self = self, self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        debugLog("[Claude] Retry \(self.retryCount)/\(self.maxRetries): \(trimmed)")
                        self.emitEvent(.error(message: "正在重试... (\(self.retryCount)/\(self.maxRetries))", isRetryable: true))
                        DispatchQueue.main.asyncAfter(deadline: .now() + self.retryDelay) {
                            if let msg = self.lastMessage {
                                self.sendInternal(message: msg)
                            }
                        }
                        return
                    }
                    self?.emitEvent(.error(message: trimmed, isRetryable: false))
                }
            } else {
                // 成功完成，重置重试计数
                self?.retryCount = 0
            }

            DispatchQueue.main.async {
                self?.currentProcess = nil
            }
        }

        do {
            try proc.run()
            currentProcess = proc
            debugLog("[Claude] Process started: \(args.joined(separator: " "))")
        } catch {
            emitEvent(.error(message: "无法启动 Claude CLI: \(error.localizedDescription)", isRetryable: false))
        }
    }

    /// 内部发送（用于重试，不重置 lastMessage）
    private func sendInternal(message: String) {
        // 停止当前进程但不重置 lastMessage
        currentProcess?.terminate()
        currentProcess = nil
        stopTimeoutMonitor()

        let path = claudePath ?? findClaudeBinary()
        guard FileManager.default.isExecutableFile(atPath: path) else {
            emitEvent(.error(message: "找不到 Claude CLI: \(path)", isRetryable: false))
            return
        }

        let proc = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.executableURL = URL(fileURLWithPath: path)

        var args = ["-p", message, "--output-format", "stream-json", "--verbose"]
        if let sid = sessionId {
            args += ["--resume", sid]
        }
        if let prompt = systemPrompt, !prompt.isEmpty {
            args += ["--system-prompt", prompt]
        }
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin",
                          "\(NSHomeDirectory())/.local/bin"]
        if let existing = env["PATH"] {
            env["PATH"] = extraPaths.joined(separator: ":") + ":" + existing
        }
        proc.environment = env
        proc.standardOutput = stdout
        proc.standardError = stderr

        var accumulated = ""
        lastActivityTime = Date()
        startTimeoutMonitor()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }

            self?.lastActivityTime = Date()

            accumulated += chunk
            while let newlineRange = accumulated.range(of: "\n") {
                let line = String(accumulated[accumulated.startIndex..<newlineRange.lowerBound])
                accumulated = String(accumulated[newlineRange.upperBound...])

                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = json["type"] as? String else { continue }

                self?.handleStreamEvent(type: type, json: json)
            }
        }

        proc.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            self?.stopTimeoutMonitor()

            if !accumulated.isEmpty,
               let lineData = accumulated.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
               let type = json["type"] as? String {
                self?.handleStreamEvent(type: type, json: json)
            }

            if proc.terminationStatus != 0 {
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? "未知错误"
                let trimmed = errStr.trimmingCharacters(in: .whitespacesAndNewlines)

                if !trimmed.isEmpty {
                    if let self = self, self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        debugLog("[Claude] Retry \(self.retryCount)/\(self.maxRetries)")
                        self.emitEvent(.error(message: "正在重试... (\(self.retryCount)/\(self.maxRetries))", isRetryable: true))
                        DispatchQueue.main.asyncAfter(deadline: .now() + self.retryDelay) {
                            if let msg = self.lastMessage {
                                self.sendInternal(message: msg)
                            }
                        }
                        return
                    }
                    self?.emitEvent(.error(message: trimmed, isRetryable: false))
                }
            } else {
                self?.retryCount = 0
            }

            DispatchQueue.main.async {
                self?.currentProcess = nil
            }
        }

        do {
            try proc.run()
            currentProcess = proc
        } catch {
            emitEvent(.error(message: "无法启动 Claude CLI: \(error.localizedDescription)", isRetryable: false))
        }
    }

    // MARK: - Stream Event 解析

    /// 解析 stream-json 事件（完整版）
    private func handleStreamEvent(type: String, json: [String: Any]) {
        switch type {

        // ── system 事件（会话初始化等）──
        case "system":
            let subtype = json["subtype"] as? String ?? ""
            if subtype == "init" {
                let model = json["model"] as? String ?? "unknown"
                let tools = json["tools"] as? [String] ?? []
                emitEvent(.sessionInit(model: model, tools: tools))
                debugLog("[Claude] Init: model=\(model), tools=\(tools.count)")
            }
            // 其他 subtype (status, api_retry 等) 仅记录日志
            else {
                debugLog("[Claude] System event: \(subtype)")
            }

        // ── assistant 事件（完整消息，包含 text 和 tool_use 块）──
        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    let blockType = block["type"] as? String ?? ""

                    if blockType == "text", let text = block["text"] as? String {
                        emitEvent(.textComplete(text: text))
                    }
                    else if blockType == "tool_use" {
                        let id = block["id"] as? String ?? ""
                        let name = block["name"] as? String ?? ""
                        let input: String
                        if let inputDict = block["input"] as? [String: Any],
                           let inputData = try? JSONSerialization.data(withJSONObject: inputDict),
                           let inputStr = String(data: inputData, encoding: .utf8) {
                            input = inputStr
                        } else {
                            input = "{}"
                        }
                        emitEvent(.toolUseStart(id: id, name: name, input: input))
                    }
                    else if blockType == "thinking", let text = block["thinking"] as? String {
                        emitEvent(.thinking(text: text))
                    }
                }
            }

        // ── stream_event 事件（增量流式）──
        case "stream_event":
            if let event = json["event"] as? [String: Any],
               let eventType = event["type"] as? String {

                switch eventType {
                case "content_block_start":
                    // 检查是否是 tool_use block
                    if let contentBlock = event["content_block"] as? [String: Any],
                       let cbType = contentBlock["type"] as? String,
                       cbType == "tool_use" {
                        let id = contentBlock["id"] as? String ?? ""
                        let name = contentBlock["name"] as? String ?? ""
                        emitEvent(.toolUseStart(id: id, name: name, input: ""))
                    }

                case "content_block_delta":
                    if let delta = event["delta"] as? [String: Any],
                       let deltaType = delta["type"] as? String {
                        if deltaType == "text_delta", let text = delta["text"] as? String {
                            emitEvent(.textDelta(text: text))
                        }
                        else if deltaType == "thinking_delta", let text = delta["thinking"] as? String {
                            emitEvent(.thinking(text: text))
                        }
                        // input_json_delta 用于工具输入流，暂不转发
                    }

                case "message_stop":
                    // 消息流结束，等待 result 事件
                    break

                default:
                    break
                }
            }

        // ── tool_progress 事件 ──
        case "tool_progress":
            let name = json["tool_name"] as? String ?? ""
            let elapsed = json["elapsed_time_seconds"] as? Double ?? 0
            emitEvent(.toolProgress(name: name, elapsed: elapsed))

        // ── tool_use_summary 事件 ──
        case "tool_use_summary":
            let summary = json["summary"] as? String ?? ""
            // 从 preceding_tool_use_ids 推断工具名
            let name = json["tool_name"] as? String ?? "tool"
            emitEvent(.toolResult(name: name, summary: summary))

        // ── result 事件（完成/错误）──
        case "result":
            let subtype = json["subtype"] as? String ?? "success"
            let sid = json["session_id"] as? String
            let cost = json["total_cost_usd"] as? Double
            let duration = json["duration_ms"] as? Double

            if let sid = sid {
                sessionId = sid
                debugLog("[Claude] Session: \(sid)")
            }

            if subtype.hasPrefix("error") {
                let errors = json["errors"] as? [String] ?? []
                let errMsg = errors.joined(separator: "\n")
                emitEvent(.error(message: errMsg.isEmpty ? "执行出错" : errMsg, isRetryable: false))
            }

            emitEvent(.done(sessionId: sid, cost: cost, duration: duration))

        default:
            debugLog("[Claude] Unhandled event type: \(type)")
        }
    }

    // MARK: - 超时监控

    private func startTimeoutMonitor() {
        stopTimeoutMonitor()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let elapsed = Date().timeIntervalSince(self.lastActivityTime)
            if elapsed >= self.timeoutInterval {
                debugLog("[Claude] Timeout after \(self.timeoutInterval)s")
                self.stop()
                self.emitEvent(.error(message: "Claude 响应超时，请重试", isRetryable: true))
            }
        }
        timer.resume()
        timeoutTimer = timer
    }

    private func stopTimeoutMonitor() {
        timeoutTimer?.cancel()
        timeoutTimer = nil
    }

    // MARK: - 事件发送

    private func emitEvent(_ event: ClaudeStreamEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    /// 重置会话
    func resetSession() {
        stop()
        sessionId = nil
        retryCount = 0
    }

    /// 停止当前请求
    func stop() {
        stopTimeoutMonitor()
        currentProcess?.terminate()
        currentProcess = nil
    }

    /// 查找 claude 可执行文件路径
    private func findClaudeBinary() -> String {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", "which claude"]
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }

        return "/usr/local/bin/claude"
    }
}
