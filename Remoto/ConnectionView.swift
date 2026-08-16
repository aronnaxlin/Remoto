import SwiftUI
import TVRemoteKit

/// The connection screen — a persistent, standalone place to find and pair a
/// TV, not a row bolted onto the remote. Reached on first launch, after
/// "Switch TV", or when an auto-reconnect fails.
///
/// Three ways in, weakest last: scan the network, pick a remembered TV, or
/// type an IP by hand. Local Network permission is only requested after the
/// user taps "Search for TVs" — never on appear (CLAUDE.md).
struct ConnectionView: View {
    let model: AppModel

    /// Plain HTTP, the port a TV's own control service listens on. Only a
    /// starting point: the field is editable precisely because the SDK's other
    /// drivers are not all there.
    private static let defaultManualPort = 80

    @State private var manualHost = ""
    @State private var manualPort = ""
    @State private var manualSecret = ""
    @State private var showManualEntry = false
    /// Local mirror of the pairing prompt so `.sheet(item:)` gets a binding
    /// (`$model` needs a `@State`/`@Bindable`, not a plain `let`).
    @State private var pairingRequest: AppModel.PairingRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let error = model.connectionError {
                    connectionFailureRow(error)
                }

                searchSection

                if !model.discovered.isEmpty {
                    discoveredSection
                }

                if !model.store.devices.isEmpty {
                    rememberedSection
                }

                manualSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .background(Color(white: 0.05).ignoresSafeArea())
        .overlay { connectingOverlay }
        .sheet(item: $pairingRequest) { request in
            PairingSheet(request: request)
                .presentationDetents([.medium])
        }
        .onChange(of: model.pairingRequest) { _, request in
            pairingRequest = request
        }
        .onDisappear { model.stopDiscovery() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Only when a session is still running underneath. Opened from the
            // remote's device button this screen is a detour, and a detour needs
            // a way back that is not "pick something"; reached on first launch or
            // after a failed reconnect there is nothing behind it, and a Done
            // button would lead nowhere.
            if model.canReturnToRemote {
                Button {
                    KeyPressWeight.light.fire()
                    model.returnToRemote()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.footnote.weight(.semibold))
                        Text("Remote")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
                .accessibilityLabel("Back to the remote")
            }

            Text("Connect a TV")
                .font(.largeTitle.bold())
            Text("Remoto controls TVs on your home network. Nothing leaves this network.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// A failed attempt has to say so here: the connecting overlay disappears on
    /// failure, and without this the tap simply looks ignored.
    private func connectionFailureRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityLabel("Connection failed. \(message)")
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                KeyPressWeight.medium.fire()
                if model.discoveryState == .searching {
                    model.stopDiscovery()
                } else {
                    model.startDiscovery()
                }
            } label: {
                HStack(spacing: 10) {
                    if model.discoveryState == .searching {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching…")
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text("Search for TVs")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(.rect(cornerRadius: 26))
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive().tint(.blue.opacity(0.35)), in: .capsule)

            // The only discovery failure mode worth special-casing: iOS hides
            // the Local Network permission state, so a bare timeout is the
            // signal. Guide, don't just report (Task 2).
            if model.discoveryState == .finished && model.discovered.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No TVs found")
                        .font(.headline)
                    Text("If this is the first search, iOS may have asked for Local Network access. Check Settings → Privacy & Security → Local Network, make sure the TV and this phone share a Wi-Fi network, then search again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
    }

    private var discoveredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Found on this network")
                .font(.headline)
                .foregroundStyle(.secondary)
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    ForEach(model.discovered, id: \.identity.id) { device in
                        deviceCard(
                            title: device.identity.displayName,
                            subtitle: subtitle(for: device.identity),
                            systemImage: "tv"
                        ) {
                            KeyPressWeight.medium.fire()
                            Task { await model.connect(to: device.identity) }
                        }
                    }
                }
            }
        }
    }

    private var rememberedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remembered")
                .font(.headline)
                .foregroundStyle(.secondary)
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    ForEach(model.store.devices) { device in
                        deviceCard(
                            title: device.identity.displayName,
                            subtitle: subtitle(for: device.identity),
                            systemImage: "clock.arrow.circlepath"
                        ) {
                            KeyPressWeight.medium.fire()
                            Task { await model.connect(to: device.identity) }
                        }
                    }
                }
            }
        }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.smooth) { showManualEntry.toggle() }
            } label: {
                HStack {
                    Text("Enter IP address manually")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: showManualEntry ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showManualEntry {
                VStack(spacing: 12) {
                    TextField("IP address (e.g. 192.168.1.20)", text: $manualHost)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    // Asked for, not guessed: drivers listen on different ports
                    // (a media-center app is not on the TV's own web port), and
                    // the app is not allowed to know which brand uses which.
                    // Blank means 80, which is what a TV's own service uses.
                    TextField("Port (leave empty for \(Self.defaultManualPort))", text: $manualPort)
                        .keyboardType(.numberPad)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    // Optional: leaving it empty is the normal path — the TV
                    // asks, and the pairing sheet handles it with the driver's
                    // own wording. Not a number pad; a key can contain letters.
                    SecureField("Secret, if the TV asks for one", text: $manualSecret)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    Button {
                        KeyPressWeight.medium.fire()
                        Task {
                            await model.connectManual(
                                host: manualHost,
                                port: Int(manualPort.trimmingCharacters(in: .whitespaces))
                                    ?? Self.defaultManualPort,
                                secret: manualSecret.isEmpty ? nil : manualSecret
                            )
                        }
                    } label: {
                        Text("Connect")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .contentShape(.rect(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive().tint(.blue.opacity(0.35)), in: .capsule)
                    .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var connectingOverlay: some View {
        if model.isConnecting {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Connecting to \(model.connectingIdentity?.displayName ?? "TV")…")
                        .font(.subheadline)
                }
                .padding(28)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
            }
        }
    }

    // MARK: - Pieces

    private func deviceCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityLabel("Connect to \(title)")
    }

    private func subtitle(for identity: DeviceIdentity) -> String {
        // Brand comes from the driver that claimed the device — displayed, not
        // branched on. Model name is only present when the TV volunteered it.
        [identity.manufacturer, identity.modelName, identity.host]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

#Preview {
    ConnectionView(model: AppModel())
        .preferredColorScheme(.dark)
}
