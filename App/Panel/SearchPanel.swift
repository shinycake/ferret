import AppKit

/// Floating, non-activating search panel (SPEC §6.1). Created once and reused.
final class SearchPanel: NSPanel {
    static let width: CGFloat = 680
    static let fieldHeight: CGFloat = 56
    static let rowHeight: CGFloat = 44
    static let maxRows = 9
    static let footerHeight: CGFloat = 22

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.fieldHeight + Self.footerHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    static func height(rows: Int) -> CGFloat {
        fieldHeight + CGFloat(min(max(rows, 0), maxRows)) * rowHeight + footerHeight
    }
}
