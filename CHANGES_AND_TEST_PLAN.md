# Glass Remote – change notes, build-readiness and hardware test plan

Built from the uploaded project (treated as the source of truth). **Not compiled** — no Swift toolchain or Xcode was
available. Let the GitHub Actions workflow (`macos-26`, XcodeGen) be the first real build.

## 1. Established vs hypothesis

**Established (from the code and `media.txt`)**
* `willResignActive` only clears a flag; backgrounding sends no command to the box. Media polling only runs
  `cat /proc/uptime; dumpsys media_session` (read-only). The only automatic device command paths found were none; all
  `input keyevent` calls come from user taps, power actions or Quick Actions.
* A full reconnect (`connect()` -> `teardownSession()`) closes the mouse and keyboard streams and the ADB connection.
* Before this patch, on resume a media poll and the health check ran together (4 s limit), and media polling started
  before the mouse helper finished its READY handshake.
* Stremio's session advertises actions=770 (pause, seek-to, play/pause) and only a description in metadata:
  no duration, no artwork. Android has no ADB command that seeks to an arbitrary position.

**Hypothesis (NOT proven — needs the tests below)**
* The Stremio pause/reload comes from the UHID mouse/keyboard devices being destroyed and recreated on reconnect
  (Android may recreate an activity on an input-configuration change). Not confirmed; the video may instead be
  pausing for another reason.
* The concurrent polling/startup race contributed to the mouse regression. The actual mouse failure was never reproduced.

## 2. Changes
* `GRLog.swift` (new): `os.Logger`, subsystem `GlassRemote`, millisecond stamps. Logs lifecycle, connect/disconnect,
  teardown, recovery health checks, mouse stream failures and each command (typed text is redacted).
* `RemoteModel.swift`: lifecycle logging; no media poll on resume; recovery health check now 8 s x2 before a full
  rebuild; media polling starts after mouse + keyboard are ready; `isBusyConnecting`.
* `RemoteModel+Features.swift`: `pollMedia` skips while connecting/recovering; key logging.
* `MediaSession.swift`: `advertisesSeekTo`, `durationMs` (always nil: no real source exists).
* `NowPlayingSheet.swift` (new): opened by tapping the Now Playing artwork/title. Elapsed time, play/pause, and
  prev/next/rewind/FF only when advertised. **No seek bar** while duration is unavailable; it says so on screen.
  A progress bar appears only if `durationMs` is ever non-nil.
* `Assets.xcassets/stremio_nowplaying.imageset` (new): your transparent PNG, outline removed, centred square.
  Used in the Now Playing card and sheet only. The nine tile assets are untouched.
* `GlassStyle.swift`: `glassSurface` is now satin smoked graphite (flat vertical tone ramp, one even hairline edge,
  soft shadow). No diagonal reflections, glow, bright rims or bubble highlights. Native `glassEffect` is used only for
  `accent: true` (selected Mouse/D-pad pill and the D-pad OK button), with a heavy graphite tint and a matte fallback.
  All fills are static, so nothing was added to the pointer-movement path.
* `RemoteView.swift`: dimmer neutral backdrop, smaller status-dot glow, lifted trackpad, clearer D-pad ring, slightly
  lifted Now Playing card. Layout, proportions, tiles, controls and gestures are unchanged.
* Not touched: Android helpers (`glass_uhid_bridge`, `glass_uhid_keyboard.c`, cursor jar/PNG), ADB identity, the
  mouse protocol/scaling/tap threshold, two-finger scroll, haptics, app list, any device configuration.

## 3. Build-readiness audit (static reading only)
* Fixed: `NowPlayingSheet` used the two-parameter `onChange` (iOS 17+) but the target is iOS 16; now single-parameter.
* Checked and OK: every asset name referenced exists with its file; all `Contents.json` parse; the three bundled
  resources exist and match `project.yml`; new Swift files are picked up by `path: GlassRemote`; APIs used are available
  on iOS 16 (`presentationDetents`, `TimelineView`, `os.Logger`, etc.); braces/parentheses balance in edited files.
