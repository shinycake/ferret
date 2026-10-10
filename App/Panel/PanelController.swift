import AppKit
import FerretCore

/// Backend used until the daemon is connected.
struct DisconnectedBackend: SearchBackend {
    func search(_ request: FSearchClient.SearchRequest) async throws -> SearchPayload { throw FSearchError.notConnected }
    func status() async throws -> DaemonStatus { throw FSearchError.notConnected }
}

/// Owns the search panel: field, scope chip, results table, cheat sheet, hint and footer (SPEC §6.1–6.2).
@MainActor
final class PanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let window: SearchPanel
    let field = NSTextField()
    let chip = ScopeChipView()
    let table = NSTableView()
    let scrollView = NSScrollView()
    let cheatSheet = CheatSheetView()
    let hintLabel = NSTextField(labelWithString: "")
    let footerStatus = NSTextField(labelWithString: "")
    let footerTiming = NSTextField(labelWithString: "")
    let coordinator: SearchCoordinator
    private let background: NSView

    private(set) var isVisible = false
    private(set) var scope: String?
    var query: String? { field.stringValue.isEmpty ? nil : field.stringValue }
    private(set) var rows: [ResultRow] = []
    private(set) var navigationMode = false
    private var previousApp: NSRunningApplication?
    private let demo: Bool

    /// Called when Quick Look (or another owned window) should keep the panel open on resign.
    var keepOpenOnResign: (() -> Bool)?
    var onStateChange: ((SearchCoordinator.State) -> Void)?

    init(backend: SearchBackend = DisconnectedBackend(), settings: SettingsStore = SettingsStore(), demo: Bool = false) {
        self.demo = demo
        window = SearchPanel()
        coordinator = SearchCoordinator(backend: backend, settings: settings)
        if demo {
            let solid = NSView()
            solid.wantsLayer = true
            solid.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
            solid.layer?.cornerRadius = 12
            background = solid
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 12
            effect.layer?.masksToBounds = true
            background = effect
        }
        super.init()
        buildViews()
        coordinator.onChange = { [weak self] state in self?.apply(state) }
    }

    // MARK: building

    private func buildViews() {
        window.delegate = self
        if demo { window.appearance = NSAppearance(named: .darkAqua) }
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        background.frame = content.bounds
        background.autoresizingMask = [.width, .height]
        content.addSubview(background)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22, weight: .light)
        field.placeholderString = "Search files and folders"
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        content.addSubview(field)

        chip.isHidden = true
        chip.onRemove = { [weak self] in self?.setScope(nil) }
        content.addSubview(chip)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = SearchPanel.rowHeight
        table.usesAutomaticRowHeights = false
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.refusesFirstResponder = true
        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        content.addSubview(scrollView)

        cheatSheet.isHidden = true
        content.addSubview(cheatSheet)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.isHidden = true
        content.addSubview(hintLabel)

        for label in [footerStatus, footerTiming] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .tertiaryLabelColor
            content.addSubview(label)
        }
        footerTiming.alignment = .right
        footerStatus.stringValue = "Starting…"
        window.contentView = content
        relayout(rowCount: 0, cheat: true)
    }

    private func relayout(rowCount: Int, cheat: Bool) {
        let bodyRows = cheat ? 7 : rowCount
        let height = SearchPanel.height(rows: bodyRows)
        var frame = window.frame
        let top = frame.maxY
        frame.size = NSSize(width: SearchPanel.width, height: height)
        frame.origin.y = top - height
        window.setFrame(frame, display: true)
        let w = SearchPanel.width
        let fieldY = height - SearchPanel.fieldHeight
        var fieldX: CGFloat = 18
        if !chip.isHidden {
            let cw = chip.preferredWidth
            chip.frame = NSRect(x: 14, y: fieldY + 14, width: cw, height: 28)
            fieldX = 14 + cw + 8
        }
        field.frame = NSRect(x: fieldX, y: fieldY + 13, width: w - fieldX - 18, height: 30)
        let bodyHeight = height - SearchPanel.fieldHeight - SearchPanel.footerHeight
        scrollView.frame = NSRect(x: 0, y: SearchPanel.footerHeight, width: w, height: bodyHeight)
        cheatSheet.frame = scrollView.frame
        table.tableColumns.first?.width = w - 4
        hintLabel.frame = NSRect(x: 18, y: fieldY - 2, width: w - 36, height: 14)
        footerStatus.frame = NSRect(x: 14, y: 3, width: w / 2, height: 15)
        footerTiming.frame = NSRect(x: w / 2, y: 3, width: w / 2 - 14, height: 15)
    }

    // MARK: show / hide

    func show(scope: String?, query: String? = nil) {
        setScope(scope, search: false)
        if let query { field.stringValue = query }
        present()
        coordinator.update(text: field.stringValue, scope: self.scope)
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        window.orderOut(nil)
        let app = previousApp
        previousApp = nil
        if let app, app != NSRunningApplication.current { app.activate() }
    }

    /// Hotkey toggles visibility and keeps the current query and scope.
    func toggle() {
        if isVisible {
            hide()
        } else {
            present()
            coordinator.update(text: field.stringValue, scope: scope)
        }
    }

    private func present() {
        let front = NSWorkspace.shared.frontmostApplication
        if front != NSRunningApplication.current { previousApp = front }
        position()
        isVisible = true
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame ?? screen?.frame else { return }
        let size = window.frame.size
        let x = visible.midX - size.width / 2
        let top = visible.maxY - visible.height * 0.25
        window.setFrameTopLeftPoint(NSPoint(x: x, y: top))
        _ = size
    }

    func setScope(_ newScope: String?, search: Bool = true) {
        scope = newScope
        if let newScope {
            chip.set(scope: newScope)
            chip.isHidden = false
        } else {
            chip.isHidden = true
        }
        relayout(rowCount: rows.count, cheat: !cheatSheet.isHidden)
        if search { coordinator.update(text: field.stringValue, scope: scope) }
    }

    func setFooterStatus(_ text: String) {
        footerStatus.stringValue = text
    }

    // MARK: state

    private func apply(_ state: SearchCoordinator.State) {
        hintLabel.isHidden = true
        switch state {
        case .idle:
            rows = []
            showCheatSheet(true)
            footerTiming.stringValue = ""
        case .results(let set):
            setRows(set.rows)
            footerTiming.stringValue = Self.formatTiming(set.tookUs) + (set.partial ? " · partial" : "")
            if set.contentPending > 0 { showHint("content index catching up (\(set.contentPending) folders)") }
            if set.rows.isEmpty { showHint("No matches") }
        case .hint(let message, let keeping):
            if let keeping { setRows(keeping.rows) }
            showHint(message)
        case .indexing:
            setRows([])
            showHint("Indexing… the first run scans the whole disk (~20 s)")
            footerStatus.stringValue = "Indexing…"
        case .daemonDown(let message):
            setRows([])
            showHint("Search engine unavailable: \(message)")
        }
        onStateChange?(state)
    }

    private func showHint(_ text: String) {
        hintLabel.stringValue = text
        hintLabel.isHidden = false
    }

    private func showCheatSheet(_ visible: Bool) {
        cheatSheet.isHidden = !visible
        scrollView.isHidden = visible
        table.reloadData()
        relayout(rowCount: rows.count, cheat: visible)
    }

    private func setRows(_ newRows: [ResultRow]) {
        let selectedPath = selectedRow?.path
        rows = newRows
        cheatSheet.isHidden = true
        scrollView.isHidden = false
        table.reloadData()
        relayout(rowCount: max(rows.count, 1), cheat: false)
        if let selectedPath, let index = rows.firstIndex(where: { $0.path == selectedPath }) {
            select(index)
        } else if !rows.isEmpty {
            select(0)
        }
    }

    static func formatTiming(_ us: UInt64) -> String {
        String(format: "%.1f ms", Double(us) / 1000)
    }

    var selectedIndex: Int? {
        let r = table.selectedRow
        return r >= 0 && r < rows.count ? r : nil
    }

    var selectedRow: ResultRow? { selectedIndex.map { rows[$0] } }

    func select(_ index: Int) {
        guard !rows.isEmpty else { return }
        let clamped = min(max(index, 0), rows.count - 1)
        table.selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
        table.scrollRowToVisible(clamped)
        selectionDidChange()
    }

    /// Hook for Quick Look to follow the selection.
    var onSelectionChange: (() -> Void)?
    private func selectionDidChange() { onSelectionChange?() }

    func moveSelection(by delta: Int, wrap: Bool = true) {
        guard !rows.isEmpty else { return }
        navigationMode = true
        let current = selectedIndex ?? (delta > 0 ? -1 : rows.count)
        var next = current + delta
        if wrap {
            next = (next % rows.count + rows.count) % rows.count
        }
        select(next)
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        navigationMode = false
        coordinator.update(text: field.stringValue, scope: scope)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        handle(command: selector)
    }

    /// Returns true when the command was consumed. T10/T11 extend this map.
    func handle(command selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
            moveSelection(by: SearchPanel.maxRows, wrap: false)
            return true
        case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
            moveSelection(by: -SearchPanel.maxRows, wrap: false)
            return true
        case #selector(NSResponder.moveToBeginningOfDocument(_:)):
            navigationMode = true
            select(0)
            return true
        case #selector(NSResponder.moveToEndOfDocument(_:)):
            navigationMode = true
            select(rows.count - 1)
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            if field.stringValue.isEmpty, scope != nil {
                setScope(nil)
                return true
            }
            return false
        case #selector(NSResponder.cancelOperation(_:)):
            if !field.stringValue.isEmpty {
                field.stringValue = ""
                navigationMode = false
                coordinator.update(text: "", scope: scope)
            } else {
                hide()
            }
            return true
        default:
            return extraCommandHandler?(selector) ?? false
        }
    }

    /// Extension point for Finder actions and Quick Look commands.
    var extraCommandHandler: ((Selector) -> Bool)?
    var onDoubleClick: ((ResultRow) -> Void)?

    @objc private func doubleClicked() {
        let row = table.clickedRow
        guard row >= 0, row < rows.count else { return }
        select(row)
        onDoubleClick?(rows[row])
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, !demo else { return }
        if keepOpenOnResign?() == true { return }
        hide()
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: ResultCellView.identifier, owner: nil) as? ResultCellView) ?? ResultCellView()
        cell.configure(rows[row], query: coordinator.currentQuery)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectionDidChange()
    }
}
