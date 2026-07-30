import SwiftUI
import TVRemoteKit

/// The remote keyboard (Task 4), hosted inline in `ModeDock` — not a sheet.
/// The D-pad stays put above the dock, because type → pick a result → type
/// again is a tight loop that forbids page jumps or disappearing anchors.
///
/// Text goes through `session.sendText`, which types straight into the TV's
/// focused field and bypasses the on-screen keyboard. `.unsupported` means no
/// field is focused — the normal state, mapped to guidance rather than alarm.
struct KeyboardPanel: View {
    let model: RemoteViewModel

    @State private var text = ""
    /// Flash feedback after a successful send — the typing equivalent of a
    /// button's press haptic.
    @State private var sentFlash = false
    @State private var hint: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                TextField("Type to the TV…", text: $text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.send)
                    .focused($fieldFocused)
                    .onSubmit(send)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .capsule)

                Button(action: send) {
                    Image(systemName: sentFlash ? "checkmark" : "arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(sentFlash ? .green : .primary)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive().tint(.blue.opacity(0.35)), in: .circle)
                .disabled(text.isEmpty)
                .accessibilityLabel("Send text")
            }

            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .onAppear { fieldFocused = true }
    }

    private func send() {
        let payload = text
        guard !payload.isEmpty else { return }
        KeyPressWeight.light.fire()
        Task {
            do {
                try await model.sendText(payload)
                text = ""
                hint = nil
                withAnimation(.smooth) { sentFlash = true }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.smooth) { sentFlash = false }
            } catch TVRemoteError.unsupported {
                withAnimation(.smooth) {
                    hint = "No text field is focused on the TV — open a search box there first."
                }
            } catch {
                withAnimation(.smooth) {
                    hint = RemoteViewModel.describe(error)
                }
            }
        }
    }
}
