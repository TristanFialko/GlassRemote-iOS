# Glass Remote (iOS)

Native iPhone remote for an ARRIS VIP7802 Android TV box running Glass Launcher, plus a Samsung TV
link. Native Liquid Glass, iOS 26 deployment target (`project.yml`). Dark by default, with light and adaptive themes.

> **Build status.** GitHub Actions builds every push to `main`, `v0.4-dev` and `Phase-*` branches for the
> simulator and a generic iPhone, runs the unit tests, packages an unsigned IPA (artifact `glassremote-unsigned-ipa`)
> and reports the result on the tracking pull request. Device behaviour is still checked by hand with
> `REGRESSION_CHECKLIST.md` on the real Android TV box and Samsung TV. Nothing in this README is claimed as hardware-verified unless it says so.

## Pages (floating dock in portrait, side rail in landscape)
The dock has exactly three destinations: **Remote**, **Discover** and **Profile**; switching between them is a cross-fade. Now Playing is not a dock destination: it is presented over the pages from the mini-player (portrait), the rail tile (landscape) or the Remote page's Now Playing card, and closed with its grabber or any dock item.

- **Remote**: Android TV or Samsung TV (explicit selector). Android: Apps panel, now playing, Mouse / D-pad, Back / Home / Sources / Search / Keyboard, and the volume row. Samsung: trackpad and a short key set with one Play/Pause button. Header: Glass Remote logo (menu), Box/TV status, power menu. Landscape is laid out around the pad: a slim top bar (status, Mouse / D-pad over the pad, device switch and power), a key rail under each thumb, the trackpad across the middle (about three quarters of the width) and volume along its foot.
- **Now Playing** (over the pages, not in the dock): what the box is playing, laid out like the Apple Music player. Portrait: title artwork runs edge to edge from the top of the screen and fades into a full-screen colour wash built from the poster's prominent colours (not a blurred copy of it); the title sits on that fade, above a thin timeline, transport glyphs with press feedback and a volume row with a mute button (a level number only when the level is read back). Landscape: a large rounded artwork card beside a column as tall as the card (title at its top, volume at its bottom); the rail stays visible. Without title artwork the app's artwork shows on a rounded card. Limits: the box reports no duration and nothing can seek to a position, so the timeline never fills and has no scrubber (elapsed time only); seeking is the app's own relative step (see `SEEKING_REPORT.md`); previous/next appear only for audio apps (never for Nuvio video); posters come from Cinemeta by title, so a title with no match has none. A mini-player above the dock (a tile on the rail in landscape) appears while a media session is active and opens it; the one media poll (`dumpsys media_session`) feeds both.
- **Discover**: pinned search, Continue Watching (landscape cards) and Recently watched from your Nuvio account, Cinemeta carousels, genre browsing, detail page (a sheet in portrait, full screen in landscape), "Open in Nuvio". Tapping an episode (or resuming one) opens the stream picker on that episode.
- **Profile**: profiles with their own theme, ambient background, motion setting and add-ons. Add-on links (which can carry a personal token) live in the Keychain, never in the saved list; the same add-on can be installed more than once with different configurations; deleting a profile removes its add-ons and their Keychain items. Plain http add-on links are only accepted on the local network. Removing an add-on (including swipe-to-delete) asks for confirmation.

## Setup
1. **TV box (ADB).** Connection settings → *Android TV*: address and ADB port (5555). The address field starts at `192.168.1.70`, the author's box (saved as `tvHost` once changed); set it to your box, or use *Scan Wi-Fi for devices*. Turn on network debugging on the box. On first connect (or when the key is refused) the box shows "Allow USB debugging?": choose Allow, tick "Always allow from this computer", then tap Connect. The app keeps its ADB key, so an approved box does not ask again.
2. **Samsung TV (optional).** There is no built-in Samsung address. Switch on *Samsung TV link*, then scan or type the TV's IP and accept the pairing prompt on the TV. A fresh install stays unconfigured until you do. An upgrade keeps its saved address, or otherwise takes the address of the TV that issued the saved pairing token; the link defaults on only when an address is known. Changing the address (after a short pause) moves both the remote socket and the volume link to the new TV.

