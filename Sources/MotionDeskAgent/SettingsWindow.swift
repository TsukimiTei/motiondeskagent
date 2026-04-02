import AppKit
import WebKit

/// 独立的设置窗口（浮在所有窗口上方，可交互）
class SettingsWindow: NSPanel {
    let webView: WKWebView
    private var configManager: ConfigManager
    private weak var desktopBridge: WebViewBridge?

    init(configManager: ConfigManager, desktopBridge: WebViewBridge?) {
        self.configManager = configManager
        self.desktopBridge = desktopBridge

        let webConfig = WKWebViewConfiguration()
        webConfig.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webConfig.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 620), configuration: webConfig)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.title = "MotionDeskAgent 设置"
        self.level = .floating
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        self.contentView = webView
        self.center()

        webView.configuration.userContentController.add(
            SettingsMessageHandler(configManager: configManager, desktopBridge: desktopBridge, window: self),
            name: "settings"
        )

        loadSettingsPage()
    }

    private func loadSettingsPage() {
        // 自动检测 claude 路径
        let claudePath = findClaudePath()

        var config = configManager.load()
        // 如果配置中没有 claudePath，用自动检测的
        if config["claudePath"] == nil {
            config["claudePath"] = claudePath ?? ""
        }

        // 获取桌面列表
        let spaces = SpaceManager.getSpaceList()
        let spacesJSON = spaces.map { ["index": $0.index, "spaceId": $0.spaceId, "isCurrent": $0.isCurrent] as [String: Any] }
        let spacesData = (try? JSONSerialization.data(withJSONObject: spacesJSON)) ?? Data("[]".utf8)
        let spacesStr = String(data: spacesData, encoding: .utf8) ?? "[]"

        guard let configJSON = try? JSONSerialization.data(withJSONObject: config),
              let configStr = String(data: configJSON, encoding: .utf8) else { return }

        let html = Self.settingsHTML(configJSON: configStr, detectedPath: claudePath ?? "", spacesJSON: spacesStr)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func reload() {
        loadSettingsPage()
    }

    /// 重新加载页面但保持当前 tab
    func reloadKeepingTab() {
        // 先获取当前 tab，重载后恢复
        webView.evaluateJavaScript(
            "document.querySelector('.tab.active')?.textContent || ''"
        ) { [weak self] result, _ in
            self?.loadSettingsPage()
            if let tabText = result as? String, !tabText.isEmpty {
                // 延迟一点等页面加载完
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let tabMap = ["Claude": "claude", "桌面": "desktop", "位置": "position",
                                  "显示": "display", "状态": "states"]
                    for (key, value) in tabMap {
                        if tabText.contains(key) {
                            self?.webView.evaluateJavaScript("switchTab('\(value)')", completionHandler: nil)
                            break
                        }
                    }
                }
            }
        }
    }

    // findClaudePath() 在 extension 中定义

    // MARK: - HTML

    static func settingsHTML(configJSON: String, detectedPath: String, spacesJSON: String = "[]") -> String {
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="UTF-8">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            background: #1a1a20; color: #e6e6f0;
            padding: 20px; font-size: 13px;
        }
        h3 { font-size: 13px; color: #aab; margin: 16px 0 8px; font-weight: 500; }

        .tabs { display: flex; border-bottom: 1px solid #333; margin-bottom: 16px; gap: 2px; }
        .tab { flex: 1; padding: 8px 4px; text-align: center; cursor: pointer;
               border-bottom: 2px solid transparent; color: #aab; font-size: 12px;
               white-space: nowrap; }
        .tab.active { color: #648cff; border-bottom-color: #648cff; }
        .tab:hover { color: #e6e6f0; }

        .section { display: none; }
        .section.active { display: block; }

        .form-row { display: flex; align-items: center; margin-bottom: 12px; gap: 10px; }
        .form-row label { width: 80px; flex-shrink: 0; color: #aab; font-size: 12px; }
        .form-row input[type="range"] { flex: 1; }
        .form-row input[type="number"] {
            width: 70px; background: #252530; border: 1px solid #444;
            border-radius: 6px; padding: 4px 8px; color: #e6e6f0;
            font-size: 12px; text-align: center;
        }
        .form-row .value { width: 50px; text-align: right; font-family: 'SF Mono', monospace;
                           font-size: 12px; color: #648cff; }

        input[type="range"] {
            -webkit-appearance: none; height: 4px;
            background: rgba(255,255,255,0.1); border-radius: 2px;
        }
        input[type="range"]::-webkit-slider-thumb {
            -webkit-appearance: none; width: 14px; height: 14px;
            background: #648cff; border-radius: 50%; cursor: pointer;
        }

        .state-item { border: 1px solid #333; border-radius: 8px; padding: 10px; margin-bottom: 10px; }
        .state-header { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; }
        .state-name { font-family: 'SF Mono', monospace; font-size: 11px;
                      background: rgba(100,140,255,0.15); color: #648cff;
                      padding: 2px 8px; border-radius: 4px; }
        .state-label { font-size: 12px; color: #aab; }
        .clip-list { font-size: 11px; color: #888; }
        .clip-item { display: flex; align-items: center; gap: 6px; padding: 6px 8px;
                     background: rgba(255,255,255,0.02); border-radius: 6px; margin-bottom: 4px; }
        .clip-name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: #ccc; }
        .clip-modes { display: flex; gap: 3px; }
        .clip-mode { font-size: 10px; padding: 2px 6px; border-radius: 4px; cursor: pointer;
                     border: 1px solid #444; color: #888; background: transparent; white-space: nowrap; }
        .clip-mode.active { border-color: #648cff; color: #648cff; background: rgba(100,140,255,0.1); }
        .clip-mode:hover { border-color: #888; color: #ccc; }
        .clip-mode.processing { border-color: #f0ad4e; color: #f0ad4e; opacity: 0.7; cursor: wait; }
        .clip-remove { font-size: 14px; color: #666; cursor: pointer; padding: 0 4px; }
        .clip-remove:hover { color: #f87171; }
        .clip-add { font-size: 11px; color: #648cff; background: rgba(100,140,255,0.08);
                    border: 1px dashed rgba(100,140,255,0.3); border-radius: 6px;
                    padding: 5px; cursor: pointer; margin-top: 4px; text-align: center; }
        .clip-add:hover { background: rgba(100,140,255,0.15); }

        .btn { padding: 6px 14px; border-radius: 6px; border: none; cursor: pointer; font-size: 12px; }
        .btn-primary { background: #648cff; color: white; }

        /* Claude CLI 设置 */
        .cli-status { display: flex; align-items: center; gap: 10px; margin-bottom: 16px;
                      padding: 12px; background: rgba(255,255,255,0.03); border-radius: 8px;
                      border: 1px solid #333; }
        .cli-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
        .cli-dot.found { background: #4ade80; box-shadow: 0 0 6px rgba(74,222,128,0.4); }
        .cli-dot.missing { background: #f87171; box-shadow: 0 0 6px rgba(248,113,113,0.4); }
        .cli-info { flex: 1; }
        .cli-info .label { font-size: 11px; color: #888; }
        .cli-info .path { font-family: 'SF Mono', monospace; font-size: 12px; color: #e6e6f0;
                         word-break: break-all; }
        .cli-info .path.missing { color: #f87171; }

        .cli-path-input { display: flex; gap: 8px; margin-top: 12px; }
        .cli-path-input input {
            flex: 1; background: #252530; border: 1px solid #444; border-radius: 6px;
            padding: 6px 10px; color: #e6e6f0; font-size: 12px;
            font-family: 'SF Mono', monospace; outline: none;
        }
        .cli-path-input input:focus { border-color: #648cff; }

        .cli-actions { display: flex; gap: 8px; margin-top: 12px; }
        .cli-actions .btn { flex: 1; }
        .btn-outline { background: rgba(100,140,255,0.08); color: #648cff;
                       border: 1px solid rgba(100,140,255,0.3); }
        .btn-outline:hover { background: rgba(100,140,255,0.15); }

        .cli-version { font-size: 11px; color: #888; margin-top: 8px; padding: 8px;
                       background: rgba(0,0,0,0.2); border-radius: 6px;
                       font-family: 'SF Mono', monospace; white-space: pre-wrap; }

        /* 桌面选择 */
        .space-grid { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
        .space-card { width: 110px; padding: 14px 10px; border-radius: 10px; text-align: center;
                      cursor: pointer; border: 2px solid #333; background: rgba(255,255,255,0.02);
                      transition: all 0.2s; }
        .space-card:hover { border-color: #555; background: rgba(255,255,255,0.05); }
        .space-card.active { border-color: #648cff; background: rgba(100,140,255,0.08); }
        .space-card.current::after { content: '当前'; display: block; font-size: 9px;
                                     color: #4ade80; margin-top: 4px; }
        .space-card .space-num { font-size: 22px; font-weight: 600; color: #e6e6f0; }
        .space-card .space-label { font-size: 10px; color: #888; margin-top: 2px; }
        .space-card-all { border-style: dashed; }
        .space-card-all .space-num { font-size: 16px; }
        .space-refresh { font-size: 11px; color: #648cff; background: none; border: none;
                         cursor: pointer; margin-top: 12px; }
        .space-refresh:hover { text-decoration: underline; }
        </style>
        </head>
        <body>
        <div class="tabs">
            <div class="tab active" onclick="switchTab('claude')">Claude CLI</div>
            <div class="tab" onclick="switchTab('desktop')">桌面</div>
            <div class="tab" onclick="switchTab('position')">位置 & 大小</div>
            <div class="tab" onclick="switchTab('display')">显示</div>
            <div class="tab" onclick="switchTab('states')">状态 & 视频</div>
        </div>

        <!-- Claude CLI -->
        <div id="tab-claude" class="section active">
            <h3>Claude Code CLI</h3>
            <div class="cli-status" id="cli-status">
                <div class="cli-dot" id="cli-dot"></div>
                <div class="cli-info">
                    <div class="label" id="cli-label"></div>
                    <div class="path" id="cli-path-display"></div>
                </div>
            </div>

            <div class="cli-path-input">
                <input type="text" id="cli-path" placeholder="/usr/local/bin/claude">
                <button class="btn btn-outline" onclick="browseCLI()">浏览...</button>
            </div>

            <div class="cli-actions">
                <button class="btn btn-outline" onclick="autoDetect()">🔍 自动检测</button>
                <button class="btn btn-primary" onclick="saveCLIPath()">保存路径</button>
            </div>

            <div class="cli-version" id="cli-version" style="display:none"></div>
        </div>

        <!-- 位置 & 大小 -->
        <!-- 桌面选择 -->
        <div id="tab-desktop" class="section">
            <h3>选择角色显示的桌面</h3>
            <div class="space-grid" id="space-grid"></div>
            <button class="space-refresh" onclick="refreshSpaces()">↻ 刷新桌面列表</button>
        </div>

        <div id="tab-position" class="section">
            <h3>角色位置（百分比）</h3>
            <div class="form-row">
                <label>X 位置</label>
                <input type="range" id="charX" min="0" max="100" step="1" oninput="updatePosition()">
                <span class="value" id="charX-val"></span>
            </div>
            <div class="form-row">
                <label>Y 位置</label>
                <input type="range" id="charY" min="0" max="100" step="1" oninput="updatePosition()">
                <span class="value" id="charY-val"></span>
            </div>
            <h3>角色大小</h3>
            <div class="form-row">
                <label>宽度 (px)</label>
                <input type="number" id="charW" min="100" max="2000" step="10" oninput="updatePosition()">
            </div>
            <div class="form-row">
                <label>高度 (px)</label>
                <input type="number" id="charH" min="100" max="2000" step="10" oninput="updatePosition()">
            </div>
        </div>

        <!-- 显示 -->
        <div id="tab-display" class="section">
            <h3>Chromakey 抠色</h3>
            <div class="form-row">
                <label>阈值</label>
                <input type="range" id="threshold" min="0" max="1" step="0.01" oninput="updateDisplay()">
                <span class="value" id="threshold-val"></span>
            </div>
            <div class="form-row">
                <label>平滑度</label>
                <input type="range" id="smoothness" min="0" max="0.5" step="0.01" oninput="updateDisplay()">
                <span class="value" id="smoothness-val"></span>
            </div>
        </div>

        <!-- 状态 & 视频 -->
        <div id="tab-states" class="section">
            <div id="states-list"></div>
        </div>

        <script>
        const config = \(configJSON);
        const detectedPath = '\(detectedPath)';
        let spaces = \(spacesJSON);
        const selectedSpace = config.desktopSpace || 'all';

        // 位置 & 大小
        const charX = document.getElementById('charX');
        const charY = document.getElementById('charY');
        const charW = document.getElementById('charW');
        const charH = document.getElementById('charH');
        const threshold = document.getElementById('threshold');
        const smoothness = document.getElementById('smoothness');

        charX.value = config.characterX ?? 50;
        charY.value = config.characterY ?? 8;
        charW.value = config.characterWidth ?? 400;
        charH.value = config.characterHeight ?? 400;
        threshold.value = config.chromakeyThreshold ?? 0.3;
        smoothness.value = config.chromakeySmoothness ?? 0.1;
        updateLabels();

        // Claude CLI
        const cliPathInput = document.getElementById('cli-path');
        const savedPath = config.claudePath || '';
        cliPathInput.value = savedPath || detectedPath;
        updateCLIStatus(cliPathInput.value, !!detectedPath);

        renderStates();

        function sendMsg(type, payload) {
            window.webkit?.messageHandlers?.settings?.postMessage({type, payload});
        }

        function updateCLIStatus(path, isValid) {
            const dot = document.getElementById('cli-dot');
            const label = document.getElementById('cli-label');
            const display = document.getElementById('cli-path-display');

            if (path && isValid) {
                dot.className = 'cli-dot found';
                label.textContent = '已找到 Claude CLI';
                display.textContent = path;
                display.className = 'path';
                // 请求版本信息
                sendMsg('checkCLI', { path });
            } else if (path) {
                dot.className = 'cli-dot missing';
                label.textContent = '路径无效';
                display.textContent = path;
                display.className = 'path missing';
            } else {
                dot.className = 'cli-dot missing';
                label.textContent = '未找到 Claude CLI';
                display.textContent = '请手动指定路径或点击自动检测';
                display.className = 'path missing';
            }
        }

        function autoDetect() {
            sendMsg('autoDetectCLI', {});
        }

        function browseCLI() {
            sendMsg('browseCLI', {});
        }

        function saveCLIPath() {
            const path = cliPathInput.value.trim();
            sendMsg('saveCLIPath', { path });
        }

        function updateLabels() {
            document.getElementById('charX-val').textContent = charX.value + '%';
            document.getElementById('charY-val').textContent = charY.value + '%';
            document.getElementById('threshold-val').textContent = parseFloat(threshold.value).toFixed(2);
            document.getElementById('smoothness-val').textContent = parseFloat(smoothness.value).toFixed(2);
        }

        function updatePosition() {
            updateLabels();
            sendMsg('updateLayout', {
                characterX: parseInt(charX.value), characterY: parseInt(charY.value),
                characterWidth: parseInt(charW.value), characterHeight: parseInt(charH.value),
            });
        }

        function updateDisplay() {
            updateLabels();
            sendMsg('updateDisplay', {
                chromakeyThreshold: parseFloat(threshold.value),
                chromakeySmoothness: parseFloat(smoothness.value),
            });
        }

        function switchTab(name) {
            const tabMap = { claude: 'Claude', desktop: '桌面', position: '位置', display: '显示', states: '状态' };
            document.querySelectorAll('.tab').forEach(t => {
                t.classList.toggle('active', t.textContent.includes(tabMap[name] || ''));
            });
            document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
            document.getElementById('tab-' + name).classList.add('active');
        }

        function renderStates() {
            const list = document.getElementById('states-list');
            let html = '';
            for (const [name, state] of Object.entries(config.states || {})) {
                // 新格式：clip 是单个对象 {path, loopMode}，不是数组
                const clip = state.clip;
                let clipHTML = '';
                if (clip && clip.path) {
                    const mode = clip.loopMode || 'loop';
                    const fileName = clip.path.split('/').pop();
                    clipHTML = '<div class="clip-item">' +
                        '<span class="clip-name" title="' + clip.path + '">' + fileName + '</span>' +
                        '<div class="clip-modes">' +
                        '<button class="clip-mode ' + (mode === 'loop' ? 'active' : '') +
                            '" onclick="setClipMode(\\'' + name + '\\',\\'loop\\')">Loop</button>' +
                        '<button class="clip-mode ' + (mode === 'pingpong' ? 'active' : '') +
                            '" id="pp-' + name +
                            '" onclick="setClipMode(\\'' + name + '\\',\\'pingpong\\')">∞ Loop</button>' +
                        '</div>' +
                        '<span class="clip-remove" onclick="removeClip(\\'' + name + '\\')">✕</span>' +
                        '</div>';
                }
                const btnLabel = clip && clip.path ? '更换视频' : '选择视频';
                html += '<div class="state-item">' +
                    '<div class="state-header"><span class="state-name">' + name +
                    '</span><span class="state-label">' + (state.label || '') + '</span></div>' +
                    '<div class="clip-list">' + (clipHTML || '<em style="color:#666">暂无视频</em>') + '</div>' +
                    '<div class="clip-add" onclick="pickVideo(\\'' + name + '\\')">' + btnLabel + '</div></div>';
            }
            list.innerHTML = html;
        }

        function pickVideo(stateName) { sendMsg('pickVideo', { stateName }); }

        // 桌面选择
        renderSpaces();

        function renderSpaces() {
            const grid = document.getElementById('space-grid');
            let html = '<div class="space-card space-card-all ' + (selectedSpace === 'all' ? 'active' : '') +
                '" onclick="selectSpace(\\'all\\')">' +
                '<div class="space-num">✦</div><div class="space-label">所有桌面</div></div>';
            spaces.forEach(s => {
                html += '<div class="space-card ' +
                    (String(s.spaceId) === String(selectedSpace) ? 'active' : '') +
                    (s.isCurrent ? ' current' : '') +
                    '" onclick="selectSpace(\\'' + s.spaceId + '\\')">' +
                    '<div class="space-num">' + s.index + '</div>' +
                    '<div class="space-label">桌面 ' + s.index + '</div></div>';
            });
            grid.innerHTML = html;
        }

        function selectSpace(spaceId) {
            sendMsg('setDesktopSpace', { spaceId });
        }

        function refreshSpaces() {
            sendMsg('refreshSpaces', {});
        }

        function removeClip(stateName) {
            sendMsg('removeClip', { stateName });
        }

        function setClipMode(stateName, mode) {
            if (mode === 'pingpong') {
                const btn = document.getElementById('pp-' + stateName);
                if (btn) { btn.classList.add('processing'); btn.textContent = '处理中...'; }
            }
            sendMsg('setClipMode', { stateName, mode });
        }

        // 接收 Swift 回调
        window.settingsCallback = {
            cliDetected: function(path) {
                cliPathInput.value = path;
                updateCLIStatus(path, true);
            },
            cliNotFound: function() {
                updateCLIStatus('', false);
            },
            cliVersion: function(version) {
                const el = document.getElementById('cli-version');
                el.style.display = 'block';
                el.textContent = version;
            },
            cliPathSaved: function(path, valid) {
                updateCLIStatus(path, valid);
            },
            spacesUpdated: function(newSpaces, newSelected) {
                spaces = newSpaces;
                renderSpaces();
            }
        };
        </script>
        </body>
        </html>
        """;
    }
}

/// 处理设置窗口中 JS 发来的消息
class SettingsMessageHandler: NSObject, WKScriptMessageHandler {
    private let configManager: ConfigManager
    private weak var desktopBridge: WebViewBridge?
    private weak var window: SettingsWindow?

    init(configManager: ConfigManager, desktopBridge: WebViewBridge?, window: SettingsWindow) {
        self.configManager = configManager
        self.desktopBridge = desktopBridge
        self.window = window
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        let payload = body["payload"] as? [String: Any] ?? [:]

        switch type {
        case "updateLayout":
            var config = configManager.load()
            for key in ["characterX", "characterY", "characterWidth", "characterHeight"] {
                if let v = payload[key] { config[key] = v }
            }
            configManager.save(config)
            desktopBridge?.sendToJS(type: "updateLayout", payload: payload)

        case "updateDisplay":
            var config = configManager.load()
            if let t = payload["chromakeyThreshold"] { config["chromakeyThreshold"] = t }
            if let s = payload["chromakeySmoothness"] { config["chromakeySmoothness"] = s }
            configManager.save(config)
            desktopBridge?.sendToJS(type: "updateDisplay", payload: payload)

        case "autoDetectCLI":
            DispatchQueue.global().async { [weak self] in
                if let path = self?.window?.findClaudePath() {
                    DispatchQueue.main.async {
                        self?.callJS("window.settingsCallback.cliDetected('\(path)')")
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.callJS("window.settingsCallback.cliNotFound()")
                    }
                }
            }

        case "saveCLIPath":
            if let path = payload["path"] as? String {
                var config = configManager.load()
                config["claudePath"] = path
                configManager.save(config)
                let valid = FileManager.default.isExecutableFile(atPath: path)
                callJS("window.settingsCallback.cliPathSaved('\(path)', \(valid))")
            }

        case "checkCLI":
            if let path = payload["path"] as? String {
                DispatchQueue.global().async { [weak self] in
                    let version = self?.getClaudeVersion(path: path) ?? "无法获取版本"
                    let escaped = version.replacingOccurrences(of: "'", with: "\\'")
                        .replacingOccurrences(of: "\n", with: "\\n")
                    DispatchQueue.main.async {
                        self?.callJS("window.settingsCallback.cliVersion('\(escaped)')")
                    }
                }
            }

        case "browseCLI":
            DispatchQueue.main.async { [weak self] in
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.title = "选择 Claude CLI 可执行文件"
                panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
                if panel.runModal() == .OK, let url = panel.url {
                    self?.callJS("window.settingsCallback.cliDetected('\(url.path)')")
                    var config = self?.configManager.load() ?? [:]
                    config["claudePath"] = url.path
                    self?.configManager.save(config)
                }
            }

        case "pickVideo":
            if let stateName = payload["stateName"] as? String {
                DispatchQueue.main.async { [weak self] in
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.allowsMultipleSelection = false
                    panel.allowedContentTypes = [
                        .init(filenameExtension: "mp4")!,
                        .init(filenameExtension: "mov")!,
                        .init(filenameExtension: "webm")!,
                    ]
                    if panel.runModal() == .OK, let url = panel.url {
                        self?.setClipForState(stateName: stateName, path: url.path, loopMode: "loop")
                    }
                }
            }

        case "removeClip":
            if let stateName = payload["stateName"] as? String {
                var config = configManager.load()
                if var states = config["states"] as? [String: Any],
                   var state = states[stateName] as? [String: Any] {
                    state.removeValue(forKey: "clip")
                    states[stateName] = state
                    config["states"] = states
                    configManager.save(config)
                    desktopBridge?.sendToJS(type: "config", payload: config)
                    window?.reloadKeepingTab()
                }
            }

        case "setClipMode":
            if let stateName = payload["stateName"] as? String,
               let mode = payload["mode"] as? String {
                handleSetClipMode(stateName: stateName, mode: mode)
            }

        case "setDesktopSpace":
            if let spaceIdStr = payload["spaceId"] as? String {
                var config = configManager.load()
                config["desktopSpace"] = spaceIdStr
                configManager.save(config)

                // 获取桌面窗口并移动
                if let desktopWindow = NSApp.windows.first(where: { $0 is DesktopWindow }) as? DesktopWindow {
                    if spaceIdStr == "all" {
                        SpaceManager.setWindowOnAllSpaces(desktopWindow, allSpaces: true)
                    } else if let spaceId = UInt64(spaceIdStr) {
                        SpaceManager.setWindowOnAllSpaces(desktopWindow, allSpaces: false)
                        SpaceManager.moveWindow(desktopWindow, toSpace: CGSSpaceID(spaceId))
                    }
                }
                window?.reload()
            }

        case "refreshSpaces":
            window?.reload()

        default:
            break
        }
    }

    /// 设置状态的视频（替换，每个状态只有一个）
    private func setClipForState(stateName: String, path: String, loopMode: String) {
        var config = configManager.load()
        if var states = config["states"] as? [String: Any],
           var state = states[stateName] as? [String: Any] {
            state["clip"] = ["path": path, "loopMode": loopMode] as [String: Any]
            states[stateName] = state
            config["states"] = states
            configManager.save(config)
            desktopBridge?.sendToJS(type: "config", payload: config)
            window?.reloadKeepingTab()
        }
    }

    /// 设置 clip 的循环模式
    private func handleSetClipMode(stateName: String, mode: String) {
        var config = configManager.load()
        guard var states = config["states"] as? [String: Any],
              var state = states[stateName] as? [String: Any],
              var clip = state["clip"] as? [String: Any],
              let currentPath = clip["path"] as? String else { return }

        // 获取原始路径（pingpong 模式下可能已被替换为拼接版本）
        let originalPath = clip["originalPath"] as? String ?? currentPath

        if mode == "pingpong" {
            DispatchQueue.global().async { [weak self] in
                let pingpongPath = self?.generatePingPong(inputPath: originalPath)
                DispatchQueue.main.async {
                    if let pp = pingpongPath {
                        clip = ["path": pp, "loopMode": "pingpong", "originalPath": originalPath]
                    } else {
                        clip["loopMode"] = "pingpong"
                    }
                    state["clip"] = clip
                    states[stateName] = state
                    config["states"] = states
                    self?.configManager.save(config)
                    self?.desktopBridge?.sendToJS(type: "config", payload: config)
                    self?.window?.reloadKeepingTab()
                }
            }
        } else {
            // 恢复原始路径
            state["clip"] = ["path": originalPath, "loopMode": "loop"] as [String: Any]
            states[stateName] = state
            config["states"] = states
            configManager.save(config)
            desktopBridge?.sendToJS(type: "config", payload: config)
            window?.reloadKeepingTab()
        }
    }

    /// 用 ffmpeg 生成正放+倒放拼接视频
    private func generatePingPong(inputPath: String) -> String? {
        let inputURL = URL(fileURLWithPath: inputPath)
        let dir = inputURL.deletingLastPathComponent()
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension
        let outputPath = dir.appendingPathComponent("\(baseName)_pingpong.\(ext)").path

        // 如果已经存在就直接返回
        if FileManager.default.fileExists(atPath: outputPath) {
            return outputPath
        }

        // 查找 ffmpeg
        let ffmpegPath = findFFmpeg()
        guard let ffmpeg = ffmpegPath else {
            debugLog("[FFmpeg] ffmpeg not found")
            return nil
        }

        // 步骤1：生成倒放视频
        let reversedPath = dir.appendingPathComponent("\(baseName)_reversed.\(ext)").path
        let reverseProc = Process()
        reverseProc.executableURL = URL(fileURLWithPath: ffmpeg)
        reverseProc.arguments = ["-i", inputPath, "-vf", "reverse", "-an", reversedPath, "-y"]
        reverseProc.standardOutput = Pipe()
        reverseProc.standardError = Pipe()
        do {
            try reverseProc.run()
            reverseProc.waitUntilExit()
            guard reverseProc.terminationStatus == 0 else { return nil }
        } catch { return nil }

        // 步骤2：拼接正放+倒放
        let concatFile = dir.appendingPathComponent("\(baseName)_concat.txt").path
        let concatContent = "file '\(inputPath)'\nfile '\(reversedPath)'\n"
        try? concatContent.write(toFile: concatFile, atomically: true, encoding: .utf8)

        let concatProc = Process()
        concatProc.executableURL = URL(fileURLWithPath: ffmpeg)
        concatProc.arguments = ["-f", "concat", "-safe", "0", "-i", concatFile, "-c", "copy", outputPath, "-y"]
        concatProc.standardOutput = Pipe()
        concatProc.standardError = Pipe()
        do {
            try concatProc.run()
            concatProc.waitUntilExit()
        } catch { return nil }

        // 清理临时文件
        try? FileManager.default.removeItem(atPath: reversedPath)
        try? FileManager.default.removeItem(atPath: concatFile)

        return FileManager.default.fileExists(atPath: outputPath) ? outputPath : nil
    }

    private func findFFmpeg() -> String? {
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private func callJS(_ js: String) {
        window?.webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func getClaudeVersion(path: String) -> String? {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--version"]
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

}

extension SettingsWindow {
    func findClaudePath() -> String? {
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
           !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }
}
