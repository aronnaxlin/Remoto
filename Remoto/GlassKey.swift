import SwiftUI
import UIKit

/// The pressure of a key press, mapped to a distinct haptic weight.
/// Direction taps feel light, power feels deliberate — the hand learns the layout by feel.
enum KeyPressWeight {
    case light
    case medium
    case heavy

    @MainActor
    func fire() {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = switch self {
        case .light: .light
        case .medium: .medium
        case .heavy: .heavy
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

/// A single circular glass key: Back, Home, Mute, Power.
///
/// The button owns its label and haptic; the parent owns what the press *does*.
/// Liquid Glass requires iOS 26, which is also this app's deployment target, so
/// no material fallback is needed anywhere in the codebase.
struct GlassCircleKey: View {
    let systemImage: String
    let accessibilityLabel: String
    let weight: KeyPressWeight
    let tint: Color?
    let action: () -> Void

    init(
        systemImage: String,
        accessibilityLabel: String,
        weight: KeyPressWeight = .medium,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.weight = weight
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button {
            weight.fire()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 62, height: 62)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: .circle)
        .accessibilityLabel(accessibilityLabel)
    }

    private var glass: Glass {
        var g = Glass.regular.interactive()
        if let tint {
            g = g.tint(tint.opacity(0.35))
        }
        return g
    }
}

/// The two-piece volume key, modelled on a physical remote's rocker:
/// one long glass pill, "+" on top, "−" below, a hairline gap between.
struct GlassVolumeRocker: View {
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            VStack(spacing: 4) {
                rockerButton(systemImage: "plus", label: "Volume Up", action: onUp)
                rockerButton(systemImage: "minus", label: "Volume Down", action: onDown)
            }
        }
    }

    private func rockerButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            KeyPressWeight.light.fire()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 62, height: 76)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 31))
        .accessibilityLabel(label)
    }
}
