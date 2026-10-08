// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import Foundation

/// Pure geometry: auxiliary safe areas describe the notch horizontally, but
/// their vertical bounds need not match the native status button on every OS.
enum StatusAnchorGeometry {
    static func isUsable(
        item: CGRect,
        screen: CGRect,
        menuBarHeight: CGFloat,
        rightSafeArea: CGRect?
    ) -> Bool {
        guard !item.isEmpty, !screen.isEmpty,
              item.minX >= screen.minX, item.maxX <= screen.maxX,
              item.midY >= screen.maxY - max(menuBarHeight, 24) - 4,
              item.midY <= screen.maxY + 1 else { return false }
        if let area = rightSafeArea {
            // Check the entire width, not just its center, against the notch.
            return item.minX >= area.minX && item.maxX <= area.maxX
        }
        return true
    }
}
