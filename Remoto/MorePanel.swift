import SwiftUI
import TVRemoteKit

/// The "More" panel (Task 5), hosted inline in `ModeDock` — the remote home
/// stays visible above the dock. Everything here is driven by `supportedKeys`:
///
/// - now playing (Task 6) — hidden entirely when the TV reports nothing
/// - media transport — play/pause/stop/rewind/fast-forward/next/previous
/// - menu family — menu/options/exit
/// - digits — a foldable 0–9 pad
/// - vendor keys — the TV's brand-specific apps (Netflix, YouTube…), shown
///   by name; the UI never hardcodes a brand
struct MorePanel: View {
    let model: RemoteViewModel
    let onSwitchTV: () -> Void

    @State private var digitsExpanded = false

    private struct TransportItem {
        let key: RemoteKey
        let icon: String
        let label: String
    }

    private let transport: [TransportItem] = [
        .init(key: .rewind, icon: "backward.fill", label: "Rewind"),
        .init(key: .play, icon: "play.fill", label: "Play"),
        .init(key: .pause, icon: "pause.fill", label: "Pause"),
        .init(key: .stop, icon: "stop.fill", label: "Stop"),
        .init(key: .fastForward, icon: "forward.fill", label: "Fast forward"),
        .init(key: .previous, icon: "backward.end.fill", label: "Previous"),
        .init(key: .next, icon: "forward.end.fill", label: "Next")
    ]

    private struct MenuItem {
        let key: RemoteKey
        let icon: String
        let label: String
    }

    private let menuKeys: [MenuItem] = [
        .init(key: .menu, icon: "list.bullet", label: "Menu"),
        .init(key: .options, icon: "ellipsis.circle", label: "Options"),
        .init(key: .exit, icon: "xmark.circle", label: "Exit")
    ]

    private var vendorKeys: [RemoteKey] {
        model.capabilities?.supportedKeys
            .filter(\.isVendorSpecific)
            .sorted { $0.name < $1.name } ?? []
    }

    private var supportedDigits: [Int] {
        (0...9).filter { model.supports(.digit($0)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let playing = model.nowPlaying, playing.title != nil {
                    nowPlayingRow(playing)
                }

                transportSection
                menuSection
                digitsSection

                if !vendorKeys.isEmpty {
                    vendorSection
                }

                switchTVRow
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .task { await model.refreshNowPlaying() }
    }

    // MARK: - Sections

    private func nowPlayingRow(_ playing: NowPlaying) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.tv")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Now playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(playing.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var transportSection: some View {
        let items = transport.filter { model.supports($0.key) }
        return Group {
            if !items.isEmpty {
                section(title: "Playback") {
                    let columns = [GridItem(.adaptive(minimum: 64), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items, id: \.key) { item in
                            GlassRectKey(
                                systemImage: item.icon,
                                accessibilityLabel: item.label,
                                height: 56
                            ) { model.press(item.key) }
                        }
                    }
                }
            }
        }
    }

    private var menuSection: some View {
        let items = menuKeys.filter { model.supports($0.key) }
        return Group {
            if !items.isEmpty {
                section(title: "Menus") {
                    HStack(spacing: 12) {
                        ForEach(items, id: \.key) { item in
                            GlassRectKey(
                                systemImage: item.icon,
                                accessibilityLabel: item.label,
                                height: 52
                            ) { model.press(item.key) }
                        }
                    }
                }
            }
        }
    }

    private var digitsSection: some View {
        Group {
            if !supportedDigits.isEmpty {
                section(title: "Digits") {
                    VStack(spacing: 12) {
                        Button {
                            withAnimation(.smooth) { digitsExpanded.toggle() }
                        } label: {
                            HStack {
                                Text(digitsExpanded ? "Hide number pad" : "Show number pad")
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: digitsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        if digitsExpanded {
                            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9], id: \.self) { digit in
                                    digitKey(digit)
                                }
                                Color.clear.frame(height: 52)
                                digitKey(0)
                                Color.clear.frame(height: 52)
                            }
                        }
                    }
                }
            }
        }
    }

    private func digitKey(_ digit: Int) -> some View {
        Group {
            if model.supports(.digit(digit)) {
                GlassRectKey(
                    title: "\(digit)",
                    accessibilityLabel: "Digit \(digit)",
                    weight: .light,
                    height: 52
                ) { model.press(.digit(digit)) }
            } else {
                Color.clear.frame(height: 52)
            }
        }
    }

    private var vendorSection: some View {
        section(title: "Apps") {
            let columns = [GridItem(.adaptive(minimum: 112), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(vendorKeys, id: \.self) { key in
                    GlassRectKey(
                        title: Self.displayName(for: key),
                        accessibilityLabel: Self.displayName(for: key),
                        height: 60,
                        titleLineLimit: 2
                    ) { model.press(key) }
                }
            }
        }
    }

    /// Vendor key names arrive exactly as the device spells them —
    /// `AudioOutput_TVSpeaker`, `Tv_Radio`, `*AD`. Split them for reading only:
    /// the key that gets pressed is untouched, and the app still knows nothing
    /// about what any of them mean.
    static func displayName(for key: RemoteKey) -> String {
        var out = ""
        for character in key.name.replacingOccurrences(of: "_", with: " ") {
            if character.isUppercase,
               let last = out.last,
               last.isLowercase || last.isNumber {
                out.append(" ")
            }
            out.append(character)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private var switchTVRow: some View {
        Button {
            KeyPressWeight.medium.fire()
            onSwitchTV()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Switch TV")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .accessibilityLabel("Switch TV")
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            GlassEffectContainer(spacing: 12) {
                content()
            }
        }
    }
}
