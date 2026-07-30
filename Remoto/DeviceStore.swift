import Foundation
import TVRemoteKit

/// A TV the app knows how to reconnect to. Persisted records are Codable
/// (UserDefaults plist); the *secret* is not here — it lives in the Keychain
/// under the device ID.
struct StoredDevice: Codable, Hashable, Identifiable {
    var id: DeviceID { identity.id }
    var identity: DeviceIdentity
    /// Which kind of secret sits in the Keychain for this device. Persisted
    /// rather than assumed: `preSharedKey` is Sony's, and a driver that pairs
    /// on-device issues a `token` instead. Reading a token back as a PSK would
    /// hand the driver a credential it refuses (`Credentials.secret` is
    /// kind-checked), which surfaces as an inexplicable auth failure.
    var credentialKind: String = CredentialKind.preSharedKey.rawValue

    /// Keychain account for this device's credential.
    var credentialAccount: String { "device.\(identity.id.rawValue)" }

    /// "no credential" is a valid stored state (auth-free TVs); a stored
    /// record with no secret returns `nil` and must not fall back to another
    /// device's key.
    var credentials: Credentials? {
        get {
            guard let data = KeychainStore.load(account: credentialAccount) else { return nil }
            return Credentials(kind: CredentialKind(credentialKind), payload: data)
        }
        nonmutating set {
            guard let newValue,
                  let payload = newValue.payload(newValue.kind),
                  !payload.isEmpty else {
                KeychainStore.delete(account: credentialAccount)
                return
            }
            KeychainStore.save(account: credentialAccount, data: payload)
        }
    }
}

/// Persists the known-TV list and which one to auto-reconnect to on launch.
/// UserDefaults is fine for identity (not secret); the secret never touches it.
@Observable
@MainActor
final class DeviceStore {
    private(set) var devices: [StoredDevice] = []
    /// The device to auto-connect on launch; `nil` until the first pairing.
    private(set) var lastUsedID: DeviceID?

    private static let devicesKey = "storedDevices"
    private static let lastUsedKey = "lastUsedDeviceID"

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.devicesKey),
           let decoded = try? JSONDecoder().decode([StoredDevice].self, from: data) {
            devices = decoded
        }
        if let raw = defaults.string(forKey: Self.lastUsedKey) {
            lastUsedID = DeviceID(raw)
        }
    }

    var lastUsed: StoredDevice? {
        devices.first { $0.id == lastUsedID }
    }

    /// Inserts or updates a device (identity may strengthen after auth), stores
    /// its credential in the Keychain, and marks it as the one to reconnect.
    func save(_ identity: DeviceIdentity, credentials: Credentials) {
        let record = StoredDevice(identity: identity, credentialKind: credentials.kind.rawValue)
        if let index = devices.firstIndex(where: { $0.id == identity.id }) {
            devices[index] = record
        } else {
            devices.append(record)
        }
        record.credentials = credentials.isEmpty ? nil : credentials
        lastUsedID = identity.id
        persist()
    }

    func forget(_ device: StoredDevice) {
        devices.removeAll { $0.id == device.id }
        KeychainStore.delete(account: device.credentialAccount)
        if lastUsedID == device.id { lastUsedID = devices.first?.id }
        persist()
    }

    /// The stored identity's ID can strengthen after `refreshIdentity()` (a
    /// provisional `manual:host` ID becomes a hardware-anchored one). Migrates
    /// the record — and its Keychain entry — to the new ID.
    func migrateID(from old: DeviceID, to identity: DeviceIdentity) {
        guard old != identity.id,
              let index = devices.firstIndex(where: { $0.id == old }) else { return }
        let credentials = devices[index].credentials
        KeychainStore.delete(account: devices[index].credentialAccount)
        let record = StoredDevice(identity: identity, credentialKind: devices[index].credentialKind)
        record.credentials = credentials
        devices[index] = record
        if lastUsedID == old { lastUsedID = identity.id }
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(devices), forKey: Self.devicesKey)
        defaults.set(lastUsedID?.rawValue, forKey: Self.lastUsedKey)
    }
}
