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
    /// Published because the volume bar above the key row lines its ends up with
    /// the outermost keys' edges, and it can only do that arithmetic if it knows
    /// how wide a key is.
    static let diameter: CGFloat = 62

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
                .frame(width: Self.diameter, height: Self.diameter)
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