* Risks I cannot clear without a compiler: possible Swift concurrency warnings from the new notification closures;
  the `if accent, #available(iOS 26.0, *)` form inside a `@ViewBuilder`; `SwiftADB` is pulled from `branch: main`
  (unpinned). `retroarch_light.imageset` contains nested imageset folders from the original project; Xcode may warn.
* Visual result is unverified: I could not render SwiftUI. The matte direction follows the earlier screenshots in
  `03_DESIGN_REFERENCES`; I did not receive any new reference images in the last message.

## 4. Hardware test plan
**Mouse connectivity**
1. Fresh launch -> status shows "Mouse ready". Move, tap-click, drag, two-finger scroll (vertical + horizontal), white cursor.
2. Switch Mouse/D-pad several times; mouse still works.
3. Lock the phone 10 s, 60 s, 5 min; unlock each time. Note whether mouse works without manual reconnect and how long it takes.
4. Toggle Wi-Fi off/on on the phone; confirm recovery.
5. Capture Console.app logs (filter `GlassRemote`): look for `teardownSession`, `recovery health check`, `mouse` lines.

**Stremio continuity**
1. Play a film. `adb logcat | grep -i -E "stremio|InputDevice|ActivityManager|ConfigurationContainer"` from a PC.
2. Press Home on the phone, wait 30 s, return. Does video keep playing (audio/picture)? Does Stremio reload?
3. Repeat with phone lock for 60 s and 5 min.
4. Match phone log timestamps (`didBecomeActive`, `teardownSession`, `connect()`) against logcat input-device
   add/remove and activity recreate events. If reload coincides with device re-creation -> hypothesis confirmed.
5. Confirm no `cmd` lines (keyevents) appear in the phone log during background/foreground.

**Other**: keyboard sheet, D-pad/Back/Home/Menu, all nine app launches, media buttons, expanded player open/close
and Stremio artwork scaling, Quick Actions, power menu (unverified features stay unverified until tested).

---
# Update — refinement pass 3

## Modified in this pass
* `RemoteView.swift`: the whole compact Now Playing card now opens the player. The tap target is a clear, card-shaped
  layer *behind* the content (`.background` before the glass surface), so Previous / Play-Pause / Next, which are drawn
  on top, receive their own taps and cannot open the sheet. The old title-only gesture was removed. Added an
  accessibility action "Open player". `backdrop` now returns `AmbientBackdrop()`.
* `GlassStyle.swift`: new `AmbientBackdrop` (black canvas, broad charcoal glow centred at ~55% height peaking at
  white 0.095, plus a faint lift at ~78% height under the control surface; edges stay black). Surface tones raised
  slightly (normal 0.14 -> 0.088, elevated 0.19 -> 0.125, was 0.125/0.075 and 0.175/0.115) so panels separate from the
  new background. Edge, shadow and matte treatment unchanged. No blur, material or animation.
* Pointer path: `AmbientBackdrop` has no inputs or state, so SwiftUI does not re-evaluate it on touch moves.
  Note (pre-existing, untouched): `RemoteView` stores `lastPoint` in `@State`, so its body re-runs on each drag
  update. That was already true before this pass; I did not change the mouse code. Real-device smoothness is unverified.

## Genuine Stremio seeking — answer: NOT possible with the interfaces the app has today. Not implemented.
Established from your diagnostics (`media.txt`): the session advertises actions=770 (pause, seek-to, play/pause); the
metadata line prints only `size=4, description=<title>, null, null`; there is no duration anywhere in the dumps.
From general Android 11 knowledge (not verified on this box):
* `dumpsys media_session` never prints METADATA_KEY_DURATION, so no read-only dump can supply a length.
* `cmd media_session dispatch` accepts play, pause, play-pause, stop, next, previous, rewind, fast-forward, mute,
  headsethook. There is no seek-to-position subcommand. You can check this yourself, read-only:
  `adb shell cmd media_session` (prints the usage text).
