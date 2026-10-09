import Foundation

public enum QueryText {
    /// Same substrings the server uses to route a search onto the grep path.
    public static let contentKeys = ["grep:", "regex:", "sym:", "content:", "symbol:"]

    /// True when `q` contains any content key, including inside a larger token (`mygrep:x`).
    public static func isContent(_ q: String) -> Bool {
        contentKeys.contains { q.contains($0) }
    }

    /// False when a content key is followed by the end of the string or a space (an empty pattern).
    public static func isSendable(_ q: String) -> Bool {
        for key in contentKeys {
            var rest = q[...]
            while let range = rest.range(of: key) {
                let after = range.upperBound
                if after == q.endIndex || q[after] == " " {
                    return false
                }
                rest = q[after...]
            }
        }
        return true
    }

    /// Display and copy form only. The socket request sends the path as the `in` field.
    public static func scopeToken(for path: String) -> String {
        if path.contains(" ") {
            return "in:\"\(path)\""
        }
        return "in:\(path)"
    }

    public static func normalized(_ q: String) -> String {
        q.split { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
            .joined(separator: " ")
    }
}
