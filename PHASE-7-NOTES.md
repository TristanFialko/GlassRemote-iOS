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
- Mouse / D-pad ownership (RemoteView.swift RemoteInputGuard + RemoteInputPolicy, GlassStyle.swift ModeSelector, RepeatKey.swift). The 0.35 s settle delay is gone. Input path traced: the selector's drag flips remote.isTrackpad mid-drag, which swaps the mouse surface and the pad. Real leaks were (a) a pad touch or hold-repeat already down when the selector was touched or the mode changed, and (b) RepeatKey's repeat task kept firing when its key left the screen mid-hold, because the gesture's end never arrived. Now ModeSelector reports its touch through a self-resetting GestureState; every pad touch takes a token for the current ownership epoch (a finger still down when the epoch moves keeps a nil token until it lifts; the pad's GestureState closes the session on lift or cancellation); the epoch moves on with selector touch start/end and mode changes; input is accepted only with a current token, outside Mouse mode, with no selector touch. RepeatKey cancels its repeat and unlights on disappear (mode switch, rotation). Tests: Phase73InputOwnershipTests; the old timing test is removed.
- Hero swipe (Discover/DiscoverHero.swift): the hero now carries a PagerExclusionZone, so a sideways swipe on it changes the featured title and never pages; the text follows the finger (resisted, max 60 pt, off with Reduce Motion) and springs back as the next title cross-fades; opening stays tap-only. Pure rules in HeroSwipePolicy (vertical scroll never counts, short drags ignored, same-direction flicks count). Tests: Phase73GestureTests.
- Pager exclusion lifecycle (PagerExclusion.swift, RootPagerView.swift): every page stays alive in the pager's HStack, so zones from off-screen or hidden pages were still registered. Zones now count only when shown (no hidden or transparent ancestor) and on screen (PagerGesturePolicy.visibleZones). Page swipes below the hero and outside selectors are unchanged.

## Phase 7.4 (still on branch Phase-7.2)

### Starting state checked
- Head dd5f792. Run #162 (42897217874) in progress at start; #160/#161 superseded on PR #4 (the GitHub connection has no Actions run/log tools, only PR check runs).

### Done
- 1.1 Search shortcut focus (PageNavigator.swift, RootPagerView.swift, DiscoverPage.swift): the fixed 450 ms sleep is gone. iOS 16 target has no animation completion, so PageSettleObserver (an AnimatableModifier on the pager, driven by the page index) reports when the slide has visually finished. SearchFocusPolicy fires focus exactly once per request when the target page is Discover, the slide has settled, the field is mounted and the scene is active; leaving Discover or backgrounding cancels, stale settle reports are ignored, repeated taps make one focus. Tests: Phase74SearchFocusTests.
- 1.2 Header gestures: the floating header carries a PagerExclusionZone (registered by window membership, filtered by visibleZones), so a swipe from the search capsule never pages. The hero's tap is now a global SpatialTapGesture that ignores taps above the header's bottom edge (DiscoverTouchPolicy), on top of the header's own tap absorber. Typing, clear and account buttons are untouched.

### Next
- 1.3 search behaviour (DiscoverModel live search cancellation, SearchRanking, header hide/show hysteresis).

## Phase 8 one-sweep redesign (still on branch Phase-7.2)

### Starting state checked
- Head 0fa837c. Run #163 (42898357164) green. PRs #2, #3, #4 are tracking PRs and stay unmerged. The GitHub connection has no Actions run/log tools; CI is read from PR #4 check runs.

