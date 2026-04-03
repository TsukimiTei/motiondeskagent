import AppKit
import WebKit

/// 独立的聊天浮动面板——不遮挡其他窗口，只占屏幕底部
class ChatPanel: NSPanel, WKScriptMessageHandler {
    let webView: WKWebView
    private weak var claudeManager: ClaudeCLIManager?
    private weak var chatHistoryManager: ChatHistoryManager?
    var onDeactivate: (() -> Void)?

    init(claudeManager: ClaudeCLIManager, chatHistoryManager: ChatHistoryManager) {
        self.claudeManager = claudeManager
        self.chatHistoryManager = chatHistoryManager

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenW = screen.frame.width
        let panelW: CGFloat = min(screenW * 0.7, 900)
        let panelH: CGFloat = 350
        let panelX = (screenW - panelW) / 2
        let panelY: CGFloat = 40  // 底部留一点空间给 dock

        let webConfig = WKWebViewConfiguration()
        webConfig.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webConfig.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            configuration: webConfig
        )
        webView.setValue(false, forKey: "drawsBackground")

        super.init(
            contentRect: NSRect(x: panelX, y: panelY, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.contentView = webView

        webView.configuration.userContentController.add(self, name: "chat")

        // Claude 统一事件回调
        claudeManager.onEvent = { [weak self] event in
            self?.handleClaudeEvent(event)
        }

        loadChatHTML()
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Claude 事件处理

    private func handleClaudeEvent(_ event: ClaudeStreamEvent) {
        switch event {
        case .textComplete(let text):
            callJS("onClaudeReplace('\(Self.escapeJS(text))')")

        case .textDelta(let text):
            callJS("onClaudeTextDelta('\(Self.escapeJS(text))')")

        case .toolUseStart(_, let name, _):
            callJS("onClaudeToolStart('\(Self.escapeJS(name))')")

        case .toolProgress(let name, let elapsed):
            callJS("onClaudeToolProgress('\(Self.escapeJS(name))', \(elapsed))")

        case .toolResult(let name, let summary):
            callJS("onClaudeToolResult('\(Self.escapeJS(name))', '\(Self.escapeJS(summary))')")

        case .done(_, _, _):
            callJS("onClaudeDone()")

        case .error(let message, _):
            callJS("onClaudeError('\(Self.escapeJS(message))')")

        case .thinking(let text):
            callJS("onClaudeThinking('\(Self.escapeJS(text))')")

        case .sessionInit(_, _):
            break
        }
    }

    // MARK: - JS → Swift

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]

        switch type {
        case "sendMessage":
            if let content = payload["content"] as? String {
                claudeManager?.send(message: content)
            }
        case "deactivate":
            onDeactivate?()
        case "clearHistory":
            chatHistoryManager?.clear()
            claudeManager?.resetSession()
            loadChatHTML()
        default:
            break
        }
    }

