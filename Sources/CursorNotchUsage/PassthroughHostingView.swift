import AppKit
import SwiftUI

/// Lets clicks fall through outside the interactive island rect.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRectInView: (() -> CGRect)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let rect = interactiveRectInView?(), rect.contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }

    override var acceptsFirstResponder: Bool { true }
}
