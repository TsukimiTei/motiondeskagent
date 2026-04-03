import Foundation

// MARK: - 记忆类型

enum MemoryType: String, CaseIterable {
    case user       // 用户信息（角色、偏好、知识水平）
    case feedback   // 用户对 Agent 行为的反馈
    case context    // 项目/工作上下文
    case reference  // 外部资源引用

    var label: String {
        switch self {
        case .user: return "用户"
        case .feedback: return "反馈"
        case .context: return "上下文"
        case .reference: return "参考"
        }
    }
}

// MARK: - 记忆条目

struct MemoryEntry {
    let id: String
    let type: MemoryType
    var content: String
    let created: String   // ISO 8601
    var updated: String   // ISO 8601
}

// MARK: - 记忆管理器

/// 文件系统持久化记忆管理——存储在 ApplicationSupport/MotionDeskAgent/memory/
class MemoryManager {
    let memoryDir: URL
    private let indexFile: URL  // MEMORY.md

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MotionDeskAgent")
        memoryDir = appDir.appendingPathComponent("memory")
        indexFile = memoryDir.appendingPathComponent("MEMORY.md")

        // 确保目录存在
        try? FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)

        // 确保 MEMORY.md 存在
        if !FileManager.default.fileExists(atPath: indexFile.path) {
            try? "# 记忆索引\n\n".write(to: indexFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - CRUD 操作

    /// 加载所有记忆条目
    func loadAll() -> [MemoryEntry] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        var entries: [MemoryEntry] = []
        for url in contents {
            guard url.pathExtension == "md",
                  url.lastPathComponent != "MEMORY.md" else { continue }
            if let entry = parseMemoryFile(at: url) {
                entries.append(entry)
            }
        }

        // 按更新时间排序（新的在前）
        return entries.sorted { $0.updated > $1.updated }
    }

    /// 加载 MEMORY.md 索引内容
    func loadIndex() -> String {
        return (try? String(contentsOf: indexFile, encoding: .utf8)) ?? ""
    }

    /// 添加新记忆
    @discardableResult
    func add(type: MemoryType, content: String) -> MemoryEntry {
        let id = "mem_\(Int(Date().timeIntervalSince1970))"
        let now = isoDate()
        let entry = MemoryEntry(id: id, type: type, content: content, created: now, updated: now)

        // 写入记忆文件
        let fileContent = buildFileContent(entry)
        let fileURL = memoryDir.appendingPathComponent("\(id).md")
        try? fileContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // 更新索引
        appendToIndex(entry)

        debugLog("[Memory] Added: \(id) (\(type.rawValue)) — \(content.prefix(50))")
        return entry
    }

    /// 更新已有记忆
    func update(id: String, content: String) -> Bool {
        let fileURL = memoryDir.appendingPathComponent("\(id).md")
        guard var entry = parseMemoryFile(at: fileURL) else { return false }

        entry.content = content
        entry.updated = isoDate()

        let fileContent = buildFileContent(entry)
        try? fileContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // 重建索引
        rebuildIndex()

        debugLog("[Memory] Updated: \(id)")
        return true
    }

    /// 删除记忆
    func delete(id: String) -> Bool {
        let fileURL = memoryDir.appendingPathComponent("\(id).md")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }

        try? FileManager.default.removeItem(at: fileURL)

        // 重建索引
        rebuildIndex()

        debugLog("[Memory] Deleted: \(id)")
        return true
    }

    /// 简单关键词搜索
    func search(query: String) -> [MemoryEntry] {
        let all = loadAll()
        let lowered = query.lowercased()
        return all.filter { entry in
            entry.content.lowercased().contains(lowered) ||
            entry.type.rawValue.lowercased().contains(lowered)
        }
    }

    // MARK: - 系统提示词构建

    /// 构建供系统提示词使用的记忆上下文字符串
    func buildContextString() -> String {
        let entries = loadAll()
        if entries.isEmpty {
            return "暂无保存的记忆。"
        }

        var lines: [String] = ["以下是你记住的关于用户的信息：\n"]

        for entry in entries.prefix(20) {  // 最多 20 条，避免提示词过长
            let typeLabel = entry.type.label
            lines.append("- [\(typeLabel)] \(entry.content)")
        }

        if entries.count > 20 {
            lines.append("\n（还有 \(entries.count - 20) 条记忆未列出）")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - 文件格式

    /// 构建记忆文件内容（YAML frontmatter + 正文）
    private func buildFileContent(_ entry: MemoryEntry) -> String {
        return """
        ---
        id: \(entry.id)
        type: \(entry.type.rawValue)
        created: \(entry.created)
        updated: \(entry.updated)
        ---
        \(entry.content)
        """
    }

    /// 解析记忆文件
    private func parseMemoryFile(at url: URL) -> MemoryEntry? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        // 解析 YAML frontmatter
        let pattern = "---\\s*\\n([\\s\\S]*?)---\\s*\\n?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let yamlRange = Range(match.range(at: 1), in: raw) else {
            return nil
        }

        let yaml = String(raw[yamlRange])
        let bodyStart = raw.index(raw.startIndex, offsetBy: match.range.upperBound, limitedBy: raw.endIndex) ?? raw.endIndex
        let content = String(raw[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

        // 简单解析 YAML 键值对
        var fields: [String: String] = [:]
        for line in yaml.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                fields[key] = value
            }
        }

        guard let id = fields["id"] else { return nil }
        let type = MemoryType(rawValue: fields["type"] ?? "") ?? .user
        let created = fields["created"] ?? isoDate()
        let updated = fields["updated"] ?? isoDate()

        return MemoryEntry(id: id, type: type, content: content, created: created, updated: updated)
    }

    // MARK: - 索引管理

    /// 向 MEMORY.md 追加条目
    private func appendToIndex(_ entry: MemoryEntry) {
        let line = "- [\(entry.type.label)](\(entry.id).md) — \(entry.content.prefix(80))\n"
        if let handle = try? FileHandle(forWritingTo: indexFile) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
    }

    /// 重建索引（删除/更新后调用）
    private func rebuildIndex() {
        let entries = loadAll()
        var content = "# 记忆索引\n\n"
        for entry in entries {
            let summary = entry.content.prefix(80)
            content += "- [\(entry.type.label)](\(entry.id).md) — \(summary)\n"
        }
        try? content.write(to: indexFile, atomically: true, encoding: .utf8)
    }

    // MARK: - 工具

    private func isoDate() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
