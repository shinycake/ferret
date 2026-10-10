import AppKit
import Quartz

/// Quick Look for the selected row (SPEC §6.4). Sits in the panel's responder chain.
@MainActor
final class QuickLookController: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    weak var panel: PanelController?

    init(panel: PanelController) {
        self.panel = panel
        super.init()
    }

    required init?(coder: NSCoder) { fatalError() }

    var currentURL: URL? {
        panel?.selectedRow.map { URL(fileURLWithPath: $0.path) }
    }

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func toggle() {
        if isVisible { close() } else { show() }
    }

    func show() {
        guard currentURL != nil, let ql = QLPreviewPanel.shared() else { return }
        ql.dataSource = self
        ql.delegate = self
        ql.makeKeyAndOrderFront(nil)
        ql.reloadData()
    }

    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    func selectionChanged() {
        guard isVisible else { return }
        QLPreviewPanel.shared().reloadData()
    }

    // MARK: responder chain control

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: data source

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { currentURL == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { currentURL as NSURL? }
    }

    // MARK: delegate

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return MainActor.assumeIsolated {
            switch event.keyCode {
            case 125: self.panel?.moveSelection(by: 1); return true
            case 126: self.panel?.moveSelection(by: -1); return true
            case 53: self.close(); return true
            default: return false
            }
        }
    }
}
