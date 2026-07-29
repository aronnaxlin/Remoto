import SwiftUI

/// A Control Center–style vertical volume slider: one thick glass column,
/// filled from the bottom to the current level. Drag anywhere on the column
/// to set; the speaker glyph sits at the foot and flips with mute.
///
/// Interaction contract: the view owns the *visual* level while a drag is in
/// flight (no network round-trip per pixel), and reports absolute levels via
/// `onChange` throttled to a trailing edge — see `VolumeSliderModel`.
struct VolumeSlider: View {
    /// Last known device volume. While a drag is active this is ignored in
    /// favor of the local thumb position; on drag end it re-syncs.
    let level: Int
    let isMuted: Bool
    let maxLevel: Int
    /// Called at most once per gesture (on release) with the absolute level.
    let onCommit: (Int) -> Void
    /// Called on every frame while dragging, for live HUD-style feedback.
    let onPreview: (Int) -> Void

    @State private var dragLevel: Double?
    @GestureState private var isDragging = false

    init(
        level: Int,
        isMuted: Bool,
        maxLevel: Int = 100,
        onCommit: @escaping (Int) -> Void,
        onPreview: @escaping (Int) -> Void = { _ in }
    ) {
        self.level = level
        self.isMuted = isMuted
        self.maxLevel = max(1, maxLevel)
        self.onCommit = onCommit
        self.onPreview = onPreview
    }

    private var displayFraction: Double {
        if let dragLevel { return dragLevel }
        return Double(level) / Double(maxLevel)
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let width = proxy.size.width
            let fillHeight = height * displayFraction

            ZStack(alignment: .bottom) {
                // Track: the glass column itself.
                RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: width / 2))

                // Fill: bright lobe rising from the foot.
                RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                    .fill(isMuted ? Color.gray.opacity(0.5) : Color.white.opacity(0.85))
                    .frame(height: max(fillHeight, width)) // keep the foot cap round at zero
                    .padding(4)
                    .animation(.smooth(duration: 0.15), value: displayFraction)

                // Foot glyph.
                Image(systemName: speakerSymbol)
                    .font(.system(size: width * 0.34, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.7))
                    .frame(width: width, height: width)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: width / 2, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        let fraction = 1 - (value.location.y / height)
                        let clamped = min(1, max(0, fraction))
                        dragLevel = clamped
                        onPreview(Int((clamped * Double(maxLevel)).rounded()))
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    .onEnded { value in
                        let fraction = 1 - (value.location.y / height)
                        let clamped = min(1, max(0, fraction))
                        let absolute = Int((clamped * Double(maxLevel)).rounded())
                        dragLevel = nil
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onCommit(absolute)
                    }
            )
            .opacity(isDragging ? 1.0 : 0.92)
            .scaleEffect(isDragging ? 1.04 : 1.0)
            .animation(.smooth(duration: 0.18), value: isDragging)
        }
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(level) of \(maxLevel)")
        .accessibilityAdjustableAction { direction in
            let step = max(1, maxLevel / 20)
            switch direction {
            case .increment: onCommit(min(maxLevel, level + step))
            case .decrement: onCommit(max(0, level - step))
            @unknown default: break
            }
        }
    }

    private var speakerSymbol: String {
        if isMuted || displayFraction == 0 { return "speaker.slash.fill" }
        if displayFraction < 0.34 { return "speaker.fill" }
        if displayFraction < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
}
