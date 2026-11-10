# Glass Remote Phase 5: notes

Checked by the iOS build workflow on the `Phase-5` branch (simulator build, unit tests, unsigned device
build). The layout fixes still need a quick look on the phone; nothing here was run on the TV box or Samsung TV.

## Discover
- **Featured hero overflowed the screen.** A 16:9 backdrop filled to the hero's 210 pt height is wider than a
  phone's content width, and as the hero's base view it stretched the whole card past the right edge of the
  screen. The artwork now sits in an overlay on a fixed-size base, so the card is always the screen width and
  the backdrop is cropped inside it.
- **Hero meta line.** "Movie  · 2026" had a wide gap before the dot and the rating had none. It is now one
  line of text with the same spaced dot between every part ("Movie · 2026 · ★ 7.4"), and no dangling dot
  when the year is missing (`DiscoverMetaLine`, covered by `Phase5Tests`).
- **Posters and the detail backdrop keep exact frames.** Poster cards (2:3) and the detail sheet's backdrop
  (16:9) use the same base-plus-overlay layout, so artwork with a slightly different shape can't resize them
  once it loads.

## Samsung remote
- The trackpad's VoiceOver hint pointed to arrow buttons that this surface doesn't have. It is now a single
  VoiceOver element: activate = OK, actions Move up / down / left / right, scrub (escape) = Back.
- The trackpad hint text uses the same colour as the Android trackpad hint (it was much fainter in dark mode).
- "Connecting to the TV…" shows a small spinner instead of a static icon.

## Build and CI
- SwiftADB is pinned by revision in `project.yml` (main's head since 2026-06-17, the commit the green Phase-5
  runs built against) instead of following `main`.
- The workflow also runs on pushes to `Phase-*` branches.
- xcodebuild output is saved to `build/ci-logs/` (part of the failure log artifact). When a run fails, compiler
  and test errors become annotations on the run page and are listed in the job summary.

## Not changed
Connections, ADB identity and keys, Samsung pairing and token storage, the UHID helpers, mouse and cursor
handling, and seeking are untouched.

## Worth checking later
- `GlassRemote/Assets.xcassets/retroarch_light.imageset/` contains nested `*_dark.imageset` folders (disney,
  moonlight, netflix, prime-video, retroarch, rhenium, spotify, stremio, youtube). They look like leftovers
  from an upload and may not be the images the app actually uses.
