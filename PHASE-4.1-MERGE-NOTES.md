# Phase 4.1 merged project notes

This project combines the two supplied Phase 4.1 variants. It uses the larger second-variant Remote/D-pad layout and artwork cache, together with the first variant's richer theme contrast tokens, drag-following selector, adaptive palette handling, dynamic dock clearance, responsive Discover pager policy, and measured seeking implementation.

## Retained / combined

- Android mini-player remains removed; shared MediaSession polling and Player page remain.
- Remote trackpad/D-pad uses the 420 pt cap from the larger-layout variant, with compact-screen constraints retained.
- Mouse/D-pad selector uses the grab-offset, finger-following glass lens and haptic selection behaviour.
- Dock clearance is calculated from the actual bottom safe-area inset and passed to pages.
- Light-theme dock/control contrast is independent of artwork accent colours.
- Adaptive palette extraction and luminance clamping are retained from the more developed theme implementation.
- Discover keeps text-only All / Movies / Series filters and the UIKit horizontal page-paging recogniser with carousel/touch exclusions.
- Player retains the portrait poster layout and measured rewind/fast-forward reporting. It does not claim arbitrary seek-to-position support.
- Dedicated seeking, palette, pager, and dock regression tests are included.

## Deliberately not merged

The TV-screen-frame thumbnail capture experiment was not carried into the final Player page. Captured frames can contain playback controls, menus, or protected/black video and are less reliable than catalogue artwork. The shared artwork cache remains in the project for catalogue posters.

## Verification status

All Swift source files passed `swiftc -frontend -parse` syntax parsing in this environment. This is not an Xcode build, iOS SDK typecheck, simulator test, or device test. Run the project's GitHub Actions workflow and the device checks in `REGRESSION_CHECKLIST.md` before treating this merge as release-ready.
