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
final class RemoteViewModel: Identifiable {
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
    private(set) var power: PowerState?
    private(set) var nowPlaying: NowPlaying?
    /// The TV's physical inputs, loaded on demand by the Inputs panel.
    private(set) var inputs: [InputSource] = []
    private(set) var isLoadingInputs = false
    /// The session's post-auth identity — may carry a stronger ID than the
    /// one the caller connected with (see `DeviceStore.migrateID`).
    private(set) var connectedIdentity: DeviceIdentity?

    /// Transient error text shown inline. Cleared by the next successful action
    /// *and* by a timer: an error that outlives its cause becomes furniture, and
    /// this line shares space with the volume readout.
    private(set) var lastError: String?
    private var errorClearTask: Task<Void, Never>?

    private var session: (any DeviceSession)?

    var isConnected: Bool { connectionState == .connected }

    func supports(_ key: RemoteKey) -> Bool {
        capabilities?.supports(key) ?? true // optimistic until capabilities load
    }

    /// Optimistic until capabilities load: a control that exists on nearly every
    /// TV should not flash into view a second late.
    /// Named differently from `supports(_ key:)` on purpose: `.powerOn` exists as
    /// both a key and a feature, so an overload here would be ambiguous at every
    /// call site.
    private func has(_ feature: Feature) -> Bool {
        capabilities?.supports(feature) ?? true
    }

    /// Absolute volume drives the slider. A set without it may still have the
    /// IRCC ± keys (`volumeRelative`), which is a different control entirely —
    /// the SDK reports them separately, so the UI must too.
    var supportsAbsoluteVolume: Bool { has(.volumeAbsolute) }

    var supportsRelativeVolume: Bool {
        has(.volumeRelative) || supports(.volumeUp) || supports(.volumeDown)
    }

    /// Whether this TV can type at all. "No field is focused right now" is a
    /// separate, per-call condition that only `sendText` can report.
    var supportsTextEntry: Bool { has(.textEntry) }

    /// Listing inputs and switching to one are separate features: on real
    /// hardware the list is unauthenticated while the switch is not.
    var supportsInputList: Bool { has(.inputQuery) }
    var supportsInputSelect: Bool { has(.inputSelect) }

    /// Power through the SDK's `setPower`, which tries every wake route, rather
    /// than an IRCC key that a sleeping set may ignore.
    var supportsPowerControl: Bool { has(.powerOn) && has(.powerOff) }

    /// The URI of the input currently on screen, if the TV says. The SDK's
    /// contract: this is `nowPlaying().uri`, not a separate query.
    var currentInputID: String? { nowPlaying?.uri }

    // MARK: - Connection

    /// Connects the session and loads initial state. Throws the SDK's error
    /// vocabulary unchanged — the caller (AppModel) decides between the
    /// pairing sheet and the inline error line.
    func connect(to identity: DeviceIdentity, credentials: Credentials) async throws {
        connectionState = .connecting
        clearError()
        do {
            // The identity names the driver that claimed the device. Taking the
            // first bundled driver instead would hand an LG set to the Sony
            // driver the moment a second brand ships.
            guard let driver = Self.driver(for: identity) else {
                throw TVRemoteError.unsupported(feature: "no driver for \(identity.driverID)")
            }
            let session = try await driver.connect(
                to: identity,
                credentials: credentials,
                context: DriverContext(http: URLSessionHTTPClient())
            )
            self.session = session
            let refreshed = try await session.refreshIdentity()
            connectedIdentity = refreshed
            deviceName = refreshed.displayName
            connectionState = .connected
            async let caps: () = refreshCapabilities()
            async let vol: () = refreshVolume()
            async let pow: () = refreshPower()
            _ = await (caps, vol, pow)
        } catch {
            connectionState = .failed(Self.describe(error))
            throw error
        }
    }

