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
private final class DraggableStatusButton: NSButton {
    var onCommandDragEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let window {
            window.performDrag(with: event)
            onCommandDragEnded?()
            return
        }
        super.mouseDown(with: event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var notchPanel: NSPanel?
    private var notchButton: DraggableStatusButton?
    private var usesNotchPanel = false
    private var lastPopoverRefreshAt = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private let notchPositionKey = "CodexAuraNotchOffsetX.v1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "CodexAuraStatusItemCompactV4"
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
        configureNotchSafePlacement()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                if let remaining = snapshot.remainingPercent {
                    let image = self.statusImage(for: remaining)
                    let toolTip = "Codex Aura · \(snapshot.windowTitle)剩余 \(Int(remaining.rounded()))%"
                    self.statusItem?.button?.image = image
                    self.statusItem?.button?.toolTip = toolTip
                    self.notchButton?.image = image
                    self.notchButton?.toolTip = toolTip + " · ⌘拖动位置"
                } else {
                    let image = self.statusImage(for: nil)
                    let toolTip = "Codex Aura · 正在同步用量"
                    self.statusItem?.button?.image = image
                    self.statusItem?.button?.toolTip = toolTip
                    self.notchButton?.image = image
                    self.notchButton?.toolTip = toolTip + " · ⌘拖动位置"
                }
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

    @objc private func screenParametersDidChange(_ notification: Notification) {
        configureNotchSafePlacement()
    }

    private func showPopover() {
        let button = usesNotchPanel ? notchButton : statusItem?.button
        guard let button else { return }

        let now = Date()
        if now.timeIntervalSince(lastPopoverRefreshAt) >= 2 {
            lastPopoverRefreshAt = now
            store.refresh()
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

    private func configureNotchSafePlacement() {
        guard let screen = NSScreen.main,
              let rightArea = screen.auxiliaryTopRightArea,
              screen.safeAreaInsets.top > 0 else {
            usesNotchPanel = false
            notchPanel?.orderOut(nil)
            statusItem?.isVisible = true
            return
        }

        usesNotchPanel = true
        statusItem?.isVisible = false

        let buttonSize = NSSize(width: rightArea.height, height: rightArea.height)
        let panel: NSPanel
        let button: DraggableStatusButton

        if let existingPanel = notchPanel, let existingButton = notchButton {
            panel = existingPanel
            button = existingButton
        } else {
            panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: buttonSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            // Keep the button above long application menus so it never becomes
            // visually covered or impossible to click.
            panel.level = .popUpMenu
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.isMovable = true
            panel.isMovableByWindowBackground = false

            button = DraggableStatusButton(frame: NSRect(origin: .zero, size: buttonSize))
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.image = statusItem?.button?.image
            button.contentTintColor = .white
            button.toolTip = (statusItem?.button?.toolTip ?? "Codex Aura") + " · ⌘拖动位置"
            button.setButtonType(.momentaryChange)
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.onCommandDragEnded = { [weak self] in
                self?.finishNotchDrag()
            }
            panel.contentView = button

            notchPanel = panel
            notchButton = button
        }

        let maximumOffset = max(rightArea.width - buttonSize.width, 0)
        let savedOffset = (UserDefaults.standard.object(forKey: notchPositionKey) as? NSNumber)
            .map { CGFloat(truncating: $0) } ?? 8
        let safeOffset = min(max(savedOffset, 0), maximumOffset)
        let origin = NSPoint(
            x: rightArea.minX + safeOffset,
            y: rightArea.midY - (buttonSize.height / 2)
        )
        panel.setFrame(NSRect(origin: origin, size: buttonSize), display: true)
        button.frame = NSRect(origin: .zero, size: buttonSize)
        panel.orderFrontRegardless()
    }

    private func finishNotchDrag() {
        guard let panel = notchPanel else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main
        guard let screen,
              let rightArea = screen.auxiliaryTopRightArea,
              screen.safeAreaInsets.top > 0 else {
            configureNotchSafePlacement()
            return
        }

        let maximumX = max(rightArea.maxX - panel.frame.width, rightArea.minX)
        let safeX = min(max(panel.frame.minX, rightArea.minX), maximumX)
        let safeY = rightArea.midY - (panel.frame.height / 2)
        panel.setFrameOrigin(NSPoint(x: safeX, y: safeY))
        UserDefaults.standard.set(Double(safeX - rightArea.minX), forKey: notchPositionKey)
        panel.orderFrontRegardless()
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