    private func callJS(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private static func escapeJS(_ s: String) -> String {
        return s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    // MARK: - HTML

    private func loadChatHTML() {
        let history = chatHistoryManager?.load() ?? []
        let historyJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: history),
           let str = String(data: data, encoding: .utf8) {
            historyJSON = str
        } else {
            historyJSON = "[]"
        }

        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="UTF-8">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { background: transparent; overflow: hidden;
                     font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                     color: rgba(230,230,240,0.95); height: 100%; }
        .container { display: flex; flex-direction: column; height: 100%;
                     padding: 0 20px 12px; }

        /* 对话历史 */
        .messages { flex: 1; overflow-y: auto; display: flex; flex-direction: column;
                    gap: 8px; padding: 8px 0; scrollbar-width: thin;
                    scrollbar-color: rgba(100,100,120,0.3) transparent; }
        .messages::-webkit-scrollbar { width: 3px; }
        .messages::-webkit-scrollbar-thumb { background: rgba(100,100,120,0.3); border-radius: 2px; }

        .msg { padding: 10px 14px; border-radius: 12px; font-size: 13px; line-height: 1.6;
               backdrop-filter: blur(16px); max-width: 90%;
               animation: fadeIn 0.25s ease; word-wrap: break-word; }
        .msg.user { background: rgba(45,45,55,0.85); align-self: flex-end;
                    border-bottom-right-radius: 4px; border: 1px solid rgba(100,140,255,0.15); }
        .msg.assistant { background: rgba(20,20,25,0.88); align-self: flex-start;
                         border-bottom-left-radius: 4px; border: 1px solid rgba(80,80,100,0.3); }
        .msg.error { background: rgba(60,20,20,0.85); border-color: rgba(255,80,80,0.3); }

        /* 工具活动指示器 */
        .msg.tool { background: rgba(25,25,35,0.7); align-self: flex-start;
                    border: 1px solid rgba(100,180,255,0.15); font-size: 12px;
                    padding: 6px 12px; color: rgba(150,170,200,0.9); }
        .msg.tool .tool-icon { display: inline-block; margin-right: 6px; }
        .msg.tool .tool-name { color: rgba(100,180,255,0.9); font-weight: 500; }
        .msg.tool .tool-elapsed { color: rgba(120,130,150,0.7); font-size: 11px; margin-left: 8px; }
        .msg.tool.active { border-color: rgba(100,180,255,0.3); }
        .msg.tool.active .tool-icon { animation: pulse 1.5s infinite; }
        @keyframes pulse { 50% { opacity: 0.4; } }

        .msg pre { background: rgba(0,0,0,0.4); border-radius: 6px; padding: 8px;
                   margin: 6px 0; overflow-x: auto; font-size: 12px;
                   font-family: 'SF Mono', 'Fira Code', monospace; }
        .msg code { font-family: 'SF Mono', 'Fira Code', monospace; font-size: 12px; }
        .msg :not(pre) > code { background: rgba(255,255,255,0.08); padding: 1px 4px;
                                 border-radius: 3px; color: #e8b87a; }

        @keyframes fadeIn { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }

        .cursor { animation: blink 0.8s infinite; color: rgba(100,160,255,0.8); }
        @keyframes blink { 50% { opacity: 0; } }

        /* 控制栏 */
        .controls { display: flex; justify-content: center; gap: 10px; padding: 4px 0; }
        .ctrl-btn { font-size: 10px; color: rgba(160,165,180,0.6); background: rgba(255,255,255,0.04);
                    border: 1px solid rgba(80,80,100,0.25); border-radius: 14px;
                    padding: 2px 10px; cursor: pointer; }
        .ctrl-btn:hover { color: rgba(230,230,240,0.8); background: rgba(255,255,255,0.08); }

        /* Caption 输入 */
        .input-area { position: relative; padding-top: 6px; }
        .glow-line { height: 1px; margin: 0 10%;
                     background: linear-gradient(90deg, transparent, rgba(100,160,255,0.5) 30%,
                     rgba(130,200,255,0.8) 50%, rgba(100,160,255,0.5) 70%, transparent);
                     transition: all 0.3s; }
        .glow-line.focused { margin: 0 2%; box-shadow: 0 0 16px rgba(100,160,255,0.25); }
        .input-text { font-size: 24px; font-weight: 300; color: rgba(240,245,255,0.95);
                      text-align: center; padding: 10px 16px; outline: none; min-height: 40px;
                      max-height: 100px; overflow-y: auto; line-height: 1.3;
                      text-shadow: 0 0 24px rgba(100,160,255,0.12);
                      caret-color: rgba(130,190,255,0.9); }
        .input-text:empty::before { content: attr(data-placeholder);
                                     color: rgba(150,160,180,0.3); font-weight: 200;
                                     pointer-events: none; }
        .input-text.disabled { opacity: 0.35; }
        .hint { text-align: center; font-size: 10px; letter-spacing: 1.5px;
                color: rgba(140,150,170,0.35); padding: 3px 0; }
        </style>
        </head>
        <body>
        <div class="container">
            <div class="messages" id="messages"></div>
            <div class="controls">
                <button class="ctrl-btn" id="historyBtn" onclick="toggleHistory()">查看历史</button>
                <button class="ctrl-btn" onclick="clearAll()">新对话</button>
            </div>
            <div class="input-area">
                <div class="glow-line" id="glow"></div>
                <div class="input-text" id="input" contenteditable="true"
                     data-placeholder="说点什么..." onfocus="onFocus()" onblur="onBlur()"></div>
                <div class="hint" id="hint">Enter 发送 · Esc 退出</div>
            </div>
        </div>

        <script>
        const messagesEl = document.getElementById('messages');
        const inputEl = document.getElementById('input');
        const glowEl = document.getElementById('glow');
        const hintEl = document.getElementById('hint');

        let allMessages = \(historyJSON);
        let showAll = false;
        let streaming = false;
        let streamText = '';
        let activeTools = [];

        renderMessages();
        setTimeout(() => inputEl.focus(), 100);

        function send(type, payload) {
            window.webkit?.messageHandlers?.chat?.postMessage({type, payload});
        }

        // 键盘事件
        inputEl.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                const text = inputEl.innerText.trim();
                if (!text || streaming) return;
                allMessages.push({ role: 'user', content: text, timestamp: Date.now() });
                inputEl.innerText = '';
                streamText = '';
                streaming = false;
                activeTools = [];
                renderMessages();
                send('sendMessage', { content: text });
                hintEl.textContent = '思考中...';
            }
            if (e.key === 'Escape') {
                send('deactivate', {});
            }
        });

