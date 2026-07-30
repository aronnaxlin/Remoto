import SwiftUI
import TVRemoteKit

/// Input/source switching (信号源), hosted inline in `ModeDock`.
///
/// The SDK enumerates sources — `session.inputs()` returns each with an opaque
/// id, a kind, a port number and whether anything is plugged in — so this panel
/// lists them and switches directly. Which one is live comes from now-playing's
/// URI, which is where the SDK carries it; there is deliberately no second query
/// to disagree with.
///
/// A TV that lists nothing, or that cannot be switched over the network, falls
/// back to its own on-screen input menu via the `input` key, driven by the D-pad
/// that never moved. Channel keys ride along here because they belong to live-TV
/// sources.
struct InputsPanel: View {
    let model: RemoteViewModel

    var body: some View {
        VStack(spacing: 14) {
            if model.supportsInputList {
                inputList
            }

            if !model.supportsInputSelect, model.supports(.input) {
                openTVMenuRow
            }

            if model.supports(.channelUp) || model.supports(.channelDown) {
                channelRow
            }

            if !model.supportsInputList,
               !model.supports(.input),
               !model.supports(.channelUp),
               !model.supports(.channelDown) {
                Text("This TV reports no input or channel controls.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
        .task { await model.refreshInputs() }
    }

    // MARK: - Source list

    @ViewBuilder
    private var inputList: some View {
        if model.inputs.isEmpty {
            HStack(spacing: 10) {
                if model.isLoadingInputs {
                    ProgressView().controlSize(.small)
                    Text("Reading inputs…")
                } else {
                    Text("This TV reports no external inputs.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.inputs) { input in
                        inputRow(input)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 300)
        }
    }

    private func inputRow(_ input: InputSource) -> some View {
        let isCurrent = input.id == model.currentInputID
        // "Nothing plugged in" is worth showing but never worth blocking on: the
        // SDK reports `nil` for "the TV didn't say", which is not the same as
        // "empty", and a set can be selectable while reporting no connection.
        let isEmpty = input.isConnected == false

        return Button {
            guard model.supportsInputSelect else { return }
            KeyPressWeight.medium.fire()
            model.selectInput(input)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon(for: input.kind))
                    .font(.title3)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label(for: input))
                        .font(.headline)
                        .lineLimit(1)
                    if isEmpty {
                        Text("Nothing connected")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
            }
            .foregroundStyle(isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .glassEffect(
            isCurrent
                ? .regular.interactive().tint(.blue.opacity(0.35))
                : .regular.interactive(),
            in: .rect(cornerRadius: 18)
        )
        .disabled(!model.supportsInputSelect)
        .accessibilityLabel(label(for: input))
        .accessibilityValue(isCurrent ? "Current source" : (isEmpty ? "Nothing connected" : ""))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    /// The device's own name when it gave one — including a name its owner set
    /// on the TV — and a kind-derived fallback when it did not. The app never
    /// parses the name: the SDK warns it is a localised display string.
    private func label(for input: InputSource) -> String {
        if let title = input.title, !title.isEmpty { return title }
        let base = kindName(input.kind)
        return input.port.map { "\(base) \($0)" } ?? base
    }

    private func kindName(_ kind: InputKind) -> String {
        switch kind {
        case .hdmi: "HDMI"
        case .composite: "Composite"
        case .component: "Component"
        case .scart: "SCART"
        case .vga: "VGA"
        case .usb: "USB"
        case .tuner: "TV"
        case .screenMirroring: "Screen mirroring"
        default: "Input"
        }
    }

    /// Icons come from the SDK's generic `InputKind`, never from a URI or a
    /// brand's own icon field.
    private func icon(for kind: InputKind) -> String {
        switch kind {
        case .hdmi: "cable.connector"
        case .composite, .component, .scart: "cable.connector"
        case .vga: "display"
        case .usb: "cable.connector.horizontal"
        case .tuner: "antenna.radiowaves.left.and.right"
        case .screenMirroring: "airplayvideo"
        default: "rectangle.connected.to.line.below"
        }
    }

    // MARK: - Fallbacks

    private var openTVMenuRow: some View {
        Button {
            KeyPressWeight.medium.fire()
            model.press(.input)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title3)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open input menu on TV")
                        .font(.headline)
                    Text("Then pick the source with the direction pad")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityLabel("Open input menu on TV")
    }

    private var channelRow: some View {
        HStack(spacing: 14) {
            if model.supports(.channelDown) {
                GlassRectKey(
                    systemImage: "chevron.down",
                    accessibilityLabel: "Channel down",
                    height: 56
                ) { model.press(.channelDown) }
            }
            VStack(spacing: 2) {
                Image(systemName: "tv")
                    .font(.title3)
                Text("CH")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48)
            if model.supports(.channelUp) {
                GlassRectKey(
                    systemImage: "chevron.up",
                    accessibilityLabel: "Channel up",
                    height: 56
                ) { model.press(.channelUp) }
            }
        }
    }
}
