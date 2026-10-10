import AppKit
import FerretCore

enum RowFormat {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func size(_ row: ResultRow) -> String {
        guard row.kind == .file, let size = row.size else { return "" }
        return byteFormatter.string(fromByteCount: Int64(size))
    }

    static func date(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        if now.timeIntervalSince(date) < 7 * 86_400 {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return f.localizedString(for: date, relativeTo: now)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        if let range = path.range(of: #"^/Users/[^/]+"#, options: .regularExpression), ProcessInfo.processInfo.environment["FERRET_DEMO"] == "1" {
            return "~" + path[range.upperBound...]
        }
        return path
    }

    /// Bold the first token found as a cheap case-insensitive substring of the name.
    static func highlighted(name: String, query: String, font: NSFont) -> NSAttributedString {
        let text = NSMutableAttributedString(string: name, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let tokens = query.split(separator: " ").map(String.init).filter { !$0.contains(":") && $0.count > 1 }
        for token in tokens {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "'^$!\""))
            guard !cleaned.isEmpty else { continue }
            let range = (name as NSString).range(of: cleaned, options: .caseInsensitive)
            if range.location != NSNotFound {
                text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: font.pointSize), range: range)
            }
        }
        return text
    }
}

final class ResultCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ResultCell")
    let icon = NSImageView()
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    let sizeLabel = NSTextField(labelWithString: "")
    let dateLabel = NSTextField(labelWithString: "")
    private var representedPath: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.lineBreakMode = .byTruncatingTail
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        for label in [sizeLabel, dateLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
        }
        for view in [icon, title, subtitle, sizeLabel, dateLabel] as [NSView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width
        icon.frame = NSRect(x: 12, y: (h - 32) / 2, width: 32, height: 32)
        let right: CGFloat = 110
        title.frame = NSRect(x: 54, y: h / 2, width: w - 54 - right - 12, height: 18)
        subtitle.frame = NSRect(x: 54, y: h / 2 - 17, width: w - 54 - right - 12, height: 15)
        sizeLabel.frame = NSRect(x: w - right - 12, y: h / 2, width: right, height: 16)
        dateLabel.frame = NSRect(x: w - right - 12, y: h / 2 - 16, width: right, height: 15)
    }

    func configure(_ row: ResultRow, query: String) {
        representedPath = row.path
        title.attributedStringValue = RowFormat.highlighted(name: row.name, query: query, font: .systemFont(ofSize: 14))
        if let snippet = row.snippet {
            subtitle.stringValue = snippet
            toolTip = row.path
            sizeLabel.stringValue = row.extraMatches > 0 ? "+\(row.extraMatches) more" : ""
            dateLabel.stringValue = RowFormat.abbreviate(row.parent)
        } else {
            subtitle.stringValue = RowFormat.abbreviate(row.parent)
            toolTip = nil
            sizeLabel.stringValue = RowFormat.size(row)
            dateLabel.stringValue = RowFormat.date(row.mtime)
        }
        let path = row.path
        icon.image = IconCache.shared.icon(for: row) { [weak self] image in
            guard let self, self.representedPath == path else { return }
            self.icon.image = image
        }
        needsLayout = true
    }
}
