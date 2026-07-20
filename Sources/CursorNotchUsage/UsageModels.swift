import Foundation

struct CursorUsageSummary: Equatable, Sendable {
    var membership: String
    var totalPercentUsed: Double
    var autoPercentUsed: Double
    var apiPercentUsed: Double
    var includedSpendCents: Int
    var limitCents: Int
    var remainingCents: Int
    /// Compact time until billing cycle end ("12d", "4h1m").
    var cycleRemainingLabel: String
    var label: String
}

struct BridgeSnapshot: Equatable, Sendable {
    var usage: CursorUsageSummary?
}
