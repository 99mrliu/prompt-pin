import Foundation

public struct Project: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public struct Prompt: Identifiable, Codable, Equatable {
    public var id: UUID
    public var projectID: UUID
    public var title: String
    public var body: String
    public var isPinned: Bool
    public var updatedAt: Date
    public init(id: UUID = UUID(), projectID: UUID, title: String, body: String, isPinned: Bool = false, updatedAt: Date = Date()) {
        self.id = id; self.projectID = projectID; self.title = title
        self.body = body; self.isPinned = isPinned; self.updatedAt = updatedAt
    }
}

public struct Library: Codable, Equatable {
    public var version: Int = 1
    public var projects: [Project]
    public var prompts: [Prompt]
    public init(projects: [Project], prompts: [Prompt]) { self.projects = projects; self.prompts = prompts }
    public static var starter: Library {
        let writing = Project(name: "日常写作")
        let code = Project(name: "代码助手")
        let research = Project(name: "研究与学习")
        return Library(projects: [writing, code, research], prompts: [
            Prompt(projectID: writing.id, title: "把想法说清楚", body: "请帮我润色下面这段文字。保留原意，用简洁、自然的中文表达，删除重复和空洞的修饰，先说结论，再展开理由。\n\n需要润色的内容：\n", isPinned: true),
            Prompt(projectID: code.id, title: "一起审查代码", body: "请审查下面的代码，重点关注正确性、边界条件和可维护性。按严重程度列出问题，解释触发条件，并给出最小修改建议。不要为了重构而重构。\n\n代码：\n"),
            Prompt(projectID: research.id, title: "读懂一篇论文", body: "请阅读这篇论文，依次总结：研究问题、核心方法、主要结果、局限性，以及值得进一步验证的方向。区分论文中明确报告的事实和你的推断。\n\n论文内容：\n")
        ])
    }
    public func validated() throws -> Library {
        guard version == 1 else { throw LibraryError.invalid("无法读取此版本的数据，请升级应用。") }
        let ids = Set(projects.map(\.id))
        guard ids.count == projects.count,
              Set(prompts.map(\.id)).count == prompts.count,
              projects.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              prompts.allSatisfy({ ids.contains($0.projectID) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw LibraryError.invalid("数据包含重复标识、空内容或不存在的项目。") }
        return self
    }
}

public enum LibraryError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

/// Atomic replacement prevents partial JSON on shutdown. The previous valid revision is kept separately.
public struct LibraryDisk {
    public let directory: URL
    public var file: URL { directory.appendingPathComponent("library.json") }
    public var backup: URL { directory.appendingPathComponent("library.backup.json") }
    public init(directory: URL) { self.directory = directory }
    public static var standard: LibraryDisk {
        LibraryDisk(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PromptPin", isDirectory: true))
    }
    public func decode(_ data: Data) throws -> Library {
        try JSONDecoder().decode(Library.self, from: data).validated()
    }
    public func encode(_ library: Library) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(library.validated())
    }
    public func load() throws -> Library? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try decode(Data(contentsOf: file))
    }
    public func save(_ library: Library) throws {
        let data = try encode(library)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: file.path) {
            let old = try Data(contentsOf: file)
            _ = try decode(old) // Never silently overwrite a corrupt or future-version library.
            try old.write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    public func restoreBackup() throws -> Library {
        let data = try Data(contentsOf: backup)
        let library = try decode(data)
        if FileManager.default.fileExists(atPath: file.path) {
            let preserved = directory.appendingPathComponent("library.unreadable-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: file, to: preserved)
        }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return library
    }
}
