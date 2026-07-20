import AppKit

enum NotchGeometry {
    /// System primary display (menu bar) — not the focus-following `NSScreen.main`.
    static var primaryScreen: NSScreen? {
        NSScreen.screens.first
    }

    static var menubarHeight: CGFloat {
        guard let screen = primaryScreen else { return 34 }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }

    /// Exact hardware notch size from the auxiliary top areas on the primary screen.
    static var notchSize: CGSize {
        notchSize(on: primaryScreen)
    }

    static func notchSize(on screen: NSScreen?) -> CGSize {
        guard
            let screen,
            let left = screen.auxiliaryTopLeftArea?.width,
            let right = screen.auxiliaryTopRightArea?.width
        else {
            return CGSize(width: 180, height: menubarHeight)
        }

        return CGSize(
            width: screen.frame.width - left - right,
            height: max(screen.safeAreaInsets.top, 1)
        )
    }

    static func notchFrame(on screen: NSScreen? = primaryScreen) -> NSRect {
        guard let screen else { return .zero }
        let size = notchSize(on: screen)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Large top-anchored window so the island can grow without reflow jumps.
    static func panelFrame(on screen: NSScreen? = primaryScreen) -> NSRect {
        guard let screen else { return .zero }
        let size = NSSize(
            width: screen.frame.width / 2,
            height: screen.frame.height / 2
        )
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func viewRect(forScreenRect screenRect: NSRect, panelFrame: NSRect) -> NSRect {
        NSRect(
            x: screenRect.minX - panelFrame.minX,
            y: screenRect.minY - panelFrame.minY,
            width: screenRect.width,
            height: screenRect.height
        )
    }
}
