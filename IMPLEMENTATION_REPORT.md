# Implementation report: UI refactor and Google Play

## Build status (read this first)
**Nothing was compiled or run.** This environment has no Xcode, `xcodebuild`, `xcodegen` or Swift toolchain, and no network. So: no XcodeGen run, no simulator build, no test run, no device test. What was done instead: a manual read-through of every changed file, a brace/bracket balance check (clean apart from one parenthesis artefact in `DiscoverPage.swift` that is identical in the original file and comes from the checker, not the code), and greps confirming no leftover references to `.auto`, `AppsControlsPage`, `.apps` page case or the Android MENU key. Expect to fix a few compile errors on first build. The project's CI workflow (`.github/workflows/ios-build.yml`) is the quickest way to find them. Run XcodeGen, then build and test.

## UI changes
- **Header**: menu button (top left, replaces the app icon); Box/TV capsule is status-only (no tap action); power button kept. The duplicate sliders button is gone.
- **Menu** (`GlobalMenu.swift`): Device (Connections and devices; Reconnect Android/Samsung only when needed), Samsung TV (TV keys submenu: Input menu, Guide, Info, TV menu, Channel up/down, Stop; Volume through Samsung TV toggle; or "Set up"), Advanced (TV screenshot, Device information sheet with connection details and diagnostics).
- **Power**: stays in the header power button (Standby, Wake, Restart launcher, TV power, Turn off box and TV, Restart TV box last). I deliberately did not repeat these in the menu, to avoid duplicate entry points.
- **Selector**: Android TV / Samsung TV only. Auto removed from enum, routing, persistence, UI and tests. A saved "auto" restores as Android TV. Otherwise the last explicit choice is kept. A disconnected selected device never falls back to the other.
- **Android remote**: compact mode selector + a single bolt Quick Actions menu in one row (run actions, edit); apps launcher row slimmer; Now Playing card slimmer (controls keep 44 pt targets); pad has a 230 pt minimum and layout priority, D-pad circle cap raised 250 -> 340. Nav buttons keep 48 pt. Favourites (long-press) sort first in the launcher. Mouse protocol, gestures and D-pad code are untouched.
- **Android Menu key removed** from the UI, key tables and HID map. Quick Actions: saved MENU steps are removed on load by `QuickActionStore.migrate`, the action itself is kept, and a dismissible notice appears in the editor. MENU can no longer be sent from a Quick Action.
- **Samsung remote**: D-pad and selector deleted; trackpad is permanent with a 220 pt minimum and priority; subtler hint; 7 keys (Back, Home, Mute / Rewind, Play, Pause, Fast-forward). Play and Pause are separate keys because the TV does not report state, so a single toggle would be a guess. Samsung and Android keys share one `RemoteKeyButton` (same size, weight, glass, `HomeGlyph`).
- **Discover**: placeholder shows a title and film/TV symbol; if Cinemeta has no poster (or it fails) a Metahub poster URL built from the IMDb id is tried (`images.metahub.space`, the host Stremio's ecosystem uses; **unverified here**); then the placeholder. Search, filters and layout are unchanged.

## Google Play tab (replaces Apps)
Capabilities, as actually implemented:
- **Search on the TV**: sends one `am start -a VIEW -d 'market://search?q=<encoded>&c=apps' -p com.android.vending` over the existing ADB link; the TV shows Play's own results.
- **Open a listing on the TV**: `market://details?id=<package>` for a curated list of 15 well-known Android TV apps (also filtered locally as you type) or any validated package id.
- Result is reported as "accepted by Android", never "opened". Not connected, store missing, rejected and invalid-query states are handled.
- **Not implemented, on purpose**: results inside the iPhone app (Google Play has no public catalogue-search API; the alternatives are scraping or unofficial scrapers, which are fragile and may breach Google's terms) and **remote install** (not possible outside the Play Store UI; the person presses Install on the TV). The page says so.
- Unverified on the ARRIS VIP7802: that its Play Store handles `market://search` and `market://details`; the curated package ids (a wrong one shows Play's not-found screen).

## Where the old Apps page went
Launcher + favourites: Remote page. Quick Actions: Remote page (bolt menu + editor). Samsung TV controls / toggle: menu and power button. Device info and diagnostics: Device information sheet. Connection and discovery: Connections and devices. Restart app: long-press an app in the launcher.

## Files
- **Added**: `GooglePlay.swift`, `GooglePlayPage.swift`, `GlobalMenu.swift`, `References/UI/` (6 screenshots + README), this report.
- **Removed**: `AppsControlsPage.swift`.
- **Changed**: `RemoteRouting.swift`, `RemoteModel.swift`, `RemoteModel+Dual.swift`, `RemoteView.swift`, `SamsungRemotePanel.swift`, `DirectionalTrackpad.swift`, `GlassStyle.swift`, `AppPage.swift`, `RootPagerView.swift`, `QuickActions.swift`, `QuickActionEditor.swift`, `VirtualKeyboard.swift`, `StremioCatalog.swift`, `ArtworkCache.swift`, `DiscoverPage.swift`, `Tests/GlassRemoteTests/GlassRemoteTests.swift`, `README.md`, `REGRESSION_CHECKLIST.md`.
- `project.yml` is unchanged (new files are picked up from `GlassRemote/`; References are not bundled).

## Tests (written, not run)
Removed the Auto routing tests. Added: two targets only; legacy "auto" restore; no cross-device fallback; Samsung/Android routing per kind; Samsung layout has no D-pad keys and loses no old function; menu/power structure and no duplicates; Quick Action MENU migration (kept action, notice, no HID path); Google Play link encoding/shell-injection safety, package validation, intent target, honest outcomes, curated list; fourth tab is Google Play; poster fallback. Existing Android D-pad/HID tests are untouched. Not covered by unit tests: SwiftUI layout sizes and the actual ADB launch, which need a device.

## Remaining issues / to check on device
Compile; pad sizes on small iPhones (SE) and Pro Max; menu rendering on iOS 26 vs older; Play intents on the ARRIS box; Metahub fallback; the "Recent apps" fallback now expands the launcher instead of changing page. The header has no Android Menu or standalone reconnect tap any more, so reconnecting is in the menu.
