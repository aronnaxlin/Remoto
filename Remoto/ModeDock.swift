import SwiftUI
import TVRemoteKit

/// Which mode the dock is in. Owned by `RemoteHomeView`, because the bar and the
/// panel are two independently-positioned layers and the remote content itself
/// reacts to the keyboard mode.
enum DockMode: String, CaseIterable, Identifiable {
    case remote, keyboard, inputs, more
    var id: Self { self }
}

/// The mode bar — four items, pinned to the bottom of the screen, fixed height.
///
/// It *is* the tab bar, and it behaves like a standard one: it never resizes with
/// its content and never moves. Two things used to move it. It shared one glass
/// container with the open panel, so every menu switch dragged the four items
/// along with the panel's resize; and it respected the keyboard's safe area, so
/// raising the software keyboard lifted the whole bar. Now the panel is a
/// separate layer (`ModePanel`) and the bar ignores the keyboard, letting the
/// keyboard cover it the way it covers a `UITabBar`.
///
/// Why not sheets, for the panels: a sheet removes the bar from the screen, which
/// traps the user — the only way back to "Remote" is an implicit swipe, and the
/// bar disappears exactly when the eyes-on-TV loop (type → D-pad → type) needs it
/// as the stable anchor.
struct ModeTabBar: View {
    let model: RemoteViewModel
    @Binding var mode: DockMode

    /// Fixed on purpose: a tab bar that resizes is not a landmark.
    static let stripHeight: CGFloat = 52
    private static let barPadding: CGFloat = 8
    static var barHeight: CGFloat { stripHeight + barPadding * 2 }

    @Namespace private var barNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            item(.remote, icon: "dpad", title: "Remote")
            // Typing needs the TV to support it at all — the SDK says so through
            // `textEntry`, so the entry disappears rather than leading the user to
            // a field whose every send would fail.
            if model.supportsTextEntry {
                item(.keyboard, icon: "keyboard", title: "Keyboard")
            }
            item(.inputs, icon: "cable.connector", title: "Inputs")
            item(.more, icon: "square.grid.2x2", title: "More")
        }
        .frame(height: Self.stripHeight)
        .padding(Self.barPadding)
        .glassEffect(.regular, in: .capsule)
        // The only thing that animates here is the selection pill.
        .animation(reduceMotion ? .none : .snappy(duration: 0.28), value: mode)
        .accessibilityElement(children: .contain)
    }

    private func item(_ item: DockMode, icon: String, title: String) -> some View {
        Button {
            guard mode != item else { return }
            KeyPressWeight.light.fire()
            mode = item
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(mode == item ? Color.white : Color.secondary)
            .frame(width: 72)
            .frame(maxHeight: .infinity)
            .contentShape(Capsule())
            .background {
                if mode == item {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .matchedGeometryEffect(id: "dockSelection", in: barNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(mode == item ? .isSelected : [])
        .accessibilityHint(item == .remote ? "Closes the panel" : "")
    }
}

/// The open panel, in its own glass surface above the bar.
///
/// Positioned by `RemoteHomeView` in a layer that *does* respect the keyboard, so
/// the field rises with it while the bar underneath stays put and gets covered.
struct ModePanel: View {
    let model: RemoteViewModel
    @Binding var mode: DockMode
    /// Owned by the parent so that leaving the tab can release the keyboard even
    /// as this view is being torn down — a panel that owns its own focus can only
    /// take it, never give it back on the way out.
    @FocusState.Binding var isTyping: Bool
    let onSwitchTV: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if mode != .remote {
                content
                    .padding(8)
                    .glassEffect(.regular, in: .rect(cornerRadius: 28))
                    // Taller than this and the panel scrolls internally rather
                    // than growing off the top of the screen.
                    .frame(maxHeight: 470)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(panelTransition)
                    // Swipe down to return to Remote — the sheet-dismissal habit
                    // without the sheet's trap. Deliberately not on the bar, so a
                    // mis-swipe there cannot close anything.
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                guard value.translation.height > 48,
                                      abs(value.translation.height) > abs(value.translation.width)
                                else { return }
                                mode = .remote
                            }
                    )
            }
        }
        .animation(reduceMotion ? .none : .smooth, value: mode)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .remote:
            EmptyView()
        case .keyboard:
            KeyboardPanel(model: model, isTyping: $isTyping)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        case .inputs:
            InputsPanel(model: model)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        case .more:
            MorePanel(model: model, onSwitchTV: {
                mode = .remote
                onSwitchTV()
            })
        }
    }

    private var panelTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .bottom))
        )
    }
}
