import SwiftUI
import TVRemoteKit

/// A rectangular glass key for the secondary panels (media transport, digits,
/// vendor apps) — same haptic contract as `GlassCircleKey`, different shape.
struct GlassRectKey: View {
    let title: String?
    let systemImage: String?
    let accessibilityLabel: String
    let weight: KeyPressWeight
    let height: CGFloat
    /// Vendor key names are raw device strings of any length
    /// ("ShopRemoteControlForcedDynamic" exists on real hardware), so a caller
    /// that shows them can allow a second line before truncation kicks in.
    let titleLineLimit: Int
    let action: () -> Void

    init(
        title: String? = nil,
        systemImage: String? = nil,
        accessibilityLabel: String,
        weight: KeyPressWeight = .medium,
        height: CGFloat = 56,
        titleLineLimit: Int = 1,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.weight = weight
        self.height = height
        self.titleLineLimit = titleLineLimit
        self.action = action
    }

    var body: some View {
        Button {
            weight.fire()
            action()
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                } else if let title {
                    Text(title)
                        .font(titleLineLimit > 1 ? .subheadline : .headline)
                        .lineLimit(titleLineLimit)
                        // Shrink a little, then truncate — an unbounded
                        // minimumScaleFactor turns a long name into unreadable
                        // 6pt text instead of an honest ellipsis.
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        // Without this the glyphs run into the glass edge.
                        .padding(.horizontal, 10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(.rect(cornerRadius: height / 2.5))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: height / 2.5))
        .accessibilityLabel(accessibilityLabel)
    }
}