### Done
- Remote, both orientations (RemoteView.swift, Remote/RemoteStageLayout.swift, Remote/RemoteChrome.swift): the ScrollView stack is replaced by one composition. Portrait is a compact header (status pill, Android/Samsung switch, power), a large Mouse/D-pad selector, a dominant pad, then a nav/media cluster and the volume slider. Landscape is a three-column stage: launcher and controls on the left, a full-height pad in the middle, media, TV group and volume on the right. RemoteStageLayout is a custom Layout that places children by `.remoteStage(column, bottom:)` and is pure-tested. RemoteLayoutPolicy owns composition, the compact threshold, pad minimums, selector height, D-pad diameter and column widths.
- Apps launcher (Remote/AppLauncherSheet.swift): the Apps dropdown is gone. There is now a sheet with a searchable icon grid, favourites first, and offline, scanning, scan-failed and empty states. It opens from the portrait cluster key or the landscape launcher card. AppLauncherPolicy is pure-tested.
- Remote menu (GlobalMenu.swift): Themes, Connections and Devices left the Remote top-left menu. That menu is now RemoteStatusMenu behind the status pill: reconnect entries only when needed, Samsung keys and volume routing, screenshot, and a Profile settings link. PageNavigator.openProfile(_:) and ProfilePage's NavigationStack path open the right Profile subpage. GlobalMenuSpec.movedToProfile records the move.
- Samsung (SamsungRemotePanel.swift): there is a dedicated landscape layout with the trackpad as the centre pad; back and home on the left; rewind, play and fast-forward plus a grouped mute and Ch − / Ch + on the right; no duplicated keys. Portrait keeps primaryRows. The WebSocket, key allowlist, volume and calibration are untouched. SamsungLinkBanner shows only when the link is not up.
- D-pad (Remote/GlassDpad.swift): the pebble is slimmer (0.38 to 0.36) so the arrows have more room. There is a basin shading towards the OK groove, a theme tint in the lower rim, an accent under-glow and a press-in scale on OK. The hit policy, wedges, ADB key names and repeat are unchanged.
- Volume (GlassVolumeSlider.swift): glass track, theme gradient fill with a specular sheen, a glass thumb on the fill edge, a live step readout (Mute/Min/1–20) and a soft haptic per step only while dragging. The API, relative drag, VolumeCalibration.magnet and accessibility actions are unchanged. VolumeSliderGeometry is pure-tested.
- Themes (Theme.swift): new Synthwave, Rosewood, Graphite and Glacier themes. Each has its own canvas, tint and accent pair. New Dusk, Nebula, Prism and Mist ambients are drawn and static, so nothing renders while idle. Mountains and MountainShape are removed; a stored "mountains" migrates to Dusk on launch (AmbientStyle.migrated).
- Play button (Discover/DiscoverHero.swift, DiscoverDetail.swift): GlassTheme.playFill/playInk. Default Dark (and any neutral accent) gets a frosted 16 % pill instead of a solid white slab. Coloured themes keep their accent, with dark ink on bright accents.
- Tests: Phase8RemoteTests.swift (layout policy, stage frames, launcher, nav cluster, menu move, Samsung landscape keys and banner, volume geometry) and Phase8ThemeTests.swift (new themes, distinct accents, Mountains migration, Play tone-down, Play ink contrast, luminance bounds). In GlassRemoteTests.swift, the menu tests follow the move (`testAdvancedHoldsScreenshotAndProfileSettings`) and the ThemeID count is now 15.

### Commits and CI
- 65a357d Remote redesign → run 43046424406.
- dce0f38 volume slider and D-pad → run 43047255372.
- 62a53e4 themes, ambients and Play → its own run (queued after 43047255372).
- None of these runs had finished when this note was written. Nothing here was compiled locally (no Xcode in the session sandbox), so the first green build is the real check.

### Exact checkpoint (next session starts here)
1. Read the latest PR #4 check run. If red, open the job log and fix compile/test errors first. Most likely spots are the new Layout in RemoteStageLayout.swift, the RemoteView rewrite and the `.onChange(of:)` iOS 16 signatures.
2. Workstream 2:
   - The floating dock and landscape rail show the active profile's photo (initials fallback, refresh on change). Keep the DockMetrics test values.
   - Glass variants: refractive lens (iOS 26 native glass plus a bounded iOS 17 Metal `layerEffect` fallback), subtle and plain. No idle rendering; Reduce Motion falls back to plain.
   - Vibrant perceptual adaptive palette with bounds tests.
   - Themes and ambient stored per profile.
3. Workstream 3:
   - SearchRanking: exact/prefix first, then popularity/vote count and media type, then a metadata tie-break (series over a weak movie), with no hardcoded titles.
   - DiscoverModel debounce and cancellation.
   - Header hide/show hysteresis.
   - Detail: verify X close and nested dismiss, the full cast with portraits/initials, the landscape detail layout, and that no metadata is invented.
4. Workstream 4: Profile subpages own Connections, Devices, Add-ons, Appearance and General (check ThemePickerSheet/DeviceInfo are reachable there now that the Remote sheets are gone). Torrentio multi-install and Keychain checks; tokens never shown.
5. Final CI: simulator build plus the full test count, Release device build, ARM32/ARM64 helpers, unsigned IPA artifact `glassremote-unsigned-ipa`.

