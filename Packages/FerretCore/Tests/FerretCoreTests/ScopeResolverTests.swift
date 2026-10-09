import XCTest
@testable import FerretCore

final class ScopeResolverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        root = base.appendingPathComponent("ferret-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDirectoryResolvesToItself() throws {
        let dir = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: file)

        XCTAssertEqual(ScopeResolver.scope(targeted: root, selected: [dir]), dir.path)
        XCTAssertEqual(ScopeResolver.scope(targeted: root, selected: [dir, file]), dir.path)
    }

    func testFileResolvesToParent() throws {
        let dir = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: file)

        XCTAssertEqual(ScopeResolver.scope(targeted: root, selected: [file]), dir.path)
    }

    func testPackageResolvesToParent() throws {
        let package = root.appendingPathComponent("Foo.app", isDirectory: true)
        let contents = package.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.example.foo</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleName</key><string>Foo</string>
        </dict></plist>
        """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        let recognized = (try? package.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
        XCTAssertTrue(recognized, "Foo.app was not recognized as a package")
        XCTAssertEqual(ScopeResolver.scope(targeted: root, selected: [package]), root.path)
    }

    func testNoSelectionUsesTargeted() {
        XCTAssertEqual(ScopeResolver.scope(targeted: root, selected: []), root.path)
        XCTAssertNil(ScopeResolver.scope(targeted: nil, selected: []))
    }
}