    /// The bundled driver that owns `identity`.
    static func driver(for identity: DeviceIdentity) -> (any TVDriver)? {
        TVRemoteKit.bundledDrivers.first { $0.id == identity.driverID }
    }

    /// Tears down the live session (switching TVs, forgetting a device).
    func endSession() async {
        await session?.disconnect()
        session = nil
        connectionState = .disconnected
        connectedIdentity = nil
        capabilities = nil
        volume = nil
        power = nil
        nowPlaying = nil
        inputs = []
    }

    func refreshCapabilities() async {
        guard let session else { return }
        capabilities = try? await session.capabilities()
    }

    func refreshVolume() async {
        guard let session else { return }
        volume = try? await session.volumeState()
    }

    func refreshPower() async {
        guard let session else { return }
        power = try? await session.powerState()
    }

    /// Now-playing is polled on demand (the More panel asks when it opens, the
    /// Inputs panel to learn which source is live). Skipped when the TV never
    /// advertised the feature — a call that cannot succeed is not worth making.
    func refreshNowPlaying() async {
        guard let session, has(.nowPlaying) else { return }
        nowPlaying = (try? await session.nowPlaying()) ?? nil
    }

    /// Loads the TV's inputs. Also refreshes now-playing, because that is where
    /// the SDK carries "which of these is on screen".
    func refreshInputs() async {
        guard let session, supportsInputList else { return }
        isLoadingInputs = true
        defer { isLoadingInputs = false }
        do {
            inputs = try await session.inputs()
            clearError()
        } catch {
            fail(error)
        }
        await refreshNowPlaying()
    }

    /// Switches to `input`, then re-reads which source is live so the checkmark
    /// follows the TV rather than the tap.
    func selectInput(_ input: InputSource) {
        clearError()
        Task {
            do {
                try await session?.selectInput(input)
                await refreshNowPlaying()
            } catch {
                fail(error)
            }
        }
    }

    /// Toggles power the way the SDK intends: `setPower` tries Wake-on-LAN, the
    /// REST call, and the IRCC code in turn, because which one works depends on
    /// how deeply the set is asleep. Pressing the power *key* only covers the
    /// last of those three.
    func togglePower() {
        clearError()
        let turningOn = power != .on
        Task {
            do {
                if supportsPowerControl {
                    try await session?.setPower(turningOn)
                } else {
                    try await session?.press(.powerToggle)
                }
                await refreshPower()
            } catch {
                fail(error)
                await refreshPower()
            }
        }
    }

    /// Types into the TV's focused field. Throws `.unsupported` when no field
    /// is focused — the keyboard sheet maps that to "open a search box first".
    func sendText(_ text: String) async throws {
        try await session?.sendText(text)
    }

    /// Absolute volume set, used by the Control Center–style slider.
    /// Optimistically updates the on-screen level so the slider doesn't snap
    /// back while the request is in flight; re-reads on completion.
    func setVolume(_ level: Int) {
        clearError()
        if let current = volume {
            volume = VolumeState(
                level: level,
                minLevel: current.minLevel,
                maxLevel: current.maxLevel,
                isMuted: false,
                target: current.target
            )
        }
        Task {
            do {
                try await session?.setVolume(level)
                await refreshVolume()
            } catch {
                fail(error)
                await refreshVolume() // revert to the truth on failure
            }
        }
    }

    // MARK: - Key presses

    func press(_ key: RemoteKey) {
        clearError()
        Task {
            do {
                try await session?.press(key)
                // Volume keys change on-screen state; re-read so the bar follows.
                if key == .volumeUp || key == .volumeDown || key == .mute {
                    await refreshVolume()
                }
            } catch {
                fail(error)
            }
        }
    }

    // MARK: - Error text

    /// Shows `error` inline and schedules its own removal.
    private func fail(_ error: Error) {
        errorClearTask?.cancel()
        lastError = Self.describe(error)
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.lastError = nil
        }
    }

    private func clearError() {
        errorClearTask?.cancel()
        lastError = nil
    }

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
