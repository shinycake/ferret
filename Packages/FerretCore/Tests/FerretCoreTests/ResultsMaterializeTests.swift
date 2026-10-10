import Foundation
import XCTest
@testable import FerretCore

final class ResultsMaterializeTests: XCTestCase {
    func testUniqueNames() {
        var taken: Set<String> = []
        XCTAssertEqual(ResultsFolderService.uniqueName("README.md", isPackageOrDir: false, taken: &taken), "README.md")
        XCTAssertEqual(ResultsFolderService.uniqueName("README.md", isPackageOrDir: false, taken: &taken), "README (2).md")
        XCTAssertEqual(ResultsFolderService.uniqueName("README.md", isPackageOrDir: false, taken: &taken), "README (3).md")
        XCTAssertEqual(ResultsFolderService.uniqueName("Foo.app", isPackageOrDir: true, taken: &taken), "Foo.app")
        XCTAssertEqual(ResultsFolderService.uniqueName("Foo.app", isPackageOrDir: true, taken: &taken), "Foo (2).app")
        XCTAssertEqual(ResultsFolderService.uniqueName("Makefile", isPackageOrDir: false, taken: &taken), "Makefile")
        XCTAssertEqual(ResultsFolderService.uniqueName("Makefile", isPackageOrDir: false, taken: &taken), "Makefile (2)")
    }

    func testMaterializeSkipsMissingAndCleanupKeepsTargets() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mat-\(UUID().uuidString)")
        let a = root.appendingPathComponent("a/README.md"), b = root.appendingPathComponent("b/README.md")
        for url in [a, b] {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        let cache = root.appendingPathComponent("cache")
        let service = ResultsFolderService(cacheDir: cache)
        let folder = try service.materialize(paths: [a.path, b.path, root.appendingPathComponent("missing.txt").path], query: "readme", scope: root.path)
        let names = try fm.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["README (2).md", "README.md", "_query.txt"])
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: folder.appendingPathComponent("README.md").path), a.path)
        XCTAssertTrue(folder.lastPathComponent.hasPrefix("results-"))
        try ResultsFolderService(cacheDir: cache).cleanup(maxAge: -1, keep: 0)
        XCTAssertFalse(fm.fileExists(atPath: folder.path))
        XCTAssertTrue(fm.fileExists(atPath: a.path))
        XCTAssertTrue(fm.fileExists(atPath: b.path))
        try? fm.removeItem(at: root)
    }
}