### Physical-device checks still needed
- Portrait and landscape Remote on small (SE) and large (Pro Max) phones; launcher in both orientations; Samsung landscape against a real TV; D-pad and trackpad ownership while rotating; volume haptics; each new theme and ambient; Default Dark Play contrast.

## Phase 9 Liquid Glass and interaction overhaul (branch Phase-9, from Phase-7.2 at a1c816f)

Phase-7.2 is left as it was. PRs #2, #3 and #4 are tracking PRs and stay unmerged. Nothing below has been checked on a physical iPhone or TV.

### Starting state checked
- Phase-7.2 HEAD a1c816f (Phase 8 notes). Its CI run 43048665477 is green (check run on PR #4); run 43047444095 was cancelled.
- The GitHub connection in the agent session has no Actions run, log or artifact tools. CI is therefore read from check runs and from the build report the workflow posts on the Phase 9 tracking PR (CI tracking only, do not merge).

### CI and workflow
- ios-build.yml: a concurrency group cancels a superseded run on the same branch; the results report step now also runs for Phase-9* branches, so compiler and test errors reach the tracking PR.
- project.yml: deployment target iOS 26.0.


### §0 Native Liquid Glass and refraction
- Native only: GlassStyle's surface, bar and lens modifiers, `glassMorph` and `GlassGroup` call `glassEffect`, `glassEffectID` and `GlassEffectContainer` directly. The material fallbacks (`.ultraThinMaterial`, `.thinMaterial`, gradient rims), `GlassSupport.isNative`, the pre-iOS 26 `LensSpecular` and every `#if compiler(>=6.2)` / `#available` guard are removed (the remaining iOS 17 and 18 checks in SamsungRemotePanel, GlassVolumeSlider, DiscoverPage and DiscoverLayout became unconditional). `onChange` uses the iOS 17 two-parameter form throughout.
- Refraction investigation:
  - Native glass already lenses its backdrop at the rim. Over the app's smooth gradient canvas that bending is close to invisible, because a displaced smooth gradient looks like the same gradient. That is why the earlier builds read as having no refraction.
  - A SwiftUI `layerEffect` samples only the layer it is applied to, never what is behind a view, so a shader on the glass element itself cannot refract the backdrop.
  - What ships: `DesignSystem/Refraction.metal` (`glassRefraction`) plus `DesignSystem/Refraction.swift` (`refractiveLens`, `RefractionStyle`, `RefractionPolicy`, `RefractionGeometry`). The shader is applied to the content directly beneath a glass element and bends only the pixels inside that element's rounded shape: gentle interior magnification, an outward-bending rim band and a small per-channel spread on the rim. Pixels outside the shape are returned untouched, so there is no rectangular bound. The lens rectangle is animatable, so it tracks the springing bubble frame by frame.
  - Where it runs: the scrub selector bubble (page dock, Mouse / D-pad, segmented controls) bends the labels it covers; the volume thumb, now native clear glass, bends the fill edge, glyph and readout under it.
  - Where it does not: cards, sheets, bars over scrolling content and large panels keep native glass alone; a layer shader across a page would rasterise the page every frame.
  - Off, with native glass unchanged, under Reduce Motion (system or the in-app preference), Increase Contrast, Reduce Transparency, or for lenses under 12 pt.
  - Tests: Phase9GlassTests covers untouched pixels outside the shape (including the rounded corner), the fixed centre, magnification, rim bending, the declared sample-offset bound, the accessibility fallbacks, degenerate lenses, radius clamping and the volume thumb's lens rectangle.
  - Needs a device check: whether the strength reads well in each theme, and frame rate while scrubbing the dock and the volume slider.
- CI: a new "Ensure Metal toolchain" step runs `xcodebuild -downloadComponent MetalToolchain` when the runner's Xcode 26 lacks the Metal compiler.

### §1 Remote redesign and §2 Apps folder (checkpoint 1, 2a7ff15; CI green: runs 43060272115, 43068283385)
- §1.1 icon-only keys: `RemoteNavKey` lost its captions (`showsCaptions == false`) and gained `symbol` and `hint`. Every cluster key keeps a full-size hit target, its name as the VoiceOver label, a hint, a pointer tooltip (`.help`) and a Large Content Viewer entry. Samsung keys are icon-only too; only Channel + / Channel − keep a short caption (`SamsungRemoteLayout.caption(for:)`).
- §1.2 landscape: column widths are 27 % (176–280) and 23 % (156–252) of the stage, and the pad always keeps at least 200 pt and 38 % of the width. `RemoteStageLayout` now reserves both columns (`reservesColumns`), so the pad's frame depends only on the stage size and the Android and Samsung pads are identical in the same size class. The D-pad bezel uses the same elevated glass as the mouse and Samsung pads.
- Header: in landscape the status pill has the whole first row (no more "And..."), the device switch shares the second row with power. `RemoteLayoutPolicy.pillStyle` drops to the short name, then the chevron, before anything truncates.
- Apps card: shows only as many preview icons as fit beside its one-line text (`launcherPreviewCount`), the count is "No apps" / "1 app" / "n apps" on one line, the trailing glyph is gone, and it is highlighted only while its folder is visible. The Samsung link banner stacks its action under the message in the landscape column.
- §2 Apps folder (`Remote/AppsFolder.swift`): replaces the Apps sheet. `AppsFolderState` (closed / opening / open / closing, with a generation counter so stale animation completions are ignored), `AppsFolderLayout` (portrait: centred above the Apps key, at most 72 % of the height; landscape: beside the Apps card over the pad, bottom-aligned; always inside 12 pt margins; centred when there is no usable anchor) and `AppsFolderGesture` (pull down 90 pt or flick 200 pt). The shell grows out of the Apps control's frame and collapses back into it with `Motion.folderOpen` / `folderClose` (reduced under Reduce Motion), floats over the page with a light scrim, and closes on an outside tap, the close button, a downward swipe, Escape, launching an app, switching device, leaving the Remote page or the view disappearing. Tiles launch only once it is fully open. Any pad touch, drag or mouse session is ended when it opens. VoiceOver: the folder is modal, focus moves to its title and returns to the Apps control on close.
- `AppLauncherPolicy` moved into AppsFolder.swift unchanged; AppLauncherSheet.swift is emptied in this commit and deleted once CI is green.
- Tests: new Phase9RemoteTests (icon-only keys, Samsung captions, pad minimum across widths 454–1100, identical Android/Samsung pad frames, pill styles, preview fit and count label, folder lifecycle incl. stale completions and every dismiss path, folder geometry in portrait / landscape / small landscape / no anchor / empty, swipe thresholds, favourites-first search). Phase8RemoteTests: wide column caps 270/240 → 280/252.
- Needs a device check: the folder animation's feel and frame rate, the anchor position after rotation, and the keyboard with the folder's search field in landscape.
- Next: continuation brief §A–§I (below).

## Phase 9 continuation (brief: GlassRemote_Phase_9_Continuation.md)
Scope: every section of the continuation brief, §A–§L. Order: A Apps folder, B refraction, C volume slider, then D navigation, E motion, F Discover, G glass/background/profile avatar, H Profile, Add-ons and Torrentio, I performance. CI-verified and device-verified results are kept apart: nothing below has been checked on a device by the agent.

### §A Apps folder refinements (checkpoint A: 9561e3e + 200ed5b; CI pending)
- A1: the close button and the "Tap to open on the TV box" / "TV box offline" subtitle are gone (the offline banner already says it). A compact "Apps" title shares one row with the search field; a small grabber pill at the top shows the folder can be pulled down. Dismissal: outside tap, pull on the grabber or title, Escape on a hardware keyboard (hidden `.cancelAction` shortcut), the VoiceOver escape gesture plus a "Close Apps" custom action, launching an app, and every context change. `DismissReason.closeButton` was removed.
- A2: search is case- and diacritic-insensitive with favourites first among the matches (`AppLauncherPolicy.visible`). Return only puts the keyboard away (`AppsFolderInteraction.submitLaunchesFirstMatch == false`). While the keyboard is up, an outside tap only ends editing (`AppsFolderInteraction.outsideTap`). Clear button and empty state ("No apps" / "No apps match …" with Clear search) kept.
- A3: a fixed 3-column grid (`AppsFolderLayout.columns == 3`, `AppLauncherPolicy.columns(for:)` always 3). Width 320 in portrait and 340 in landscape (capped by the margins). `AppsFolderMetrics` scales 64 pt tiles and their spacing down (to 44 pt at the least) so three rows fit short screens before anything else changes; a fourth row scrolls inside the folder. Columns are a fixed third of the grid, so tiles sit centred with even gutters.
- A4: `AppsFolderMotion`: open spring 0.30 s / 0.80 damping (was 0.44), close 0.22 s / 0.94 (was 0.34). Under Reduce Motion (system or in-app) the shell does not morph out of the Apps control: it cross-fades in place in 0.14 s and the content is not scaled. Interruption, rapid taps and rotation use the existing generation counter; the Apps highlight is on only while the folder is visible.
- A5: the ordered, filtered catalogue is cached in `@State` and rebuilt only when the query, favourites or the app list change, not on animation or drag frames. Icons come from the existing downsampled `AppIconCache`. The scrim is a flat tint, no full-screen blur.
- AppLauncherSheet.swift deleted (unreferenced since checkpoint 1).
- Tests: new Phase9FolderRefinementTests (3 columns and fit on nine screen sizes × six app counts × banner, touch-size floor, scroll beyond nine, tile scaling on short landscape, rotation mid-transition, dismissal without a close button, rapid taps, search, empty states, no accidental launch/dismiss, motion constants and Reduce Motion). Phase9RemoteTests geometry updated (portrait 320 × 372 at y 178; landscape 340 × 316 at x 190); Phase8RemoteTests column test now expects 3 at every width.
- Needs a device check: feel of the faster spring, pulling the grabber, Escape on an iPad keyboard, tile size on an SE-class screen.

### §B Refraction without magnification (checkpoint B, CI pending)
- The shader's `zoom` term is gone from `Refraction.metal`, `RefractionStyle` and the modifier. Everything deeper than the rim band now samples itself: the centre is fixed and text under the dock bubble, segmented controls and volume thumb keeps its real size.
- Rim: the band is capped at 75 % of the half short side (`RefractionGeometry.rimWidth`), so even small lenses keep a still centre. Inside the band, light bends outward along the edge normal with a smoothstep profile (no crease where rim meets interior), much stronger than before: selector 12 pt rim / 9 pt bend (was 9 / 5), thumb 14 / 11 (was 10 / 6). Sample spacing along the normal never drops below pixel spacing, so the rim compresses and never enlarges.
- Dispersion: 1.2 pt (selector) / 1.4 pt (thumb), weighted by t³ so only the outermost rim separates colour.
- Bounds: outside the rounded shape nothing moves (including the corners of its bounding box); `maxSampleOffset` is now bend + dispersion + 1 and no longer grows with the lens size, so the rasterised margin is smaller.
- Where: unchanged call sites (GlassStyle's scrub selector lens for the dock, rail, Mouse / D-pad switch and segmented controls; the volume thumb). The Apps folder edge does not get it: a layer effect only sees its own layer, so refracting the Remote behind the folder would mean rasterising the whole Remote page under a shader every frame of the open animation. Native glass covers the folder. Other large controls keep native glass for the same reason.
- Accessibility: unchanged fallback to plain native glass under Reduce Motion (system or in-app), Increase Contrast and Reduce Transparency.
- Tests: Phase9GlassTests rewritten (no magnification across three lens shapes, fixed centre, monotonic rim without enlargement, stronger outward bend, smooth profile, dispersion only on the outer rim, rim cap leaves a centre, displacements within the declared bound, bound independent of lens size, untouched pixels outside the shape, accessibility, degenerate lenses, radius clamp, thumb lens rect).
- Needs a device check: strength in each theme, legibility of labels under the bubble, frame rate while scrubbing.


### §C Volume slider (checkpoint C, CI pending)
- C1 look: `GlassVolumeSlider` is one integrated piece of glass. Native clear-glass track with edge lighting (bright upper rim, faint lower rim) and a recessed inner shade; the level is a neutral luminous body in adaptive ink tones (no theme accent anywhere), lit along its top and shaded at its foot; the thumb is a substantial clear-glass lens (diameter = track height − 10) with a specular highlight, lit rim, inner edge and a contact shadow that deepens while held, sitting inside the level's rounded end. The bounded refraction lens from §B still bends the layer under the thumb, without magnification. Reduce Motion drops the settle and press springs; Reduce Transparency / Increase Contrast keep the existing glass fallbacks.
- C1 haptics: one soft tick per real level the finger moves through (`VolumeHapticPolicy`), at the target's own resolution; TV readings and programmatic updates never tick. The ADB/soundbar key drain no longer ticks too, so a drag is not doubled.
- C2 range per target (`VolumeScale.swift`, inspected separately):
  - Samsung over UPnP: absolute 0…100, narrowed only by the learned calibration. A calibrated floor above raw 0 is a *minimum* (speaker glyph, "Minimum, 0 percent"); raw 0 is *mute* (slashed speaker, "Muted, 0 percent").
  - Samsung over its remote socket only: one key per step of the soundbar scale (`tvVolumeMax`).
  - Android over ADB: the box's own music-stream range from `cmd media_session volume --stream 3 --get` (fallback `media volume …`), parsed from "volume is N in range [lo..hi]". Until the box answers, the old 20-step assumption stands. Read on appear, on connect, 0.4 s after an ADB volume key, and after each drag.
  - The readout is now a real percentage of that range: 0 only at the floor, 100 only at the top, 1–99 between, never the step index. Only the very ends of the slider command the ends; every other fraction is at least one step inside.
- C2 echoes and reconcile (`VolumeSync`): no device reading moves the thumb during a drag or within 2 s of the last user change (a reading already in flight is stale); 2.1 s after the drag (or a VoiceOver increment) the device is read once more and the slider settles on what it really did. Readings are numbered (`VolumeReadingEvent`) so a repeated value still settles. Calibration, relative drag, the 1.5 % end magnet, mute, routing and the accessibility adjustable action are kept; VoiceOver steps land on real levels (one step on short scales, about 5 % on long ones).
- C3 landscape: the slider has its own deck along the foot of the pad and the trailing column (the leading column keeps its full height). 66 pt tall (thumb 56, larger than portrait's 50), 320–806 pt long across stage widths 454–1100 (always ≥ 300 pt, ≥ 60 % of the stage, at least twice the old trailing-column slider). The deck gives way to 56 pt on short stages before the pad drops below 200 pt. Column widths are unchanged, and the pad frame is still identical for Android and Samsung (`padRect` now reserves the deck). The Samsung TV group sits directly above the deck. Portrait keeps its balanced 60 pt (56 compact) slider at the bottom.
- Tests: new Phase9VolumeTests (0/1/25/50/75/99/100 on standard and calibrated Samsung, Android 15-level and 20-level fallback, Samsung keys, only the ends show 0/100, mute vs minimum, the ADB parser, echo gate and single reconcile, VoiceOver reconcile, one haptic tick per level, VoiceOver steps, deck length/thickness/no overlap across widths and heights, short stages, identical Android/Samsung pad and deck, portrait thickness, stages without a deck unchanged). Phase9RemoteTests' shared-pad test now uses the deck.
- Not device-verified: the Android range read (the `cmd media_session` output differs between Android builds; a box that answers neither command keeps the 20-step behaviour), the haptic density on the 100-step Samsung scale, and how the glass reads in each theme.

### §D Landscape vertical paging (checkpoint D, CI pending)

- **Axis.** New `PagerAxis` (`GlassRemote/PagerAxis.swift`). Portrait stays horizontal (Remote → Player → Discover → Profile, RTL mirroring unchanged: the horizontal strip offset is the pre-§D formula). Landscape stacks the same pages top to bottom, Remote at the top and Profile at the bottom, matching the rail.
- **Same views, new layout.** `RootPagerView` switches the strip between `HStackLayout` and `VStackLayout` through `AnyLayout`, which keeps every page's identity: rotating never recreates the Remote, never touches ADB/UHID, polling or connections. Vertical pages sit one whole screen apart (`pageStride` = height + top + bottom safe areas, `pageGap` between them) and `PagerClip` cuts neighbours at the safe-area edges, so no neighbour shows in the status-bar or home-indicator zones; content can still run sideways under the rail. `HorizontalClip` is replaced by `PagerClip` (portrait clip unchanged).
- **Gesture ownership.** `PagerPan` takes the axis: translation and velocity use the axis component; `AppPage.target`/`resisted` work on the stride (±1 page per swipe, resistance at both ends). A page swipe begins only when clearly along the axis (`isVerticalDominant`, same 1.4 dominance). Rail taps, the dock zone and exclusion zones are rejected exactly as before.
- **Discover scrolling and carousels.** In landscape a vertical swipe that starts inside a page's own vertical scroll view pages only when that scroll view is already at its end in the swipe direction (`scrollerYieldsVerticalPage`, insets respected) and is not decelerating; then its pan is cancelled so it does not also bounce. Horizontal carousels have no vertical range (`isVerticalScroller` false) and a horizontal drag is never vertical-dominant, so carousels keep their drags.
- **Remote.** The landscape Remote is almost all controls, so a vertical page swipe may start only in `PagerSwipeArea`s: the free space in its side columns, laid out by `RemoteStageLayout` as `.gap` children (`Frames.leadingGap`/`trailingGap`, one spacing clear of every control, the pad and the volume deck, ≥ 44 pt or none). They take no touches (hit-test nil) and are removed while the Apps folder is open. Portrait Remote keeps its edge strips.
- **Rotation mid-swipe.** An axis change cancels an active swipe (`cancelsOnAxisChange`) and the travel resets on the size-class change; nothing carries over to the new axis.
- **Tests.** `Phase9NavigationTests`: axis resolution, portrait offsets equal to the old formula, vertical stride/gap/offsets, clip vs neighbours for several safe areas, vertical dominance, up/down targets, boundaries and resistance, short/cancelled swipes, rapid flicks one page at a time, Remote swipe-area acceptance (landscape) vs edge strips (portrait), rail taps, scroll-end hand-off with insets, carousel is not a vertical scroller, rotation cancel, depth on stride, Android/Samsung stage swipe areas clear of all controls and nil when too short. Existing `PagerGesturePolicy` APIs are kept for the earlier phase tests.
- **Not device-verified.** The feel of the scroll-end hand-off, interplay with system edge gestures (Control Centre / notification pull) in landscape, and rotation while a finger is down. CI only proves it compiles and the policies hold.

### §E Shared motion language (checkpoint E, CI pending)

- **One source of curves.** `Motion` now describes every spring as numbers (`Motion.SpringSpec`, `Motion.Springs`) and exposes the tokens the app uses: the existing `page`, `snappy`, `expand`, `hero`, `artwork`, `tracking`, `theme`, `reduced` (unchanged curves), plus `press`, `pressBounce`, `lensSettle`, `lensLift`, `lensStretch`, `settle`, `release`, `content`, `poster`, `ambient` and `fade`. Control springs respond in ≤ 0.3 s with damping ≥ 0.7 (no wobble under the finger); spatial moves (pages, hero, posters) are slower; colour washes never overshoot.
- **Call sites moved onto tokens.** Selection lens (glide, lift, stretch), `PressStyle`, poster buttons, repeat keys, mode selector, volume slider settle/bounce/readout, page navigator, Player title/poster, Samsung play/pause, ambient palette and theme/ambient pickers, hero swipe release, artwork fade, Discover header, profile editor and add-on rows. The only curves outside `Motion.swift` are the Apps folder springs tuned and tested in §A.
- **Reduce Motion everywhere.** `Motion.resolve` (system + in-app preference) for views with an environment, `Motion.unlessReduced` for decorative motion that should disappear entirely, `Motion.adaptive` for stores and actions without an environment. Finger tracking still follows the finger.
- **No animation sleeps.** Audit: no navigation, transition or presentation code waits on a timer (search focus already waits for the real page settle). The remaining timed waits are transport, polling, input or idle rules (ADB/Samsung, scans, account polling, key repeat, hold-to-drag, click release, search debounce, palette settle, hero auto-advance, lens idle); the lens idle wait is now the named `InteractionTiming.lensIdleNanos`.
- **Interruptible by construction.** Every token is a SwiftUI spring (retargets mid-flight) or a short fade; no control waits for an animation, so remote input gets no added lag.
- **Tests.** `Phase9MotionTests`: existing curves unchanged, control springs fast and well damped, spatial slower than controls, Reduce Motion and the in-app preference replace or remove motion, and two source audits (no one-off curves outside the motion language; no `Task.sleep`/`asyncAfter` outside the allow-listed transport/input files). The audits skip if the simulator cannot read the sources.
- **Not measured.** No frame-rate or hitch measurements were taken; nothing here claims a performance change. Hero-to-detail and detail presentation motion are completed in §F, avatar/indicator motion in §G, profile subpage navigation in §H.
