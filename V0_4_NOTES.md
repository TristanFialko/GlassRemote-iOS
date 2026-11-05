# Glass Remote v0.4: change report, investigations, device checklist

**Nothing here has been compiled, unit-tested, built in CI or run on a device by the author** (the
authoring environment has no Swift toolchain and no network to the TV). Everything below marked
"device test" or "CI" is unverified until you have done it. CI unit tests are now BLOCKING, so the
first CI run is also the first compile of this code: expect to fix a few compile errors.

Branch: create `v0.4-dev` from your testing branch and commit this tree there. Never main.
Unchanged: bundle id, iOS 16 target, project.yml, helper binaries, assets (one image set added),
ADB identity, mouse/keyboard/TCP helper protocols, Keychain token storage.

## 1. Playback: Play didn't work
Cause (by analysis; device test to confirm): the Player sent KEYCODE_MEDIA_PLAY_PAUSE (85), a
toggle, chosen from a session snapshot polled every 8-10 s. A stale snapshot makes the toggle do the
opposite of the button; a paused Stremio session is also slowest to refresh.
Fix (`RemoteModel+Playback.swift`): explicit Play (126) and Pause (127), idempotent. After each
command the session is re-read; if state didn't change, one retry via
`cmd media_session dispatch play|pause`; if still not, the UI says so (`status`) and logs
`GRLog` lines (request, state before, state after). The UI never shows success on its own: the
button reflects the polled session, with a spinner while a command is pending. The Remote card and
NowPlaying sheet use the same path. Next/Previous/Rewind/FF keep 87/88/89/90.

## 2. Seeking research (result: no verified mechanism; honest elapsed-time UI kept)
- `dumpsys media_session` prints no duration and ADB cannot call SEEK_TO with a position.
  `cmd media_session dispatch` has no seek subcommand.
- Stremio documents `stremio://` deep links (`/detail/{type}/{id}/{videoId}?autoPlay=`, search);
  none is a player control.
- A third-party Stremio-on-Android-TV remote reports Stremio ignores rewind/fast-forward keys and
  that its media-session seek "reached" the session but a real jump was not confirmed. So the
  Player's rewind / fast-forward buttons (89 / 90) may do nothing in Stremio. Device test.
- Not implemented (needs the ARRIS box): D-pad Left/Right as +-10 s while the Stremio player has
  focus; touch-coordinate taps on the timeline (fragile, unsafe).
Nothing is faked: no scrubber, no duration, no remaining time.

## 3. Samsung volume 2-98 %
Found: relative-drag slider needed exact finger travel to hit an end, and a TV reading arriving
>1.2 s after the last change (even mid-drag) pulled the thumb back. Cannot be reproduced without
the TV, so the TV's own behaviour is not ruled out.
Changes: 1 % end magnet (exact 0 / 100); readings never move the slider while a finger is down
or for 2 s after the last change; `VolumeCalibration` maps slider 0-1 to raw `lo...hi`
(default 0-100) and `EndpointLearner` narrows `lo`/`hi` only if, after commanding an end, the TV
reports the SAME value twice within 6 of it (then the thumb reaches both ends and the TV's real
end reads as 0 / 100 %). The range is shown in Connection settings with a reset. Limitation: if a
TV has a hard floor above 0, 0 % means that floor, not mute; use Mute. ADB fallback untouched.
Not done: reading the range from the TV's UPnP service description (URL unverified).

## 4. Samsung remote
- `RemoteTarget` Auto / Android TV / Samsung TV, persisted; glass segmented selector under the
  header. `RemoteRouting` (unit tested) sends each command to ONE device: Auto = navigation and
  media to the box while ADB is up (else the TV); source/channel/guide to the TV; volume keeps the
  existing Samsung-then-ADB preference.
- `SamsungKey` allowlist (KEY_UP ... KEY_CHDOWN) and JSON built with JSONSerialization; the legacy
  `send(name)` maps onto it. Samsung layout: D-pad, Back/Home/Menu/Info/Guide,
  Rewind/Play/Pause/FF/Stop, Ch+/Ch-/Mute/Source/Power; volume uses the existing slider.
- Held arrows repeat `Click` (existing RepeatKey). Press/Release exist in the protocol and are
  in the API but unused; untested on this model.
