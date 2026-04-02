import AppKit
import Carbon

/// 全局快捷键管理：检测双击 ⌘ 键
class HotkeyManager {
    private var lastCmdPressTime: TimeInterval = 0
    private var lastCmdReleaseTime: TimeInterval = 0
    private var cmdWasDown: Bool = false
    private let doubleTapInterval: TimeInterval = 0.3  // 双击间隔（秒）
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onActivate: () -> Void

    init(onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
    }

    func start() {
        // 全局事件监听（其他 app 获得焦点时也能监听）
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // 本地事件监听（本 app 获得焦点时）
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let cmdDown = event.modifierFlags.contains(.command)
        let now = event.timestamp

        // 只关注 ⌘ 键，忽略其他修饰键组合
        let otherModifiers: NSEvent.ModifierFlags = [.shift, .option, .control]
        if !event.modifierFlags.intersection(otherModifiers).isEmpty {
            return
        }

        if cmdDown && !cmdWasDown {
            // ⌘ 按下
            cmdWasDown = true
            lastCmdPressTime = now
        } else if !cmdDown && cmdWasDown {
            // ⌘ 释放
            cmdWasDown = false
            let pressDuration = now - lastCmdPressTime

            // 按压时间太长不算双击（排除长按）
            if pressDuration > 0.3 {
                lastCmdReleaseTime = 0
                return
            }

            // 检查与上次释放的间隔
            if lastCmdReleaseTime > 0 {
                let gap = now - lastCmdReleaseTime
                if gap < doubleTapInterval {
                    // 双击 ⌘ 检测成功！
                    DispatchQueue.main.async { [weak self] in
                        self?.onActivate()
                    }
                    lastCmdReleaseTime = 0
                    return
                }
            }

            lastCmdReleaseTime = now
        }
    }

    deinit {
        stop()
    }
}
