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

### Still to do on this branch
- Gesture and input bugs: Mouse/D-pad switch leaking a tap into the D-pad, filter swipes fighting the pager, the detail close button, Search opening the hero title.
- Remote redesign (portrait and landscape), moving Themes/Connections/Devices into Profile.
- Discover/search/detail polish, Liquid Glass material variants, theme and motion polish, performance pass.
- CI: results for each Phase-7.1 push need checking in GitHub Actions.
