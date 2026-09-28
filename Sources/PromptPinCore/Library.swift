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

public enum AccountRole: String, Codable, CaseIterable {
    case standalone, primary, subAccount, service
    public var label: String {
        switch self {
        case .standalone: return "不区分主子账号"
        case .primary: return "主账号 / 根账号"
        case .subAccount: return "子账号 / IAM 用户"
        case .service: return "服务账号 / 机器身份"
        }
    }
}

public struct CredentialContext: Codable, Equatable {
    public var role: AccountRole? = nil
    public var category: String = ""
    public var resource: String = ""
    public var notes: String = ""
    public init() {}
    public var usernameLabel: String {
        switch role {
        case .primary: return "主账号 / 用户名"
        case .subAccount: return "子账号 / 用户名"
        case .service: return "服务账号 / 身份"
        default: return "账号 / 用户名"
        }
    }
}

public struct Memo: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var body: String
    public var updatedAt: Date
    public init(id: UUID = UUID(), title: String = "", body: String = "", updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.body = body; self.updatedAt = updatedAt
    }
}

public struct AccountCredential: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var mainAccount: String
    public var subAccount: String
    public var password: String
    // A normalized login name can coexist with untouched legacy main/sub fields.
    public var username: String?
    public var loginName: String { username ?? subAccount }
    public var context: CredentialContext?
    public var updatedAt: Date
    public init(id: UUID = UUID(), title: String, mainAccount: String = "", subAccount: String, password: String, updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.mainAccount = mainAccount
        self.subAccount = subAccount; self.password = password; self.updatedAt = updatedAt
    }
}

public enum SecretKind: String, Codable, Equatable, CaseIterable {
    case accessKeys, apiKey, token, sshKey, certificate, connectionString, custom
    public var label: String {
        switch self {
        case .accessKeys: return "AK / SK"
        case .apiKey: return "API Key"
        case .token: return "Token / Bearer Token"
        case .sshKey: return "SSH 私钥"
        case .certificate: return "证书 / 私钥"
        case .connectionString: return "连接字符串"
        case .custom: return "其他凭据"
        }
    }
}

public struct SecretRecord: Identifiable, Codable, Equatable {
    public var id: UUID
    public var kind: SecretKind
    public var title: String
    public var mainAccount: String
    public var subAccount: String
    public var accessKey: String
    public var secretKey: String
    public var model: String
    public var apiKey: String
    public var baseURL: String
    // Normalized fields preserve legacy slots for lossless upgrades.
    public var username: String?
    public var ownerAccount: String?
    public var endpointURL: String?
    public var loginName: String { username ?? subAccount }
    public var ownerName: String { ownerAccount ?? mainAccount }
    public var endpoint: String { endpointURL ?? baseURL }
    public var context: CredentialContext?
    public var updatedAt: Date
    public init(id: UUID = UUID(), kind: SecretKind, title: String, mainAccount: String = "", subAccount: String = "", accessKey: String = "", secretKey: String = "", model: String = "", apiKey: String = "", baseURL: String = "", updatedAt: Date = Date()) {
        self.id = id; self.kind = kind; self.title = title; self.mainAccount = mainAccount
        self.subAccount = subAccount; self.accessKey = accessKey; self.secretKey = secretKey
        self.model = model; self.apiKey = apiKey; self.baseURL = baseURL; self.updatedAt = updatedAt
    }
}

public struct Library: Codable, Equatable {
    public var version: Int = 2
    public var projects: [Project]
    public var prompts: [Prompt]
    public var accounts: [AccountCredential] = []
    public var secrets: [SecretRecord] = []
    public var memos: [Memo] = []
    public init(projects: [Project], prompts: [Prompt]) { self.projects = projects; self.prompts = prompts }
    public init(projects: [Project], prompts: [Prompt], accounts: [AccountCredential], secrets: [SecretRecord]) {
        self.projects = projects; self.prompts = prompts; self.accounts = accounts; self.secrets = secrets
    }
    // Credentials were added later; missing keys in older files decode as empty lists.
    public enum CodingKeys: String, CodingKey { case version, projects, prompts, accounts, secrets, memos }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        if version == 1 { version = 2 }
        projects = try container.decode([Project].self, forKey: .projects)
        prompts = try container.decode([Prompt].self, forKey: .prompts)
        accounts = try container.decodeIfPresent([AccountCredential].self, forKey: .accounts) ?? []
        secrets = try container.decodeIfPresent([SecretRecord].self, forKey: .secrets) ?? []
        memos = try container.decodeIfPresent([Memo].self, forKey: .memos) ?? []
    }
    public func merging(_ incoming: Library) -> Library {
        var result = self
        let projectIDs = Set(projects.map(\.id)), promptIDs = Set(prompts.map(\.id))
        let accountIDs = Set(accounts.map(\.id)), secretIDs = Set(secrets.map(\.id)), memoIDs = Set(memos.map(\.id))
        result.projects += incoming.projects.filter { !projectIDs.contains($0.id) }
        result.prompts += incoming.prompts.filter { !promptIDs.contains($0.id) }
        result.accounts += incoming.accounts.filter { !accountIDs.contains($0.id) }
        result.secrets += incoming.secrets.filter { !secretIDs.contains($0.id) }
        result.memos += incoming.memos.filter { !memoIDs.contains($0.id) }
        return result
    }
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
        guard version == 2 else { throw LibraryError.invalid("无法读取此版本的数据，请升级应用。") }
        let ids = Set(projects.map(\.id))
        let accountIDs = Set(accounts.map(\.id))
        let secretIDs = Set(secrets.map(\.id))
        let trimmedNonEmpty = { (value: String) in !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let secretsValid = secrets.allSatisfy { record in
            guard trimmedNonEmpty(record.title) else { return false }
            switch record.kind {
            case .accessKeys: return trimmedNonEmpty(record.accessKey) && trimmedNonEmpty(record.secretKey)
            default: return trimmedNonEmpty(record.apiKey)
            }
        }
        guard ids.count == projects.count,
              Set(prompts.map(\.id)).count == prompts.count,
              accountIDs.count == accounts.count,
              secretIDs.count == secrets.count,
              Set(memos.map(\.id)).count == memos.count,
              memos.allSatisfy({ trimmedNonEmpty($0.title) && trimmedNonEmpty($0.body) }),
              projects.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              prompts.allSatisfy({ ids.contains($0.projectID) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              accounts.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              secretsValid
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