The header status is more than "ADB is open": the D-pad needs the keyboard helper, the trackpad the mouse helper, and Back / Home / volume the command shell. If one is down the status is *degraded* and names what is not working; Reconnect restarts the helpers. Failed commands (Back/Home, app launch, text entry, launcher restart) show why in the status line rather than failing silently.

## Apps
The Apps folder shows the nine curated apps first (with their artwork, whether or not they were found), then other launchable apps discovered on the box (name derived from the package, generic icon, sorted by name), then a dedicated **Android TV Settings** tile. Discovery is one shell round trip per connect: TV (Leanback) activities are preferred, a phone-launcher-only app is listed only when its package does not look like part of the system image, and the Settings packages are hidden because the Settings tile covers them. Launching uses the discovered activity (`am start -n`); Settings uses its own intent; an app with no discovered activity falls back to `monkey -p`. If discovery fails the status line says "app scan failed" and the extra tiles disappear; if the box lists packages but reports no launch activities (for example a `cmd package` without `query-activities`), it says "app list unavailable on this box". Either way the curated apps and Settings still launch. A launch is reported as started only when Android accepts it.

## Keyboard
Live typing sends each key through the virtual HID keyboard helper. If the helper is not ready the sheet says so ("helper not running" or "not connected") and holds the text until your next edit once it is ready. *Send* types over ADB (`input text`, plain ASCII only). D-pad arrows and OK also use the helper and have **no ADB fallback**: with the helper down the status reads "Virtual keyboard unavailable · reconnect to restore navigation". Back and Home always use ADB. **Remember sent text** (on by default) keeps the last 8 sent texts in the iPhone's UserDefaults (not the Keychain); switch it off before typing passwords (this also clears the list), or delete items / *Clear history*. Typed text is redacted in the app log.

## Gestures
OK fires once per touch and never repeats Enter; a true long-press needs key-down/key-up support in the keyboard helper and is not implemented. Arrow keys auto-repeat while held, and stop on lift, on a system interruption (Control Center, a call, a notification), on a page change, when Now Playing opens, when the app leaves the foreground, and after 30 s. A held mouse button is released on the same interruptions. Two-finger scrolling belongs to the Remote trackpad only.

## Volume
Connection settings → **Volume goes to** picks one output. Volume lives only in the dedicated volume row (slider and mute) on Remote and Now Playing; the Android Remote has no separate volume up/down buttons. Both rows share one slider position, and a device reading never moves the thumb mid-drag. When the chosen output is down the row is disabled, says why, and nothing is sent to other speakers instead.
- **Soundbar, through the TV box** (default): `input keyevent 24` (up) / `25` (down) / `164` (mute) on the box over ADB; the box is expected to pass them to the soundbar over HDMI-CEC. Relative: the soundbar's level cannot be read, so the slider shows no number. A full sweep is 20 key presses and pending presses never exceed one full range. From an unknown position, moving to 0 sends one full-range decrease (the soundbar clamps at its minimum, which makes the position known); moving up only sends the distance the thumb moved. Unavailable: "Connect the TV box".
- **Soundbar, through the Samsung TV**: the TV's remote keys (`KEY_VOLUP` / `KEY_VOLDOWN` / `KEY_MUTE`), one per step of *Soundbar max volume*. Relative, no number. Unavailable: "Samsung TV is off" or "Samsung TV not connected".
- **TV speakers**: the TV's own level over UPnP (RenderingControl, port 9197): absolute 0–100 with read-back; buttons move it by 1 and mute toggles. **UPnP only, with no remote-key fallback**: if UPnP is not answering the row reads "TV volume link not answering".
- The assumed key position is reset only when the active route changes. A 200 OK from the TV or a key accepted by a socket is not proof the speakers moved. Not verified on hardware: that this box forwards its volume keys to the soundbar, and which speakers each Samsung route moves on a given TV.

