# Remoto

An iOS remote control app built as a demonstration frontend for [TVRemoteKit](https://github.com/aronnaxlin/TVRemoteKit).

This app serves two purposes:
1. Provide a clean, native, brand-agnostic iOS remote for local-network smart TVs.
2. Act as the primary UI validation layer for TVRemoteKit's API design (if a feature is awkward to build here, the SDK's API is wrong).

## Features

- **Liquid Glass UI:** Built for iOS 26+, heavily utilizing native translucent surfaces, smooth morphing transitions (`GlassEffectContainer`, `.glassEffect`), and physics-based haptic feedback.
- **Brand Agnostic:** The UI layer knows absolutely nothing about Sony or any other brand. It renders dynamically based on the capabilities advertised by the TVRemoteKit driver.
- **Privacy First:** No cloud accounts, no external tracking, no local network requests other than to your own TV.

## Getting Started

```sh
git clone https://github.com/aronnaxlin/Remoto.git
cd Remoto
open Remoto.xcodeproj
```

Xcode resolves [TVRemoteKit](https://github.com/aronnaxlin/TVRemoteKit) from GitHub the first time the project opens — there is nothing to install and no second checkout to arrange. Pick your device and press Run.

**Signing.** The project builds under a free Apple ID. Select your own team under *Signing & Capabilities*, and change the bundle identifier if `dev.aronnax.Remoto` is already claimed on your account. A free account's certificate expires after seven days, after which the app stops launching until you build to the device again. The first install also needs the developer trusted under *Settings → General → VPN & Device Management*.

**The SDK pin.** The dependency follows TVRemoteKit's `main` branch, resolved to a specific commit in `Package.resolved`. That file is committed on purpose: a branch dependency without it would hand every clone whatever `main` happened to be that day, rather than a revision this app was actually built against. To take a newer SDK, use *File → Packages → Update to Latest Package Versions* and commit the updated pin.

### Developing against a local TVRemoteKit

When changing the SDK and the app together, drag a local `TVRemoteKit` checkout into the Xcode project navigator. Xcode then prefers the local package over the published one, and SDK edits take effect on the next build; removing it from the navigator restores the remote dependency.

Note that Xcode records this override in `project.pbxproj`, so leave it out of your commits — otherwise the project stops resolving for anyone who does not have the SDK at that path, which is exactly what this arrangement is meant to prevent.

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
