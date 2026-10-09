import XCTest
@testable import FerretCore

final class QueryTextTests: XCTestCase {
    func testContentKeysMatchTheServerList() {
        XCTAssertEqual(QueryText.contentKeys, ["grep:", "regex:", "sym:", "content:", "symbol:"])
    }

    func testIsContentUsesSubstringParityWithTheServer() {
        let cases: [(String, Bool)] = [
            ("mygrep:x", true),
            ("grep:x", true),
            ("grep:", true),
            ("regex:foo", true),
            ("sym:Name", true),
            ("content:apply", true),
            ("symbol:Engine", true),
            ("ext:rs grep:apply_dir", true),
            ("hello", false),
            ("grep", false),
            ("grep :x", false),
            ("GREP:x", false),
            ("", false),
            ("path:foo", false),
            ("xgrep:y", true),
        ]
        for (query, expected) in cases {
            XCTAssertEqual(QueryText.isContent(query), expected, query)
        }
    }

    func testIsSendableRejectsEmptyPatterns() {
        let cases: [(String, Bool)] = [
            ("grep:", false),
            ("ext:rs grep:", false),
            ("regex: foo", false),
            ("grep:x", true),
            ("hello", true),
            ("", true),
            ("symbol:", false),
            ("sym: ", false),
            ("content:x", true),
            ("grep:x regex:", false),
            ("mygrep:x", true),
            ("regex:foo", true),
            ("symbol:Engine", true),
            ("content:", false),
            ("sym:apply", true),
            ("grep:\tpattern", true),
        ]
        for (query, expected) in cases {
            XCTAssertEqual(QueryText.isSendable(query), expected, query)
        }
    }

    func testScopeTokenQuotesPathsWithSpaces() {
        XCTAssertEqual(QueryText.scopeToken(for: "/a/b"), "in:/a/b")
        XCTAssertEqual(QueryText.scopeToken(for: "/a/b c"), "in:\"/a/b c\"")
        XCTAssertEqual(QueryText.scopeToken(for: "/Users/idan/My Documents"), "in:\"/Users/idan/My Documents\"")
        XCTAssertEqual(QueryText.scopeToken(for: "~/Developer"), "in:~/Developer")
        XCTAssertFalse(QueryText.scopeToken(for: "/a/b").contains("\""))
        XCTAssertTrue(QueryText.scopeToken(for: "/a/b c").contains("\""))
    }

    func testNormalizedTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(QueryText.normalized("  foo   bar  "), "foo bar")
        XCTAssertEqual(QueryText.normalized("foo\t\tbar\nbaz"), "foo bar baz")
        XCTAssertEqual(QueryText.normalized("   "), "")
        XCTAssertEqual(QueryText.normalized("ext:rs   grep:apply"), "ext:rs grep:apply")
        XCTAssertEqual(QueryText.normalized("already fine"), "already fine")
    }
}
