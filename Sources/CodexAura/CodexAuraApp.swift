// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import AppKit
import Combine
import SwiftUI

#if PREVIEW_WINDOW
@main
struct CodexAuraPreviewApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        WindowGroup("Codex Aura Preview") {
            DashboardView()
                .environmentObject(store)
                .onAppear { store.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
#else
@main
struct CodexAuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class BackupStatusButton: NSButton {
    var didDrag: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let window {
            window.performDrag(with: event)
            didDrag?()
        } else {
            super.mouseDown(with: event)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = UsageStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var fallbackWindow: NSWindow?
    private var placementTimer: Timer?
    private var backupStatusPanel: NSPanel?
    private var backupStatusButton: BackupStatusButton?
    private var lastPopoverRefreshAt = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private let lowQuotaAlertKeyPrefix = "CodexAura.LowQuotaAlert.v1."

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Seed the saved ordering once. On notched displays macOS can otherwise
        // assign a new item's default slot behind the camera. Subsequent
        // Command-drags remain owned and persisted by the system.
        let autosaveName = "CodexAuraStatusItemSystemV6"
        let positionKey = "NSStatusItem Preferred Position " + autosaveName
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(200, forKey: positionKey)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = autosaveName
        item.isVisible = true

        guard let button = item.button else {
            NSApp.terminate(nil)
            return
        }

        button.image = statusImage(for: nil)
        button.imagePosition = .imageOnly
        button.toolTip = "Codex Aura · 点击查看用量"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 410)
        let hostingController = NSHostingController(
            rootView: DashboardView().environmentObject(store)
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController

        statusItem = item
        placementTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateFallbackAccess() }
        }
        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                let fiveHourRemaining = snapshot.fiveHourRemainingPercent
                let emphasizedRemaining = fiveHourRemaining ?? snapshot.weeklyRemainingPercent
                let lowQuota = self.lowQuotaDescription(for: snapshot)
                if let remaining = emphasizedRemaining {
                    let image = self.statusImage(for: remaining)
                    let windowLabel = fiveHourRemaining == nil ? "本周剩余" : "5小时剩余"
                    let toolTip = lowQuota.map { "Codex Aura · ⚠ \($0)" }
                        ?? "Codex Aura · \(windowLabel) \(Int(remaining.rounded()))%"
                    self.statusItem?.button?.image = image
                    self.statusItem?.button?.toolTip = toolTip
                    self.statusItem?.button?.contentTintColor = lowQuota == nil ? nil : .systemRed
                } else {
                    let image = self.statusImage(for: nil)
                    let toolTip = "Codex Aura · 正在同步用量"
                    self.statusItem?.button?.image = image
                    self.statusItem?.button?.toolTip = toolTip
                    self.statusItem?.button?.contentTintColor = nil
                }
                self.presentLowQuotaIfNeeded(snapshot)
                self.backupStatusButton?.image = self.statusItem?.button?.image
                self.backupStatusButton?.contentTintColor = lowQuota == nil ? .white : .systemRed
            }
            .store(in: &cancellables)

        store.$tiboSignal
            .compactMap(\.latestPost)
            .removeDuplicates { $0.id == $1.id }
            .receive(on: RunLoop.main)
            .sink { [weak self] post in
                self?.presentNewTiboPostIfNeeded(post)
            }
            .store(in: &cancellables)

        store.start()
        showWelcomePopoverIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showPopover()
        return false
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        let now = Date()
        if now.timeIntervalSince(lastPopoverRefreshAt) >= 2 {
            lastPopoverRefreshAt = now
            store.refresh()
        }

        updateFallbackAccess()
        let anchor = hasUsableStatusAnchor ? statusItem?.button : backupStatusButton
        guard let button = anchor, button.window?.isVisible == true else {
            popover.performClose(nil)
            showFallbackWindow()
            return
        }
        if fallbackWindow?.isVisible == true {
            fallbackWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Recreate the dashboard for every opening so both optional sections
        // always begin in their intended collapsed state.
        popover.contentSize = NSSize(width: 360, height: 410)
        let hostingController = NSHostingController(
            rootView: DashboardView().environmentObject(store)
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var hasUsableStatusAnchor: Bool {
        guard let button = statusItem?.button,
              let window = button.window,
              statusItem?.isVisible == true,
              !button.bounds.isEmpty else { return false }
        let frame = button.convert(button.bounds, to: nil)
        let screenFrame = window.convertToScreen(frame)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(screenFrame) }),
              screenFrame.minY >= screen.visibleFrame.maxY - 4,
              screenFrame.maxX <= screen.frame.maxX,
              screenFrame.minX >= screen.frame.minX else { return false }
        if screen.safeAreaInsets.top > 0, let rightArea = screen.auxiliaryTopRightArea {
            return rightArea.contains(NSPoint(x: screenFrame.midX, y: screenFrame.midY))
        }
        return true
    }

