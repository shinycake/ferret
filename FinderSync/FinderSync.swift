import Cocoa
import FinderSync

/// Toolbar button and context menus. Every action opens a `ferret://` URL and nothing else.
class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func beginObservingDirectory(at url: URL) {}

    override func endObservingDirectory(at url: URL) {}

    override var toolbarItemName: String { "Ferret" }

    override var toolbarItemToolTip: String { "Search with Ferret" }

    override var toolbarItemImage: NSImage {
        let image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Ferret")
            ?? NSImage()
        image.isTemplate = true
        return image
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .toolbarItemMenu:
            return toolbarMenu()
        case .contextualMenuForContainer, .contextualMenuForItems:
            return contextMenu()
        case .contextualMenuForSidebar:
            return nil
        @unknown default:
            return nil
        }
    }

    /// Finder calls this when the toolbar button is clicked, before it shows the menu. That call is the
    /// click: tell Ferret to dock its search field to this window right away (without activating it),
    /// and hand back an empty menu so nothing pops up. If Finder insists on a menu (some releases
    /// draw an empty one), the panel is already open and the menu closes on the next keystroke/click.
    private func toolbarMenu() -> NSMenu {
        let targeted = FIFinderSyncController.default().targetedURL()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(URLRoute.dock(scope: targeted?.path).url, configuration: config)
        return NSMenu(title: "")
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        let controller = FIFinderSyncController.default()
        let scope = ScopeResolver.scope(
            targeted: controller.targetedURL(),
            selected: controller.selectedItemURLs() ?? []
        )
        menu.addItem(searchItem(title: "Search here", scope: scope))
        return menu
    }

    private func searchItem(title: String, scope: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openSearch(_:)), keyEquivalent: "")
        item.target = self
        if let scope, !scope.isEmpty {
            item.representedObject = scope
        }
        return item
    }

    private func folderName(_ url: URL?) -> String {
        guard let url else { return "folder" }
        let name = url.lastPathComponent
        if name.isEmpty || name == "/" {
            return url.path.isEmpty ? "/" : url.path
        }
        return name
    }

    @objc private func openSearch(_ sender: NSMenuItem) {
        let scope = sender.representedObject as? String
        NSWorkspace.shared.open(URLRoute.search(query: nil, scope: scope).url)
    }
}
