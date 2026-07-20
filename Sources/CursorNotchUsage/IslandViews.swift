import SwiftUI

enum IslandLayout {
    /// Match the compact/hidden radii from the agent island.
    static let topCornerRadius: CGFloat = 6
    static let bottomCornerRadius: CGFloat = 14
    /// Visible gap from content → outer mask edge (after the shoulder).
    static let contentPad: CGFloat = 10
    /// Small gap between wing content and the camera cutout.
    static let innerPad: CGFloat = 8
    /// Fallback before the first layout pass.
    static let wingWidthFallback: CGFloat = 72

    static func outerInset(cornerRadius: CGFloat = topCornerRadius) -> CGFloat {
        cornerRadius + contentPad
    }

    /// Expand: snappy spring. Collapse: softer ease so text can fade first.
    static let expandAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let collapseAnimation = Animation.easeOut(duration: 0.36)
}

private struct WingWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct IslandRootView: View {
    @Bindable var viewModel: IslandViewModel

    private var notchSize: CGSize {
        _ = viewModel.geometryEpoch
        return NotchGeometry.notchSize
    }

    /// Equal wings keep the camera cutout locked to the hardware notch center.
    private var wingWidth: CGFloat {
        let measured = max(viewModel.measuredLeftWingWidth, viewModel.measuredRightWingWidth)
        return measured > 1 ? measured : IslandLayout.wingWidthFallback
    }

    private var islandWidth: CGFloat {
        notchSize.width + wingWidth * 2
    }

    /// Exact hardware notch height — no extra pad below the camera strip.
    private var islandHeight: CGFloat {
        notchSize.height
    }

    private var outerInset: CGFloat {
        IslandLayout.outerInset()
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.25), value: viewModel.usage?.label)
        .animation(
            viewModel.isHovering ? IslandLayout.expandAnimation : IslandLayout.collapseAnimation,
            value: viewModel.isHovering
        )
        .animation(
            viewModel.isHovering ? IslandLayout.expandAnimation : IslandLayout.collapseAnimation,
            value: wingWidth
        )
        .onChange(of: islandWidth) { _, width in
            viewModel.measuredIslandWidth = width
        }
        .onAppear {
            viewModel.measuredIslandWidth = islandWidth
        }
    }

    private var island: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.black)
                .frame(width: islandWidth, height: islandHeight)

            usageBody
                .frame(width: islandWidth, height: islandHeight, alignment: .top)
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .top)
        .background {
            Rectangle()
                .fill(.black)
                .padding(-50)
        }
        .mask {
            NotchShape(
                topCornerRadius: IslandLayout.topCornerRadius,
                bottomCornerRadius: IslandLayout.bottomCornerRadius
            )
            .padding(.horizontal, 0.5)
            .frame(width: islandWidth, height: islandHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: islandWidth, height: islandHeight)
        .frame(maxWidth: .infinity, alignment: .top)
        .compositingGroup()
        .opacity(viewModel.usage == nil ? 0.72 : 1)
        .contextMenu {
            Button("Quit Cursor Notch Usage") {
                NSApp.terminate(nil)
            }
        }
    }

    private var usageBody: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: wingWidth, height: islandHeight, alignment: .leading)

            // Always exactly notch-wide and centered between equal wings.
            Color.clear
                .frame(width: notchSize.width, height: islandHeight)

            rightWing
                .frame(width: wingWidth, height: islandHeight, alignment: .trailing)
        }
        .frame(width: islandWidth, height: islandHeight)
    }

    @ViewBuilder
    private var leftWing: some View {
        HStack(spacing: 6) {
            if viewModel.isHovering, let usage = viewModel.usage {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text("✦")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(sparkleColor(for: usage))
                        Text(planName(for: usage))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    Text("|")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.16))
                }
                .transition(.opacity)
            }

            usageBucket(title: "Auto", percent: viewModel.usage?.autoPercentUsed)
        }
        .padding(.leading, outerInset)
        .padding(.trailing, IslandLayout.innerPad)
        .fixedSize(horizontal: true, vertical: false)
        .background(wingWidthReader)
        .onPreferenceChange(WingWidthKey.self) { width in
            updateWingWidth(\.measuredLeftWingWidth, width)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rightWing: some View {
        HStack(spacing: 6) {
            usageBucket(title: "API", percent: viewModel.usage?.apiPercentUsed)

            if viewModel.isHovering, let usage = viewModel.usage, !secondaryMeta(for: usage).isEmpty {
                Text(secondaryMeta(for: usage))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
                    .monospacedDigit()
                    .transition(.opacity)
            }
        }
        .padding(.leading, IslandLayout.innerPad)
        .padding(.trailing, outerInset)
        .fixedSize(horizontal: true, vertical: false)
        .background(wingWidthReader)
        .onPreferenceChange(WingWidthKey.self) { width in
            updateWingWidth(\.measuredRightWingWidth, width)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private var wingWidthReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: WingWidthKey.self, value: proxy.size.width)
        }
    }

    private func updateWingWidth(
        _ keyPath: ReferenceWritableKeyPath<IslandViewModel, CGFloat>,
        _ width: CGFloat
    ) {
        guard width > 1, abs(width - viewModel[keyPath: keyPath]) > 0.5 else { return }
        viewModel[keyPath: keyPath] = width
    }

    private func usageBucket(title: String, percent: Double?) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            if let percent {
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(percentColor(percent))
                    .monospacedDigit()
            } else {
                Text("—%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
    }

    private func planName(for usage: CursorUsageSummary) -> String {
        let raw = usage.membership.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "Cursor" }
        return raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
    }

    private func secondaryMeta(for usage: CursorUsageSummary) -> String {
        if !usage.cycleRemainingLabel.isEmpty { return usage.cycleRemainingLabel }
        if usage.remainingCents > 0 {
            let dollars = Double(usage.remainingCents) / 100
            if dollars >= 100 { return "$\(Int(dollars))" }
            return String(format: "$%.0f", dollars)
        }
        return ""
    }

    private func sparkleColor(for usage: CursorUsageSummary) -> Color {
        let pct = max(usage.autoPercentUsed, usage.apiPercentUsed, usage.totalPercentUsed)
        if pct >= 90 { return Color(red: 0.95, green: 0.45, blue: 0.4) }
        if pct >= 70 { return Color(red: 0.95, green: 0.72, blue: 0.38) }
        return Color(red: 0.92, green: 0.62, blue: 0.38)
    }

    private func percentColor(_ percent: Double) -> Color {
        if percent >= 90 { return Color(red: 0.95, green: 0.45, blue: 0.4) }
        if percent >= 70 { return Color(red: 0.95, green: 0.75, blue: 0.35) }
        return Color(red: 0.45, green: 0.9, blue: 0.55)
    }
}
