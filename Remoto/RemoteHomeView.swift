import SwiftUI
import TVRemoteKit

/// The remote home screen — the app's destination, not a waypoint.
///
/// Layout (top to bottom): TV name + status, directional pad, function keys,
/// volume rocker, floating glass mode bar. Buttons render only when the
/// connected TV reports them in `supportedKeys`; a missing key disappears
/// rather than greys out.
struct RemoteHomeView: View {
    let model: RemoteViewModel

    /// Which sheet the mode bar is hosting. Tab visuals, sheet behavior.
    private enum ActiveSheet: Identifiable {
        case keyboard, more
        var id: Self { self }
    }

    @Namespace private var modeBarNamespace
    @State private var activeSheet: ActiveSheet?
    @State private var debugHost: String = ""
    @State private var debugPSK: String = ""

    var body: some View {
        ZStack {
            Color(white: 0.05)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                Spacer()
                DirectionalPad(
                    onDirection: { model.press($0.key) },
                    onConfirm: { model.press(.confirm) }
                )
                .opacity(model.isConnected ? 1 : 0.35)
                .disabled(!model.isConnected)
                Spacer()
                controlRow
                modeBar
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .keyboard:
                Text("Keyboard arrives in Task 4")
                    .presentationDetents([.height(120)])
            case .more:
                Text("More keys arrive in Task 5")
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(headerTitle)
                    .font(.headline)
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

            // Bootstrap-only connect row, replaced by the discovery flow in Task 2.
            if !model.isConnected {
                HStack(spacing: 10) {
                    TextField("TV IP address", text: $debugHost)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(maxWidth: .infinity)
                    TextField("PSK", text: $debugPSK)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(width: 100)
                    Button("Connect") {
                        Task { await model.connect(host: debugHost, preSharedKey: debugPSK.isEmpty ? nil : debugPSK) }
                    }
                    .disabled(debugHost.isEmpty || debugPSK.isEmpty)
                }
                .padding(.horizontal, 24)
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

    // MARK: - Controls

    private var controlRow: some View {
        GlassEffectContainer(spacing: 40) {
            HStack(alignment: .center, spacing: 40) {
                functionKeys
                if model.supportsAbsoluteVolume {
                    VolumeSlider(
                        level: model.volume?.level ?? 0,
                        isMuted: model.volume?.isMuted ?? false,
                        maxLevel: model.volume?.maxLevel ?? 100,
                        onCommit: { model.setVolume($0) }
                    )
                    .frame(width: 64, height: 176)
                }
            }
        }
        .opacity(model.isConnected ? 1 : 0.35)
        .disabled(!model.isConnected)
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
                if model.supports(.powerToggle) {
                    GlassCircleKey(
                        systemImage: "power",
                        accessibilityLabel: "Power",
                        weight: .heavy,
                        tint: .red
                    ) { model.press(.powerToggle) }
                }
            }
        }
    }

    // MARK: - Mode bar

    private var modeBar: some View {
        HStack(spacing: 0) {
            modeBarItem(icon: "dpad", title: "Remote", selected: activeSheet == nil) {
                withAnimation(.smooth) { activeSheet = nil }
            }
            modeBarItem(icon: "keyboard", title: "Keyboard", selected: activeSheet == .keyboard) {
                withAnimation(.smooth) { activeSheet = .keyboard }
            }
            modeBarItem(icon: "square.grid.2x2", title: "More", selected: activeSheet == .more) {
                withAnimation(.smooth) { activeSheet = .more }
            }
        }
        .padding(6)
        .glassEffect(.regular, in: .capsule)
    }

    private func modeBarItem(
        icon: String,
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(width: 88, height: 56)
            .contentShape(Capsule())
            .background {
                if selected {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .matchedGeometryEffect(id: "modeBarSelection", in: modeBarNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
