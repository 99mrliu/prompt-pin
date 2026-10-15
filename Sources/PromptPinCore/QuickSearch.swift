import Foundation

/// One row in the global quick-search panel. Copy text is picked per content kind
/// so pressing Return always copies the most useful value without opening an editor.
public struct QuickSearchHit: Identifiable, Equatable {
    public enum Kind: String, Equatable {
        case prompt, account, secret, memo
        public var label: String {
            switch self {
            case .prompt: return "提示词"
            case .account: return "账号"
            case .secret: return "密钥"
            case .memo: return "备忘录"
            }
        }
        /// What pressing Return copies, described in Chinese for the row hint.
        public var actionLabel: String {
            switch self {
            case .prompt: return "复制全文"
            case .account: return "复制密码"
            case .secret: return "复制密钥"
            case .memo: return "复制内容"
            }
        }
    }

    public let kind: Kind
    public let recordID: UUID
    public var id: String { "\(kind.rawValue)-\(recordID.uuidString)" }
    public let title: String
    public let subtitle: String
    public let copyText: String
    public let actionLabel: String
    public let updatedAt: Date

    public init(kind: Kind, recordID: UUID, title: String, subtitle: String, copyText: String, actionLabel: String? = nil, updatedAt: Date) {
        self.kind = kind
        self.recordID = recordID
        self.title = title
        self.subtitle = subtitle
        self.copyText = copyText
        self.actionLabel = actionLabel ?? kind.actionLabel
        self.updatedAt = updatedAt
    }
}

public enum QuickSearchIndex {
    /// Builds cross-collection hits. An empty query returns the most recently edited records.
    public static func hits(in library: Library, query: String, limit: Int = 8) -> [QuickSearchHit] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var hits: [QuickSearchHit] = []
        let projectNames = Dictionary(uniqueKeysWithValues: library.projects.map { ($0.id, $0.name) })
        let matches: (String...) -> Bool = { fields in
            keyword.isEmpty || fields.contains { $0.localizedStandardContains(keyword) }
        }

        for prompt in library.prompts {
            let projectName = projectNames[prompt.projectID] ?? ""
            guard matches(prompt.title, prompt.body, projectName) else { continue }
            hits.append(QuickSearchHit(
                kind: .prompt, recordID: prompt.id, title: prompt.title,
                subtitle: projectName, copyText: prompt.body, updatedAt: prompt.updatedAt))
        }

        for account in library.accounts {
            let context = account.context
            guard matches(account.title, account.mainAccount, account.loginName,
                          context?.category ?? "", context?.resource ?? "", context?.notes ?? "",
                          context?.role?.label ?? "") else { continue }
            hits.append(QuickSearchHit(
                kind: .account, recordID: account.id, title: account.title,
                subtitle: contextSummary(context), copyText: account.password, updatedAt: account.updatedAt))
        }

        for secret in library.secrets {
            let context = secret.context
            guard matches(secret.title, secret.ownerName, secret.loginName, secret.accessKey, secret.apiKey,
                          context?.category ?? "", context?.resource ?? "", context?.notes ?? "",
                          context?.role?.label ?? "") else { continue }
            // AK/SK pairs are almost always copied for the SK; other kinds carry the key in apiKey.
            let isAccessKeys = secret.kind == .accessKeys
            let copyText = isAccessKeys ? secret.secretKey : secret.apiKey
            let subtitle = [secret.kind.label, contextSummary(context)]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            hits.append(QuickSearchHit(
                kind: .secret, recordID: secret.id, title: secret.title,
                subtitle: subtitle, copyText: copyText,
                actionLabel: isAccessKeys ? "复制 SK" : "复制密钥",
                updatedAt: secret.updatedAt))
        }

        for memo in library.memos {
            guard matches(memo.title, memo.body) else { continue }
            hits.append(QuickSearchHit(
                kind: .memo, recordID: memo.id, title: memo.title,
                subtitle: "备忘录", copyText: memo.body, updatedAt: memo.updatedAt))
        }

        return Array(hits.sorted { $0.updatedAt > $1.updatedAt }.prefix(max(1, limit)))
    }

    private static func contextSummary(_ context: CredentialContext?) -> String {
        guard let context else { return "" }
        return [context.category, context.role?.label ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
