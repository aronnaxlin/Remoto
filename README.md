# Remoto

An iOS remote control app built as a demonstration frontend for [TVRemoteKit](https://github.com/aronnaxlin/TVRemoteKit).

This app serves two purposes:
1. Provide a clean, native, brand-agnostic iOS remote for local-network smart TVs.
2. Act as the primary UI validation layer for TVRemoteKit's API design (if a feature is awkward to build here, the SDK's API is wrong).

## Features

- **Liquid Glass UI:** Built for iOS 26+, heavily utilizing native translucent surfaces, smooth morphing transitions (`GlassEffectContainer`, `.glassEffect`), and physics-based haptic feedback.
- **Brand Agnostic:** The UI layer knows absolutely nothing about Sony or any other brand. It renders dynamically based on the capabilities advertised by the TVRemoteKit driver.
- **Privacy First:** No cloud accounts, no external tracking, no local network requests other than to your own TV.

## Relationship with TVRemoteKit

| Repository | Responsibility |
|---|---|
| [TVRemoteKit](https://github.com/aronnaxlin/TVRemoteKit) | Swift SDK — discovery, protocols, authentication, capabilities. Cross-platform, headless. |
| **Remoto** (This repo) | iOS App — UI, interactions, device management, user preferences. |

The dependency is strictly one-way: `Remoto → TVRemoteKit`. Protocol bugs are fixed in the SDK, not patched in the UI.

## Environment & Constraints

- **Deployment Target:** iOS 26.0 (Requires Xcode 26.3+)
- **Swift Version:** Swift 6
- **Entitlement-Free:** Built to run on a free Apple Developer account without MDM/custom entitlements. Device discovery uses standard Bonjour and subnet scanning rather than SSDP multicast. Wake-on-LAN broadcast is similarly disabled.
- **Authentication:** Pre-Shared Keys are securely stored in the iOS Keychain.

## Status

🚧 **Early Development.** Currently implemented:
- Base project skeleton and SDK linking.
- Home screen UI: Directional pad, function keys, mode bar, and a Control Center–style continuous volume slider.

## License

MIT