- Previous/Next are NOT offered: Samsung has no standard track keys (Rewind/FF cover it).
- Per-model key support is unknown: a key the TV ignores gives no error. Device test every key.
- Connection: states off / connecting / pairing / connected / denied / unreachable shown in a
  banner and the header. A denied or unanswered first-pairing prompt (45 s) sets `pairingBlocked`;
  the supervisor then leaves the TV alone until the user taps Reconnect, so the approval prompt is
  not re-raised. Keychain token and the single WebSocket are unchanged; tokens are never logged.

## 5. Remote page
Header: app icon (new `BrandIcon` image set copied from AppIcon.png, 240 px), Box / TV status
capsule (tap: reconnect, else Connection), settings + power in one glass group. Menu button replaced
by Recent Apps (KEYCODE_APP_SWITCH 187): the focused window is compared before / after; if the
launcher visibly did nothing, the Apps page opens instead and a status line says why. If the focus
probe fails nothing is claimed. Android MENU (82) moved to the power menu. Search button opens
Discover and focuses its field (existing search, no second implementation).
Apps hitch: cause = 12+ 1024 px PNGs decoded on the main thread when the grid first appeared, plus
glass corner-radius animation. Now: `AppIconCache` pre-decodes ~200 px bitmaps off-thread at
launch, constant glass radius, opacity-only transition. Launch behaviour untouched. Device test
(Instruments not run).

## 6. Discover
All / Movies / Series glass filter (local, no new request), recent searches (last 8, local),
skeleton loading, empty / error states, larger posters, richer detail sheet, disclaimer that a
listing is not a stream. Cinemeta backend unchanged. Deep link now uses the documented form
(`/detail/movie/{id}/{id}`, `/detail/series/{id}`) and stays behind the experimental switch.

## 7. Liquid Glass
iOS 26 (guarded by `compiler(>=6.2)` + `#available`): `glassBar` (untinted Glass.regular,
interactive), `glassLens` (Glass.clear, light tint), `glassMorph` (glassEffectID), one
GlassEffectContainer per group. Dock = one wide glass bar + one sliding lens (icon over caption),
floating over content (pages scroll under it; `DockMetrics.clearance` keeps controls clear).
Same pattern: device selector, Discover filter, Player transport bar. Surface smoke tint lowered so
refraction shows. iOS 16-25 use material fallbacks. Not visually verified on iOS 26; the
YouTube-style look depends on content passing under the bar (Discover, Apps) more than on Remote.

## 8. Player
Larger poster-aspect artwork (icon fallback), ambient light from the artwork's average colour,
title cross-fade, state badge, one glass transport bar with a prominent Play/Pause. Artwork is
only ever a Discover poster whose title matches the session (the box exposes none).

## Files
New: AppIconCache, PageNavigator, RemoteRouting, RemoteModel+Dual, RemoteModel+Playback,
SamsungRemotePanel, VolumeCalibration, Assets.xcassets/BrandIcon.imageset, this file.
Rewritten: RootPagerView, PlayerPage, DiscoverPage. Edited: GlassStyle, RemoteView,
GlassVolumeSlider, SamsungTV, RemoteModel, RemoteModel+Features, RemoteModel+Stremio,
StremioCatalog, AppsControlsPage, ConnectionSheet, NowPlayingSheet, ArtworkCache,
GlassRemoteApp, Tests, ios-build.yml (unit tests now blocking).

## CI / packaging
Not run. The workflow's helper checks (arm32 + arm64 binaries, resources in the .app, IPA export)
are unchanged; check the run log and the IPA artifact yourself. Run workflow manually on the dev
branch (push trigger is main only).

## Device checklist
1. Build passes (fix compile errors first). 2. Pause then Play from Player and Remote card, three
times each; read the diagnostics log for confirmed / NOT accepted. 3. Try rewind / FF in Stremio.
4. Drag volume to both ends several times; note TV readings; check the learned range.
5. Samsung target: every key; hold arrows; deny the pairing prompt once and confirm it is not
re-shown until Reconnect; confirm Auto never double-sends. 6. Recent Apps on the ARRIS launcher.
7. Remote Search button: Discover opens, keyboard appears. 8. Apps grid expand: smooth?
9. Switch pages repeatedly while Stremio plays; background and reopen; Stremio must not restart.
10. Live typing, mouse, screenshots, Quick Actions, favourites, Samsung Keychain pairing.
11. iOS 26 look vs the reference; iOS 16-25 fallback; Dynamic Type; VoiceOver on the dock.
