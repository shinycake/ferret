import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.space, modifiers: [.option]))
}

/// Global hotkey (default ⌥Space) that toggles the search panel (SPEC §6.6).
@MainActor
final class HotkeyService {
    let panel: PanelController
    private var registered = false

    init(panel: PanelController) {
        self.panel = panel
    }

    func register() {
        guard !registered else { return }
        registered = true
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.fire()
        }
    }

    /// When set, the hotkey docks the panel to Finder while Finder is frontmost.
    var finderDock: FinderDockController?

    func fire() {
        if let finderDock, FinderDockController.finderIsFrontmost || (panel.isVisible && panel.docked) {
            finderDock.toggle(folder: nil)
            return
        }
        panel.toggle()
    }

    static var defaultShortcut: KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.Name.togglePanel.defaultShortcut
    }

    /// Recorder for the Settings window.
    static func recorder() -> some View {
        KeyboardShortcuts.Recorder("Search hotkey:", name: .togglePanel)
    }
}
