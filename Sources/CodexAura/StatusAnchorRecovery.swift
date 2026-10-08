// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import Foundation

struct StatusAnchorRecovery {
    // Unavailability is diagnostic state, not a request to display a Dock icon.
    enum Action { case wait, ready, recreate, unavailable }
    private var unavailableSince: TimeInterval?
    private var attemptedRepair = false

    mutating func layoutChanged() { unavailableSince = nil }

    mutating func update(usable: Bool, now: TimeInterval) -> Action {
        if usable {
            unavailableSince = nil
            return .ready
        }
        guard let since = unavailableSince else {
            unavailableSince = now
            return .wait
        }
        if !attemptedRepair, now - since >= 8 {
            attemptedRepair = true
            unavailableSince = now
            return .recreate
        }
        if attemptedRepair, now - since >= 4 { return .unavailable }
        return .wait
    }
}
