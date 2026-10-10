import AppKit

/// Panel lifecycle for the menu bar and URL router.
/// The search field, results list, and window chrome land with the panel ticket.
@MainActor
final class PanelController: NSObject {
    private(set) var isVisible = false
    private(set) var scope: String?
    private(set) var query: String?

    func show(scope: String?, query: String? = nil) {
        self.scope = scope
        self.query = query
        isVisible = true
    }

    func hide() {
        isVisible = false
    }

    /// Hotkey toggles visibility and keeps the current query and scope.
    func toggle() {
        if isVisible {
            hide()
        } else {
            isVisible = true
        }
    }
}
