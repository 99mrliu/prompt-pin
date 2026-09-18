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
}
