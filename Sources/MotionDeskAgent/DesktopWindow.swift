import AppKit
import WebKit

/// 桌面窗口：始终在桌面层，只负责显示角色视频
class DesktopWindow: NSWindow {
    let webView: WKWebView
    var bridge: WebViewBridge?

    init(config: ConfigManager) {
        debugLog("[Window] init start")

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            fatalError("No screen found")
        }
        let screenFrame = screen.frame

        let webConfig = WKWebViewConfiguration()
        webConfig.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webConfig.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: screenFrame, configuration: webConfig)

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // 始终桌面层，黑色背景
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        self.backgroundColor = .black
        self.isOpaque = true
        self.hasShadow = false
        self.ignoresMouseEvents = true  // 桌面层不需要接收鼠标事件
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.contentView = webView

        loadFrontend()
        debugLog("[Window] init complete")
    }

    // MARK: - 前端加载

    private func loadFrontend() {
        if let resourceURL = Bundle.main.resourceURL {
            let frontendDir = resourceURL.appendingPathComponent("frontend")
            let indexFile = frontendDir.appendingPathComponent("index.html")
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
                webView.loadFileURL(indexFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
                return
            }
        }

        if let frontendDir = findProjectFrontendPath() {
            let indexFile = frontendDir.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: indexFile.path) {
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
