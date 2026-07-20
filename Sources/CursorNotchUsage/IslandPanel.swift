import AppKit

final class IslandPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        hasShadow = false
        backgroundColor = .clear
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Do NOT set `isFloatingPanel = true` — it forces `.floating` level and
        // AppKit then clamps the frame under the menu bar / notch.
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = false
        // Set last so nothing else can override it.
        level = .mainMenu + 2
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
