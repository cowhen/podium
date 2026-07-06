import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

let appWM = WindowManager()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?
    private var loginItem: NSMenuItem!
    private var switcherItem: NSMenuItem!
    private var settingsWC: SettingsWindowController?

    func applicationDidFinishLaunching(_ note: Notification) {
        setupStatusItem()
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            start()
        } else {
            updateStatus(trusted: false)
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
                if AXIsProcessTrusted() { t.invalidate(); self?.start() }
            }
        }
    }

    private func start() {
        applyHotkey()
        applyRadial()
        DirectActions.register()
        DragSnapManager.shared.start()
        RestoreCenter.shared.start()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: SettingsStore.changed, object: nil)
        // Setup-Wechsel (Umstecken, Wake): passendes Layout ggf. automatisch anwenden.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            LayoutPresetStore.shared.screenSetupChanged()
        }
        Onboarding.showIfNeeded()
    }

    // Radial-Menü-Hotkey (konfigurierbar, Default ⌃⌥Space) je nach Einstellung
    // an/ab. Achtung: ⌃⌥Space kann von der Eingabequellen-Umschaltung belegt
    // sein — dann in den Einstellungen umlegen.
    private func applyRadial() {
        if SettingsStore.shared.radialMenu {
            let st = SettingsStore.shared
            HotKeyCenter.shared.register(id: 30, keyCode: st.radialKeyCode, mods: st.radialMods) {
                RadialMenu.shared.toggle()
            }
        } else {
            HotKeyCenter.shared.unregister(id: 30)
        }
    }

    // Kurzbefehl aus den Einstellungen (neu) registrieren; Menü-Titel spiegeln.
    private func applyHotkey() {
        let s = SettingsStore.shared
        let ok = HotKeyCenter.shared.register(id: 1, keyCode: s.hotkeyKeyCode, mods: s.hotkeyMods) {
            OverlayController.shared.toggle()
        }
        switcherItem?.title = "Fenster-Switcher (\(s.hotkeyLabel))"
        updateStatus(trusted: true, hotkeyOK: ok)
    }

    @objc private func settingsChanged() {
        applyHotkey()
        applyRadial()
        if !SettingsStore.shared.linkedEdges { LinkedEdges.shared.untrackAll() }
    }

    // MARK: Menüleiste

    // Template-Icon (schwarz auf transparent) — passt sich hell/dunkel an.
    private static var menuIcon: NSImage? {
        guard let img = Bundle.main.image(forResource: "MenuIconTemplate") else { return nil }
        img.isTemplate = true
        return img
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = Self.menuIcon {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "⊟"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "PODIUM", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        switcherItem = NSMenuItem(title: "Fenster-Switcher (\(SettingsStore.shared.hotkeyLabel))",
                                  action: #selector(relayoutNow), keyEquivalent: "r")
        menu.addItem(switcherItem)
        menu.addItem(NSMenuItem(title: "Anordnung wiederherstellen", action: #selector(restoreNow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Layout für dieses Setup speichern", action: #selector(saveLayout), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Gespeichertes Layout anwenden", action: #selector(applyLayout), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Radial-Menü öffnen", action: #selector(openRadial), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: ","))
        loginItem = NSMenuItem(title: "Bei Anmeldung starten", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func updateStatus(trusted: Bool, hotkeyOK: Bool = true) {
        if !trusted {
            statusItem.button?.image = nil
            statusItem.button?.title = "⚠"
            statusItem.button?.toolTip = "Bedienungshilfen-Zugriff fehlt – in Systemeinstellungen freigeben"
        } else if !hotkeyOK {
            statusItem.button?.image = nil
            statusItem.button?.title = "⚠"
            statusItem.button?.toolTip = "Hotkey ⌥⇥ konnte nicht registriert werden (anderweitig belegt?)"
        } else {
            statusItem.button?.title = ""
            if let icon = Self.menuIcon { statusItem.button?.image = icon }
            statusItem.button?.toolTip = "PODIUM aktiv"
        }
    }

    @objc private func relayoutNow() { OverlayController.shared.toggle() }
    @objc private func restoreNow() { RestoreCenter.shared.restoreNow() }
    @objc private func saveLayout() { LayoutPresetStore.shared.saveCurrent() }
    @objc private func openRadial() { RadialMenu.shared.toggle() }
    @objc private func applyLayout() {
        guard let p = LayoutPresetStore.shared.preset(for: displaySetFingerprint()) else { return }
        LayoutPresetStore.shared.apply(p)
    }
    @objc private func openSettings() {
        if settingsWC == nil { settingsWC = SettingsWindowController() }
        settingsWC?.showWindow(nil)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggleLoginItem() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
