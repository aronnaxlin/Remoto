import SwiftUI
import TVRemoteKit

/// Full-screen pairing prompt, shown when a TV answers a connection attempt
/// with `.authenticationRequired` or `.authenticationFailed` (Task 3).
///
/// Renders entirely from the SDK: `AuthHint` supplies the message and any
/// setup URL, and the driver's `requiredCredential` decides what to ask for —
/// which kind of secret it is, and whether the user types one at all. Success
/// stores the credential in the Keychain via `AppModel.connect`, so after one
/// pairing the sheet never reappears.
struct PairingSheet: View {
    let request: AppModel.PairingRequest

    @State private var key = ""

    /// A driver whose credential comes from approving a prompt on the TV has
    /// nothing for the user to type. Nothing bundled works that way yet, so this
    /// path says so plainly instead of showing a field that cannot help.
    private var isPairedOnDevice: Bool { request.requirement.isObtainedByPairing }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "tv.badge.wifi")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.isRetry ? "Secret rejected" : "Pairing required")
                        .font(.headline)
                    Text(request.identity.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(request.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let url = request.setupURL {
                Link(destination: url) {
                    Label("Open the TV's setup page", systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if isPairedOnDevice {
                Text("This TV pairs by approving a prompt on the screen itself. Remoto can't drive that yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SecureField(fieldLabel, text: $key)
                    // Not a number pad: a pre-shared key is whatever the owner
                    // typed into the TV, letters included. A numeric keyboard
                    // makes an alphanumeric key impossible to enter.
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    .onSubmit(submit)
            }

            HStack(spacing: 14) {
                Button("Cancel") { request.resume(nil) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)

                if !isPairedOnDevice {
                    Button("Pair", action: submit)
                        .buttonStyle(.plain)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .glassEffect(.regular.interactive().tint(.blue.opacity(0.35)), in: .capsule)
                        .disabled(key.isEmpty)
                }
            }
        }
        .padding(24)
        .presentationBackground(Color(white: 0.08))
    }

    /// The driver names the credential; the app only renders it.
    private var fieldLabel: String {
        switch request.requirement.kind {
        case .preSharedKey: "Pre-shared key"
        case .pin: "PIN shown on the TV"
        case .token: "Access token"
        default: "Secret"
        }
    }

    private func submit() {
        guard !key.isEmpty else { return }
        KeyPressWeight.medium.fire()
        request.resume(Credentials(kind: request.requirement.kind, secret: key))
    }
}
