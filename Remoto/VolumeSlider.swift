import SwiftUI

/// A horizontal volume bar that sits above the function keys: a hairline of
/// glass at rest, growing into a full slider under the thumb — the same move
/// the iOS lock-screen scrubber makes.
///
/// Two decisions follow from where it lives. It is directly above four buttons
/// the thumb travels to constantly, so a *tap* never changes the volume; only a
/// drag does. And it stays expanded for a moment after release, so the level
/// you just set is legible instead of vanishing with your finger.
///
/// Interaction contract: the view owns the *visual* level while a drag is in
/// flight (no network round-trip per pixel) and reports the absolute level once
/// on release, plus optional live values through `onPreview`.
struct VolumeSlider: View {
    /// Last known device volume. While a drag is active this is ignored in
    /// favor of the local thumb position; on release it re-syncs.
    let level: Int
    let isMuted: Bool
    let maxLevel: Int
    /// Called at most once per gesture (on release) with the absolute level.
    let onCommit: (Int) -> Void
    /// Called on every level step while dragging, for live HUD-style feedback.
    let onPreview: (Int) -> Void

    @State private var dragLevel: Double?
    @State private var isExpanded = false
    /// Fires the collapse after a release. Held so the next touch can cancel it.
    @State private var collapseTask: Task<Void, Never>?
    /// The last level a tick was played for — the haptic marks steps, not frames.
    @State private var lastTickLevel: Int?

    /// Resting height: a hairline, not a control. Any thicker and the empty part
    /// of the track reads as an unfilled box waiting to be filled in — which at
    /// volume 0 is exactly what it looked like.
    private static let restingHeight: CGFloat = 4
    private static let expandedHeight: CGFloat = 38
    /// The touch target, which never changes size — the bar grows inside it, so
    /// expanding does not move the thing under the thumb.
    private static let touchHeight: CGFloat = 44
    /// How long the expanded bar lingers after the thumb leaves.
    private static let lingerAfterRelease: Duration = .milliseconds(900)
    /// Below this the gesture is a tap on the way to a button, not a scrub.
    private static let dragSlop: CGFloat = 4

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

    private var displayLevel: Int { absoluteLevel(displayFraction) }

    var body: some View {
        GeometryReader { proxy in
            bar(width: proxy.size.width)
                // Centred in the touch target, so growth is symmetric and the
                // bar's midline never shifts.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(.rect)
                .gesture(scrub(width: proxy.size.width))
        }
        .frame(height: Self.touchHeight)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(isMuted ? "Muted" : "\(level) of \(maxLevel)")
        .accessibilityAdjustableAction { direction in
            let step = max(1, maxLevel / 20)
            switch direction {
            case .increment: onCommit(min(maxLevel, level + step))
            case .decrement: onCommit(max(0, level - step))
            @unknown default: break
            }
        }
    }

    private func bar(width: CGFloat) -> some View {
        let height = isExpanded ? Self.expandedHeight : Self.restingHeight
        // The fill is inset inside the track only once there is room for an
        // inset to read as one; at 4pt it would just eat the bar.
        let inset: CGFloat = isExpanded ? 4 : 0
        let trackWidth = max(0, width - inset * 2)
        let fillHeight = height - inset * 2
        // Never narrower than its own end cap, or zero volume renders as a
        // sliver of a circle rather than a dot.
        let fillWidth = max(fillHeight, trackWidth * displayFraction)

        return ZStack(alignment: .leading) {
            // Two tracks, crossfaded rather than swapped, so neither pops in.
            // At rest the bar has to *recede*: glass over black lights up as a
            // pale slab, which at full width reads as an empty container — the
            // single ugliest thing on the screen at volume 0. So resting is a
            // plain dim rule, and the glass only arrives with the expansion,
            // where its thickness has something to say.
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
                .opacity(isExpanded ? 0 : 1)

            Capsule(style: .continuous)
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
                .opacity(isExpanded ? 1 : 0)

            // Opaque white, deliberately. A translucent fill lets the glass and
            // the wall behind it through, and the level stops being a solid
            // quantity you can read at a glance — it turns into fog. Mute dims
            // it to half rather than tinting it grey, for the same reason.
            Capsule(style: .continuous)
                .fill(Color.white.opacity(isMuted ? 0.4 : 1))
                .frame(width: fillWidth, height: fillHeight)
                .padding(inset)

            readout(fillWidth: fillWidth, inset: inset)
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.12), value: displayFraction)
        .animation(.smooth(duration: 0.22), value: isExpanded)
    }

    /// Speaker glyph and level, drawn only in the expanded bar — nothing legible
    /// fits in a 6pt rule, and fading them in is what makes the growth read as
    /// an unfolding rather than a resize.
    private func readout(fillWidth: CGFloat, inset: CGFloat) -> some View {
        // The glyph sits over the fill at most levels and over bare glass near
        // zero; it takes the contrasting colour for whichever it is standing on.
        let glyphTrailingEdge = inset + 14 + 18
        let isGlyphOverFill = fillWidth + inset >= glyphTrailingEdge

        return HStack(spacing: 0) {
            Image(systemName: speakerSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isGlyphOverFill ? Color.black.opacity(0.65) : Color.white.opacity(0.8))
            Spacer(minLength: 0)
            Text(isMuted ? "Muted" : "\(displayLevel)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .opacity(isExpanded ? 1 : 0)
        .allowsHitTesting(false)
    }

    private func scrub(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                expand()
                guard hasScrubbed(value) else { return }
                let fraction = clampedFraction(value.location.x / width)
                dragLevel = fraction
                let absolute = absoluteLevel(fraction)
                if absolute != lastTickLevel {
                    lastTickLevel = absolute
                    UISelectionFeedbackGenerator().selectionChanged()
                    onPreview(absolute)
                }
            }
            .onEnded { value in
                // A touch that never moved was aimed at something else, or was
                // asking to see the level; either way it must not set it.
                if hasScrubbed(value) {
                    let absolute = absoluteLevel(clampedFraction(value.location.x / width))
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onCommit(absolute)
                }
                dragLevel = nil
                lastTickLevel = nil
                scheduleCollapse()
            }
    }

    private func hasScrubbed(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) > Self.dragSlop
    }

    private func clampedFraction(_ raw: Double) -> Double {
        min(1, max(0, raw))
    }

    private func absoluteLevel(_ fraction: Double) -> Int {
        Int((fraction * Double(maxLevel)).rounded())
    }

    private func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        guard !isExpanded else { return }
        isExpanded = true
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: Self.lingerAfterRelease)
            guard !Task.isCancelled else { return }
            isExpanded = false
        }
    }

    private var speakerSymbol: String {
        if isMuted || displayFraction == 0 { return "speaker.slash.fill" }
        if displayFraction < 0.34 { return "speaker.fill" }
        if displayFraction < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }
}
