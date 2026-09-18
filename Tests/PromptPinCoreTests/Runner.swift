import Foundation

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

@main enum CoreChecks {
    static func main() throws {
        let tests = LibraryTests()
        let checks: [(String, () throws -> Void)] = [
            ("Unicode / multiline persistence across instances", tests.testPersistsUnicodeAndMultilineAcrossInstances),
            ("Backup recovery preserves corrupt source", tests.testBackupKeepsPreviousRevisionAndCanRecoverCorruption),
            ("Reject dangling references and duplicate IDs", tests.testRejectsDanglingReferencesAndDuplicates),
            ("Protect future-version data", tests.testFutureVersionDoesNotGetOverwritten),
            ("Empty library and missing file", tests.testEmptyLibraryAndMissingFile),
            ("Failed save leaves existing data intact", tests.testFailedSavePreservesExistingData)
        ]
        for (name, check) in checks { try check(); print("PASS: \(name)") }
        print("All \(checks.count) core checks passed.")
    }
}