    private func updateFallbackAccess() {
        statusItem?.isVisible = true
        if hasUsableStatusAnchor {
            backupStatusPanel?.orderOut(nil)
        } else {
            showBackupStatusButton()
        }
        // Keep a Dock entry whenever the system cannot provide a usable menu
        // bar anchor. Reopening the app must always offer a reachable window.
        let needsDock = (!hasUsableStatusAnchor && backupStatusPanel?.isVisible != true)
            || fallbackWindow?.isVisible == true
        let policy: NSApplication.ActivationPolicy = needsDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    private func showBackupStatusButton() {
        guard let screen = NSScreen.main else { return }
        let area = screen.auxiliaryTopRightArea ?? NSRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.maxY,
            width: screen.frame.width,
            height: max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        )
        let size = min(max(area.height, 24), 32)
        if backupStatusPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.isMovable = true
            let button = BackupStatusButton(frame: NSRect(x: 0, y: 0, width: size, height: size))
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "Codex Aura · 点击查看用量 · ⌘拖动位置"
            button.didDrag = { [weak self] in
                guard let frame = self?.backupStatusPanel?.frame else { return }
                UserDefaults.standard.set(Double(frame.minX - area.minX), forKey: "CodexAuraBackupStatusOffset.v1")
            }
            panel.contentView = button
            backupStatusPanel = panel
            backupStatusButton = button
        }
        guard let panel = backupStatusPanel else { return }
        let saved = UserDefaults.standard.object(forKey: "CodexAuraBackupStatusOffset.v1") as? NSNumber
        let offset = min(max(saved?.doubleValue ?? 8, 0), max(area.width - size, 0))
        panel.setFrame(NSRect(x: area.minX + offset, y: area.midY - size / 2, width: size, height: size), display: true)
        backupStatusButton?.frame = NSRect(x: 0, y: 0, width: size, height: size)
        backupStatusButton?.image = statusItem?.button?.image
        backupStatusButton?.contentTintColor = statusItem?.button?.contentTintColor ?? .white
        panel.orderFrontRegardless()
    }

    private func showFallbackWindow() {
        NSApp.setActivationPolicy(.regular)
        if let fallbackWindow {
            fallbackWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 410),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Codex Aura · 可拖动窗口"
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.delegate = self
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let controller = NSHostingController(
            rootView: DashboardView(onPanelHeightChange: { [weak self] height in
                self?.resizeFallbackWindow(to: height)
            }).environmentObject(store)
        )
        controller.sizingOptions = [.preferredContentSize]
        panel.contentViewController = controller
        fallbackWindow = panel
        if !panel.setFrameUsingName("CodexAuraFallbackWindow.v1") { panel.center() }
        panel.setFrameAutosaveName("CodexAuraFallbackWindow.v1")
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resizeFallbackWindow(to height: CGFloat) {
        guard let panel = fallbackWindow else { return }
        let top = panel.frame.maxY
        panel.setContentSize(NSSize(width: 360, height: height))
        var frame = panel.frame
        frame.origin.y = top - frame.height
        if let screen = panel.screen ?? NSScreen.main {
            frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
            frame.origin.y = max(frame.origin.y, screen.visibleFrame.minY)
        }
        panel.setFrame(frame, display: true)
    }

    func windowWillClose(_ notification: Notification) {
        if hasUsableStatusAnchor || backupStatusPanel?.isVisible == true {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func showWelcomePopoverIfNeeded() {
        let key = "hasShownWelcomePopoverCompactV4"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            self?.showPopover()
        }
    }

    private func presentNewTiboPostIfNeeded(_ post: TiboPost) {
        guard store.radarEnabled, store.tiboSignal.isLive else { return }
        let key = "lastPresentedTiboPostID"
        guard UserDefaults.standard.string(forKey: key) != post.id else { return }
        UserDefaults.standard.set(post.id, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            if !self.popover.isShown {
                self.showPopover()
            }
        }
    }

    private func lowQuotaDescription(for snapshot: UsageSnapshot) -> String? {
        if let remaining = snapshot.weeklyRemainingPercent, remaining <= 1 {
            return remaining <= 0 ? "每周额度已用尽" : "每周额度仅剩 \(Int(remaining.rounded()))%"
        }
        if let remaining = snapshot.fiveHourRemainingPercent, remaining <= 1 {
            return remaining <= 0 ? "5小时额度已用尽" : "5小时额度仅剩 \(Int(remaining.rounded()))%"
        }
        return nil
    }

    private func presentLowQuotaIfNeeded(_ snapshot: UsageSnapshot) {
        guard snapshot.updatedAt != .distantPast else { return }
        let windows: [(name: String, remaining: Double?, resetsAt: Date?)] = [
            ("weekly", snapshot.weeklyRemainingPercent, snapshot.weeklyResetsAt),
            ("fiveHour", snapshot.fiveHourRemainingPercent, snapshot.fiveHourResetsAt)
        ]
        let defaults = UserDefaults.standard
        var shouldPresent = false

        for window in windows {
            guard let remaining = window.remaining else { continue }
            let key = lowQuotaAlertKeyPrefix + window.name
            if remaining > 1 {
                defaults.removeObject(forKey: key)
                continue
            }

            let cycle = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "unknown"
            guard defaults.string(forKey: key) != cycle else { continue }
            defaults.set(cycle, forKey: key)
            shouldPresent = true
        }

        if shouldPresent, !popover.isShown {
            showPopover()
        }
    }

    private func statusImage(for remainingPercent: Double?) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 7

            NSColor.labelColor.withAlphaComponent(0.24).setStroke()
            let track = NSBezierPath()
            track.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 0,
                endAngle: 360
            )
            track.lineWidth = 2.15
            track.stroke()

            if let remainingPercent {
                NSColor.labelColor.setStroke()
                let progress = NSBezierPath()
                let ratio = min(max(remainingPercent / 100, 0), 1)
                progress.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - (360 * ratio),
                    clockwise: true
                )
                progress.lineWidth = 2.15
                progress.lineCapStyle = .round
                progress.stroke()
            }

            let symbolName = remainingPercent == nil ? "sparkles" : "bolt.fill"
            let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
            let symbol = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "Codex Aura"
            )?.withSymbolConfiguration(symbolConfiguration)
            symbol?.draw(
                in: NSRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}
#endif
