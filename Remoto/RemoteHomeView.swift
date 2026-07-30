import SwiftUI
import TVRemoteKit

/// The remote home screen — the app's destination, not a waypoint.
///
/// Layout (top to bottom): TV name + status, directional pad, function keys,
/// volume rocker, and the persistent `ModeDock` pinned to the bottom with
/// four entries: Remote, Keyboard, Inputs, More. The dock never leaves the
/// screen; panels expand inside it, so the mode strip is always the stable
/// anchor for the eyes-on-TV blind-operation loop.
///
/// Buttons render only when the connected TV reports them in
/// `supportedKeys`; a missing key disappears rather than greys out.
struct RemoteHomeView: View {
    let model: RemoteViewModel
    /// "Switch TV" — returns to the connection screen.
    let onSwitchTV: () -> Void

    init(model: RemoteViewModel, onSwitchTV: @escaping () -> Void = {}) {
        self.model = model
        self.onSwitchTV = onSwitchTV
    }

    /// Height the collapsed dock occupies (strip + its glass padding). The remote
    /// content reserves exactly this much so that opening a panel does not move
    /// anything above it.
    private static let collapsedDockHeight: CGFloat = 84

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(white: 0.05)
                .ignoresSafeArea()

            // The remote proper. Its layout is fixed: the dock is NOT a sibling
            // that competes for space, because an expanding panel would then
            // squeeze the D-pad — and the squeeze is what makes a blind-operated
            // remote unusable, since the buttons move under the thumb.
            VStack(spacing: 24) {
                header
                Spacer(minLength: 12)
                DirectionalPad(
                    onDirection: { model.press($0.key) },
                    onConfirm: { model.press(.confirm) }
                )
                .opacity(model.isConnected ? 1 : 0.35)
                .disabled(!model.isConnected)
                Spacer(minLength: 12)
                controlRow
            }
            .padding(.horizontal, 28)
            .padding(.bottom, Self.collapsedDockHeight + 12)
            // The software keyboard must not compress this either: when the
            // keyboard panel is open the dock rises above the keyboard and covers
            // the pad, which is expected — the pad shrinking is not.
            .ignoresSafeArea(.keyboard, edges: .bottom)

            ModeDock(model: model, onSwitchTV: onSwitchTV)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
        }
    }

    // MARK: - Header

    private var header: some View {
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
        .padding(.top, 16)
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
        GlassEffectContainer(spacing: 40) {
            HStack(alignment: .center, spacing: 40) {
                functionKeys
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
                    .frame(width: 64, height: 176)
                } else if model.supportsRelativeVolume {
                    volumeRocker
                }
            }
        }
        .opacity(model.isConnected ? 1 : 0.35)
        .disabled(!model.isConnected)
    }

    /// The fallback for a TV with no absolute-volume API: the two IRCC keys,
    /// stacked in the slider's footprint so the layout does not reflow.
    private var volumeRocker: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                GlassCircleKey(
                    systemImage: "plus",
                    accessibilityLabel: "Volume up"
                ) { model.press(.volumeUp) }
                GlassCircleKey(
                    systemImage: "minus",
                    accessibilityLabel: "Volume down"
                ) { model.press(.volumeDown) }
            }
        }
        .frame(width: 64, height: 176)
    }

    private var functionKeys: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                if model.supports(.back) {
                    GlassCircleKey(
                        systemImage: "arrow.uturn.left",
                        accessibilityLabel: "Back"
                    ) { model.press(.back) }
                }
                if model.supports(.home) {
                    GlassCircleKey(
                        systemImage: "house.fill",
                        accessibilityLabel: "Home"
                    ) { model.press(.home) }
                }
                if model.supports(.mute) {
                    GlassCircleKey(
                        systemImage: model.volume?.isMuted == true ? "speaker.slash.fill" : "speaker.fill",
                        accessibilityLabel: "Mute",
                        tint: model.volume?.isMuted == true ? .orange : nil
                    ) { model.press(.mute) }
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
