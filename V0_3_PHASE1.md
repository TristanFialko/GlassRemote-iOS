# Glass Remote v0.3, Phase 1

Branch: testing only. Not built or run in the authoring environment (no Swift toolchain, no
network): every item marked "device test" or "CI" below is unverified until it has been.

## Investigation results (MediaSession)
Source: `MediaSession.swift` parses `dumpsys media_session` (read-only, polled every 8-10 s).
| Item | Available? |
|---|---|
| Title | Yes (`metadata: description=`), unchanged `title` field |
| Subtitle / episode | Probably: Android prints "title, subtitle, description". New `headline`/`subtitle` fields; **device test** against a real Stremio session |
| Artwork | No. dumpsys prints no bitmap or URL. Player uses the app icon, or a Discover poster when the session title matches the title launched from Discover |
| Position, state, speed | Yes |
| Duration | **No** (`durationMs` stays nil). No progress bar, no remaining time |
| Supported actions | Yes (bitmask); controls enable only when advertised |
| SEEK_TO | May be advertised, but ADB has no way to invoke it with a position. **No seeking implemented** |
Rewind / fast-forward send keycodes 89 / 90; what they do (skip distance) depends on Stremio.

## Architecture
- `RootPagerView` keeps all four pages alive in one offset HStack. Page changes only change an offset: no view teardown, no helper, ADB, HID or polling changes.
- Gesture policy: Remote page never pages from its body. Swipe works from the dock and 16 pt edge strips (in the side padding, outside every control). Pages 2-4 page on a horizontal-dominant swipe anywhere. No page gesture sends TV input.
- `RemoteView` is unchanged. Only the app entry point and a bottom dock (safe-area inset) are new.
- Pages: `PlayerPage` (reads `remote.media`, sends media keys), `DiscoverPage`, `AppsControlsPage`.
- Shared services: `ArtworkCache` (NSCache + URLCache, https only), `PlayerArtworkStore`, `StremioCatalog`, `AppFavourites`.

## Discover
- Search: Stremio's public Cinemeta catalog from the phone (not the TV). Unverified without network: **device test**.
- Dictation: system keyboard microphone. No Speech framework, no new permissions.
- Launching: experimental `am start -a VIEW -d stremio:///detail/<type>/<imdb id> -p com.stremio.one`, off by default behind a switch, one intent per tap, id strictly validated. Whether this Stremio build handles it is **unknown**; the UI says so and shows Android's reply.

## Helper lifecycle
No changes. No HOME/BACK/PAUSE/STOP is sent anywhere new. Mouse and keyboard protocols untouched.

## Modified files
New: AppPage, RootPagerView, PlayerPage, DiscoverPage, AppsControlsPage, ArtworkCache, StremioCatalog, AppFavourites, RemoteModel+Stremio, this file.
Changed: GlassRemoteApp (root view), MediaSession (subtitle fields), Tests (new test classes).
Earlier fix: KeyboardSheet, Tests (Live Typing).
Unchanged: project.yml, bundle id, deployment target (iOS 16), workflow.

## Known limitations
- No scrubber, duration or seeking (see above). No real artwork from the session.
- Remote page can't be swiped from its body, by design (trackpad conflict).
- Favourites are an unordered-by-user list in tap order; no drag reordering yet.
- "Find devices" opens the existing Connection sheet rather than a second scanner.
- CI runs unit tests with `continue-on-error`; that flag is untouched.

## Device-testing checklist
1. Launch: lands on Remote; status connects as before.
2. Swipe from the dock and edges; confirm trackpad/D-pad drags never change page and pages never move the cursor.
3. Switch pages repeatedly while Stremio plays: no restart, no cursor/keyboard helper restart in Connection status.
4. Background and reopen on each page.
5. Player: title/subtitle/state/elapsed correct; disabled controls match advertised actions.
6. Discover: search, poster loading, detail sheet; with the switch on, try a deep link and record the reply.
7. Apps: launch, favourite, restart, Quick Action, Samsung buttons.
8. Dynamic Type at the largest sizes; VoiceOver page switching.
9. Live Typing stays on while typing, connected and disconnected.
