import Combine
import SwiftUI
import TVRemoteKit

/// The remote home screen — the app's destination, not a waypoint.
///
/// Layout (top to bottom): TV name + status, directional pad, the volume bar,
/// the function keys it spans, and `ModeTabBar` pinned to the bottom with four
/// entries: Remote, Keyboard, Inputs, More.
///
/// Three layers, deliberately independent, because each has a different answer to
/// "what happens when something grows":
///   1. the remote itself — fixed; never squeezed by a panel or the keyboard,
///      because buttons that move under the thumb defeat blind operation;
///   2. `ModeTabBar` — pinned to the physical bottom, ignores the keyboard, so
///      the keyboard covers it like it covers a UITabBar;
///   3. `ModePanel` — the only layer that respects the keyboard, so the text
///      field rises with it and everything else stays where it was.
///
/// Buttons render only when the connected TV reports them in
/// `supportedKeys`; a missing key disappears rather than greys out.
struct RemoteHomeView: View {
    let model: RemoteViewModel
    /// "Switch TV" — returns to the connection screen.
    let onSwitchTV: () -> Void

    /// Which dock mode is open. Held here because the remote itself has to react
    /// to it: while typing, half of these controls sit behind the system keyboard.
    @State private var dockMode: DockMode = .remote
    /// Focus lives here so that leaving the keyboard tab — by any route — releases
    /// the system keyboard, and so the remote can react to it really being up
    /// rather than merely inferring it from the selected tab.
    @FocusState private var isTypingNow: Bool
    /// How much of the screen the software keyboard covers, straight from the
    /// keyboard notifications.
    ///
    /// Needed because the whole screen opts out of keyboard safe-area avoidance
    /// below. `.ignoresSafeArea(.keyboard)` on a *child* is not enough: the
    /// container is what gets inset, so a bottom-aligned child still rides up with
    /// it. Opting the container out pins everything — and then the one layer that
    /// should move is lifted by hand.
    @State private var keyboardOverlap: CGFloat = 0
    /// Width of the control cluster, measured so the volume bar can be inset to
    /// the key row's own edges. See `keyEdgeInset`.
    @State private var controlWidth: CGFloat = 0

    init(model: RemoteViewModel, onSwitchTV: @escaping () -> Void = {}) {
        self.model = model
        self.onSwitchTV = onSwitchTV
    }

    /// "The keyboard is covering the remote" — true only while a field really has
    /// focus, so dismissing the keyboard without leaving the tab restores the
    /// remote immediately.
    private var isTyping: Bool { dockMode == .keyboard && isTypingNow }

    /// The remote reserves exactly the tab bar's height, so opening a panel — which
    /// floats above the bar — never moves anything up here.
    private static var collapsedDockHeight: CGFloat { ModeTabBar.barHeight }

    /// How far the tab bar floats above the bottom safe area.
    private static let barLift: CGFloat = 12

    /// Visible air between the round keys and the tab bar — counted from the
    /// bar's *top edge*, which is why `barLift` is in the sum below; leaving it
    /// out is what put the two rows flush against each other.
    ///
    /// Generous on purpose: two Liquid Glass surfaces this close stop reading as
    /// two pieces — the keys' rims and the bar's capsule bleed into one another
    /// and the row looks welded onto the dock. Glass has to be given room.
    private static let dockClearance: CGFloat = 34

