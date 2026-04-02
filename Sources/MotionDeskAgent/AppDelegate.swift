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

        desktopWindow = DesktopWindow(config: configManager)
        desktopWindow.bridge = WebViewBridge(
            webView: desktopWindow.webView,
            claudeManager: claudeManager,
            configManager: configManager,
            chatHistoryManager: chatHistoryManager
        )

        desktopWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        debugLog("[App] Window visible: \(desktopWindow.isVisible), level: \(desktopWindow.level.rawValue)")

        hotkeyManager = HotkeyManager { [weak self] in
            self?.desktopWindow.bridge?.sendToJS(type: "hotkeyActivate", payload: [:])
        }
        hotkeyManager.start()

        setupStatusBar()
        debugLog("[App] Startup complete")
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
        desktopWindow.bridge?.sendToJS(type: "claudeDone", payload: [:])
    }

    @objc private func quitApp() {
        claudeManager.stop()
        NSApp.terminate(nil)
    }
}
