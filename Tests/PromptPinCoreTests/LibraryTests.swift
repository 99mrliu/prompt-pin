import Foundation
import PromptPinCore

final class LibraryTests {
    var cleanup: [() -> Void] = []
    deinit { cleanup.forEach { $0() } }
    private func temporaryDisk() throws -> LibraryDisk {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cleanup.append { try? FileManager.default.removeItem(at: directory) }
        return LibraryDisk(directory: directory)
    }
    func testPersistsUnicodeAndMultilineAcrossInstances() throws {
        let disk = try temporaryDisk()
        let project = Project(name: "论文 / 文献")
        let prompt = Prompt(projectID: project.id, title: "中文与 🧪", body: "第一行\n\n  保留缩进\n```python\nprint('你好')\n```\n")
        let library = Library(projects: [project], prompts: [prompt])
        try disk.save(library)
        try expectEqual(try LibraryDisk(directory: disk.directory).load(), library)
    }
    func testBackupKeepsPreviousRevisionAndCanRecoverCorruption() throws {
        let disk = try temporaryDisk()
        let original = Library.starter
        try disk.save(original)
        var edited = original
        edited.prompts[0].body = "修改后的内容"
        try disk.save(edited)
        try expectEqual(try disk.decode(Data(contentsOf: disk.backup)), original)
        try Data("broken".utf8).write(to: disk.file)
        try expectThrows(try disk.load())
        try expectThrows(try disk.save(edited))
        try expectEqual(try Data(contentsOf: disk.file), Data("broken".utf8))
        try expectEqual(try disk.restoreBackup(), original)
        try expectEqual(try disk.load(), original)
        try expectTrue(try FileManager.default.contentsOfDirectory(atPath: disk.directory.path).contains { $0.hasPrefix("library.unreadable-") })
    }
    func testRejectsDanglingReferencesAndDuplicates() throws {
        let disk = try temporaryDisk()
        var library = Library.starter
        library.prompts[0].projectID = UUID()
        try expectThrows(try disk.save(library))
        library = Library.starter
        library.projects.append(library.projects[0])
        try expectThrows(try disk.save(library))
        library = Library.starter
        library.prompts.append(library.prompts[0])
        try expectThrows(try disk.save(library))
    }
    func testFutureVersionDoesNotGetOverwritten() throws {
        let disk = try temporaryDisk()
        var json = try JSONSerialization.jsonObject(with: disk.encode(.starter)) as! [String: Any]
        json["version"] = 99
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: disk.file)
        try expectThrows(try disk.load())
        try expectThrows(try disk.save(.starter))
        try expectEqual(try Data(contentsOf: disk.file), data)
    }
    func testEmptyLibraryAndMissingFile() throws {
        let disk = try temporaryDisk()
        try expectNil(try disk.load())
        let empty = Library(projects: [], prompts: [])
        try disk.save(empty)
        try expectEqual(try disk.load(), empty)
    }
    func testFailedSavePreservesExistingData() throws {
        let disk = try temporaryDisk()
        let original = Library.starter
        try disk.save(original)
        var invalid = original
        invalid.prompts[0].title = "  \n"
        try expectThrows(try disk.save(invalid))
        try expectEqual(try disk.load(), original)
    }
    func testLegacyFileWithoutCredentialKeysDecodesWithEmptyLists() throws {
        let disk = try temporaryDisk()
        var json = try JSONSerialization.jsonObject(with: disk.encode(.starter)) as! [String: Any]
        json.removeValue(forKey: "accounts")
        json.removeValue(forKey: "secrets")
        try JSONSerialization.data(withJSONObject: json).write(to: disk.file)
        let loaded = try expectNotNil(try disk.load())
        try expectTrue(loaded.accounts.isEmpty && loaded.secrets.isEmpty)
        try expectEqual(loaded.prompts.count, Library.starter.prompts.count)
    }
    func testCredentialsPersistRoundTripAndValidate() throws {
        let disk = try temporaryDisk()
        let account = AccountCredential(title: "云控制台", mainAccount: "ops@example.com", subAccount: "deploy-bot", password: "p@ss 密码")
        let secret = SecretRecord(kind: .apiKey, title: "大模型", model: "gpt-4o", apiKey: "sk-test", baseURL: "https://api.example.com/v1")
        var library = Library(projects: [], prompts: [])
        library.accounts = [account]; library.secrets = [secret]
        try disk.save(library)
        try expectEqual(try LibraryDisk(directory: disk.directory).load(), library)
        var broken = library
        broken.secrets[0].apiKey = "  \n"
        try expectThrows(try disk.save(broken))
        var incomplete = library
        incomplete.secrets.append(SecretRecord(kind: .accessKeys, title: "缺 SK", accessKey: "AKID"))
        try expectThrows(try disk.save(incomplete))
        try expectEqual(try disk.load(), library)
    }
    func testLegacyCredentialsSurviveMetadataUpgrade() throws {
        let disk = try temporaryDisk()
        let original = Library(projects: [], prompts: [], accounts: [AccountCredential(title: "Legacy", mainAccount: "owner", subAccount: "member", password: "  unchanged 密码\n")], secrets: [SecretRecord(kind: .accessKeys, title: "Bucket", mainAccount: "root", subAccount: "user", accessKey: "AK", secretKey: " SK\n", model: "keep-hidden", apiKey: "keep-hidden-key", baseURL: "https://example.invalid")])
        var json = try JSONSerialization.jsonObject(with: disk.encode(original)) as! [String: Any]
        json["version"] = 1; json.removeValue(forKey: "memos")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        try legacy.write(to: disk.file)
        var upgraded = try expectNotNil(try disk.load())
        try expectEqual(try Data(contentsOf: disk.file), legacy)
        try expectEqual(upgraded.accounts, original.accounts)
        try expectEqual(upgraded.secrets, original.secrets)
        try expectNil(upgraded.secrets[0].context)
        var context = CredentialContext(); context.category = "对象存储 / 存储桶"; context.role = .standalone
        upgraded.secrets[0].context = context
        var primary = upgraded.accounts[0]
        primary.username = primary.mainAccount
        try expectEqual(primary.loginName, primary.mainAccount)
        try expectEqual(primary.subAccount, upgraded.accounts[0].subAccount)
        var normalized = upgraded.secrets[0]
        normalized.username = ""; normalized.ownerAccount = ""; normalized.endpointURL = "https://storage.example.invalid"
        try expectEqual(normalized.loginName, "")
        try expectEqual(normalized.ownerName, "")
        try expectEqual(normalized.endpoint, "https://storage.example.invalid")
        try expectEqual(normalized.mainAccount, original.secrets[0].mainAccount)
        try expectEqual(normalized.subAccount, original.secrets[0].subAccount)
        try expectEqual(normalized.baseURL, original.secrets[0].baseURL)
        var normalizedLibrary = upgraded; normalizedLibrary.secrets[0] = normalized
        try expectEqual(try disk.decode(disk.encode(normalizedLibrary)), normalizedLibrary)
        upgraded.memos = [Memo(title: "步骤", body: "第一步\n第二步")]
        try disk.save(upgraded)
        let reloaded = try expectNotNil(try disk.load())
        try expectEqual(reloaded, upgraded)
        try expectEqual(reloaded.accounts, original.accounts)
        var withoutMetadata = reloaded.secrets[0]; withoutMetadata.context = nil
        try expectEqual(withoutMetadata, original.secrets[0])
        try expectEqual(try Data(contentsOf: disk.backup), legacy)
    }
    func testOptionalAccountRelationshipsAndAllSecretKinds() throws {
        let disk = try temporaryDisk()
        var library = Library(projects: [], prompts: [])
        library.accounts = [AccountCredential(title: "密码", subAccount: "", password: "fixture-password")]
        for kind in SecretKind.allCases {
            var record = SecretRecord(kind: kind, title: kind.label, accessKey: "fixture-ak", secretKey: "fixture-sk", apiKey: "line 1\nline 2\n")
            var context = CredentialContext(); context.resource = "bucket-name"; context.category = "对象存储 / 存储桶"
            record.context = context
            library.secrets.append(record)
        }
        try disk.save(library)
        try expectEqual(try disk.load(), library)
        for role in AccountRole.allCases {
            library.secrets[0].context?.role = role
            try disk.save(library)
            try expectEqual(try disk.load(), library)
        }
    }
    private func makeQuickSearchLibrary() -> Library {
        let project = Project(name: "搜索验证项目")
        var prompt = Prompt(projectID: project.id, title: "独特标题Alpha", body: "正文含共享关键词斑马")
        prompt.updatedAt = Date(timeIntervalSince1970: 100)
        var account = AccountCredential(title: "账号Beta", subAccount: "", password: "PW-COPY-VALUE")
        var accountContext = CredentialContext()
        accountContext.resource = "神秘资源词"
        accountContext.category = "云平台"
        account.context = accountContext
        account.updatedAt = Date(timeIntervalSince1970: 200)
        var accessKeySecret = SecretRecord(kind: .accessKeys, title: "AK密钥Gamma", accessKey: "AKID-X", secretKey: "SK-COPY-VALUE")
        accessKeySecret.updatedAt = Date(timeIntervalSince1970: 300)
        var apiSecret = SecretRecord(kind: .apiKey, title: "API密钥Delta", apiKey: "API-COPY-VALUE")
        apiSecret.updatedAt = Date(timeIntervalSince1970: 400)
        var memo = Memo(title: "备忘录Epsilon", body: "memo内容词")
        memo.updatedAt = Date(timeIntervalSince1970: 500)
        var library = Library(projects: [project], prompts: [prompt], accounts: [account], secrets: [accessKeySecret, apiSecret])
        library.memos = [memo]
        return library
    }

    func testQuickSearchEmptyQueryReturnsRecentFirst() throws {
        let library = makeQuickSearchLibrary()
        let hits = QuickSearchIndex.hits(in: library, query: "  ")
        try expectEqual(hits.count, 5)
        try expectTrue(zip(hits, hits.dropFirst()).allSatisfy { $0.updatedAt >= $1.updatedAt })
        try expectEqual(hits.first?.kind, .memo)
        try expectEqual(hits.first?.title, "备忘录Epsilon")
    }

    func testQuickSearchMatchesAllKindsAndPicksCopyValue() throws {
        let library = makeQuickSearchLibrary()
        let promptHits = QuickSearchIndex.hits(in: library, query: "斑马")
        try expectEqual(promptHits.count, 1)
        try expectEqual(promptHits[0].kind, .prompt)
        try expectEqual(promptHits[0].copyText, "正文含共享关键词斑马")
        try expectEqual(promptHits[0].subtitle, "搜索验证项目")

        let accountHits = QuickSearchIndex.hits(in: library, query: "神秘资源词")
        try expectEqual(accountHits.count, 1)
        try expectEqual(accountHits[0].kind, .account)
        try expectEqual(accountHits[0].copyText, "PW-COPY-VALUE")

        let akHits = QuickSearchIndex.hits(in: library, query: "Gamma")
        try expectEqual(akHits.count, 1)
        try expectEqual(akHits[0].kind, .secret)
        try expectEqual(akHits[0].copyText, "SK-COPY-VALUE")
        try expectEqual(akHits[0].actionLabel, "复制 SK")

        let apiHits = QuickSearchIndex.hits(in: library, query: "Delta")
        try expectEqual(apiHits.count, 1)
        try expectEqual(apiHits[0].copyText, "API-COPY-VALUE")
        try expectEqual(apiHits[0].actionLabel, "复制密钥")

        let memoHits = QuickSearchIndex.hits(in: library, query: "memo内容词")
        try expectEqual(memoHits.count, 1)
        try expectEqual(memoHits[0].kind, .memo)
        try expectEqual(memoHits[0].copyText, "memo内容词")

        try expectEqual(QuickSearchIndex.hits(in: library, query: "不存在的词xyz").count, 0)
    }

    func testQuickSearchHonorsLimitAndPersistsFixture() throws {
        let disk = try temporaryDisk()
        let library = makeQuickSearchLibrary()
        try disk.save(library)
        try expectEqual(try disk.load(), library)
        try expectEqual(QuickSearchIndex.hits(in: library, query: "", limit: 2).count, 2)
        try expectEqual(QuickSearchIndex.hits(in: library, query: "", limit: 99).count, 5)
    }

    func testMemoMergePreservesExistingRecords() throws {
        let disk = try temporaryDisk()
        var existing = Library.starter
        let memo = Memo(title: "已有记录", body: "不要覆盖\n中文")
        existing.memos = [memo]
        var incoming = existing
        incoming.memos[0].body = "导入版本，不应该替换"
        incoming.prompts[0].body = "不应该替换"
        incoming.memos.append(Memo(title: "新记录", body: "新内容"))
        let merged = existing.merging(incoming)
        try expectEqual(merged.memos[0], memo)
        try expectEqual(merged.prompts, existing.prompts)
        try expectEqual(merged.memos.count, 2)
        try expectEqual(merged.merging(incoming), merged)
        try disk.save(merged)
        try expectEqual(try disk.load(), merged)
        var invalid = merged; invalid.memos.append(invalid.memos[0])
        try expectThrows(try disk.save(invalid))
    }

}