    var body: some View {
        GeometryReader { proxy in
            layers(safeAreaBottom: proxy.safeAreaInsets.bottom)
        }
        // Nothing in the hierarchy is repositioned by the keyboard; `ModePanel`
        // opts back in explicitly, by height.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(Self.keyboardOverlapPublisher) { overlap in
            withAnimation(.smooth(duration: 0.28)) { keyboardOverlap = overlap }
        }
    }

    /// Emits the keyboard's on-screen height: its frame height while showing, zero
    /// while hiding.
    /// A single shared instance, not a computed one: `onReceive` re-subscribes
    /// whenever the publisher it is handed changes identity, which for a computed
    /// property is every redraw.
    private static let keyboardOverlapPublisher: AnyPublisher<CGFloat, Never> = {
        let center = NotificationCenter.default
        let show = center.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { note -> CGFloat in
                let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                return frame?.height ?? 0
            }
        let hide = center.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat.zero }
        return show.merge(with: hide).eraseToAnyPublisher()
    }()

    private func layers(safeAreaBottom: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Color(white: 0.05)
                .ignoresSafeArea()

            // The remote proper. Its layout is fixed: the dock is NOT a sibling
            // that competes for space, because an expanding panel would then
            // squeeze the D-pad — and the squeeze is what makes a blind-operated
            // remote unusable, since the buttons move under the thumb.
            // One spacer, not two. Two split the screen's slack into a pair of
            // equal voids — one above the pad, one below it — which left the pad
            // floating mid-screen between two chasms and the controls stranded
            // at the bottom: three islands, no instrument. With a single spacer
            // the pad, the volume bar and the keys stay welded together at a
            // fixed rhythm and sit low, where the hand is; all the slack
            // collects in one deliberate field under the title.
            VStack(spacing: 0) {
                header
                Spacer(minLength: 24)
                DirectionalPad(
                    onDirection: { model.press($0.key) },
                    onConfirm: { model.press(.confirm) }
                )
                .opacity(model.isConnected ? 1 : 0.35)
                .disabled(!model.isConnected)
                controlRow
                    .padding(.top, 28)
                    // The volume bar and function keys are the first things the
                    // keyboard swallows; hiding them beats showing half a control.
                    .opacity(isTyping ? 0 : 1)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, Self.collapsedDockHeight + Self.barLift + Self.dockClearance)
            // The software keyboard must not compress this either: when the
            // keyboard panel is open the dock rises above the keyboard and covers
            // the pad, which is expected — the pad shrinking is not.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // While typing, the remote recedes rather than sitting half-cut behind
            // the keyboard: it is visibly still there, but it is not the subject.
            .opacity(isTyping ? 0.12 : 1)
            .allowsHitTesting(!isTyping)
            .animation(.smooth, value: isTyping)

            // Tapping the receded remote puts the keyboard away — the habit every
            // other iOS text field trains, and the reason a "Done" button is not
            // needed on the panel.
            if isTyping {
                Color.clear
                    .contentShape(.rect)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .onTapGesture { dockMode = .remote }
                    .accessibilityLabel("Close keyboard")
                    .accessibilityAddTraits(.isButton)
            }

            // The bar stays at the physical bottom, always. The keyboard covers
            // it; it never moves out of the keyboard's way.
            ModeTabBar(model: model, mode: $dockMode)
                .padding(.horizontal, 28)
                .padding(.bottom, Self.barLift)
        }
        // The panel is the one layer that rides the keyboard, lifted by the
        // measured height so the bar underneath can stay put and be covered.
        .overlay(alignment: .bottom) {
            ModePanel(
                model: model,
                mode: $dockMode,
                isTyping: $isTypingNow,
                onSwitchTV: onSwitchTV
            )
            .padding(.horizontal, 28)
            // Above the bar when the keyboard is down; just above the keyboard
            // when it is up, since the bar is behind it at that point.
            .padding(.bottom, panelLift(safeAreaBottom: safeAreaBottom))
            .animation(.smooth, value: isTyping)
        }
        .onChange(of: dockMode) { _, newMode in
            // Entering the tab raises the keyboard; leaving it by any route — a
            // tab tap, the swipe, "Switch TV" — puts it away.
            isTypingNow = newMode == .keyboard
        }
        .onChange(of: model.supportsTextEntry) { _, canType in
            // Capabilities arrive a beat after the first paint; if typing turns out
            // to be unsupported, don't strand the user in a panel whose tab just
            // disappeared.
            if !canType, dockMode == .keyboard { dockMode = .remote }
        }
    }

    /// Where the panel's bottom edge sits. Above the bar with the keyboard down;
    /// just above the keyboard when it is up — the bar is behind it by then, so
    /// there is nothing to clear but the keyboard itself.
    private func panelLift(safeAreaBottom: CGFloat) -> CGFloat {
        guard keyboardOverlap > 0 else { return Self.collapsedDockHeight + 22 }
        // The layer's bottom already sits `safeAreaBottom` above the screen edge,
        // so only the remainder of the keyboard has to be cleared.
        return max(12, keyboardOverlap - safeAreaBottom + 12)
    }

    // MARK: - Header

    private var header: some View {
        titleBlock
            // Overlaid rather than placed in a row: the title stays centred on
            // the screen, not on whatever is left of it.
            .overlay(alignment: .topLeading) { devicesButton }
            .padding(.top, 16)
    }

    /// The way to the device list, at the top-left corner where a screen's
    /// "where am I / take me elsewhere" control belongs. It used to live behind
    /// More → Switch TV, which is two taps and a guess for the one thing a
    /// multi-device household does most.
    private var devicesButton: some View {
        Button {
            KeyPressWeight.medium.fire()
            onSwitchTV()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Devices")
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(headerTitle)
                    .font(.headline)
                if let power = model.power, power != .on {
                    Text(powerLabel(power))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.1), in: .capsule)
                }
            }
            .foregroundStyle(.primary)

            if let error = model.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else if let volume = model.volume {
                Text(volume.isMuted ? "Muted" : "Volume \(volume.level)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        // Clear of the device button on the left, and by the same amount on the
        // right so a long device name stays optically centred rather than
        // shunted sideways.
        .padding(.horizontal, 50)
    }

    private var headerTitle: String {
        switch model.connectionState {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return model.deviceName
        case .failed(let reason): return reason
        }
    }

    private var statusColor: Color {
        switch model.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected, .failed: return .gray
        }
    }

    private func powerLabel(_ power: PowerState) -> String {
        switch power {
        case .on: return "On"
        case .standby: return "Standby"
        case .off: return "Off"
        case .unknown(let raw): return raw.capitalized
        }
    }

    // MARK: - Controls

    private var controlRow: some View {
        // Tight: the bar and the keys are one cluster, and the bar already
        // carries ~20pt of dead touch target on each side of its hairline.
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 8) {
                // Absolute and relative volume are different SDK features, and a
                // set can have only the second. Falling through to a rocker keeps
                // volume reachable instead of leaving the screen with no way to
                // change it at all.
                if model.supportsAbsoluteVolume {
                    VolumeSlider(
                        level: model.volume?.level ?? 0,
                        isMuted: model.volume?.isMuted ?? false,
                        maxLevel: model.volume?.maxLevel ?? 100,
                        onCommit: { model.setVolume($0) }
                    )
                    // Ends flush with the outer keys. Full-bleed it overhung the
                    // row by half a column and stopped reading as part of the
                    // cluster — it looked like a divider ruled across the screen.
                    .padding(.horizontal, keyEdgeInset)
                } else if model.supportsRelativeVolume {
                    volumeRocker
                        .padding(.horizontal, keyEdgeInset)
                }
                functionKeys
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { controlWidth = $0 }
        .opacity(model.isConnected ? 1 : 0.35)
        .disabled(!model.isConnected)
    }

    /// How far a key's edge sits from the edge of its column — the amount the
    /// volume bar has to give up on each side to end where the outer keys do.
    ///
    /// Derived rather than hard-coded, because the row's key count is whatever
    /// the TV reports: a set without a power key lays out three wider columns,
    /// and a fixed inset would then be visibly wrong.
    private var keyEdgeInset: CGFloat {
        guard controlWidth > 0, visibleKeyCount > 0 else { return 0 }
        let column = controlWidth / CGFloat(visibleKeyCount)
        return max(0, (column - GlassCircleKey.diameter) / 2)
    }

    private var visibleKeyCount: Int {
        var count = 0
        if model.supports(.back) { count += 1 }
        if model.supports(.home) { count += 1 }
        if model.supports(.mute) { count += 1 }
        if model.supportsPowerControl || model.supports(.powerToggle) { count += 1 }
        return count
    }

    /// The fallback for a TV with no absolute-volume API: the two IRCC keys,
    /// side by side in the bar's footprint so the layout does not reflow.
    private var volumeRocker: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                GlassRectKey(
                    systemImage: "minus",
                    accessibilityLabel: "Volume down",
                    height: 48
                ) { model.press(.volumeDown) }
                GlassRectKey(
                    systemImage: "plus",
                    accessibilityLabel: "Volume up",
                    height: 48
                ) { model.press(.volumeUp) }
            }
        }
    }

    /// The four round keys, each centred in an equal column rather than packed
    /// at a fixed spacing. Keys come and go with `supportedKeys`, so a fixed
    /// spacing gives the row a different width on every TV — and then the volume
    /// bar above it and the tab bar below it line up with neither. Equal columns
    /// pin all three to the same edges no matter how many keys survive.
    private var functionKeys: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 0) {
                if model.supports(.back) {
                    GlassCircleKey(
                        systemImage: "arrow.uturn.left",
                        accessibilityLabel: "Back"
                    ) { model.press(.back) }
                    .frame(maxWidth: .infinity)
                }
                if model.supports(.home) {
                    GlassCircleKey(
                        systemImage: "house.fill",
                        accessibilityLabel: "Home"
                    ) { model.press(.home) }
                    .frame(maxWidth: .infinity)
                }
                if model.supports(.mute) {
                    GlassCircleKey(
                        systemImage: model.volume?.isMuted == true ? "speaker.slash.fill" : "speaker.fill",
                        accessibilityLabel: "Mute",
                        tint: model.volume?.isMuted == true ? .orange : nil
                    ) { model.press(.mute) }
                    .frame(maxWidth: .infinity)
                }
                // Power goes through the SDK's setPower when the TV advertises
                // it: that path tries every wake route, where the IRCC key alone
                // is the one a deeply-asleep set is most likely to ignore.
                if model.supportsPowerControl || model.supports(.powerToggle) {
                    GlassCircleKey(
                        systemImage: "power",
                        accessibilityLabel: model.power == .on ? "Turn TV off" : "Turn TV on",
                        weight: .heavy,
                        tint: .red
                    ) { model.togglePower() }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private extension RemoteDirection {
    var key: RemoteKey {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        }
    }
}

#Preview {
    RemoteHomeView(model: RemoteViewModel())
        .preferredColorScheme(.dark)
}
