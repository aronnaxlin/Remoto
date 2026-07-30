import SwiftUI
import TVRemoteKit

/// The remote keyboard (Task 4), hosted inline in `ModeDock` — not a sheet.
/// The D-pad stays put above the dock, because type → pick a result → type
/// again is a tight loop that forbids page jumps or disappearing anchors.
///
/// The field is a **mirror of the TV's field**, not an outbox. `sendText` sets
/// the TV's field to the whole string — it replaces, never appends — so pushing
/// the current text after every edit is what makes the iOS keyboard's backspace
/// work. There is no "delete" key to map: none exists in the SDK's common
/// vocabulary, and the Sony test unit's 146-key table has none either. Deleting
/// a character here and re-sending *is* the delete.
///
/// Edits are coalesced: one request per pause in typing, not one per keystroke.
struct KeyboardPanel: View {
    let model: RemoteViewModel

    /// Focus is owned by `ModeDock` so that leaving the tab can release the
    /// keyboard even as this view is being removed.
    @FocusState.Binding var isTyping: Bool

    @State private var text = ""
    @State private var mirrorTask: Task<Void, Never>?
    @State private var isSyncing = false
    /// Flash feedback after a successful submit — the typing equivalent of a
    /// button's press haptic.
    @State private var didSubmit = false
    @State private var hint: String?

    /// How long to wait for typing to stop before pushing. Long enough that a
    /// burst of keystrokes becomes one request, short enough to feel live.
    private static let coalesceDelay = Duration.milliseconds(250)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                TextField("Type to the TV…", text: $text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($isTyping)
                    .onSubmit(submit)
                    .padding(.horizontal, 16)
                    .padding(.trailing, text.isEmpty ? 0 : 28)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .capsule)
                    .overlay(alignment: .trailing) { clearButton }

                Button(action: submit) {
                    Image(systemName: didSubmit ? "checkmark" : "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(didSubmit ? .green : .primary)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive().tint(.blue.opacity(0.35)), in: .circle)
                .disabled(text.isEmpty)
                .accessibilityLabel("Search on TV")
            }

            statusLine
        }
        .onAppear { isTyping = true }
        .onDisappear { mirrorTask?.cancel() }
        // Every edit is an edit of the TV's field, including a deletion and
        // including the clear button — there is no local-only state to protect.
        .onChange(of: text) { _, newValue in
            scheduleMirror(of: newValue)
        }
    }

    @ViewBuilder
    private var clearButton: some View {
        if !text.isEmpty {
            // Clears both sides: the TV's field holds whatever this one does, so
            // emptying it here empties it there.
            Button {
                KeyPressWeight.light.fire()
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear text")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let hint {
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        } else {
            HStack(spacing: 6) {
                if isSyncing {
                    ProgressView().controlSize(.mini)
                }
                Text("Mirrors the TV's field — backspace deletes there too.")
            }
            .font(.footnote)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Mirroring

    /// Replaces any pending push, so a fast typist produces one request per pause
    /// instead of one per character.
    private func scheduleMirror(of value: String) {
        mirrorTask?.cancel()
        mirrorTask = Task {
            try? await Task.sleep(for: Self.coalesceDelay)
            guard !Task.isCancelled else { return }
            await push(value)
        }
    }

    private func push(_ value: String) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await model.sendText(value)
            withAnimation(.smooth) { hint = nil }
        } catch TVRemoteError.unsupported {
            // The normal case, not a fault: nothing on the TV is focused yet.
            withAnimation(.smooth) {
                hint = "No text field is focused on the TV — open a search box there first."
            }
        } catch {
            withAnimation(.smooth) { hint = RemoteViewModel.describe(error) }
        }
    }

    /// Pushes whatever is in the field right now, then presses OK so the TV acts
    /// on it. The text stays put afterwards: it mirrors the TV's field, and
    /// clearing it after a search would clear the TV's too.
    private func submit() {
        guard !text.isEmpty else { return }
        KeyPressWeight.light.fire()
        mirrorTask?.cancel()
        Task {
            await push(text)
            guard hint == nil else { return } // nothing landed on the TV
            model.press(.confirm)
            withAnimation(.smooth) { didSubmit = true }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.smooth) { didSubmit = false }
        }
    }
}
