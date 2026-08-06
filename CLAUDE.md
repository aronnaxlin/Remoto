# Remoto

An iOS app for controlling TVs on your local network. No server, no cloud, no account.

All protocol work lives in [TVRemoteKit](https://github.com/aronnaxlin/TVRemoteKit), a
generic SDK where each TV brand is a pluggable driver. **Remoto's goal is to expose whatever
the SDK supports** — as drivers land in the SDK, Remoto gains brands without redesign. Sony
BRAVIA is the first.

The project depends on it as a remote Swift package tracking `main`, pinned in
`Package.resolved`, so a fresh clone builds with no setup. When changing both at once, drag
a local checkout into the project navigator to override the remote package — and keep that
override out of commits, since it only resolves on a machine that has the SDK at that path.

## The one rule

**Keep the app brand-agnostic.** No Sony-specific logic, no vendor branching, no protocol
knowledge in the UI layer. The app talks to the SDK's generic device abstraction.

A protocol bug gets fixed in TVRemoteKit, never patched here. Dependency is one-way.

This also makes the app the SDK's API design validator: if a feature is awkward to build
here, the SDK's API is wrong. Say so rather than working around it.

## Constraints

- **No paid Apple Developer account.** Free signing means device certs expire every 7 days.
  Capabilities needing Apple approval are unavailable — no SSDP multicast, no Wake-on-LAN
  broadcast. Discovery is Bonjour + subnet scan, both entitlement-free.
- Requires `NSLocalNetworkUsageDescription` and `NSBonjourServices` in Info.plist. Neither is
  an entitlement. If the user denies local network access there is no API to detect it — it
  surfaces as a timeout, so distinguish that case in the UI.
- Powering on relies on the TV keeping its HTTP server alive in standby, since WoL is
  unavailable on iOS.

## Security

Pre-shared keys go in the Keychain. Never in source, never in the repo, never off-device.
The app makes no network requests except to the user's own TV.

## Status

Early. The SDK is still taking shape; this repo is a skeleton.
