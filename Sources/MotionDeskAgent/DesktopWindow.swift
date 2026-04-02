import AppKit
import WebKit

class DesktopWindow: NSWindow {
    let webView: WKWebView
    var bridge: WebViewBridge?

    init(config: ConfigManager) {
        debugLog("[Window] init start")

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            fatalError("No screen found")
        }
        let screenFrame = screen.frame
        debugLog("[Window] screen: \(screenFrame)")

        let webConfig = WKWebViewConfiguration()
        webConfig.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webConfig.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        debugLog("[Window] webConfig done")

        webView = WKWebView(frame: screenFrame, configuration: webConfig)
        debugLog("[Window] webView created")

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        debugLog("[Window] super.init done")

        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        self.backgroundColor = .black
        self.isOpaque = true
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.contentView = webView
        debugLog("[Window] properties set")

        loadFrontend()
        debugLog("[Window] init complete")
    }

    // MARK: - 交互模式切换

    /// 进入交互模式：窗口提升到浮动层，隐藏 Dock
    func enterInteractiveMode() {
        debugLog("[Window] → interactive mode")
        self.level = .floating
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Dock 不隐藏
    }

    /// 退出交互模式：窗口降回桌面层，恢复 Dock
    func exitInteractiveMode() {
        debugLog("[Window] → desktop mode")
        // 恢复默认
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        self.orderBack(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - 前端加载

    private func loadFrontend() {
        debugLog("[Window] loadFrontend start")

        if let resourceURL = Bundle.main.resourceURL {
            let frontendDir = resourceURL.appendingPathComponent("frontend")
            let indexFile = frontendDir.appendingPathComponent("index.html")
            debugLog("[Window] checking: \(indexFile.path)")
            if FileManager.default.fileExists(atPath: indexFile.path) {
                debugLog("[Window] loading from bundle")
                webView.loadFileURL(indexFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
                return
            }
        }

        if let envPath = ProcessInfo.processInfo.environment["MOTIONDESK_FRONTEND_PATH"],
           !envPath.isEmpty {
            let indexFile = URL(fileURLWithPath: envPath).appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: indexFile.path) {
                debugLog("[Window] loading from env path")
                webView.loadFileURL(indexFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
                return
            }
        }

        if let frontendDir = findProjectFrontendPath() {
            let indexFile = frontendDir.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: indexFile.path) {
                debugLog("[Window] loading from project path: \(frontendDir.path)")
                webView.loadFileURL(indexFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
                return
            }
        }

        debugLog("[Window] no frontend found, trying dev server")
        let devURL = URL(string: "http://localhost:5173")!
        webView.load(URLRequest(url: devURL))
    }

    private func findProjectFrontendPath() -> URL? {
        let execPath = Bundle.main.executableURL?.deletingLastPathComponent()
        var current = execPath
        for _ in 0..<5 {
            guard let dir = current else { break }
            let frontendDist = dir.appendingPathComponent("frontend/dist")
            if FileManager.default.fileExists(atPath: frontendDist.path) {
                return frontendDist
            }
            current = dir.deletingLastPathComponent()
        }
        return nil
    }
}
