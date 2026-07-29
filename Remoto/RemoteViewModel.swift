import Foundation
import Observation
import TVRemoteKit

/// Drives the remote home screen.
///
/// The view model speaks *only* the SDK's generic vocabulary — `DeviceSession`,
/// `RemoteKey`, `Capabilities`. No brand logic exists here or anywhere in the app:
/// buttons render from `supportedKeys`, and every press goes through `session.press`.
@Observable
@MainActor
final class RemoteViewModel {
    /// Connection lifecycle for the top-of-screen status line.
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var deviceName: String = ""
    private(set) var capabilities: Capabilities?
    private(set) var volume: VolumeState?

    /// Transient error text shown inline; cleared on the next successful press.
    private(set) var lastError: String?

    private var session: (any DeviceSession)?

    var isConnected: Bool { connectionState == .connected }

    func supports(_ key: RemoteKey) -> Bool {
        capabilities?.supports(key) ?? true // optimistic until capabilities load
    }

    // MARK: - Connection

    /// Temporary bootstrap for UI bring-up: connect straight to a host.
    /// Task 2 replaces this with discovery; Task 3 adds the PSK sheet on
    /// `.authenticationRequired`. The view layer already routes errors here.
    func connect(host: String, port: Int = 80, preSharedKey: String? = nil) async {
        connectionState = .connecting
        lastError = nil
        do {
            guard let driver = TVRemoteKit.bundledDrivers.first else {
                throw TVRemoteError.unsupported(feature: "no driver bundled")
            }
            let identity = DeviceIdentity(
                id: DeviceID("manual:\(host)"),
                idSource: .provisional,
                driverID: driver.id,
                host: host,
                port: port,
                displayName: host
            )
            let credentials = preSharedKey.map(Credentials.preSharedKey) ?? .none
            let session = try await driver.connect(
                to: identity,
                credentials: credentials,
                context: DriverContext(http: URLSessionHTTPClient())
            )
            self.session = session
            deviceName = session.identity.displayName
            connectionState = .connected
            async let caps: () = refreshCapabilities()
            async let vol: () = refreshVolume()
            _ = await (caps, vol)
        } catch {
            connectionState = .failed(Self.describe(error))
        }
    }

    func refreshCapabilities() async {
        guard let session else { return }
        capabilities = try? await session.capabilities()
    }

    func refreshVolume() async {
        guard let session else { return }
        volume = try? await session.volumeState()
    }

    // MARK: - Key presses

    func press(_ key: RemoteKey) {
        lastError = nil
        Task {
            do {
                try await session?.press(key)
                // Volume keys change on-screen state; re-read so the bar follows.
                if key == .volumeUp || key == .volumeDown || key == .mute {
                    await refreshVolume()
                }
            } catch {
                lastError = Self.describe(error)
            }
        }
    }

    // MARK: - Error text

    /// Maps the SDK's error vocabulary to one-line user-facing text.
    /// UI displays; it never parses protocol details.
    static func describe(_ error: Error) -> String {
        guard let error = error as? TVRemoteError else {
            return error.localizedDescription
        }
        switch error {
        case .notConnected:
            return "Not connected to the TV."
        case .connectionFailed(_, let reason):
            return "Connection failed: \(reason)"
        case .timedOut(_, let hint):
            return hint == .possiblyLocalNetworkPermissionDenied
                ? "Timed out. Check Settings → Privacy & Security → Local Network."
                : "The TV didn't respond in time."
        case .authenticationRequired(let hint):
            return hint.recoverySuggestion ?? "This TV requires a pre-shared key."
        case .authenticationFailed(let hint):
            return hint.recoverySuggestion ?? "The TV rejected that key."
        case .devicePoweredOff:
            return "The TV is off."
        case .unsupported(let feature):
            return "Unsupported: \(feature)"
        case .deviceBusy:
            return "The TV is busy — try again."
        case .driverFault(let fault):
            return "TV error \(fault.code)."
        case .invalidResponse:
            return "The TV sent an unexpected reply."
        case .discoveryUnavailable:
            return "Discovery isn't available on this network."
        case .cancelled:
            return "Cancelled."
        }
    }
}
