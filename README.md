# Glass Remote iOS — first native prototype

Separate native iPhone app. The Safari/Windows remote is not modified.

## Current prototype scope
- Native SwiftUI layout for iPhone, designed to fit the iPhone 13 Pro portrait safe area without a vertical ScrollView.
- App grid order: Netflix, YouTube, Stremio / RetroArch, Prime Video, Disney+ / Sunshine, Spotify, Rhenium.
- Reuses the supplied light/dark 800×480 app artwork.
- Direct ADB TCP connection to the VIP7802, RSA host identity persisted in iOS Keychain, package discovery and app launch.
- ADB shell starts the bundled ARM32 `glass_uhid_bridge` under Android's shell UID; single-finger pointer movement and click reports are sent through one persistent shell stream.
- Native UIKit haptic feedback.
- The first trackpad prototype does not yet implement the Safari version's complete two-finger scroll/right-click/drag gesture parity or persistent custom cursor override.

## Important test status
This is a first source prototype, not a tested IPA. It must be built by GitHub Actions on macOS and tested on the actual VIP7802. SwiftADB is an external dependency; its API and the device's existing ADB authorization path must be validated by the cloud build and hardware test. The app cannot bypass Android's ADB authorization prompt.

The helper binary is the existing ARM32 executable from the supplied Glass Remote project. It requires `/dev/uhid` access for the ADB shell identity, which was previously confirmed on this VIP7802.

## Build from Windows
1. Create a **private** GitHub repository named `GlassRemote-iOS`.
2. Upload the contents of this folder to the repository root (not the enclosing folder).
3. Open Actions and run `iOS build` (or push to `main`).
4. Download the `glassremote-build-logs` artifact if the build fails. The first run may reveal SwiftADB/Xcode API issues that need adjustment.

This workflow currently builds an iOS Simulator target for compile validation. Device IPA signing/sideloading is a later step and needs signing credentials/profile or a sideload workflow. The Swift files have only been syntax-parsed in this environment; a real Xcode build and VIP7802 connection test are still required.
