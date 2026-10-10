import AppKit

/// Removable "in: <folder>" token left of the search field; the full path is the tooltip.
final class ScopeChipView: NSView {
    let label = NSTextField(labelWithString: "")
    let removeButton = NSButton()
    var onRemove: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        removeButton.bezelStyle = .inline
        removeButton.isBordered = false
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove scope")
        removeButton.target = self
        removeButton.action = #selector(remove)
        addSubview(label)
        addSubview(removeButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(scope: String) {
        let name = (scope as NSString).lastPathComponent
        label.stringValue = "in: \(name.isEmpty ? scope : name)"
        toolTip = scope
    }

    var preferredWidth: CGFloat {
        min(label.intrinsicContentSize.width + 34, 220)
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 8, y: (bounds.height - 18) / 2, width: bounds.width - 30, height: 18)
        removeButton.frame = NSRect(x: bounds.width - 22, y: (bounds.height - 16) / 2, width: 16, height: 16)
    }

    @objc private func remove() { onRemove?() }
}
