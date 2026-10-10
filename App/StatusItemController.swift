import AppKit

/// Default shown on Search… until the KeyboardShortcuts recorder lands.
enum MenuHotkey {
    static let keyEquivalent = " "
    static let modifiers: NSEvent.ModifierFlags = .option
    static let display = "⌥Space"
}

@MainActor
final class StatusItemController: NSObject {
    let panel: PanelController
    let statusItem: NSStatusItem
    let menu: NSMenu
    let searchItem: NSMenuItem
    let setupItem: NSMenuItem
    let settingsItem: NSMenuItem
    let reindexItem: NSMenuItem
    let statusLine: NSMenuItem
    let openLogsItem: NSMenuItem
    let quitItem: NSMenuItem

    private var healthTask: Task<Void, Never>?
    private let openLogs: () -> Void

    init(panel: PanelController, health: AsyncStream<ShellHealth>, openLogs: @escaping () -> Void = StatusItemController.openLogsFolder) {
        self.panel = panel
        self.openLogs = openLogs
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        searchItem = NSMenuItem(title: "Search…", action: #selector(showSearch(_:)), keyEquivalent: MenuHotkey.keyEquivalent)
        setupItem = NSMenuItem(title: "Setup…", action: #selector(showSetup(_:)), keyEquivalent: "")
        settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        reindexItem = NSMenuItem(title: "Reindex…", action: #selector(reindex(_:)), keyEquivalent: "")
        statusLine = NSMenuItem(title: ShellHealth.starting.menuTitle, action: nil, keyEquivalent: "")
        openLogsItem = NSMenuItem(title: "Open Logs", action: #selector(openLogs(_:)), keyEquivalent: "")
        quitItem = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        super.init()

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Ferret") {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = "Ferret"
        }

        searchItem.keyEquivalentModifierMask = MenuHotkey.modifiers
        settingsItem.keyEquivalentModifierMask = .command
        quitItem.keyEquivalentModifierMask = .command
        statusLine.isEnabled = false

        menu.autoenablesItems = false
        for item in [searchItem, setupItem, settingsItem, reindexItem, openLogsItem, quitItem] {
            item.target = self
            item.isEnabled = true
        }
        menu.addItem(searchItem)
        menu.addItem(setupItem)
        menu.addItem(settingsItem)
        menu.addItem(reindexItem)
        menu.addItem(.separator())
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(openLogsItem)
        menu.addItem(quitItem)
        statusItem.menu = menu

        healthTask = Task { @MainActor [weak self] in
            for await event in health {
                self?.apply(event)
            }
        }
    }

    var statusTitle: String { statusLine.title }

    var menuItemTitles: [String] {
        menu.items.map(\.title)
    }

    /// Titles plus the Search… hotkey, for the CI log line.
    var menuDumpLine: String {
        menu.items.map { item in
            if item.isSeparatorItem { return "----" }
            if item === searchItem { return "\(item.title) [\(MenuHotkey.display)]" }
            return item.title
        }.joined(separator: " | ")
    }

    func apply(_ health: ShellHealth) {
        statusLine.title = health.menuTitle
        statusLine.isEnabled = false
    }

    @objc private func showSearch(_ sender: Any?) {
        panel.show(scope: nil, query: nil)
    }

    @objc func showSetup(_ sender: Any?) { OnboardingPresenter.showLive() }

    @objc func showSettings(_ sender: Any?) { SettingsPresenter.showLive() }

    @objc private func reindex(_ sender: Any?) {
        if SettingsPresenter.confirmReindex(SettingsModel.reindexConfirmation) {
            DaemonBridge.shared?.reindex()
        }
    }

    @objc private func openLogs(_ sender: Any?) {
        openLogs()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private static func openLogsFolder() {
        let directory = AppLocations.logDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}
