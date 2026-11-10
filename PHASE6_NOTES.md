# Glass Remote — Phase 6 implementation notes

## Delivered

- Enabled portrait plus iPhone landscape orientations in `project.yml` without changing the iOS 16 deployment target.
- Added purpose-built landscape compositions for Remote, Player, Discover, Apps & Controls, and Connection. Rotation only changes layout; `RemoteModel.shared` and its ADB/UHID/Samsung state remain alive.
- Kept native iOS 26 Liquid Glass (`glassEffect`, `.interactive()`, and `GlassEffectContainer`) as the primary renderer, with a restrained material fallback for older supported OS versions.
- Upgraded Discover to fetch verified Cinemeta metadata on demand, including backdrop artwork, descriptions, ratings and genres, with a cinematic landscape detail layout.
- Added an explicit Nuvio integration boundary. Glass Remote hands off titles to the existing TV app and never fabricates streams, subtitle availability, addon endpoints, or debrid credentials.
- Added unit coverage for pager behavior and Cinemeta parsing.
- Updated GitHub Actions to run for the Phase 6 branch and pull requests, preserving unsigned IPA packaging.

## Nuvio limitation discovered

Installed addons are configured inside Nuvio on the TV. The repository does not contain a documented companion API, addon manifest/config URL, or safe credential handoff that the iPhone can use. Therefore source discovery, SubSense data, and Real-Debrid/Torbox selection remain Nuvio responsibilities. The app is provider-agnostic and does not modify addon configuration.

## Physical-device checks still required

- Rotate a connected phone while using the trackpad, two-finger scroll, virtual keyboard, ADB, persistent UHID helpers, and Samsung pairing.
- Verify iOS 26 native glass behavior on supported hardware and fallback appearance on an iOS 16–25 device.
- Verify the installed Nuvio/Stremio build accepts the existing `stremio:///detail/...` handoff.
- Verify artwork/network behavior, Dynamic Type, VoiceOver, dark appearance and the generated unsigned IPA on the GitHub Actions macOS runner.
