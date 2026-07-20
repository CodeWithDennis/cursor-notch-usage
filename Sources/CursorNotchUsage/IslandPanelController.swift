import AppKit
import SwiftUI

@MainActor
final class IslandPanelController {
    private let panel: IslandPanel
    private let hostingView: PassthroughHostingView<IslandRootView>
    private let viewModel: IslandViewModel
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var hoverTimer: Timer?

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel

        let frame = NotchGeometry.panelFrame()
        let hosting = PassthroughHostingView(rootView: IslandRootView(viewModel: viewModel))
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.safeAreaRegions = []
        self.hostingView = hosting

        let panel = IslandPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentView = hosting
        panel.level = .mainMenu + 2
        self.panel = panel

        hosting.interactiveRectInView = { [weak self] in
            self?.interactiveRectInPanelView() ?? .zero
        }
    }

    func show() {
        guard let screen = NotchGeometry.targetScreen else { return }
        var frame = NotchGeometry.panelFrame(on: screen)
        frame.origin = NSPoint(x: frame.minX, y: screen.frame.maxY - frame.height)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        viewModel.measuredLeftWingWidth = 0
        viewModel.measuredRightWingWidth = 0
        viewModel.geometryEpoch &+= 1
        panel.alphaValue = 1
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        startMouseTracking()
    }

    func stop() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func startMouseTracking() {
        stop()

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .rightMouseDown, self.hotZone().contains(NSEvent.mouseLocation) {
                self.showQuitMenu(with: event)
                return nil
            }
            self.syncHoverFromMouseLocation()
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return }
            if event.type == .rightMouseDown, self.hotZone().contains(NSEvent.mouseLocation) {
                self.showQuitMenu(with: event)
                return
            }
            self.syncHoverFromMouseLocation()
        }

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncHoverFromMouseLocation()
            }
        }
        if let hoverTimer {
            RunLoop.main.add(hoverTimer, forMode: .common)
        }
    }

    private func showQuitMenu(with event: NSEvent) {
        let menu = NSMenu()
        let quit = NSMenuItem(
            title: "Quit Cursor Notch Usage",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: hostingView)
    }

    private func syncHoverFromMouseLocation() {
        let location = NSEvent.mouseLocation
        viewModel.updateHover(isInside: hotZone().contains(location))
    }

    private func hotZone() -> NSRect {
        guard let screen = NotchGeometry.targetScreen else { return .zero }
        let notch = NotchGeometry.notchFrame(on: screen)
        let fallback = notch.width + IslandLayout.wingWidthFallback * 2
        let width = viewModel.measuredIslandWidth > 1
            ? viewModel.measuredIslandWidth
            : fallback
        var zone = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - notch.height,
            width: width,
            height: notch.height
        )
        zone = zone.insetBy(dx: -10, dy: 0)
        zone.origin.y -= 4
        zone.size.height += 4
        return zone
    }

    private func interactiveRectInPanelView() -> CGRect {
        NotchGeometry.viewRect(forScreenRect: hotZone(), panelFrame: panel.frame)
    }
}
