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
}