## Samsung pairing
The pairing token is stored in the Keychain and belongs to the TV that issued it; it is never sent to another address. A prompt that is denied is reported as denied (not as a timeout) and is not raised again until the user reconnects. **Reset Samsung pairing…** in Connection settings asks for confirmation, forgets only that token and the TV it came from, then connects without a token so the TV asks again. Reconnecting the remote and reconnecting the volume link are separate actions. Samsung TLS certificate pinning is not implemented (needs a real TV to validate).

## Recovery
- **Volume row unavailable:** read the reason. "Connect the TV box" → reconnect the box. "Samsung TV is off" → switch on *Samsung TV link*. "Samsung TV not connected" → check the TV's power and address, then *Connect to Samsung TV*. "TV volume link not answering" → *Reconnect volume link only*, or deliberately pick another output.
- **ADB refused / unauthorised:** accept "Allow USB debugging?" on the TV (see Setup), then Connect.
- **Header degraded, or "keyboard helper missing on TV":** tap Connect / Reconnect on the box to recreate the helpers.
- **Samsung TV address changed:** enter or scan the new address; both links follow it. Accept the pairing prompt if the TV asks again; use *Reset Samsung pairing…* only if the old approval is stuck.
- **Add-on needs repair:** a stream add-on whose link is missing from the Keychain (for example after restoring to a new device) shows "Link missing". Open it and use *Add the link again* with the same install link; nothing else changes.

## Limitations
No exact seek or duration (`SEEKING_REPORT.md`); OK has no long-press; discovered apps have no artwork. Continue Watching has no pull-to-refresh (deliberately not implemented: it conflicts with the Discover hero pull gesture); it catches up when you return from a title and when the app returns to the foreground, at most once a minute. Not done: Samsung TLS pinning, authentication of the TV-side loopback helper listener.

## Themes
Logo menu -> **Themes**. Eleven options: Default Dark, Deep Blue, Violet, Amber, Light Glass, Forest, Crimson, Ocean, Glass White, **Adaptive** (accents from the artwork on screen, one shared palette) and **Auto** (follows iOS Light/Dark). Optional drawn ambient backgrounds (Off by default). All colours come from `Theme.swift`; views read `\.glassTheme` and `Color.ink`. Changing theme never touches the models, ADB or helpers.

## Nuvio integration (what it does and does not do)
See `NUVIO_MIGRATION.md` for the verified / unverified breakdown. In short:
- Account: Nuvio's own device-link sign-in (code shown here, approved on nuvio.tv). No password is entered in this app. Session tokens live in the Keychain. Read-only.
- Continue Watching / Recently watched: `sync_pull_watch_progress`, named and posted via Cinemeta (Nuvio's default metadata addon). No library or watchlist row: those RPCs are unverified.
- Opening: `nuvio://detail/...` and `nuvio://search?q=` sent with `am start -p com.nuvio.app`; if Android refuses, Nuvio is launched and the app says so. Never auto-plays.
- Player: unchanged seeking limits (see `SEEKING_REPORT.md`). No exact seek or duration; no companion helper was built.

## Build
Upload the contents of this folder to the GitHub repo (include `.github`) and run **iOS build**. The workflow compiles the ARM32/ARM64 Android helpers with the NDK, generates the project with XcodeGen, builds for the simulator, runs the unit tests, builds for a physical iPhone, bundles and verifies the helpers, and packages `GlassRemote-unsigned.ipa`. Progress notes and checkpoints are in `PHASE-7-NOTES.md` (historical); the current remediation state is in `audit/REMEDIATION_CHECKPOINT.md`.

## Protected
UHID mouse/keyboard protocols and helpers (`glass_uhid_bridge`, `glass_uhid_keyboard`, `glass_tcp_input_server`), ADB identity, Samsung WebSocket pairing and Keychain token, connection recovery.
