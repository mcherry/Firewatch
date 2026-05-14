import AppKit
import SwiftUI
import Combine
// MARK: - Floating Panel

final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let statusManager = StatusManager()
    let updateChecker = UpdateChecker()
    private var statusItem: NSStatusItem!
    private var panel: StatusPanel!
    private var settingsWindow: NSWindow?
    private var uptimeWindow: NSWindow?
    private var hostingController: NSHostingController<AnyView>!
    private var cancellables = Set<AnyCancellable>()
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var lastToggleTime: TimeInterval = 0
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "refreshInterval": 120.0,
            "notificationsEnabled": false,
            "autoCheckForUpdates": true,
            "uptimeLoggingEnabled": false
        ])

        statusManager.notificationManager.setup()
        setupStatusItem()
        setupPanel()
        setupKeyboardShortcut()
        setupGlobalClickMonitor()
        observeStatusChanges()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings),
            name: .openSettings,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenUptimeHistory),
            name: .openUptimeHistory,
            object: nil
        )

        Task {
            await statusManager.refreshAll(force: true)
            updateChecker.checkIfNeeded()
        }
    }

    @objc private func handleOpenSettings() {
        hidePanel(restoreFocus: false)
        openSettings()
    }

    @objc private func handleOpenUptimeHistory() {
        hidePanel(restoreFocus: false)
        openUptimeHistory()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(
                systemSymbolName: "circle.dotted",
                accessibilityDescription: "Firewatch"
            )?.withSymbolConfiguration(config)
            button.image = image
            button.action = #selector(handleStatusItemClick)
            button.target = self
        }

        // Local monitor as backup for when button.action works (app active)
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  let buttonWindow = self.statusItem.button?.window,
                  event.window == buttonWindow else {
                return event
            }
            self.togglePanel()
            return nil
        }
    }

    @objc private func handleStatusItemClick() {
        NSLog("[Firewatch] button.action: status item click")
        togglePanel()
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        let health = statusManager.overallHealth

        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [health.nsColor])
        let config = sizeConfig.applying(colorConfig)

        if let image = NSImage(
            systemSymbolName: health.iconName,
            accessibilityDescription: health.displayName
        )?.withSymbolConfiguration(config) {
            image.isTemplate = false
            button.image = image
        }
    }

    // MARK: - Panel

    private func setupPanel() {
        let rootView = AnyView(
            StatusDashboardView()
                .environmentObject(statusManager)
        )
        hostingController = NSHostingController(rootView: rootView)
        hostingController.safeAreaRegions = []

        panel = StatusPanel(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentViewController = hostingController

        // Opaque rounded background on the content view so the panel
        // always renders, even when the app isn't active
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView?.layer?.cornerRadius = 14
        panel.contentView?.layer?.masksToBounds = true
    }

    private func hidePanel(restoreFocus: Bool = true) {
        panel.orderOut(nil)
        NotificationCenter.default.post(name: .panelDidClose, object: nil)

        if restoreFocus, let app = previousApp, !app.isTerminated {
            app.activate()
        }
        previousApp = nil
    }

    func togglePanel() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastToggleTime > 0.3 else { return }
        lastToggleTime = now

        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        previousApp = NSWorkspace.shared.frontmostApplication
        updatePanelSize()
        positionPanelBelowStatusItem()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func updatePanelSize() {
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude)
        )
        let width: CGFloat = 420
        let height = min(max(fittingSize.height, 200), 650)
        panel.setContentSize(NSSize(width: width, height: height))
    }

    private func positionPanelBelowStatusItem() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        // The button's window frame is its exact position in the menu bar
        let statusFrame = buttonWindow.frame
        let panelSize = panel.frame.size

        // Center the panel horizontally under the status item
        var x = statusFrame.midX - panelSize.width / 2
        let y = statusFrame.minY - panelSize.height - 4

        // Clamp to screen edges
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            x = max(visibleFrame.minX + 4, min(x, visibleFrame.maxX - panelSize.width - 4))
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Keyboard Shortcut

    private func setupKeyboardShortcut() {
        let combo = HotkeyManager.shared.loadSaved() ?? .default
        HotkeyManager.shared.register(combo: combo) { [weak self] in
            Task { @MainActor [weak self] in
                self?.togglePanel()
            }
        }
    }

    // MARK: - Click Outside to Dismiss

    private func setupGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let clickPoint = NSEvent.mouseLocation

                if let buttonWindow = self.statusItem.button?.window,
                   buttonWindow.frame.contains(clickPoint) {
                    self.togglePanel()
                    return
                }

                // Don't dismiss if we just showed the panel (local monitor may have
                // already handled this same click)
                let now = ProcessInfo.processInfo.systemUptime
                guard now - self.lastToggleTime > 0.5 else { return }

                if self.panel.isVisible {
                    self.hidePanel()
                }
            }
        }
    }

    // MARK: - Observation

    private func observeStatusChanges() {
        statusManager.$services
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarIcon()
            }
            .store(in: &cancellables)
    }

    // MARK: - Settings Window

    func openSettings() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            settingsWindow.orderFrontRegardless()
            NSApp.activate()
            return
        }

        let settingsView = SettingsView()
            .environmentObject(statusManager)
            .environmentObject(updateChecker)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Firewatch Settings"
        window.contentViewController = NSHostingController(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()

        // Reset level after it appears so it behaves like a normal window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            window.level = .normal
        }

        settingsWindow = window
    }

    // MARK: - Uptime History Window

    func openUptimeHistory() {
        if let uptimeWindow, uptimeWindow.isVisible {
            uptimeWindow.makeKeyAndOrderFront(nil)
            uptimeWindow.orderFrontRegardless()
            NSApp.activate()
            return
        }

        let historyView = UptimeHistoryView(uptimeStore: statusManager.uptimeStore)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Uptime History"
        window.contentViewController = NSHostingController(rootView: historyView)
        window.minSize = NSSize(width: 600, height: 400)
        window.setFrameAutosaveName("UptimeHistory")
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            window.level = .normal
        }

        uptimeWindow = window
    }
}
