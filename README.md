# Glass Remote (iOS)

Native iPhone remote for an ARRIS VIP7802 Android TV box running Glass Launcher, plus a Samsung TV
link. Always Dark Mode, native Liquid Glass on iOS 26+ (material fallback earlier), iOS 16 deployment target.

> **Not built or run.** The latest changes (Discover / Stremio refactor, cleanup) were only statically
> reviewed. Build with the GitHub Actions workflow and use `REGRESSION_CHECKLIST.md` on the real devices.

## Pages (floating dock)
- **Remote**: Android TV or Samsung TV (explicit selector). Android: Apps panel, now playing, Mouse / D-pad, Back / Home / Sources / Search / Keyboard, volume. Samsung: trackpad and a short key set with one Play/Pause button. Header: Glass Remote logo (menu), Box/TV status, power menu.
- **Player**: what the box is playing (title, state, position, transport). Posters come from Cinemeta by title.
- **Discover**: pinned search, Continue Watching and Library from your Stremio account, Cinemeta carousels, genre browsing, detail sheet, "Open in Stremio".

## Stremio integration (what it does and does not do)
- Account: email/password sent to `api.strem.io` (Stremio has no OAuth for apps); only the session key is stored, in the Keychain. Read-only: library, watch history, progress.
- Catalogue and metadata: Cinemeta (search, popular, top rated, genres, details, episodes).
- Opening: documented `stremio:///detail/...` and `stremio:///search?search=` links sent to the box with `am start`.
- Not available: a title's streams, addon-specific personalisation, a documented library deep link, recommendations data.

## Build
Upload the contents of this folder to the GitHub repo (include `.github`) and run **iOS build**. The workflow compiles the Android helpers with the NDK, generates the project with XcodeGen, builds and runs the unit tests.

## Protected
UHID mouse/keyboard protocols and helpers (`glass_uhid_bridge`, `glass_uhid_keyboard`, `glass_tcp_input_server`), ADB identity, Samsung WebSocket pairing and Keychain token, connection recovery.
