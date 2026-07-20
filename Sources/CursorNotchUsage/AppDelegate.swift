import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandController: IslandPanelController?
    private let viewModel = IslandViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        islandController = IslandPanelController(viewModel: viewModel)
        islandController?.show()
        viewModel.startBridgeIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        islandController?.stop()
        viewModel.stopBridge()
    }

    @objc private func screensChanged() {
        // Prefer a notched display when available (even if it is not the menu-bar screen).
        islandController?.show()
    }
}
