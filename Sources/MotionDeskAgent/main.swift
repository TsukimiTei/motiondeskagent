import AppKit

func debugLog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    let logPath = NSHomeDirectory() + "/motiondesk_debug.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
    NSLog("%@", msg) // 也输出到系统日志
}

debugLog("=== MotionDeskAgent starting ===")

let app = NSApplication.shared
app.setActivationPolicy(.regular)

debugLog("ActivationPolicy set")

let delegate = AppDelegate()
app.delegate = delegate

debugLog("Delegate set, calling app.run()")
app.run()
