import SwiftUI
import TVRemoteKit

/// The persistent mode dock — one glass container pinned to the bottom of the
/// remote home that never leaves the screen. It *is* the tab bar: the four
/// items (Remote / Keyboard / Inputs / More) live inside it, and the active
/// mode's panel expands inline above them. Remote is the collapsed state —
/// just the strip.
///
/// Why not sheets: a sheet removes the mode bar from the screen, which traps
/// the user — the only way back to "Remote" is an implicit swipe, and the
/// strip disappears exactly when the eyes-on-TV loop (type → D-pad → type)
/// needs it as the stable anchor. Here the dock is the anchor: it never
/// moves, panels open and close *inside* it, and the glass morphs between
/// states via the shared namespace.
struct ModeDock: View {
    let model: RemoteViewModel
    let onSwitchTV: () -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case remote, keyboard, inputs, more
        var id: Self { self }
    }

    @Namespace private var dockNamespace
    @State private var mode: Mode = .remote
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            panel
            modeStrip
        }
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        // The dock floats above the remote (see RemoteHomeView), so its height is
        // bounded against the screen rather than against its siblings: a panel
        // taller than this scrolls internally instead of growing off-screen.
        .frame(maxHeight: 560)
        // Collapsing must return the space immediately. Sizing bottom-up means a
        // panel's removal shrinks the container in the same transaction as the
        // strip staying put, rather than leaving the old height behind.
        .fixedSize(horizontal: false, vertical: true)
        // Swipe down anywhere on the dock returns to Remote — the gesture
        // matches the sheet-dismissal habit without the sheet's trap.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard mode != .remote,
                          value.translation.height > 48,
                          abs(value.translation.height) > abs(value.translation.width) else { return }
                    select(.remote)
                }
        )
        .animation(reduceMotion ? .none : .smooth, value: mode)
        .onChange(of: model.supportsTextEntry) { _, canType in
            // Capabilities arrive a beat after the first paint; if typing turns
            // out to be unsupported, don't strand the user in a panel whose tab
            // just disappeared.
            if !canType, mode == .keyboard { mode = .remote }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Panels

    @ViewBuilder
    private var panel: some View {
        switch mode {
        case .remote:
            EmptyView()
        case .keyboard:
            KeyboardPanel(model: model)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .glassEffectID("panel", in: dockNamespace)
                .transition(panelTransition)
        case .inputs:
            InputsPanel(model: model)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .glassEffectID("panel", in: dockNamespace)
                .transition(panelTransition)
        case .more:
            MorePanel(model: model, onSwitchTV: {
                select(.remote)
                onSwitchTV()
            })
            .frame(maxHeight: 420)
            .padding(.top, 4)
            .glassEffectID("panel", in: dockNamespace)
            .transition(panelTransition)
        }
    }

    private var panelTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .bottom))
        )
    }

    // MARK: - Mode strip

    private var modeStrip: some View {
        HStack(spacing: 0) {
            stripItem(.remote, icon: "dpad", title: "Remote")
            // Typing needs the TV to support it at all — the SDK says so through
            // `textEntry`, so the entry disappears rather than leading the user
            // to a field whose every send would fail.
            if model.supportsTextEntry {
                stripItem(.keyboard, icon: "keyboard", title: "Keyboard")
            }
            stripItem(.inputs, icon: "cable.connector", title: "Inputs")
            stripItem(.more, icon: "square.grid.2x2", title: "More")
        }
    }

    private func stripItem(_ item: Mode, icon: String, title: String) -> some View {
        Button {
            select(item)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(mode == item ? Color.white : Color.secondary)
            .frame(width: 72, height: 52)
            .contentShape(Capsule())
            .background {
                if mode == item {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .matchedGeometryEffect(id: "dockSelection", in: dockNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(mode == item ? .isSelected : [])
        .accessibilityHint(item == .remote ? "Closes the panel" : "")
    }

    private func select(_ item: Mode) {
        guard mode != item else { return }
        KeyPressWeight.light.fire()
        mode = item
    }
}
