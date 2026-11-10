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
