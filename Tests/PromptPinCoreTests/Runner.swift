import Foundation
import PromptPinCore

// A framework-free test runner also works with Apple's Command Line Tools,
// which do not ship XCTest. Any failed assertion returns a nonzero exit code.
struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}
func expectEqual<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) throws {
    guard try actual() == expected() else { throw CheckFailure(description: "\(file):\(line): values differ") }
}
func expectThrows<T>(_ operation: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) throws {
    do { _ = try operation() } catch { return }
    throw CheckFailure(description: "\(file):\(line): expected an error")
}
func expectTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    guard try value() else { throw CheckFailure(description: "\(file):\(line): expected true") }
}
func expectNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) throws {
    guard try value() == nil else { throw CheckFailure(description: "\(file):\(line): expected nil") }
}
func expectNotNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value = try value() else { throw CheckFailure(description: "\(file):\(line): expected non-nil") }
    return value
}

@main enum CoreChecks {
    static func main() throws {
        let tests = LibraryTests()
        let checks: [(String, () throws -> Void)] = [
            ("Unicode / multiline persistence across instances", tests.testPersistsUnicodeAndMultilineAcrossInstances),
            ("Backup recovery preserves corrupt source", tests.testBackupKeepsPreviousRevisionAndCanRecoverCorruption),
            ("Reject dangling references and duplicate IDs", tests.testRejectsDanglingReferencesAndDuplicates),
            ("Protect future-version data", tests.testFutureVersionDoesNotGetOverwritten),
            ("Empty library and missing file", tests.testEmptyLibraryAndMissingFile),
            ("Failed save leaves existing data intact", tests.testFailedSavePreservesExistingData),
            ("Legacy file without credential keys decodes with empty lists", tests.testLegacyFileWithoutCredentialKeysDecodesWithEmptyLists),
            ("Credentials persist round trip and validate", tests.testCredentialsPersistRoundTripAndValidate),
            ("Legacy credentials survive schema upgrade without value changes", tests.testLegacyCredentialsSurviveMetadataUpgrade),
            ("Optional relationships and every credential format", tests.testOptionalAccountRelationshipsAndAllSecretKinds),
            ("Quick search empty query lists recently edited first", tests.testQuickSearchEmptyQueryReturnsRecentFirst),
            ("Quick search matches all kinds and picks copy value", tests.testQuickSearchMatchesAllKindsAndPicksCopyValue),
            ("Quick search honors limit with a valid fixture", tests.testQuickSearchHonorsLimitAndPersistsFixture),
            ("Memo persistence and non-destructive import merge", tests.testMemoMergePreservesExistingRecords)
        ]
        for (name, check) in checks { try check(); print("PASS: \(name)") }
        print("All \(checks.count) core checks passed.")
        if CommandLine.arguments.count == 2 {
            // Read-only validation of a user library. Never log names, values or keys.
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            let before = try Data(contentsOf: url)
            let disk = LibraryDisk(directory: url.deletingLastPathComponent())
            let decoded = try disk.decode(before)
            let encoded = try disk.encode(decoded)
            let source = try JSONSerialization.jsonObject(with: before) as! [String: Any]
            let target = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            for collection in ["projects", "prompts", "accounts", "secrets", "memos"] {
                let old = source[collection] as? [[String: Any]] ?? []
                let new = target[collection] as? [[String: Any]] ?? []
                try expectEqual(old.count, new.count)
                for (a, b) in zip(old, new) {
                    for (key, value) in a {
                        try expectTrue(NSDictionary(dictionary: [key: value]).isEqual(to: [key: b[key] as Any]))
                    }
                }
            }
            try expectEqual(try Data(contentsOf: url), before)
            print("PASS: Existing library read-only round-trip; every original field preserved; source untouched.")
        }
    }
}
