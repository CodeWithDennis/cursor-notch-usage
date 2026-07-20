import Foundation
import SwiftUI

@MainActor
@Observable
final class IslandViewModel {
    var bridgeReady = false
    var usage: CursorUsageSummary?
    var isHovering = false
    /// Bumped when the island moves between screens so SwiftUI remeasures the notch.
    var geometryEpoch: UInt = 0
    /// Equal wings = max(left, right); keeps the notch gap centered.
    var measuredLeftWingWidth: CGFloat = 0
    var measuredRightWingWidth: CGFloat = 0
    /// Full island width for the hover hot-zone.
    var measuredIslandWidth: CGFloat = 0

    private let bridge = UsageBridgeClient()
    private var liveTask: Task<Void, Never>?
    private var backupPollTask: Task<Void, Never>?
    private var bridgeTask: Task<Void, Never>?

    func updateHover(isInside: Bool) {
        guard isInside != isHovering else { return }
        if isInside {
            withAnimation(IslandLayout.expandAnimation) {
                isHovering = true
            }
        } else {
            withAnimation(IslandLayout.collapseAnimation) {
                isHovering = false
            }
        }
    }

    func startBridgeIfNeeded() {
        bridgeTask?.cancel()
        bridgeTask = Task {
            var delayNanoseconds: UInt64 = 500_000_000
            while !Task.isCancelled {
                do {
                    try await bridge.ensureRunning()
                    bridgeReady = true
                    await refreshUsage()
                    startLiveUpdates()
                    return
                } catch {
                    bridgeReady = false
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                    delayNanoseconds = min(delayNanoseconds * 2, 8_000_000_000)
                }
            }
        }
    }

    func stopBridge() {
        liveTask?.cancel()
        backupPollTask?.cancel()
        bridgeTask?.cancel()
        liveTask = nil
        backupPollTask = nil
        bridgeTask = nil
        Task { await bridge.stop() }
    }

    private func applySnapshot(_ snapshot: BridgeSnapshot) {
        guard snapshot.usage != usage else { return }
        usage = snapshot.usage
    }

    private func refreshUsage() async {
        do {
            applySnapshot(try await bridge.listSnapshot())
        } catch {
            // Keep last good snapshot on transient failures.
        }
    }

    private func startLiveUpdates() {
        liveTask?.cancel()
        backupPollTask?.cancel()

        liveTask = Task {
            do {
                for try await snapshot in await bridge.streamSnapshots() {
                    if Task.isCancelled { break }
                    applySnapshot(snapshot)
                }
            } catch {
                // Stream retries internally.
            }
        }

        backupPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }

                do {
                    try await bridge.ensureRunning()
                    if !bridgeReady {
                        bridgeReady = true
                        startLiveUpdates()
                        break
                    }
                    bridgeReady = true
                    await refreshUsage()
                } catch {
                    bridgeReady = false
                }
            }
        }
    }
}
