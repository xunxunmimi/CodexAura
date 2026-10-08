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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    #if STATUS_ITEM_SMOKE_TEST
    private let store = UsageStore(defaults: nil, fetchUsage: { _ in
        var value = UsageSnapshot.empty
        value.usedPercent = 28
        value.windowDurationMins = 10_080
        value.windows = [QuotaWindow(usedPercent: 28, resetsAt: nil, durationMins: 10_080)]
        value.planName = "TEST"
        value.updatedAt = Date()
        return value
    })
    #else
    private let store = UsageStore()
    #endif
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var fallbackWindow: NSWindow?
    private var placementTimer: Timer?
    private var anchorRecovery = StatusAnchorRecovery()
    private var pendingPresentation: Task<Void, Never>?
    private var pendingAllowsFallback = false
    private var lastPopoverRefreshAt = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private let lowQuotaAlertKeyPrefix = "CodexAura.LowQuotaAlert.v1."

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        installStatusItem()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 410)
        let hostingController = NSHostingController(
            rootView: DashboardView().environmentObject(store)
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController

        placementTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateFallbackAccess() }
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.anchorRecovery.layoutChanged()
                self?.updateFallbackAccess()
            }
            .store(in: &cancellables)
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
                    self.statusItem?.button?.toolTip = snapshot.isQuotaStale ? toolTip + " · 上次数据，未更新" : toolTip
                    self.statusItem?.button?.contentTintColor = lowQuota == nil ? nil : .systemRed
                } else {
                    let image = self.statusImage(for: nil)
                    let toolTip = "Codex Aura · 正在同步用量"
                    self.statusItem?.button?.image = image
                    self.statusItem?.button?.toolTip = toolTip
                    self.statusItem?.button?.contentTintColor = nil
                }
                self.presentLowQuotaIfNeeded(snapshot)
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
        #if STATUS_ITEM_SMOKE_TEST
        for seconds in [2.0, 10.0, 20.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self else { return }
                print(self.menuBarDiagnostics())
                fflush(stdout)
            }
        }
        #endif
    }

    private func installStatusItem(recovering: Bool = false) {
        let image = statusItem?.button?.image ?? statusImage(for: nil)
        let tooltip = statusItem?.button?.toolTip ?? "Codex Aura · 点击查看用量"
        let tint = statusItem?.button?.contentTintColor
        popover.performClose(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        let defaults = UserDefaults.standard
        StatusItemPlacement.prepare(defaults: defaults, reset: recovering)
        let item = NSStatusBar.system.statusItem(withLength: 24)
        // Recover once into a fresh system-owned slot, without rewriting other
        // apps' positions or continually fighting the user's Command-drag order.
        item.autosaveName = StatusItemPlacement.autosaveName
        statusItem = item
        item.isVisible = true
        guard let button = item.button else { return }
        button.image = image
        button.contentTintColor = tint
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        requestPresentation(allowFallback: true)
        return false
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(clickedAnchor: sender as? NSStatusBarButton)
        }
    }

    private func showPopover(clickedAnchor: NSStatusBarButton? = nil) {
        let now = Date()
        if now.timeIntervalSince(lastPopoverRefreshAt) >= 2 {
            lastPopoverRefreshAt = now
            store.refresh()
        }

        updateFallbackAccess()
        // A delivered native click is stronger evidence than screen geometry.
        let anchor = clickedAnchor ?? (hasUsableStatusAnchor ? statusItem?.button : nil)
        guard let button = anchor, button.window != nil else {
            requestPresentation(allowFallback: false)
            return
        }
        pendingPresentation?.cancel()
        pendingPresentation = nil
        fallbackWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)

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
        #if STATUS_ITEM_SMOKE_TEST
        if ProcessInfo.processInfo.environment["CODEXAURA_SMOKE_FORCE_UNAVAILABLE"] == "1" {
            return false
        }
        #endif
        guard let button = statusItem?.button,
              let window = button.window,
              statusItem?.isVisible == true,
              window.isVisible,
              !button.bounds.isEmpty else { return false }
        let frame = button.convert(button.bounds, to: nil)
        let screenFrame = window.convertToScreen(frame)
        return NSScreen.screens.contains { screen in
            StatusAnchorGeometry.isUsable(
                item: screenFrame,
                screen: screen.frame,
                menuBarHeight: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top),
                rightSafeArea: screen.safeAreaInsets.top > 0 ? screen.auxiliaryTopRightArea : nil
            )
        }
    }

    private func updateFallbackAccess() {
        let action = anchorRecovery.update(usable: hasUsableStatusAnchor,
            now: ProcessInfo.processInfo.systemUptime)
        if action == .recreate { installStatusItem(recovering: true) }
        // Background geometry checks must never change Dock visibility. Fullscreen,
        // auto-hidden menu bars and display relayout can temporarily hide the anchor.
        // Only explicit fallback-window presentation/closure changes app policy.
    }

    private func requestPresentation(allowFallback: Bool) {
        pendingAllowsFallback = pendingAllowsFallback || allowFallback
        guard pendingPresentation == nil else { return }
        pendingPresentation = Task { @MainActor [weak self] in
            // Wait through startup / display relayout and one native-item repair.
            for _ in 0..<14 {
                guard !Task.isCancelled, let self else { return }
                self.updateFallbackAccess()
                if self.hasUsableStatusAnchor {
                    self.pendingPresentation = nil
                    self.pendingAllowsFallback = false
                    self.showPopover()
                    return
                }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
            }
            guard !Task.isCancelled, let self else { return }
            self.pendingPresentation = nil
            // Welcome / quota / post notifications never force a standalone window.
            // Only explicitly reopening the app may request that recovery window.
            let fallback = self.pendingAllowsFallback
            self.pendingAllowsFallback = false
            if fallback { self.showFallbackWindow() }
        }
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
        let controller = NSHostingController(rootView: VStack(spacing: 0) {
            HStack {
                Button("恢复菜单栏图标") { [weak self] in
                    guard let self else { return }
                    self.installStatusItem(recovering: true)
                    self.anchorRecovery.layoutChanged()
                    self.requestPresentation(allowFallback: false)
                }
                Button("复制图标诊断") { [weak self] in
                    guard let self else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(self.menuBarDiagnostics(), forType: .string)
                }
            }.padding(8)
            DashboardView(onPanelHeightChange: { [weak self] height in
                self?.resizeFallbackWindow(to: height + 40)
            }).environmentObject(store)
        })
        controller.sizingOptions = [.preferredContentSize]
        panel.contentViewController = controller
        fallbackWindow = panel
        if !panel.setFrameUsingName("CodexAuraFallbackWindow.v1") { panel.center() }
        panel.setFrameAutosaveName("CodexAuraFallbackWindow.v1")
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func menuBarDiagnostics() -> String {
        let frame = statusItem?.button.flatMap { button in
            button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) }
        }
        return [
            "Codex Aura " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "test"),
            ProcessInfo.processInfo.operatingSystemVersionString,
            "native item: \(statusItem != nil), visible: \(statusItem?.isVisible ?? false)",
            "window visible: \(statusItem?.button?.window?.isVisible ?? false), frame: \(frame.map(NSStringFromRect) ?? "nil")",
            "anchor usable: \(hasUsableStatusAnchor), policy: \(NSApp.activationPolicy().rawValue)",
            "saved position: \(UserDefaults.standard.object(forKey: StatusItemPlacement.positionKey) ?? "none")",
            "screens: " + NSScreen.screens.map {
                "\(NSStringFromRect($0.frame)); safe top=\($0.safeAreaInsets.top); right=\($0.auxiliaryTopRightArea.map(NSStringFromRect) ?? "nil")"
            }.joined(separator: " | ")
        ].joined(separator: "\n")
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
        guard let window = notification.object as? NSWindow,
              window === fallbackWindow else { return }
        NSApp.setActivationPolicy(.accessory)
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
        guard !snapshot.isQuotaStale else { return nil }
        if let remaining = snapshot.weeklyRemainingPercent, remaining <= 1 {
            return remaining <= 0 ? "每周额度已用尽" : "每周额度仅剩 \(Int(remaining.rounded()))%"
        }
        if let remaining = snapshot.fiveHourRemainingPercent, remaining <= 1 {
            return remaining <= 0 ? "5小时额度已用尽" : "5小时额度仅剩 \(Int(remaining.rounded()))%"
        }
        return nil
    }

    private func presentLowQuotaIfNeeded(_ snapshot: UsageSnapshot) {
        guard !snapshot.isQuotaStale else { return }
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
