# Phase 7 notes (research, decisions, limitations)

Branch: Phase-7 (from phase-6-ui-nuvio-rebuild at adc2ec0). PR #2 is tracking-only and must not be merged.

## What this branch adds

- Four tabs: Remote, Player, Discover (unchanged names and order) plus Profile.
- Dock: the Phase 6 magnifying lens is removed. The selection is a glass bubble with a moving specular sheen (DockSheen) that follows the drag/selection, on top of the existing native glass (iOS 26 glassEffect where available, material fallback below). Shared springs live in DesignSystem/Motion.swift, and every one resolves to a short fade under Reduce Motion or the per-profile "Reduce interface motion" switch. No continuous animations run while idle.
- Profiles (Profiles/): multiple profiles with any name and an optional photo from the system photo picker (PhotosPicker runs out of process, so there is no library permission prompt). Photos are downscaled to 512 px JPEG off the main thread. The last active profile is restored at launch. Each profile has its own theme, motion preference, poster-orientation preference and add-on list. TV pairings are shared hardware state and are never duplicated per profile.
- Profile tab: overview with switcher, TV Connections (status first, one action per device, the proven Connection screen for detailed pairing), Add-ons, Devices (device info moved here), Appearance, General (Nuvio account, privacy, accessibility, about). Landscape puts the profile card beside the sections.
- Add-ons (Addons/): Stremio-protocol client. It handles manifest URL validation (https only, http allowed only for LAN hosts, no user:password links, stremio:// accepted), tolerant manifest and stream decoding (bad entries are skipped rather than rejecting the response), resource/type/idPrefix matching, compatibility notes, duplicate detection, update-in-place when a new configured link is added, enable/disable, reorder, refresh and removal. Full links (which often contain personal tokens) are stored only in the Keychain; the UI shows the host only.
- Play (Playback/StreamPickerSheet.swift): Play asks the profile's enabled stream add-ons (in parallel, cancellable, per-episode for series), groups results by add-on with quality filters, and sends the chosen stream to the TV. "Open in Nuvio" is always the first option, and every path ends with a visible result message.
- Discover (Discover/): a full-width cinematic hero (DiscoverHero.swift). Card sizes and shapes come from DiscoverLayout.swift (DiscoverMetrics for portrait/landscape, DiscoverCardShape for the profile's Automatic/Portrait/Landscape preference, which is chosen in Profile > Appearance). Live search is debounced while typing and ranked by SearchRanking.swift.
- Detail page (DiscoverDetail.swift, DetailSections.swift, TitleDetailModel.swift, TitleMetadata.swift): the Cinemeta meta parser now reads app_extras cast (character names, https-only portraits), directors, writers, certification, trailerStreams and episodes. The page has a masked backdrop hero, a poster, a facts line (year, runtime, seasons, rating, certification), genres, an expandable overview, a credits grid, circular cast portraits with initials as a fallback, trailer thumbnail cards, a season/episode list for series, and "More like this" by genre. That row follows the poster-orientation preference.
- Remote D-pad (Remote/GlassDpad.swift): a glass disc with four wedge-shaped hit areas, so the whole ring is touchable and diagonals go to the nearest arrow. A pressed wedge lights in the theme accent, and OK is a raised glass pebble. RepeatKey gained an optional hit shape and press callback. Tap/hold/repeat timing, haptics, the ADB key names (UP/DOWN/LEFT/RIGHT/OK) and the swipe-to-arrow gesture are unchanged.
- Tests: Phase7DiscoverTests, Phase7DetailTests (meta parsing, facts, credits, similar titles, layout) and Phase7DpadTests (key names, wedge hit geometry).

## Nuvio research (from NuvioMedia/NuvioTV source)

- app/src/main/AndroidManifest.xml: the exported MainActivity handles the nuvio:// and stremio:// schemes only. There is no http(s) or video/* intent filter.
- core/deeplink/DeepLinkParser.kt: nuvio://detail/{type}/{id} and nuvio://watch/{type}/{id} open the title screen; stremio://{host}/.../manifest.json installs an add-on. No deep link accepts a stream URL or starts playback.
- Result: a direct stream handoff into Nuvio is not possible. GlassRemote therefore (1) opens the title in Nuvio (existing Phase 6 path), (2) sends direct http(s) streams to the TV's default video player with a generic VIEW intent (video/*), and (3) can install an add-on in Nuvio through the stremio:// link. Torrent streams and streams needing proxy headers are listed but marked as not sendable.

## Known limitations / not yet verified

- This environment has no Xcode, simulator or network. Builds and unit tests run in GitHub Actions CI (macos-26) only. Nothing here has been verified on a physical iPhone or TV yet; that needs the user.
- Real Liquid Glass rendering, rotation, safe areas and touch feel need on-device checks.
- Plain-http LAN add-ons may be blocked by App Transport Security (no NSAllowsLocalNetworking key is set).
- Still open on this branch: a visual and landscape pass on the Player tab; checking that the other poster surfaces (search results, collections) follow the orientation preference; CI results for the latest commits; on-device checks of the card-to-detail transition, the D-pad feel and Liquid Glass rendering.

## Phase 7.1 polish pass (branch Phase-7.1, child of Phase-7)

Progress is logged here as each item lands. Nothing below has been checked on a physical iPhone or TV.

### Done
- Add-on install identity (Addons/AddonStore.swift, AddonClient.swift, AddonsPage.swift). Each install has its own UUID (installID), separate from the manifest id, so two differently configured links of the same add-on (for example two Torrentio configurations) can be installed side by side. Each install has its own Keychain item (addon.<profile>.<install id>), enabled state and position. The same link twice is still a duplicate. "Replace link" on the add-on page swaps one install's link in place after reconfiguring it; a link for a different add-on is rejected there. When an add-on is installed more than once it is numbered by install order ("Torrentio 1", "Torrentio 2") in the list, the detail page, the Play sheet groups and the failure lines. Lists saved before this change are migrated on load: each record gets an install id and its Keychain item is moved from the manifest-id account to the install-id account. Full links are still only in the Keychain; the saved list holds the redacted host. Tests: Phase71AddonIdentityTests (side-by-side install, duplicate link, replace, legacy migration); the Phase 7 store test now uses install ids.

- Mouse / D-pad switch pressing Up (Remote/GlassDpad.swift, RemoteView.swift). Cause: each arrow's touch area was a wedge 1.42 radii long, so Up reached past the top of the pad and over the selector; the pad is drawn after the selector, so it won those touches. Each arrow now owns exactly its quarter of the pad's square (DpadQuadrant). D-pad keys and swipes are also ignored while a selector is being touched and for 0.35 s after the mode changes (RemoteInputGuard).
- Filter swipes changing page (new PagerExclusion.swift, GlassStyle.swift, RootPagerView.swift). Cause: the pager only knew a selector was in use once the selector's SwiftUI gesture reported, which inside Discover's scroll view could come after the pager had begun. Every scrub selector now marks its frame with an invisible UIKit view, and the pager refuses touches that land there (6 pt slop) before any movement.
- Search opening the hero title (DiscoverPage.swift). Cause: only the text line of the search field took touches, so taps on the rest of the capsule and in the header's gaps fell through to the hero's tap-to-open. The whole capsule now focuses search and the header swallows stray taps.
- Detail close button (DiscoverDetail.swift). Likely cause: a 36 pt target on interactive glass inside a sheet that can be dragged down, so a slightly moving tap became a drag. It is now a 44 pt target on non-interactive glass and closes by clearing the presenter's state (with dismiss() as the fallback). Needs confirming on a device.
- Tests: Phase71GestureTests (D-pad quarters stay inside the pad and cover all of it, the mode-switch guard, pager exclusion zones).
- Not fixed here: a sideways swipe on the Discover hero still both changes the featured title and pages. That is part of the hero swiping item below.

### Still to do on this branch
- Remote redesign (portrait and landscape), moving Themes/Connections/Devices into Profile.
- Discover/search/detail polish, Liquid Glass material variants, theme and motion polish, performance pass.
- CI: results for each Phase-7.1 push need checking in GitHub Actions.

## Phase 7.2 completion pass (branch Phase-7.2, child of Phase-7.1 at 02de88f)

Phase-7.1 is left as it was. Nothing below has been checked on a physical iPhone or TV.

### Done
- D-pad hit geometry (Remote/GlassDpad.swift). CI run #157 failed one test: Phase71GestureTests.testEveryPointOnThePadBelongsToAnArrow, point (5, 5). Cause: the four DpadQuadrant triangles share their edges on the exact diagonals, and (5, 5) lies on one, so Path.contains gave it to neither. The test also checked the square's corners, which are not part of the visible pad. Decision: the visible disc is the touch area. DpadQuadrant is removed. Each arrow's hit shape is now its quarter of the disc (DpadWedge, inner 0, outer 1), and DpadHitPolicy states the rule: OK inside the OK touch radius, nothing beyond the pad's radius (corners included), otherwise the nearest axis by |dx| / |dy|, with exact diagonal ties going to the horizontal arrow. The hit area still never leaves the pad's frame, so the selector above can't fire Up.
- Tests: the square-grid test is replaced by testEveryPointOnTheVisibleRingBelongsToExactlyOneArrow (shape and policy must agree on every sampled ring point). New tests cover screen-coordinate directions, the OK centre, inactive corners, points just outside the pad, diagonal ties and scaling. Phase7DpadTests uses the real hit shape now (a point outside the disc is inactive).

### Next
- Check CI for this push (tracking PR for Phase-7.2, do not merge).
- 2.3: replace RemoteInputGuard's 0.35 s timing with explicit touch ownership.
- 2.5 to 2.7: search taps, detail close button, hero swipe ownership. Then section 3.

## Phase 7.3 continuous pass (still on branch Phase-7.2)

### Done
- Mouse / D-pad ownership (RemoteView.swift RemoteInputGuard + RemoteInputPolicy, GlassStyle.swift ModeSelector, RepeatKey.swift). The 0.35 s settle delay is gone. Input path traced: the selector's drag flips remote.isTrackpad mid-drag, which swaps the mouse surface and the pad. Real leaks were (a) a pad touch or hold-repeat already down when the selector was touched or the mode changed, and (b) RepeatKey's repeat task kept firing when its key left the screen mid-hold, because the gesture's end never arrived. Now ModeSelector reports its touch through a self-resetting GestureState; every pad touch takes a token for the current ownership epoch; the epoch moves on with selector touch start/end and mode changes; input is accepted only with a current token, outside Mouse mode, with no selector touch. RepeatKey cancels its repeat and unlights on disappear (mode switch, rotation). Tests: Phase73InputOwnershipTests; the old timing test is removed.
