import Foundation

/// 管理 Claude CLI 调用：每条消息启动一次 `claude -p`，用 --resume 保持会话
class ClaudeCLIManager {
    private var currentProcess: Process?
    private var sessionId: String?
    private var claudePath: String?

    /// 收到流式文本的回调
    var onToken: ((String) -> Void)?
    /// 回复完成的回调
    var onDone: (() -> Void)?
    /// 错误回调
    var onError: ((String) -> Void)?

    init() {}

    /// 设置 claude 可执行文件路径
    func setClaudePath(_ path: String) {
        self.claudePath = path
    }

    /// 发送消息给 Claude
    func send(message: String) {
        // 取消之前的请求
        stop()

        let path = claudePath ?? findClaudeBinary()
        guard FileManager.default.isExecutableFile(atPath: path) else {
            onError?("找不到 Claude CLI: \(path)")
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

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }

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
                if !errStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DispatchQueue.main.async {
                        self?.onError?(errStr.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
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
            onError?("无法启动 Claude CLI: \(error.localizedDescription)")
        }
    }

    /// 解析 stream-json 事件
    private func handleStreamEvent(type: String, json: [String: Any]) {
        switch type {
        case "assistant":
            // 提取文本内容
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String {
                        DispatchQueue.main.async { [weak self] in
                            self?.onToken?(text)
                        }
                    }
                }
            }

        case "result":
            // 保存 session_id 用于后续 --resume
            if let sid = json["session_id"] as? String {
                sessionId = sid
                debugLog("[Claude] Session: \(sid)")
            }
            DispatchQueue.main.async { [weak self] in
                self?.onDone?()
            }

        default:
            // 忽略 system, rate_limit_event 等
            break
        }
    }

    /// 重置会话
    func resetSession() {
        stop()
        sessionId = nil
    }

    /// 停止当前请求
    func stop() {
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
