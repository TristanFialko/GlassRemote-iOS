# Glass Remote (iOS)

Native iPhone remote for an ARRIS VIP7802 Android TV box running Glass Launcher, plus a Samsung TV
link. Native Liquid Glass, iOS 26 deployment target (`project.yml`). Dark by default, with light and adaptive themes.

> **Build status.** GitHub Actions builds every push to `main`, `v0.4-dev` and `Phase-*` branches for the
> simulator and a generic iPhone, runs the unit tests, packages an unsigned IPA (artifact `glassremote-unsigned-ipa`)
> and reports the result on the tracking pull request. Device behaviour is still checked by hand with
> `REGRESSION_CHECKLIST.md` on the real Android TV box and Samsung TV.

## Pages (floating dock in portrait, side rail in landscape)
Portrait pages swipe sideways; landscape stacks the same pages top to bottom, matching the rail.

- **Remote**: Android TV or Samsung TV (explicit selector). Android: Apps panel, now playing, Mouse / D-pad, Back / Home / Sources / Search / Keyboard, volume. Samsung: trackpad and a short key set with one Play/Pause button. Header: Glass Remote logo (menu), Box/TV status, power menu.
- **Player**: what the box is playing. The artwork is the dominant element (never stretched), over a full-screen background made from the artwork with a contrast layer; landscape puts square artwork beside title, progress, play/pause and volume. Play/pause is the primary control, seeking is relative (see `SEEKING_REPORT.md`), previous/next only appear for audio apps (never for Nuvio video), and the volume slider works from this page too. Posters come from Cinemeta by title; landscape artwork is used when Discover supplied it.
- **Discover**: pinned search, Continue Watching (landscape cards) and Recently watched from your Nuvio account, Cinemeta carousels, genre browsing, detail page (a sheet in portrait, full screen in landscape), "Open in Nuvio".
- **Profile**: profiles with their own theme, ambient background, motion setting and add-ons. Add-on links (which can carry a personal token) live in the Keychain, never in the saved list; the same add-on can be installed more than once with different configurations; deleting a profile removes its add-ons and their Keychain items. Plain http add-on links are only accepted on the local network.

## Themes
Logo menu -> **Themes**. Eleven options: Default Dark, Deep Blue, Violet, Amber, Light Glass, Forest, Crimson, Ocean, Glass White, **Adaptive** (accents from the artwork on screen, one shared palette) and **Auto** (follows iOS Light/Dark). Optional drawn ambient backgrounds (Off by default). All colours come from `Theme.swift`; views read `\.glassTheme` and `Color.ink`. Changing theme never touches the models, ADB or helpers.

## Nuvio integration (what it does and does not do)
See `NUVIO_MIGRATION.md` for the verified / unverified breakdown. In short:
- Account: Nuvio's own device-link sign-in (code shown here, approved on nuvio.tv). No password is entered in this app. Session tokens live in the Keychain. Read-only.
- Continue Watching / Recently watched: `sync_pull_watch_progress`, named and posted via Cinemeta (Nuvio's default metadata addon). No library or watchlist row: those RPCs are unverified.
- Opening: `nuvio://detail/...` and `nuvio://search?q=` sent with `am start -p com.nuvio.app`; if Android refuses, Nuvio is launched and the app says so. Never auto-plays.
- Player: unchanged seeking limits (see `SEEKING_REPORT.md`). No exact seek or duration; no companion helper was built.

## Build
Upload the contents of this folder to the GitHub repo (include `.github`) and run **iOS build**. The workflow compiles the ARM32/ARM64 Android helpers with the NDK, generates the project with XcodeGen, builds for the simulator, runs the unit tests, builds for a physical iPhone, bundles and verifies the helpers, and packages `GlassRemote-unsigned.ipa`. Progress notes and checkpoints are in `PHASE-7-NOTES.md`.

## Protected
UHID mouse/keyboard protocols and helpers (`glass_uhid_bridge`, `glass_uhid_keyboard`, `glass_tcp_input_server`), ADB identity, Samsung WebSocket pairing and Keychain token, connection recovery.
