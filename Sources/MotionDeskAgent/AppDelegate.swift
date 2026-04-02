import AppKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var desktopWindow: DesktopWindow!
    var chatPanel: ChatPanel?
    var settingsWindow: SettingsWindow?
    var statusItem: NSStatusItem!
    var hotkeyManager: HotkeyManager!
    var claudeManager: ClaudeCLIManager!
    var configManager: ConfigManager!
    var chatHistoryManager: ChatHistoryManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("[App] didFinishLaunching")
        NSApp.setActivationPolicy(.regular)

        configManager = ConfigManager()
        chatHistoryManager = ChatHistoryManager()
        claudeManager = ClaudeCLIManager()

        // 从配置读取 claude 路径
        let config = configManager.load()
        if let path = config["claudePath"] as? String, !path.isEmpty {
            claudeManager.setClaudePath(path)
        }

        debugLog("[App] Managers initialized")

        // 桌面窗口（角色视频）
        desktopWindow = DesktopWindow(config: configManager)
        desktopWindow.bridge = WebViewBridge(
            webView: desktopWindow.webView,
            claudeManager: claudeManager,
            configManager: configManager,
            chatHistoryManager: chatHistoryManager
        )
        desktopWindow.makeKeyAndOrderFront(nil)

        // 全局快捷键：双击 ⌘ 切换聊天面板
        hotkeyManager = HotkeyManager { [weak self] in
            self?.toggleChat()
        }
        hotkeyManager.start()

        setupStatusBar()
        debugLog("[App] Startup complete")
    }

    /// 切换聊天面板显示/隐藏
    private func toggleChat() {
        if let panel = chatPanel, panel.isVisible {
            // 隐藏聊天面板
            panel.orderOut(nil)
            // 通知桌面窗口状态变化
            desktopWindow.bridge?.sendToJS(type: "stateChange", payload: ["state": "idle"])
        } else {
            // 显示聊天面板
            if chatPanel == nil {
                chatPanel = ChatPanel(claudeManager: claudeManager, chatHistoryManager: chatHistoryManager)
                chatPanel?.onDeactivate = { [weak self] in
                    self?.toggleChat()
                }
            }
            // 通知桌面窗口进入交互状态（播放 transition-in 等）
            desktopWindow.bridge?.sendToJS(type: "hotkeyActivate", payload: [:])

            chatPanel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

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
        chatPanel?.orderOut(nil)
        chatPanel = nil  // 下次打开重新创建（刷新历史）
    }

    @objc private func quitApp() {
        claudeManager.stop()
        NSApp.terminate(nil)
    }
}
