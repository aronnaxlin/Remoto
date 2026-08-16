import SwiftUI

/// The central directional pad, modelled on the Siri Remote's clickpad ring:
/// one continuous glass ring with four direction zones and a raised center
/// confirm button. Tapping a quadrant of the ring sends that direction;
/// tapping the center sends confirm.
///
/// The ring is one big interactive glass surface — a drag that starts on a
/// direction and slides to the center still resolves to the direction the
/// gesture *began* on, matching how the physical clickpad is zoned.
struct DirectionalPad: View {
    /// Edge length cap for the whole pad, including the ring. High enough that
    /// the content width, not this number, is the real limit on a phone: the pad
    /// is the screen's subject, and anything smaller left it swimming.
    static let defaultSize: CGFloat = 400

    let onDirection: (RemoteDirection) -> Void
    let onConfirm: () -> Void

    /// VoiceOver needs the gesture-based ring re-expressed as four buttons;
    /// the ring itself is one continuous surface with no per-direction node.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let centerRadius = size * 0.24

            ZStack {
                ring(size: size, center: center, centerRadius: centerRadius)
                confirmButton(diameter: centerRadius * 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: Self.defaultSize)
        .accessibilityElement(children: voiceOver ? .ignore : .contain)
        .accessibilityAdjustableAction { direction in
            // VoiceOver rotor: swipe up/down steps through directions and
            // confirm, keeping the D-pad one stop instead of five.
            KeyPressWeight.light.fire()
            switch direction {
            case .increment: onDirection(.up)
            case .decrement: onDirection(.down)
            @unknown default: break
            }
        }
    }

    private func ring(size: CGFloat, center: CGPoint, centerRadius: CGFloat) -> some View {
        Circle()
            .fill(.clear)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
            // On a near-black background the glass has no edge to catch, so the
            // disc dissolves into the wall it sits on. One hairline gives it a
            // rim; without it the pad reads as a smudge, not an object.
            .overlay { Circle().strokeBorder(.white.opacity(0.09), lineWidth: 1) }
            .overlay {
                // Faint etched direction marks so the ring reads as a D-pad
                // without four separate glass pieces fighting each other.
                directionMarks(radius: size / 2, centerRadius: centerRadius)
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        let distance = (dx * dx + dy * dy).squareRoot()
                        guard distance > centerRadius else { return } // center handles it
                        guard let direction = RemoteDirection(dx: dx, dy: dy) else { return }
                        KeyPressWeight.light.fire()
                        onDirection(direction)
                    }
            )
    }

    private func directionMarks(radius: CGFloat, centerRadius: CGFloat) -> some View {
        let offset = (radius + centerRadius) / 2
        return ZStack {
            Image(systemName: "chevron.up")
                .offset(y: -offset)
            Image(systemName: "chevron.down")
                .offset(y: offset)
            Image(systemName: "chevron.left")
                .offset(x: -offset)
            Image(systemName: "chevron.right")
                .offset(x: offset)
        }
        .font(.system(size: 20, weight: .semibold))
        // `.secondary` is tuned for text on a background, not glyphs on glass:
        // it left the only affordance on the pad the dimmest thing on screen.
        .foregroundStyle(.white.opacity(0.7))
        .allowsHitTesting(false)
    }

    private func confirmButton(diameter: CGFloat) -> some View {
        Button {
            KeyPressWeight.medium.fire()
            onConfirm()
        } label: {
            Circle()
                .fill(.clear)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        // Same reason as the ring's rim, and here it also draws the boundary
        // between the two concentric pieces — the only thing that says the
        // center is a separate button.
        .overlay { Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1) }
        .accessibilityLabel("Confirm")
    }
}

enum RemoteDirection {
    case up, down, left, right

    /// Quadrant resolution: the axis with the larger displacement wins,
    /// which is how the Siri Remote ring partitions taps.
    init?(dx: CGFloat, dy: CGFloat) {
        guard dx != 0 || dy != 0 else { return nil }
        if abs(dx) > abs(dy) {
            self = dx > 0 ? .right : .left
        } else {
            self = dy > 0 ? .down : .up
        }
    }
}
