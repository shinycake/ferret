import XCTest
@testable import FerretCore

final class ResultsFolderServiceTests: XCTestCase {
    private var scratch: URL!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ferret-results-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testCleanupDropsOldFoldersAndKeepsUnrelatedEntries() throws {
        let recent = try makeFolder("results-recent", age: 3_600)
        let old = try makeFolder("results-old", age: 90_000)
        let notes = scratch.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        let loose = scratch.appendingPathComponent("results-not-a-dir.txt")
        try "keep".write(to: loose, atomically: true, encoding: .utf8)

        try service().cleanup()

        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: notes.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: loose.path))
    }

    func testCleanupKeepsOnlyTheNewestTen() throws {
        var folders: [URL] = []
        for index in 0..<12 {
            folders.append(try makeFolder(String(format: "results-%02d", index), age: TimeInterval(index * 60)))
        }

        try service().cleanup()

        for index in 0..<10 {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folders[index].path), "kept \(index)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folders[10].path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folders[11].path))
    }

    func testCleanupOfMissingCacheIsANoOp() throws {
        let missing = scratch.appendingPathComponent("missing", isDirectory: true)
        try ResultsFolderService(cacheDir: missing, now: { self.now }).cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    private func service() -> ResultsFolderService {
        ResultsFolderService(cacheDir: scratch, now: { self.now })
    }

    private func makeFolder(_ name: String, age: TimeInterval) throws -> URL {
        let url = scratch.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let created = now.addingTimeInterval(-age)
        try FileManager.default.setAttributes(
            [.creationDate: created, .modificationDate: created],
            ofItemAtPath: url.path
        )
        return url
    }
}
