import Foundation

/// 管理 JSON 配置文件
/// 每个状态有一个视频 clip（不是数组），格式：{ path: string, loopMode: "loop"|"pingpong" }
class ConfigManager {
    private let configURL: URL
    private let videoExtensions: Set<String> = ["mp4", "mov", "webm", "m4v"]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MotionDeskAgent")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        configURL = appDir.appendingPathComponent("config.json")

        if !FileManager.default.fileExists(atPath: configURL.path) {
            copyDefaultConfig()
        }

        // 迁移旧格式（clips 数组 → 单个 clip）
        migrateIfNeeded()
    }

    func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return defaultConfig()
        }

        // 仅对没有 clip 的状态，从 clips 目录自动填充
        return autoFillFromDirectory(json)
    }

    func save(_ config: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: configURL)
    }

    func clipsDirectory() -> URL {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("clips"),
            findProjectPath()?.appendingPathComponent("clips"),
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        let appClips = configURL.deletingLastPathComponent().appendingPathComponent("clips")
        try? FileManager.default.createDirectory(at: appClips, withIntermediateDirectories: true)
        return appClips
    }

    // MARK: - 迁移旧格式

    /// 将 clips 数组迁移为单个 clip
    private func migrateIfNeeded() {
        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var states = json["states"] as? [String: Any] else { return }

        var migrated = false
        for stateName in states.keys {
            guard var stateDict = states[stateName] as? [String: Any] else { continue }

            // 已经有 clip 字段（新格式），跳过
            if stateDict["clip"] != nil { continue }

            // 从旧的 clips 数组迁移
            if let clips = stateDict["clips"] {
                let firstClip = extractFirstClip(from: clips)
                stateDict["clip"] = firstClip  // 可能是 nil，也存
                stateDict.removeValue(forKey: "clips")
                states[stateName] = stateDict
                migrated = true
            }
        }

        if migrated {
            json["states"] = states
            save(json)
            debugLog("[Config] Migrated clips arrays to single clip")
        }
    }

    /// 从旧 clips 数据中提取第一个 clip
    private func extractFirstClip(from clips: Any) -> [String: Any]? {
        if let arr = clips as? [[String: Any]], let first = arr.first {
            return first
        }
        if let arr = clips as? [String], let first = arr.first, !first.isEmpty {
            return ["path": first, "loopMode": "loop"]
        }
        return nil
    }

    // MARK: - 自动填充

    /// 对没有 clip 的状态，从 clips/<stateName>/ 目录自动发现视频
    private func autoFillFromDirectory(_ config: [String: Any]) -> [String: Any] {
        var result = config
        guard var states = result["states"] as? [String: Any] else { return result }

        let clipsDir = clipsDirectory()

        for stateName in states.keys {
            guard var stateDict = states[stateName] as? [String: Any] else { continue }

            // 已经有 clip，不覆盖
            if stateDict["clip"] is [String: Any] { continue }

            // 扫描目录
            let stateClipsDir = clipsDir.appendingPathComponent(stateName)
            if let contents = try? FileManager.default.contentsOfDirectory(at: stateClipsDir, includingPropertiesForKeys: nil) {
                for fileURL in contents {
                    if videoExtensions.contains(fileURL.pathExtension.lowercased()) {
                        stateDict["clip"] = ["path": fileURL.path, "loopMode": "loop"] as [String: Any]
                        states[stateName] = stateDict
                        break  // 只取第一个
                    }
                }
            }
        }

        result["states"] = states
        return result
    }

    // MARK: - 默认配置

    private func copyDefaultConfig() {
        if let projectConfig = findProjectPath()?.appendingPathComponent("config/states.json"),
           FileManager.default.fileExists(atPath: projectConfig.path) {
            try? FileManager.default.copyItem(at: projectConfig, to: configURL)
            return
        }
        if let bundlePath = Bundle.main.url(forResource: "states", withExtension: "json") {
            try? FileManager.default.copyItem(at: bundlePath, to: configURL)
            return
        }
        save(defaultConfig())
    }

    private func findProjectPath() -> URL? {
        if let path = ProcessInfo.processInfo.environment["MOTIONDESK_PROJECT_PATH"] {
            return URL(fileURLWithPath: path)
        }
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            var current: URL? = execDir
            for _ in 0..<6 {
                guard let dir = current else { break }
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent("clips").path) {
                    return dir
                }
                current = dir.deletingLastPathComponent()
            }
        }
        return nil
    }

    private func defaultConfig() -> [String: Any] {
        return [
            "states": [
                "idle": ["label": "待机", "loop": true],
                "transition-in": ["label": "唤起过渡", "loop": false],
                "listening": ["label": "等待输入", "loop": true],
                "thinking": ["label": "思考中", "loop": true],
                "speaking": ["label": "回复中", "loop": true],
                "tool-executing": ["label": "执行工具", "loop": true],
                "transition-out": ["label": "收起过渡", "loop": false],
            ] as [String: Any],
            "transitions": [
                "idle": ["transition-in"],
                "transition-in": ["listening"],
                "listening": ["thinking", "transition-out"],
                "thinking": ["speaking", "tool-executing"],
                "tool-executing": ["thinking", "speaking"],
                "speaking": ["listening", "tool-executing"],
                "transition-out": ["idle"],
            ],
            "chromakeyThreshold": 0.3,
            "chromakeySmoothness": 0.1,
            "hotkey": "double-cmd",
        ] as [String: Any]
    }
}
