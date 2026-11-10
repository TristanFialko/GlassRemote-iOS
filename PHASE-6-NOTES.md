# Phase 6 rebuild (from Phase 5)

## Base

- Branch: `phase-6-ui-nuvio-rebuild`, based on Phase 5 commit `94a8147be90689a670b6ed6954cb422f17d72fed`
  (Phase-5 head, unchanged). The branch's first commit (`ff6ce00`) only adds this branch to the CI workflow.
- Nothing from the old `phase-6-ui-nuvio` branch was used, merged or cherry-picked.

## Architecture constraints (from the Phase 5 audit)

- `RootPagerView` keeps all three pages alive side by side; navigation only moves an offset.
  `RemoteModel` (ADB, UHID mouse, keyboard helper, Samsung socket, polling) lives above the pager,
  so layout changes never reach the connection.
- Phase 6 therefore changes **values and layouts only**: no view that owns input or connection state
  is rebuilt on rotation. Orientation is resolved from the vertical size class (the keyboard
  shrinking the window in portrait never flips a page into landscape).

## Landscape

- `project.yml`: landscape left/right enabled (Phase 5 was portrait-only).
- Navigation: in landscape the bottom dock becomes a vertical glass **rail** on the leading edge;
  pages sit beside it and keep their full height. Touches on the rail never start a page swipe
  (`PagerGesturePolicy.inRail`, right-to-left aware). Pages get a small bottom clearance instead of
  the dock's.
- Remote: `AnyLayout` switches between the unchanged Phase 5 stack (portrait) and
  `RemoteLandscapeLayout` (controls column beside a full-height trackpad / D-pad / Samsung panel).
  The same views are re-arranged, so the trackpad, its recognisers and the mouse session survive
  rotation. Navigation keys and volume anchor to the bottom of the column. Dynamic Type is capped one
  step lower in landscape so the column always fits.
- Discover, Player, details and sheets: laid out beside the rail with landscape clearances.

## Liquid Glass

- `GlassScrubSelector` (dock, rail, segmented controls, mode selector) now behaves as a lens:
  - iOS 26: native `glassEffect` bar and interactive lens, morphing inside the glass container
    (native refraction and specular highlights).
  - The labels under the lens are drawn a second time, magnified about the lens centre, so an
    icon swells as the lens passes over it (half of each while crossing between two).
  - The lens stretches along the bar with the finger's speed and relaxes when the finger stops.
  - Before iOS 26: the material lens also gets drawn light: a rim highlight whose bright arc
    follows the lens position, a faint chromatic fringe on the rim, a sheen and a darker far rim.
  - Reduce Motion: no stretch, magnification or page depth.
- Section transitions: pages recede slightly (scale/opacity) while sliding away and come forward
  while sliding in (`PageDepth`), for swipes and dock jumps alike.

## Nuvio / Stremio investigation

- Catalogue and metadata on the phone come from Cinemeta's public addon endpoints (catalog/meta).
- Handoff: ADB `am start -a android.intent.action.VIEW -d nuvio://detail/<type>/<imdb id>
  -p com.nuvio.app` (strictly validated IMDb ids), plus `nuvio://search?q=`; if the link is not
  accepted Nuvio itself is launched.
- Continue Watching / Recently watched come from the user's Nuvio account (device-link sign-in,
  tokens in the Keychain), joined with Cinemeta metadata.
- Streams and subtitles: the Stremio addon protocol documents `/stream/<type>/<id>.json` and
  `/subtitles/<type>/<id>.json`, but the configured stream addons (Torrentio + Real-Debrid, Comet,
  AIOStreams) and SubSense are personal installs whose manifest URLs embed their configuration,
  including debrid keys. That configuration lives in Nuvio on the TV. Glass Remote does not read,
  store or query it, and shows no stream or subtitle results.
- Provider-agnostic by design: the phone only ever sends a title's type and IMDb id; Nuvio resolves
  streams with whatever debrid service its addons use. Moving from Real-Debrid to Torbox is a change
  inside Nuvio's addon configuration only; Glass Remote needs no change.

## Verification

- CI (macOS 26 runner): simulator build, unit tests (Phase 5 suite + `Phase6Tests`), device build,
  unsigned IPA artifact.
- Unverified, physical device only: rotation while connected; rotation mid-trackpad / mouse drag;
  rotation with the virtual keyboard active; UHID cursor after rotation; Samsung pairing and volume
  in landscape; native iOS 26 glass rendering and the pre-iOS 26 fallback on hardware; Nuvio
  handoff; VoiceOver on the rail.