* Advertising ACTION_SEEK_TO only means Stremio's own controller callback exists; reaching it needs
  `MediaController.getTransportControls().seekTo(ms)` called from a process allowed to open Stremio's session.
What it would take: a one-shot `app_process` Java helper (like the existing cursor jar) that finds the session,
reads METADATA_KEY_DURATION and calls `seekTo`. Unknowns: whether the shell UID may open other apps' sessions on this
firmware (needs MEDIA_CONTENT_CONTROL or a notification-listener grant, which would be a device change I won't make),
and whether Stremio puts a duration in its metadata at all. I also had no Android compiler here (no javac/d8) and you
asked for no experimental commands, so none of this was attempted or tested. The player therefore keeps the honest
elapsed-time display; Rewind/Fast-forward buttons still use the supported key events. No duration is estimated.

## App icon and asset audit
* `AppIcon.appiconset/AppIcon.png`: 1024x1024, unchanged from the project you supplied (md5 b5d99161...). Viewed: it is
  a plain near-black vertical gradient, not a remote render. **No Antigravity render is integrated and the icon was not changed.**
  The Antigravity reference images were not attached to this conversation, so I could not compare them.
* The nine tile assets (`*_dark` / `*_light` imagesets): byte-identical to the supplied project (checked by hash). Only
  addition to the catalog is `stremio_nowplaying.imageset`, used by the Now Playing card/sheet, not the tiles.

## Build status
**Not compiled.** No Swift toolchain was available; this was static inspection only. Checked: new/changed code uses
only iOS 16-safe APIs (`GeometryReader`, `RadialGradient`, `accessibilityAction(named:)`, `contentShape`,
single-parameter `onChange`); asset names and `Contents.json` resolve; `project.yml` and the GitHub workflow are
byte-identical to what you supplied; protected files (UHID bridge, keyboard helper/C source, cursor jar/PNG, ADB
identity, VirtualKeyboard, TwoFingerScroll, SamsungTV, QuickActions, shortcuts, sheets) are byte-identical.
Remaining unverified risks: compile errors/warnings I can't see, native `glassEffect` accent code path (iOS 26 only),
unpinned SwiftADB `main`, and how the backdrop/surface tones actually look on your OLED.

## Additional hardware checks for this pass
1. Tap the Now Playing card on artwork, title, subtitle, empty right-hand space and card margin -> player opens.
2. Tap Previous/Rewind, Play/Pause, Next/FF -> each acts and the player does NOT open. Check with Stremio playing.
3. Drag the sheet down / chevron -> closes. Nothing playing -> card tap does nothing.
4. Compare surface separation on OLED in a dark room; confirm outer edges still read black and nothing looks grey.
5. Drag the trackpad quickly for 30 s: cursor smooth, no stutter versus the previous build.
6. Re-run the mouse connectivity and Stremio continuity sequences in sections above.

---
# Update — pass 4 (consolidated final refinement)

## A. Verification of the previous pass (static reading; not run on a device)
* Whole card tappable: yes by construction. A clear card-shaped tap layer sits in `.background` behind the content; the
  artwork, text and empty card area have no gesture of their own, so they fall through to it. Previous/Play/Next are
  `Button`s drawn on top and take their own taps. **Unverified:** tapping a *disabled/dimmed* media button may fall
  through and open the player (SwiftUI hit-testing of disabled controls); check on device.
* Sheet: `.sheet(isPresented:)`, `.large` detent, drag indicator, chevron button, and auto-close when the session ends.
  Artwork is `scaledToFit` in a 1:1 frame (no crop/stretch). No scrubber is shown (see C).
* `AmbientBackdrop`: static, input-less view; panel tones 0.14->0.088 / elevated 0.19->0.125 against a centre of 0.095
  fading to black at the edges. Numerically the panels sit slightly above the glow at the top and about level with it at
  the bottom, so separation relies on the hairline edge and shadow as designed. I could not render SwiftUI, so how it looks
  on your OLED is unverified; if you want more separation, raise the backdrop's first stop (0.095) a little, not the surfaces.
* Nine tiles and AppIcon were unchanged by the previous pass; the tiles are now deliberately replaced (section B).

## B. Nine tile icons — supplied PNGs WERE available and are integrated
All nine transparent PNGs from your first message were present: netflix, youtube, stremio, retroarch, primevideo, disney,
moonlight (the Sunshine logo, used by the Sunshine tile), spotify, rhenium.
* Replaced in both `<name>_dark.imageset` and `<name>_light.imageset` (same file in both; the app only reads `_dark`).
* Your files carry a faint, near-black rounded "card" frame (8 of 9). It is outside the logos, so cropping to each logo's own
  bounds removes it without touching any logo pixel. No border, background or recolouring was added.
* Each logo: uniform scale (aspect preserved, max x1.30), fits 80% of tile width / 46% of height, centred on a transparent
  1024x1024 canvas (checked to within 3 px). Result: wide logos span ~80% of the tile, RetroArch ~69%, square marks ~46%.
* Tile view code, order, labels, package names and launching are untouched. Tile glass/background (`ultraThinMaterial`,
  clip, stroke) unchanged, so the transparent artwork now shows that glass behind it instead of the old opaque black square.
* `stremio_nowplaying` (Now Playing only) is still derived from your Stremio PNG.
* Nested duplicate imagesets inside `retroarch_light.imageset` removed (they re-declared the `*_dark` names). Originals and the
  old tiles are archived in `AssetSources/` (not compiled).

## C. Genuine Stremio seeking — conclusion: not possible with the app's current interfaces; NOT implemented
Evidence gathered (docs + your dumps; nothing was sent to the TV):
1. `cmd media_session dispatch` keys are play, pause, play-pause, mute, headsethook, stop, next, previous, rewind, record,
   fast-forward (AOSP `MediaShellCommand` usage). No seek-to, no position argument.
2. `dumpsys media_session` (your `media.txt`) prints playback position and actions but metadata only as
   `size=4, description=<title>`. No duration, so there is no read-only duration source.
3. Seeking to an arbitrary position means calling `MediaController.TransportControls.seekTo(ms)`. Android's documentation says
   `MediaSessionManager.getActiveSessions` needs `MEDIA_CONTENT_CONTROL` or an enabled notification listener, otherwise it
   throws `SecurityException`. Whether the ADB shell UID holds MEDIA_CONTENT_CONTROL on this firmware is **unknown**.
   Granting a notification listener or any permission is excluded by your rules.
4. A one-shot `app_process` helper (like the existing cursor jar) is the only candidate route. It would be new device-side
   code, needs an Android toolchain to build (none here), and its success depends on (3) plus Stremio both publishing a
   duration and honouring `seekTo`. None of that can be established without running something on the box.
5. No alternative supported interface found. Key events give only relative steps (the existing Rewind/Fast-forward).
Therefore: no slider, no estimated duration; the player keeps honest elapsed time. `durationMs` stays nil and the code would
only show a progress bar if a real duration ever exists, and still never a draggable one.
**Optional probes for you to run yourself, read-only, only if you approve** (I have not run them):
`adb shell cmd media_session` (prints usage) and `adb shell dumpsys package com.android.shell | grep -i MEDIA_CONTENT_CONTROL`.
If shell holds that permission, the next step would be a read-only helper that prints Stremio's metadata keys (duration yes/no),
and only then a seek test, with your explicit approval at each step.

## D. Rendering optimisation in the mouse view (no behaviour change)
`RemoteView` kept the drag position in `@State CGPoint?`, so every touch-move re-ran the whole view body. It now lives in a
plain reference box (`PointerBox`) read through a computed `lastPoint`, so moves no longer invalidate the view. Same values,
same order; `remote.mouse(...)`, the x2 scaling, 8-pt tap threshold, 45 ms click, scroll handling and haptics are untouched.
Unverified on device: please check cursor feel.

## E. Other files modified in this pass
`RemoteView.swift` (PointerBox; earlier card-tap/backdrop changes), `GlassStyle.swift` (unchanged this pass), nine
`*_dark/_light` tile PNGs, `retroarch_light.imageset` (nested folders removed), `AssetSources/` (new, uncompiled).
**AppIcon: unchanged** (`AppIcon.png` identical to the supplied project; a plain dark gradient, no remote render integrated).
Unchanged and byte-identical: UHID bridge, keyboard helper/C source, cursor jar/PNG, ADB identity, VirtualKeyboard,
TwoFingerScroll, SamsungTV, QuickActions, shortcuts, sheets, `project.yml`, the GitHub workflow.

## F. Build status
**Not compiled; static inspection only** (no Swift toolchain here). Checked: iOS 16-safe APIs only (no iOS 17+ patterns found),
all `Contents.json` valid and resolving, no nested imagesets left, resources match `project.yml`, workflow unchanged, braces
balanced in new/edited files. Remaining risks: compile errors I can't see; `guard let self` needs Swift 5.7+ (Xcode 26 is fine);
Swift concurrency warnings (project is Swift 5 mode); `glassEffect` accent path only builds/runs on Xcode 26 / iOS 26+;
SwiftADB is pulled from unpinned `main` and patched by the workflow with regexes that could break if upstream changes;
tile and backdrop appearance unseen on a real display.

## G. Hardware regression plan (condensed)
1. Connect; "Mouse ready". Move, tap-click, drag, two-finger scroll both axes, white cursor, Mouse/D-pad switching, fast
   dragging for 30 s (feel vs previous build).
2. Lock 10 s / 60 s / 5 min and Home-swipe away; return. Mouse works without manual reconnect. Capture Console logs (`GlassRemote`).
3. Stremio playing + `adb logcat | grep -i -E "stremio|InputDevice|ActivityManager"`: repeat 2; does video keep playing or only
   the UI reload; correlate with `teardownSession` / `connect()` log lines. No `cmd` keyevent lines during background.
4. Tiles: all nine show correctly, centred, balanced; each launches the correct app (Netflix, YouTube, Stremio, RetroArch,
   Prime Video, Disney+, Sunshine, Spotify, Rhenium). Apps grid collapses after launch.
5. Now Playing: tap artwork, title, empty space -> sheet opens; tap Previous/Play/Next -> acts, sheet does not open; try the
   dimmed state too; drag/chevron closes. Stremio artwork centred, uncropped. Elapsed time ticks; no scrubber.
6. Keyboard sheet, D-pad/OK, Back/Home/Menu, volume (ADB and Samsung path if enabled), Quick Actions, power menu, haptics.
7. Look at the backdrop/panels on the OLED in a dark room; nothing grey, outer edges black.

---
# Update — mouse + Samsung volume stabilisation
Baseline: assembled project + the five newer Swift files from files.zip (RemoteModel, RemoteModel+Features, SamsungTV, ConnectionSheet, RemoteView), then:
* Mouse: coalesced pointer motion (`mouseMove`/`mouseButton` in RemoteModel.swift), sub-point carry, 3 pt dead zone, tap = release within 0.45 s and <8 pt, no drag (removed) (RemoteView.swift).
* Cursor: white PNG started via files.zip `startCursor()` (the assembled project bundled the files but never launched them).
* Volume: new `SamsungVolume.swift` (UPnP RenderingControl, port 9197, raw NWConnection HTTP): real GetVolume polling (1 s, single in-flight, backoff), absolute SetVolume with latest-wins, slider follows TV readings, falls back to existing key paths. NOT compiled, NOT tested on hardware.