        function onFocus() { glowEl.classList.add('focused'); }
        function onBlur() { glowEl.classList.remove('focused'); }

        function toggleHistory() {
            showAll = !showAll;
            document.getElementById('historyBtn').textContent = showAll ? '只看最近' : '查看历史';
            renderMessages();
        }
        function clearAll() { allMessages = []; streamText = ''; activeTools = []; renderMessages(); send('clearHistory', {}); }

        // 渲染消息
        function renderMessages() {
            const msgs = showAll ? allMessages : getLastRound();
            let html = '';
            msgs.forEach(m => {
                if (m.role === 'tool') {
                    html += '<div class="msg tool' + (m.active ? ' active' : '') + '">' +
                            '<span class="tool-icon">⚙</span>' +
                            '<span class="tool-name">' + escapeHtml(m.toolName || '') + '</span>' +
                            (m.elapsed ? '<span class="tool-elapsed">' + m.elapsed.toFixed(1) + 's</span>' : '') +
                            (m.summary ? ' — ' + escapeHtml(m.summary) : '') +
                            '</div>';
                } else {
                    html += '<div class="msg ' + m.role + '">' + renderMarkdown(m.content) + '</div>';
                }
            });
            if (streaming && streamText) {
                html += '<div class="msg assistant">' + renderMarkdown(streamText) +
                        '<span class="cursor">▋</span></div>';
            }
            // 活动工具指示
            activeTools.forEach(t => {
                html += '<div class="msg tool active"><span class="tool-icon">⚙</span>' +
                        '<span class="tool-name">' + escapeHtml(t.name) + '</span>' +
                        '<span class="tool-elapsed">' + t.elapsed.toFixed(1) + 's</span></div>';
            });
            messagesEl.innerHTML = html;
            messagesEl.scrollTop = messagesEl.scrollHeight;
        }

        function escapeHtml(s) {
            return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        }

        function getLastRound() {
            if (allMessages.length === 0) return [];
            const result = [];
            for (let i = allMessages.length - 1; i >= 0; i--) {
                if (allMessages[i].role === 'assistant') {
                    result.unshift(allMessages[i]);
                    for (let j = i - 1; j >= 0; j--) {
                        if (allMessages[j].role === 'user') { result.unshift(allMessages[j]); break; }
                    }
                    break;
                }
            }
            if (result.length === 0 && allMessages.length > 0) result.push(allMessages[allMessages.length - 1]);
            return result;
        }

        // 简易 markdown 渲染
        function renderMarkdown(text) {
            if (!text) return '';
            let html = text
                .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                .replace(/```(\\w*)\\n([\\s\\S]*?)```/g, '<pre><code>$2</code></pre>')
                .replace(/`([^`]+)`/g, '<code>$1</code>')
                .replace(/\\*\\*(.+?)\\*\\*/g, '<strong>$1</strong>')
                .replace(/\\*(.+?)\\*/g, '<em>$1</em>')
                .replace(/\\n/g, '<br>');
            return html;
        }

        // Swift → JS 回调
        function onClaudeReplace(text) {
            streaming = true;
            streamText = text;
            hintEl.textContent = 'Enter 发送 · Esc 退出';
            renderMessages();
        }
        function onClaudeTextDelta(text) {
            streaming = true;
            streamText += text;
            renderMessages();
        }
        function onClaudeToolStart(name) {
            activeTools.push({ name: name, elapsed: 0 });
            renderMessages();
        }
        function onClaudeToolProgress(name, elapsed) {
            const tool = activeTools.find(t => t.name === name);
            if (tool) tool.elapsed = elapsed;
            renderMessages();
        }
        function onClaudeToolResult(name, summary) {
            const idx = activeTools.findIndex(t => t.name === name);
            if (idx >= 0) {
                const tool = activeTools.splice(idx, 1)[0];
                allMessages.push({ role: 'tool', toolName: name, summary: summary,
                                   elapsed: tool.elapsed, timestamp: Date.now() });
            }
            renderMessages();
        }
        function onClaudeDone() {
            if (streamText) {
                allMessages.push({ role: 'assistant', content: streamText, timestamp: Date.now() });
            }
            streaming = false;
            streamText = '';
            activeTools = [];
            hintEl.textContent = 'Enter 发送 · Esc 退出';
            renderMessages();
            inputEl.focus();
        }
        function onClaudeError(err) {
            allMessages.push({ role: 'error', content: '⚠️ ' + err, timestamp: Date.now() });
            streaming = false;
            streamText = '';
            activeTools = [];
            hintEl.textContent = 'Enter 发送 · Esc 退出';
            renderMessages();
        }
        function onClaudeThinking(text) {
            // 思考过程可以显示为淡色提示，暂存不显示
            hintEl.textContent = '思考中...';
        }
        </script>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
