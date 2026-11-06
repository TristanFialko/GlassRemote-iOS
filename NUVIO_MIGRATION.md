# Stremio to Nuvio migration (Phase 4.3)

Nothing here was compiled, run, or tested against a live Nuvio backend or a TV box. See "Validation".

## Sources used
- Official `NuvioMobile` @ 0f85c95: `core/auth/DeviceLinkAuthRepository.kt` and `features/watching/sync/SupabaseProgressSyncAdapter.kt` (supplied by the project owner).
- `NuvioTV` issue #2235 (intent extras `contentId`/`contentType` on `MainActivity`; deep links proposed, "no playback auto-start").
- Third-party reports (secondary, marked below): `https://nuvio.tv/config.js` serves the public Supabase config; `nuvio://movie|series/<imdb>` works.

## Verified from official source
| Item | Detail |
|---|---|
| Sign-in | RPC `start_device_login_session` {p_device_nonce, p_redirect_base_url, p_device_name, p_device_type=mobile} -> {device_code, user_code, verification_uri_complete, poll_interval_seconds (default 3)} |
| Poll | RPC `poll_tv_login_session` {p_code, p_device_nonce} -> {status}: `pending`, `approved`, anything else = expired. Interval clamped 2-10 s, max 120 polls, 3 consecutive failures abort |
| Exchange | function `tv-logins-exchange` {code, device_nonce} -> {access_token, refresh_token, token_type, expires_in, user?} |
| Progress | RPC `sync_pull_watch_progress` {p_profile_id[, p_since_last_watched, p_limit]} -> {content_id, content_type, video_id, season, episode, position, duration, last_watched, progress_key}. Position/duration are ms (`lastPositionMs`, `durationMs` in the push side) |

## Not verified (isolated; fails soft)
- Backend URL and anon key: read at runtime from `https://nuvio.tv/config.js` (third-party report), cached locally, never hard-coded. If the file's format differs, sign-in reports "Couldn't read Nuvio's server configuration". Fix = adjust `NuvioConfigParser`.
- `sync_pull_profiles` arguments/rows: called with `{}`, tolerant decode, falls back to profile 1.
- Token refresh: standard Supabase GoTrue `/auth/v1/token?grant_type=refresh_token` (single-use refresh tokens, serialised in `NuvioSessionManager`). Logout: `/auth/v1/logout?scope=local`.
- Library, watchlist, watched-item RPCs: not provided, so NOT implemented. Discover has no library/watchlist row and says so.
- Deep links / exported status of Nuvio's activity: unknown. The app sends one VIEW intent restricted to `com.nuvio.app` and reports Android's answer; on refusal it launches Nuvio and says so. `com.nuvio.app` is the Play Store id from the NuvioTV README; sideloaded builds may differ.
- 95 % "finished" threshold is this app's choice.
- Titles whose content id is not an IMDb id (e.g. `kitsu:`) are skipped: Cinemeta cannot name them.

## Playback (unchanged, deliberately)
No Nuvio remote-control API was found. Exact seek-to-position and duration still need an on-box helper holding a `MediaController` (see `SEEKING_REPORT.md`); that was NOT built because it cannot be compiled or tested here, and the existing code still never fakes either. Play/pause, relative seek with confirmation, volume: untouched.

## YouTube thumbnails
Not implemented. `dumpsys media_session` exposes no artwork URI or video id, and guessing ids from titles is excluded. The existing screencap-based fallback and app icon remain. The YouTube launcher and controls were not touched.

## Changes
- Added: `NuvioAccount.swift`, `NuvioAccountSheet.swift`, `RemoteModel+Nuvio.swift`, `NuvioTests.swift`, Nuvio monogram assets (neutral placeholder, NOT Nuvio's logo; replace with official brand art).
- Renamed/changed: `StremioCatalog` -> `CinemetaCatalog` (+ `CinemetaMetaCache`), `StremioTitle` -> `MediaTitle`.
- Modified: Discover page/detail/collection, Player page (poster ~10 % larger, landscape card when only backdrop art is known), `ArtworkCache`, app list/shortcuts.
- Removed: Stremio account/login (email+password to api.strem.io), Stremio deep links, Stremio assets, Stremio tests.
- Clipping fix: horizontal `ScrollView` clipped to its frame, which was exactly chip-height, so pressed interactive glass was sliced. `UnclippedHScroll` adds inner vertical room, cancels it with negative outer padding, and uses `scrollClipDisabled` on iOS 17+.
- Not touched: input protocols, helpers, ADB identity, Samsung code, themes, `Seeking.swift`, `MediaSession.swift` logic.

## Validation
Done: brace/paren balance on all Swift files, search for leftover Stremio symbols (none outside intentional Cinemeta/Stremio-addon-protocol comments and old-package test fixtures), manual type/signature review. Not done: compile, unit tests, CI, device tests.
