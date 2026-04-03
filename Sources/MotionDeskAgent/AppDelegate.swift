import AppKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var desktopWindow: DesktopWindow!
    var settingsWindow: SettingsWindow?
    var statusItem: NSStatusItem!
    var hotkeyManager: HotkeyManager!
    var claudeManager: ClaudeCLIManager!
    var configManager: ConfigManager!
    var chatHistoryManager: ChatHistoryManager!
    var memoryManager: MemoryManager!
    var systemPromptManager: SystemPromptManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("[App] didFinishLaunching")
        NSApp.setActivationPolicy(.regular)

        // 初始化管理器
        configManager = ConfigManager()
        chatHistoryManager = ChatHistoryManager()
        claudeManager = ClaudeCLIManager()
        memoryManager = MemoryManager()
        systemPromptManager = SystemPromptManager(configManager: configManager)

        // 连接记忆到系统提示词
        systemPromptManager.setMemoryManager(memoryManager)

        // 从配置读取 claude 路径
        let config = configManager.load()
        if let path = config["claudePath"] as? String, !path.isEmpty {
            claudeManager.setClaudePath(path)
        }

        // 设置系统提示词
        claudeManager.systemPrompt = systemPromptManager.buildSystemPrompt()

        debugLog("[App] Managers initialized (with memory & system prompt)")

        // 创建窗口和桥接
        desktopWindow = DesktopWindow(config: configManager)
        desktopWindow.bridge = WebViewBridge(
            webView: desktopWindow.webView,
            claudeManager: claudeManager,
            configManager: configManager,
            chatHistoryManager: chatHistoryManager
        )
        // 注入记忆管理器到 Bridge
        desktopWindow.bridge?.setMemoryManager(memoryManager)

        desktopWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        debugLog("[App] Window visible: \(desktopWindow.isVisible), level: \(desktopWindow.level.rawValue)")

        // 快捷键管理
        hotkeyManager = HotkeyManager { [weak self] in
            // 每次激活时刷新系统提示词（包含最新记忆）
            self?.refreshSystemPrompt()
            self?.desktopWindow.bridge?.sendToJS(type: "hotkeyActivate", payload: [:])
        }
        hotkeyManager.start()

        setupStatusBar()
        debugLog("[App] Startup complete")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// 刷新系统提示词（记忆变化时调用）
    private func refreshSystemPrompt() {
        claudeManager.systemPrompt = systemPromptManager.buildSystemPrompt()
    }

    // MARK: - 菜单栏

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🎭"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示角色", action: #selector(showCharacter), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "新对话", action: #selector(newSession), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "查看记忆", action: #selector(showMemories), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func showCharacter() {
        desktopWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        settingsWindow = SettingsWindow(
            configManager: configManager,
            desktopBridge: desktopWindow.bridge
        )
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func newSession() {
        claudeManager.resetSession()
        refreshSystemPrompt()
        desktopWindow.bridge?.sendToJS(type: "claudeDone", payload: [:])
    }

    @objc private func showMemories() {
        let memories = memoryManager.loadAll()
        let count = memories.count
        let summary = memories.prefix(5).map { "• [\($0.type.label)] \($0.content.prefix(60))" }.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = "Agent 记忆 (\(count) 条)"
        alert.informativeText = summary.isEmpty ? "暂无记忆" : summary + (count > 5 ? "\n\n...还有 \(count - 5) 条" : "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "清除全部")
        alert.runModal()
    }

    @objc private func quitApp() {
        claudeManager.stop()
        NSApp.terminate(nil)
    }
}
