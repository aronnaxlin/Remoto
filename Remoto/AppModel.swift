import Foundation
import Observation
import TVRemoteKit

/// The app's connection and discovery orchestrator.
///
/// Owns the "where is the app" decision: `route` starts at `.connecting` (or an
/// immediate auto-reconnect when a paired TV is on record) and moves to
/// `.remote` once a session is live. All brand knowledge stays in the SDK —
/// this model speaks `DeviceSession`, `DiscoveredDevice`, `Credentials` only.
@Observable
@MainActor
final class AppModel {
    /// Top-level routing. No navigation stack: the app has exactly two places
    /// to be — connecting to a TV, or driving one.
    enum Route: Equatable {
        case connect
        case remote
    }

    /// Discovery lifecycle for the connection screen.
    enum DiscoveryState: Equatable {
        case idle
        case searching
        case finished
    }

    /// A pairing prompt raised by `.authenticationRequired` / `.authenticationFailed`.
    /// Carries what the sheet needs to render without any brand knowledge.
    struct PairingRequest: Identifiable, Hashable {
        let id = UUID()
        let identity: DeviceIdentity
        /// User-facing guidance from the SDK (`AuthHint.recoverySuggestion`).
        let message: String
        let setupURL: URL?
        /// `.authenticationFailed` — the stored/typed secret was rejected.
        let isRetry: Bool
        /// What the *driver* says it needs: which kind of secret, how the user
        /// supplies it, and where to find it. The sheet renders from this rather
        /// than assuming every TV wants a typed-in pre-shared key.
        let requirement: CredentialRequirement
        /// The completion resumes the connection attempt with the typed secret.
        let resume: (Credentials?) -> Void

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private(set) var route: Route = .connect
    private(set) var discoveryState: DiscoveryState = .idle
    private(set) var discovered: [DiscoveredDevice] = []
    private(set) var isConnecting = false
    /// Which device a connection attempt targets — lets the sheet title name it.
    private(set) var connectingIdentity: DeviceIdentity?
    /// Non-nil while a pairing prompt should be on screen.
    var pairingRequest: PairingRequest?
    /// Why the last connection attempt failed, for the connection screen. Auth
    /// failures are not here — those raise the pairing sheet instead.
    private(set) var connectionError: String?

    let store = DeviceStore()
    private(set) var remote: RemoteViewModel?

    private var discoveryTask: Task<Void, Never>?

    init() {
        // Open the app → finger on the D-pad in under two seconds: if we have
        // a paired TV, reconnect silently in the background and start on the
        // remote screen only once it answers. `Task` inherits MainActor, so
        // property access is safe without `self.` capture gymnastics.
        if let last = store.lastUsed {
            route = .remote
            remote = RemoteViewModel()
            Task { [weak self] in
                await self?.connect(to: last.identity, credentials: last.credentials, silent: true)
            }
        }
    }

    // MARK: - Discovery

    /// Starts Bonjour + subnet scan. Called from the connection screen's
    /// "Search for TVs" button — Local Network permission prompts on first
    /// traffic, which must not happen before the user asked (CLAUDE.md).
    func startDiscovery() {
        guard discoveryState != .searching else { return }
        connectionError = nil
        discoveryState = .searching
        discovered = []
        discoveryTask = Task {
            let stream = await TVRemoteKit.discoverStream()
            for await device in stream {
                guard !Task.isCancelled else { return }
                if !discovered.contains(device) {
                    discovered.append(device)
                }
            }
            guard !Task.isCancelled else { return }
            discoveryState = .finished
        }
    }

    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        if discoveryState == .searching { discoveryState = .finished }
    }

    // MARK: - Connection

    /// Connects to a discovered or manually-entered device. Raises the pairing
    /// sheet when the TV demands a credential the store doesn't have, and
    /// resumes itself once the user supplies one.
    func connect(
        to identity: DeviceIdentity,
        credentials explicitCredentials: Credentials? = nil,
        silent: Bool = false
    ) async {
        guard !isConnecting else { return }
        isConnecting = true
        connectionError = nil
        connectingIdentity = identity
        defer {
            isConnecting = false
            connectingIdentity = nil
        }

        let stored = store.devices.first { $0.id == identity.id }
        let credentials = explicitCredentials ?? stored?.credentials ?? .none
        let model = remote ?? RemoteViewModel()
        remote = model

        do {
            try await model.connect(to: identity, credentials: credentials)
            // Identity may have strengthened post-auth (provisional → hardware
            // ID); migrate the record so Keychain + lastUsed follow the device.
            if let sessionIdentity = model.connectedIdentity, sessionIdentity.id != identity.id {
                store.migrateID(from: identity.id, to: sessionIdentity)
                store.save(sessionIdentity, credentials: credentials)
            } else {
                store.save(identity, credentials: credentials)
            }
            route = .remote
        } catch TVRemoteError.authenticationRequired(let hint) {
            if silent { route = .connect }
            presentPairing(for: identity, hint: hint, isRetry: false)
        } catch TVRemoteError.authenticationFailed(let hint) {
            // The stored key went stale — forget it so the retry isn't poisoned.
            if let record = stored {
                record.credentials = nil
            }
            if silent { route = .connect }
            presentPairing(for: identity, hint: hint, isRetry: true)
        } catch {
            // A failure with nothing on screen to explain it is the worst of
            // both worlds: the overlay vanishes and the tap looks ignored.
            connectionError = RemoteViewModel.describe(error)
            route = .connect
        }
    }

    /// Manual-IP entry: builds a provisional identity and runs the same flow.
    ///
    /// A typed-in address says nothing about the brand, so the identity is built
    /// against the first bundled driver and `connect()` corrects it — the
    /// session's `refreshIdentity()` result carries the real driver's ID, and
    /// `migrateID` moves the stored record onto it.
    func connectManual(host: String, secret: String?) async {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let driver = TVRemoteKit.bundledDrivers.first else { return }
        let identity = DeviceIdentity(
            id: DeviceID("manual:\(trimmed)"),
            idSource: .provisional,
            driverID: driver.id,
            host: trimmed,
            port: 80,
            displayName: trimmed
        )
        // Whatever kind the driver asks for — the app does not decide that.
        let credentials = secret.flatMap { value -> Credentials? in
            guard !value.isEmpty else { return nil }
            return Credentials(kind: driver.requiredCredential.kind, secret: value)
        }
        await connect(to: identity, credentials: credentials)
    }

    /// "Switch TV" — drops the live session and returns to the connection
    /// screen. The stored record stays; this is switching, not forgetting.
    func disconnect() {
        Task { await remote?.endSession() }
        route = .connect
    }

    // MARK: - Pairing

    private func presentPairing(for identity: DeviceIdentity, hint: AuthHint, isRetry: Bool) {
        let requirement = RemoteViewModel.driver(for: identity)?.requiredCredential ?? .none
        pairingRequest = PairingRequest(
            identity: identity,
            message: hint.recoverySuggestion ?? hint.message,
            setupURL: hint.setupURL,
            isRetry: isRetry,
            requirement: requirement
        ) { [weak self] credentials in
            guard let self else { return }
            self.pairingRequest = nil
            guard let credentials else { return } // cancelled
            Task { await self.connect(to: identity, credentials: credentials) }
        }
    }
}
