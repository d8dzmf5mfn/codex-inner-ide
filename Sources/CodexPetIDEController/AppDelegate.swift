import AppKit
import CodexPetIDECore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = ControllerCoordinator()
    private var statusItem: NSStatusItem?
    private var terminationInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.startLocalBridge()
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(
            systemSymbolName: "chevron.left.forwardslash.chevron.right",
            accessibilityDescription: "Codex Inner IDE"
        )
        status.button?.toolTip = "Codex Inner IDE"

        let menu = NSMenu()
        menu.addItem(item(title: "Open IDE", action: #selector(openIDE), key: "o"))
        menu.addItem(item(title: "Choose Workspace…", action: #selector(chooseWorkspace), key: ""))
        menu.addItem(.separator())
        menu.addItem(item(title: "Quit Codex Inner IDE", action: #selector(quit), key: "q"))
        status.menu = menu
        statusItem = status

        if !UserDefaults.standard.bool(forKey: "didShowCompanionLaunchPrompt") {
            UserDefaults.standard.set(true, forKey: "didShowCompanionLaunchPrompt")
            DispatchQueue.main.async { [weak self] in self?.showFirstLaunchPrompt() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationInFlight else { return .terminateLater }
        terminationInFlight = true
        Task {
            let ready = await coordinator.prepareForTermination()
            if !ready { terminationInFlight = false }
            sender.reply(toApplicationShouldTerminate: ready)
        }
        return .terminateLater
    }

    private func item(title: String, action: Selector, key: String) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: key)
        value.target = self
        return value
    }

    @objc private func openIDE() {
        Task { await coordinator.openIDE() }
    }

    private func showFirstLaunchPrompt() {
        let alert = NSAlert()
        alert.messageText = "Codex Inner IDE is ready"
        alert.informativeText = "Open the IDE now, or use the code icon in the menu bar later. After Codex integration is enabled, an IDE entry also appears below Files."
        alert.addButton(withTitle: "Open IDE")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await coordinator.openIDE() }
    }

    @objc private func chooseWorkspace() {
        Task { await coordinator.chooseWorkspace() }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
