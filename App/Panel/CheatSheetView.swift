import AppKit

/// Shown instead of rows when the query is empty (SPEC §3.5 / §6.2).
final class CheatSheetView: NSView {
    static let entries: [(String, String)] = [
        ("alpha rep", "fuzzy words; 5+ letters forgive one typo"),
        ("'exact  ^prefix  suffix$  !not", "exact, prefix, suffix, exclude"),
        ("ext:pdf,md", "by extension"),
        ("type:image|video|audio|doc|code|archive|font|app", "by type"),
        ("kind:dir  kind:file", "folders or files"),
        ("size:>5mb  size:1k..2m", "by size"),
        ("mtime:<7d  modified:>1y", "by modification time"),
        ("in:~/Developer", "inside a folder"),
        ("grep:apply_dir  regex:fn\\s+main  sym:Foo", "search file contents"),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let header = NSTextField(labelWithString: "Search filters")
        header.font = .boldSystemFont(ofSize: 12)
        header.textColor = .secondaryLabelColor
        stack.addArrangedSubview(header)
        for (example, help) in Self.entries {
            let code = NSTextField(labelWithString: example)
            code.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            code.textColor = .labelColor
            let detail = NSTextField(labelWithString: help)
            detail.font = .systemFont(ofSize: 12)
            detail.textColor = .secondaryLabelColor
            let row = NSStackView(views: [code, detail])
            row.spacing = 12
            code.widthAnchor.constraint(equalToConstant: 330).isActive = true
            stack.addArrangedSubview(row)
        }
        let tip = NSTextField(labelWithString: "Return reveals in Finder · ⌘Return opens · Space previews · ⌘⇧Return shows all")
        tip.font = .systemFont(ofSize: 11)
        tip.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(tip)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
