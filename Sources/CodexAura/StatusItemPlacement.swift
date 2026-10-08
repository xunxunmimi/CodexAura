// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import Foundation

enum StatusItemPlacement {
    static let autosaveName = "CodexAuraNativeStatusV8"
    static let positionKey = "NSStatusItem Preferred Position " + autosaveName
    static let visibleKey = "NSStatusItem Visible " + autosaveName

    static func prepare(defaults: UserDefaults, reset: Bool = false) {
        // Compatibility hint used by AppKit, NOT a public placement guarantee.
        // A new/default slot is at the far left and may be behind the notch.
        // Seed only our own new slot near the right; subsequent user drags win.
        if reset || defaults.object(forKey: positionKey) == nil {
            defaults.set(100, forKey: positionKey)
        }
        defaults.set(true, forKey: visibleKey)
    }
}
