# GlassRemote remediation report

Branch `Phase-9-remediation` (draft PR #9, base `Phase-9-gap-fixes`). Source audit: `GLASSREMOTE_PRODUCT_EXPLORATION_AUDIT.md` (repository root). Hardware acceptance: `audit/GLASSREMOTE_HARDWARE_ACCEPTANCE_CHECKLIST.md`.

> **Evidence disclaimer.** Nothing in this report proves behaviour on the physical iPhone, ARRIS VIP7802 Android TV box, Samsung TV or soundbar. Source review and unit tests show that the code implements a policy; CI shows that it compiles and the tests pass on a simulator. The simulator renders in `audit/ci-simulator-renders/` are stubbed fixtures, not device evidence. Every item below still needs the hardware checklist.

## Evidence levels used

| Level | Meaning |
|---|---|
| **S** | Source-reviewed: the change was read and checked against the finding. |
| **U** | Unit-tested: a test in `Tests/GlassRemoteTests` exercises the rule (some tests only pin wiring by reading source text; marked *wiring*). |
| **CI** | The test ran and passed in GitHub Actions on the simulator (see CI evidence). |
| **HW** | Verified on hardware. **No item has reached this level.** |

## CI evidence

| Commit | Run | Result |
|---|---|---|
| `595c0b2` | [43274440714](https://github.com/TristanFialko/GlassRemote-iOS/actions/runs/43274440714) | Failure (compile; per fix commit `c740941`: trackpad VoiceOver modifier type-check timeout, missing SwiftUI import in tests) |
| `c740941` | [43275976681](https://github.com/TristanFialko/GlassRemote-iOS/actions/runs/43275976681) | Failure: 615 tests, 1 failure (`RemediationVolumeTests.testNoPrivateAddressIsHardCodedInTheModel` matched the box host; scoped to Samsung in `93f4a8d`) |
| `93f4a8d` | [43278752485](https://github.com/TristanFialko/GlassRemote-iOS/actions/runs/43278752485) | **Success.** Simulator build and unit tests: **615 tests, 0 failures**. Helpers, physical-iPhone Release build and unsigned IPA: success. |
| continuation commit | see PR #9 | Recorded in the PR after the run; adds 4 tests (expected 619) |

Warnings: run 43278752485 reports 17 `warning:` lines, the same set as the base branch's last green run ([43253199439](https://github.com/TristanFialko/GlassRemote-iOS/actions/runs/43253199439)) with shifted line numbers: deprecated `Text +` in `DiscoverHero.swift`, unused `setHost/setPort/setKeyPair/setDeviceName` results in `RemoteModel.swift`, a no-op `await` in `VirtualKeyboard.swift`, and an orientation notice. This branch introduces no new compiler warnings. Simulator runs also log network errors (no TV on the CI network), which are expected.

## Findings addressed

Commits: `1192520` (A, volume), `e9e3169` (B, gestures), `4651a17` (C/D/E), `595c0b2` (secondary), `c740941` and `93f4a8d` (CI fixes), then the continuation commit that adds this report (RepeatKey gate, app-scan status, docs).

### A — Volume

| ID | Change | Key files | Tests | Level |
|---|---|---|---|---|
| BUG-001 | One shared slider position for Remote and Now Playing | `GlassVolumeSlider.swift`, `RemoteModel+Features.swift`, `PlayerPage.swift`, `RemoteView.swift` | `RemediationVolumeTests` (wiring) | S, U, CI |
| BUG-002 | Assumed key position resets only when the active route changes | `RemoteModel+Features.swift`, `VolumeOutput.swift` | `RemediationVolumeTests` | S, U, CI |
| BUG-003 | TV speakers is UPnP-only; no silent fallback to Samsung keys; down route reports unavailable | `VolumeOutput.swift` | `RemediationVolumeTests`, `VolumeRouteRestoreTests` | S, U, CI |
| BUG-004 | Samsung host change restarts both the WebSocket and UPnP links (debounced) | `RemoteModel+Features.swift` (`applySamsungHostChange`) | none (source only) | S |
| BUG-005 | No built-in Samsung address; saved/token host restored; fresh link off | `RemoteModel.swift`, `ConnectionSheet.swift` | `RemediationVolumeTests` (Samsung-host scoped) | S, U, CI |
| UX-002/003 | Relative vs measured readout; output named on each volume row | `GlassVolumeSlider.swift`, `VolumeOutput.swift` | `RemediationVolumeTests` | S, U, CI |
| UX-008 | Bounded key-step planning and pending presses | `RemoteModel+Features.swift` | `RemediationVolumeTests` | S, U, CI |
| UX-016 | "Soundbar max volume" labelled as the Samsung-keys route setting | `ConnectionSheet.swift` | none | S |

Protected behaviour confirmed in source: default output **Soundbar, through the TV box** sends `input keyevent 24` / `25` / `164`; the ordinary Android Remote has no volume up/down buttons; `VolumeRoutePolicy` never routes to an output other than the selected one. The only remaining private address in code is the TV *box* host default `192.168.1.70` (`RemoteModel.swift`), which predates this branch.

### B — Gestures and input

| ID | Change | Key files | Tests | Level |
|---|---|---|---|---|
| BUG-006 | Two-finger recogniser active only when the Remote surface is visible | `TwoFingerScroll.swift`, `RootPagerView.swift`, `RemoteView.swift` | `RemediationGestureTests` (wiring) | S, U, CI |
| BUG-007/015 | Key repeat stops and unlights on lost gesture end, background, page change, 30 s cap. **Continuation fix:** a key cancelled while the finger stays down can no longer restart on the same touch's next drag event (which defeated the 30 s cap) | `RepeatKey.swift`, `InputCancellation.swift` (`HeldTouchGate`) | `RemediationGestureTests` (gate tests new) | S, U; CI pending for the new tests |
| BUG-008 | Held mouse button released on cancellation/backgrounding; stale button cleared | `RemoteModel+Mouse.swift` | `RemediationGestureTests` | S, U, CI |
| BUG-009 | **Partial.** OK fires once per touch and never repeats Enter. True long-press deferred (see below) | `Remote/GlassDpad.swift` | `RemediationGestureTests` (wiring) | S, U, CI |
| UX-012 | Mode selector commits on release, ≥44 pt hit height | `GlassStyle.swift`, `Remote/RemoteStageLayout.swift` | `RemediationGestureTests` | S, U, CI |
| A11Y-001 | Trackpad VoiceOver actions (click, Back, scroll, pointer nudges) | `InputCancellation.swift`, `RemoteView.swift` | none | S, CI (compiles) |

### C — Connection and playback feedback

| ID | Change | Key files | Tests | Level |
|---|---|---|---|---|
| UX-001 | Readiness distinguishes ADB, command shell, keyboard and mouse ("degraded" instead of "Connected") | `ConnectionReadiness.swift`, `RemoteModel.swift` | `RemediationFeedbackTests` | S, U, CI |
| UX-005 | Transport failures shown on Now Playing / mini-player | `PlayerPage.swift`, `RemoteModel+Playback.swift` | `RemediationFeedbackTests` | S, U, CI |
| UX-006 | One media poll on foreground after recovery | `RemoteModel.swift` | none | S |
| UX-007 | Stale paused sessions retired from the mini-player | `MediaSession.swift`, `PlayerPolicy.swift` | `RemediationFeedbackTests` | S, U, CI |
| UX-013/014 | No empty timeline track without a duration; neutral idle copy, known package names | `PlayerPage.swift`, `PlayerPolicy.swift` | `RemediationFeedbackTests` | S, U, CI |
| UX-015 | ADB authorisation guidance, slower retries while unauthorised | `ConnectionReadiness.swift` | `RemediationFeedbackTests` | S, U, CI |
| BUG-011 | Transient playback states do not drop the session | `MediaSession.swift` | `RemediationFeedbackTests` | S, U, CI |
| BUG-016 | "Restart launcher" reports the verified result | `RemoteModel+Features.swift` | `RemediationFeedbackTests` | S, U, CI |
| A11Y-002 | Secondary text contrast on Now Playing | `PlayerPage.swift`, `GlassStyle.swift` | `RemediationFeedbackTests` | S, U, CI |

### D — Discover and Nuvio

| ID | Change | Key files | Tests | Level |
|---|---|---|---|---|
| BUG-012 | Selected/resume episode carried into the stream picker | `DiscoverDetail.swift`, `Playback/StreamPickerSheet.swift` | `RemediationDiscoverTests` | S, U, CI |
| BUG-013 | Sign-out invalidates in-flight refresh (generation counter) | `NuvioAccount.swift` | `RemediationDiscoverTests` | S, U, CI |
| BUG-014 | Restored add-ons with missing Keychain links flagged, repair UI | `Addons/AddonStore.swift`, `Addons/AddonsPage.swift` | `RemediationDiscoverTests` | S, U, CI |
| BUG-017 | Nuvio intent failure no longer matched on any "error" substring | `RemoteModel+Nuvio.swift` | `RemediationDiscoverTests`, `NuvioTests` | S, U, CI |
| BUG-018 | Cinemeta search halves survive each other's failure | `CinemetaCatalog.swift` | `RemediationDiscoverTests` | S, U, CI |
| BUG-021 | 401 forces one refresh and one retry (bounded) | `NuvioAccount.swift` | none | S |
| BUG-022 | Handoff status reflects the actual outcome | `DiscoverDetail.swift`, `Playback/RemoteModel+Handoff.swift` | `RemediationDiscoverTests` | S, U, CI |
| UX-009 | Continue Watching refresh on foreground (rate-limited) and after handoff; **pull-to-refresh deferred** | `DiscoverPage.swift`, `NuvioAccount.swift` | `RemediationDiscoverTests` | S, U, CI |
| UX-010 | Recents saved only on submit/open | `DiscoverPage.swift` | `RemediationDiscoverTests` | S, U, CI |
| UX-011 | Handoff feedback inline; return-to-Remote through See All | `CollectionView.swift`, `DiscoverDetail.swift` | none | S |
| UX-017 | Add-on swipe-delete confirmation; duplicate links ignore host case | `Addons/AddonsPage.swift`, `Addons/AddonStore.swift` | `RemediationDiscoverTests` (duplicates only; confirmation untested) | S, U, CI |
| A11Y-003/005 | Hero stops auto-advancing under VoiceOver/Reduce Motion; card labels include progress | `Discover/DiscoverHero.swift`, `DiscoverPage.swift` | `RemediationDiscoverTests` | S, U, CI |

### E — Android TV app launcher and keyboard

| ID | Change | Key files | Tests | Level |
|---|---|---|---|---|
| UX-004 | Installed launchable apps discovered (`cmd package query-activities --brief`, Leanback preferred, system/Settings packages filtered); curated nine kept first; Settings tile. **Continuation fix:** when the box lists packages but no launch activities, status says "app list unavailable on this box" instead of "N apps found" | `AppCatalog.swift`, `RemoteModel+Apps.swift`, `Remote/AppsFolder.swift` | `RemediationAppsTests` (new test for the unsupported-query case) | S, U; CI pending for the new test |
| BUG-019 | Long live typing split into steps, never truncated | `KeyboardSheet.swift`, `VirtualKeyboard.swift` | `RemediationAppsTests` | S, U, CI |
| BUG-020 | Keyboard copy no longer promises a non-existent ADB fallback | `VirtualKeyboard.swift`, `KeyboardSheet.swift` | `RemediationAppsTests` (wiring) | S, U, CI |
| BUG-023 | Back/Home wait for queued arrows (barrier) | `KeyboardSheet.swift`, `RemoteModel.swift` | `RemediationAppsTests` | S, U, CI |
| SEC-002 | **Partial.** History can be turned off (clears stored text); still plain `UserDefaults`, on by default | `KeyboardSheet.swift` | `RemediationAppsTests` | S, U, CI |

Shell safety (source review): package and component names are validated against a character allow-list and passed through `TVShell.quote`; no injection path found.

### Secondary

| ID | Change | Key files | Tests | Level |
|---|---|---|---|---|
| A11Y-006 | In-app Reduce Motion copied to new profiles | `Profiles/ProfileStore.swift` | none | S |
| SEC-003 | Keychain update-in-place, add only on `errSecItemNotFound`, status checked and logged (no secrets) | `KeychainStore.swift` | none | S |
| ARCH-002 (part) | Unused `NowPlayingSheet.swift` removed; no references remain in `project.yml`, source, tests or current docs (only historical notes and the audit) | — | — | S, CI (builds) |
| ARCH-001 (part) | README, REGRESSION_CHECKLIST and PHASE-7-NOTES banner updated to the current behaviour (continuation) | docs | — | S |

## Deferred and not done

| ID | Severity | Status / rationale | Risk | Next step and acceptance criterion |
|---|---|---|---|---|
| SEC-001 Samsung TLS accepts any certificate; token in URL query | Medium | Deferred. Pinning (trust-on-first-use) touches the protected pairing path and needs a real TV to confirm the certificate is stable across reboots/firmware. TLS was **not** weakened further. | LAN attacker could impersonate the TV and capture the pairing token. | Record the TV's leaf certificate fingerprint over several reboots (HW-SEC-05). If stable, pin per paired host with an explicit "TV certificate changed — re-pair" path. Accept when a changed certificate blocks the token and the user is told why. |
| BUG-010 Unauthenticated loopback input listener on the box | Medium | Deferred. Fix requires changing the protected C helper protocol (`glass_tcp_input_server`) and testing on the box. | Any app on the box can inject keys/mouse to port 47631/47632; newest connection displaces the app. | Run HW-SEC-06 to document exposure. Design: per-session random token passed at helper launch over ADB, first line must match. Accept when an unauthenticated `nc` probe injects nothing and the app reconnects normally. |
| BUG-009 True OK long-press | Medium | Partial. The keyboard helper has no key-down/key-up semantics; faking long-press with repeated Enter is explicitly disallowed. | Long-press menus (e.g. YouTube) unreachable from OK. | Add key-down/up to the helper protocol (protected; needs box). Accept when holding OK 1 s opens the long-press menu on Android TV home and YouTube. |
| ARCH-003 Helper provenance | Medium | Not done: the mouse helper and cursor JAR are committed binaries without source; bridge is 32-bit only. | Unreviewable binaries; 64-bit-only boxes unsupported. | Document origin/build of each binary and checksums; HW-SEC-07 records the box ABI. |
| ARCH-005 Render comparison in CI | Medium | Not done; renders are uploaded but never compared. | Visual regressions pass CI. | Add snapshot tests with tolerance against committed references; fail CI on diff. |
| VIS-001 Ghosted header in trackpad renders | Low | Not investigated; may be a simulator render artifact (see `crop-trackpad-top.jpg`). | Possibly cosmetic on device. | Check on device (HW-LAY-01); if visible, find the duplicated layer. |
| A11Y-004 Dynamic Type sweep | Low | Not done. | Clipped text at large sizes. | HW-A11-05 observation at AX sizes, then fix the fixed font sizes. |
| PERF-001–004 | Low | Not done (media republish on every poll, UPnP polling when not selected, eager stream picker, add-on cap after full download). | Battery/CPU; no correctness impact known. | Measure with Instruments first; PERF-002 (poll UPnP only when TV speakers is selected) is the cheapest. |
| UX-009 pull-to-refresh | Low | Deliberately deferred: conflicts with the Discover hero's pull gesture. | Manual refresh needs foregrounding. | Revisit with a dedicated refresh control. |
| SEC-002 remainder, SEC-004, ARCH-004/006/007 | Low | Not done. | See audit. | — |

## Known limitations found in the continuation review

- **App discovery on the real box is unverified.** If the box's `cmd package` lacks `query-activities`, only the curated nine and Settings appear (status now says so). Curated tiles without a discovered activity fall back to `monkey -p`, which uses the phone launcher category and may fail for Leanback-only apps — this fallback predates the branch. Check with HW-APP-01/09.
- **Nuvio session save failure** after a single-use token refresh is logged by the Keychain layer but not shown; the user would be signed out on the next launch. `AddonStore` and Samsung pairing also ignore the write result (logged only).
- Several implemented items have no unit test (BUG-004, BUG-021, UX-006, UX-011, SEC-003, A11Y-001/006); they are source-reviewed only.
- SwiftUI touch cancellation (Control Center, calls, rotation) cannot be exercised in unit tests; the new gate is unit-tested as pure logic only.

## Hardware verification still required

All of `audit/GLASSREMOTE_HARDWARE_ACCEPTANCE_CHECKLIST.md`, in particular: volume direction and sweep on the real soundbar through the box (HDMI-CEC), each route's unavailable state, Samsung reconnect after a host change, gesture interruption (Control Center, calls, rotation), mouse release, text entry, app discovery and launch (YouTube, Netflix, Stremio, Nuvio, Settings, browser), playback states, Nuvio handoff with episode selection, VoiceOver, and the BUG-010 / ABI observations.
