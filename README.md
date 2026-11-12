# Glass Remote (iOS)

Native iPhone remote for an ARRIS VIP7802 Android TV box running Glass Launcher, plus a Samsung TV
link. Native Liquid Glass, iOS 26 deployment target (`project.yml`). Dark by default, with light and adaptive themes.

> **Build status.** GitHub Actions builds every push to `main`, `v0.4-dev` and `Phase-*` branches for the
> simulator and a generic iPhone, runs the unit tests, packages an unsigned IPA (artifact `glassremote-unsigned-ipa`)
> and reports the result on the tracking pull request. Device behaviour is still checked by hand with
> `REGRESSION_CHECKLIST.md` on the real Android TV box and Samsung TV.

## Pages (floating dock in portrait, side rail in landscape)
The dock has exactly three destinations: **Remote**, **Discover** and **Profile**; switching between them is a cross-fade. Now Playing is not a dock destination: it is presented over the pages from the mini-player (portrait), the rail tile (landscape) or the Remote page's Now Playing card, and closed with its grabber or any dock item.

- **Remote**: Android TV or Samsung TV (explicit selector). Android: Apps panel, now playing, Mouse / D-pad, Back / Home / Sources / Search / Keyboard, volume. Samsung: trackpad and a short key set with one Play/Pause button. Header: Glass Remote logo (menu), Box/TV status, power menu.
- **Now Playing** (over the pages, not in the dock): what the box is playing, laid out like the Apple Music player. Portrait: title artwork runs edge to edge from the top of the screen and fades into a full-screen background made from it; the title sits on that fade, above a thin timeline, plain transport glyphs and a neutral volume row. Landscape: a large rounded artwork card beside a column as tall as the card (title at its top, volume at its bottom); the rail stays visible. Without title artwork the app's artwork shows on a rounded card. Limits: the box reports no duration and nothing can seek to a position, so the timeline never fills and has no scrubber (elapsed time only); seeking is the app's own relative step (see `SEEKING_REPORT.md`); previous/next appear only for audio apps (never for Nuvio video); posters come from Cinemeta by title, so a title with no match has none. A mini-player above the dock (a tile on the rail in landscape) appears while a media session is active and opens it; the one media poll (`dumpsys media_session`) feeds both.
- **Discover**: pinned search, Continue Watching (landscape cards) and Recently watched from your Nuvio account, Cinemeta carousels, genre browsing, detail page (a sheet in portrait, full screen in landscape), "Open in Nuvio".
- **Profile**: profiles with their own theme, ambient background, motion setting and add-ons. Add-on links (which can carry a personal token) live in the Keychain, never in the saved list; the same add-on can be installed more than once with different configurations; deleting a profile removes its add-ons and their Keychain items. Plain http add-on links are only accepted on the local network.

## Volume
Connection settings → **Volume goes to** picks one output; a route that is down disables the slider and says why, and nothing is sent to other speakers instead.
- **Soundbar, through the TV box** (default, restored from Phase 7.2): `input keyevent 24 / 25 / 164` on the TV box over the persistent ADB shell. The box passes volume keys to the soundbar over HDMI-CEC. This is the route Phase 7.2 actually used on this setup: its Samsung remote could not pair then, so its slider and keys fell through to the box. Phase 9 deleted the box route and sent everything to the Samsung TV, which moved the TV's own speakers. The soundbar's level cannot be read, so the slider is relative (20 key presses per full sweep, as in 7.2) and shows no number.
- **Soundbar, through the Samsung TV**: the TV's remote keys (WebSocket, `KEY_VOLUP` / `KEY_VOLDOWN` / `KEY_MUTE`), one per step of "Soundbar max volume". Never the TV's UPnP level.
- **TV speakers**: the TV's own level (UPnP RenderingControl, port 9197), an exact 0–100 with read-back; the TV's remote keys when UPnP is not answering.
- A 200 OK from the TV or a key accepted by a socket is never taken as proof that the speakers moved. Not verified on hardware: that this box forwards its volume keys to the soundbar, and which speakers each Samsung route moves on a given TV.

## Samsung pairing
The pairing token is stored in the Keychain and belongs to the TV that issued it; it is never sent to another address. A prompt that is denied is reported as denied (not as a timeout) and is not raised again until the user reconnects. **Reset Samsung pairing…** in Connection settings asks for confirmation, forgets only that token and the TV it came from, then connects without a token so the TV asks again. Reconnecting the remote and reconnecting the volume link are separate actions.

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
