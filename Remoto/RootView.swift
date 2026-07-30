import SwiftUI

/// Root: connection screen and remote home are two full-screen places, not a
/// navigation stack. `RemoteViewModel` is created only when a session exists,
/// so the remote screen never renders in a half-connected state.
struct RootView: View {
    let model: AppModel
    /// Mirrors `model.remote` so `if let` gets a fresh snapshot per redraw —
    /// `let model` doesn't observe through `@Observable` on its own.
    @State private var remote: RemoteViewModel?

    var body: some View {
        Group {
            switch model.route {
            case .connect:
                ConnectionView(model: model)
                    .transition(.opacity)
            case .remote:
                if let remote {
                    RemoteHomeView(model: remote) {
                        model.disconnect()
                    }
                    .transition(.opacity)
                } else {
                    // Reconnect-in-flight: brief dark screen while the stored
                    // TV answers; the home view appears with the session live.
                    Color(white: 0.05).ignoresSafeArea()
                }
            }
        }
        .animation(.smooth, value: model.route)
        .onChange(of: model.remote?.deviceName, initial: true) { _, _ in
            // `RemoteViewModel` isn't Equatable (MainActor); deviceName is
            // enough — a new session always rewrites it.
            remote = model.remote
        }
        .onChange(of: model.route) { _, _ in
            remote = model.remote
        }
    }
}
