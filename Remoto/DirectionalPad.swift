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
    /// Edge length of the whole pad, including the ring.
    static let defaultSize: CGFloat = 300

    let onDirection: (RemoteDirection) -> Void
    let onConfirm: () -> Void

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
    }

    private func ring(size: CGFloat, center: CGPoint, centerRadius: CGFloat) -> some View {
        Circle()
            .fill(.clear)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
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
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.secondary)
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
