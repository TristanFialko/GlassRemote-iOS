# GlassRemote hardware acceptance checklist

**Branch:** `Phase-9-remediation`. Derived from audit §19.3 (physical-device regression matrix) plus the bug/UX/accessibility/security IDs in §15–§16 and `audit/REMEDIATION_CHECKPOINT.md`.

## Purpose and ground rules

- Purpose: obtain physical-hardware evidence for the Phase 9 remediation (volume, gestures, feedback, Discover/Nuvio, apps, secondary fixes). None of it has been run on hardware yet.
- **Execute every check on real devices.** Unit tests, CI results and simulator renders are **not** evidence of hardware behaviour (the repository has no UI tests, and CI render tests are not compared with baselines). A check you cannot run is **Blocked**, never Pass.
- Never weaken a safety feature to get a pass. For failures record the build commit, the step number and, if possible, a short screen recording.
- Deferred items are observation-only: SEC-001 (Samsung TLS pinning), BUG-010 (TV-side listener authentication), A11Y-004 (Dynamic Type sweep), Discover pull-to-refresh, true OK long-press. Record what you see; that is not a regression.
- Suggested order (audit): Section 1 (volume) first, then the Section 3 interruption checks (held D-pad, mouse drag). They cover the two highest-impact unverified risks.
- Device flags: **iPhone** = phone with the app; **Box** = ARRIS VIP7802 Android TV box; **Samsung TV**; **Soundbar** = HDMI-CEC/ARC soundbar. "Small iPhone" means an SE-class device.

## Device and environment record

| Item | Value |
|---|---|
| Tester / date | |
| App build (commit SHA, CI run, install method) | |
| iPhone model / iOS (primary) | |
| iPhone model / iOS (small, SE-class) | |
| ARRIS VIP7802 / Android version / network debugging on | |
| Samsung TV model / firmware / remote-access setting | |
| Soundbar model / connected to (TV ARC or box HDMI) / CEC on | |
| Wi-Fi (iPhone, box and TV on same subnet?) | |
| Apps on box: Nuvio / Spotify / YouTube / Netflix / Stremio / browser (versions) | |
| Nuvio account / add-ons used | |
| VoiceOver, Reduce Motion, Dynamic Type settings used | |
| Starting state (fresh install vs upgrade over previous build) | |


## Traceability to audit §19.3

Each row of the audit's physical-device regression matrix and the checks that cover it. Row 10's audit criterion ("currently expected many") predates BUG-009: OK now sends exactly one Enter.

| §19.3 row | Scenario | Checks |
|---|---|---|
| 1 | Volume default sweep, mute | HW-VOL-01, 03, 04 |
| 2 | BUG-001 shared slider | HW-VOL-08 |
| 3 | BUG-002 no jump after foreground | HW-VOL-09 |
| 4 | Volume unavailable (box) | HW-VOL-10 |
| 5 | TV speakers number / UPnP blocked | HW-VOL-07, 12 (now: unavailable, never TV keys) |
| 6 | D-pad interruption | HW-GES-02, 03, 04 |
| 7 | Two-finger leak | HW-GES-09 |
| 8 | Mouse drag interruption | HW-GES-10 |
| 9 | Rotation mid-gesture | HW-GES-05, HW-LAY-04 |
| 10 | Long-press OK | HW-GES-08 |
| 11 | Back ordering | HW-GES-14, HW-APP-10 |
| 12 | Helper failure | HW-CON-02, HW-KEY-07 |
| 13 | ADB auth | HW-CON-01 |
| 14 | Text entry | HW-KEY-01 to 06 |
| 15 | App launch | HW-APP-01 to 09 |
| 16 | Now Playing states | HW-MED-01 to 06 |
| 17 | Foreground freshness | HW-CON-04 |
| 18 | Samsung reconnect / host change (never press Reset during this row) | HW-SAM-04, 06, 08 |
| 19 | Discover throttled / "terror" search | HW-NUV-03, 07, 08 |
| 20 | Series handoff | HW-NUV-01, 02 |
| 21 | Nuvio sign-out | HW-NUV-04 |
| 22 | Add-ons accept/reject, restore | HW-NUV-05, 06, HW-SEC-02 |
| 23 | Accessibility | HW-A11-01 to 05, HW-GES-13 |
| 24 | Security probe (BUG-010) | HW-SEC-06 |
| 25 | Box ABI | HW-SEC-07 |

## 1. Volume

Outputs are chosen explicitly; default is **Soundbar, through the TV box**. Reason strings in code: box route down → “Connect the TV box”; Samsung link off → “Samsung TV is off”; Samsung remote not ready → “Samsung TV not connected”; TV speakers with remote ready but UPnP silent → “TV volume link not answering”. The Connection sheet says “Nothing is sent to other speakers instead.” Box keycodes: up 24, down 25, mute 164.

### HW-VOL-01 — Default output and buttons (box → soundbar)

- **Audit IDs:** BUG-003, UX-003
- **Devices:** iPhone, Box, Soundbar
- **Preconditions:** Box connected, soundbar on, CEC enabled. Fresh install or default output.
- **Steps:**
  1. Open the volume row and read the named output.
  2. Press volume up 3×, down 3×, then mute twice.
  3. Watch the soundbar level/display.
- **Expected:** Row names “Soundbar, through the TV box”. Up raises, down lowers, mute toggles on the soundbar (ADB keys 24/25/164 → CEC). TV speakers are unaffected.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-02 — Ordinary Android Remote has no volume buttons

- **Audit IDs:** UX-002
- **Devices:** iPhone, Box
- **Preconditions:** Box connected.
- **Steps:**
  1. Inspect every control on the Android Remote page, portrait and landscape.
  2. Compare with the Samsung remote panel.
- **Expected:** The ordinary Android Remote shows no volume up/down buttons; volume lives only on the shared volume row/slider (and Samsung panel keys if present).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-03 — Box route: full upward sweep is bounded

- **Audit IDs:** BUG-001, BUG-002, UX-008
- **Devices:** iPhone, Box, Soundbar
- **Preconditions:** Output = soundbar via box. Soundbar set to a known low level using its own remote. Level freshly unknown (just selected route).
- **Steps:**
  1. Drag the slider 0% → 100% once, slowly.
  2. Count steps on the soundbar display (a full sweep is about 20 key presses).
  3. Release and wait 5 s.
- **Expected:** About 20 up steps in total; never more than one range of pending presses; no extra burst; readout is presented as relative/estimated.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-04 — Box route: downward sweep and wrong-direction check

- **Audit IDs:** BUG-001, BUG-002
- **Devices:** iPhone, Box, Soundbar
- **Preconditions:** Continue from HW-VOL-03 (slider 100%); then repeat from a freshly selected route (unknown level).
- **Steps:**
  1. Drag 100% → 0%; watch the soundbar throughout.
  2. From a fresh route selection, drag the thumb to 0% once.
- **Expected:** Soundbar only goes down on a downward drag (no upward nudge, BUG-001). From an unknown level, reaching 0 may send one full-range descent so the soundbar really reaches minimum. Upward moves send only the thumb’s distance.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-05 — Measured vs relative readout

- **Audit IDs:** UX-003, BUG-002
- **Devices:** iPhone, Box, Samsung TV, Soundbar
- **Preconditions:** Run once per output.
- **Steps:**
  1. On the box route and Samsung-key route read the slider text and its VoiceOver value.
  2. On TV speakers compare the readout with the TV’s on-screen volume.
- **Expected:** Key routes present an estimated/relative position, not a measured number (soundbar level cannot be read). TV speakers show the actual TV level matching the TV display (±1).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-06 — Soundbar through Samsung TV keys

- **Audit IDs:** BUG-003, UX-003, UX-008
- **Devices:** iPhone, Samsung TV, Soundbar
- **Preconditions:** Samsung paired and connected; output = Soundbar, through the Samsung TV.
- **Steps:**
  1. Press up/down/mute.
  2. Sweep the slider 0→100% and 100%→0%; count TV OSD / soundbar steps.
- **Expected:** Samsung remote keys are sent and the TV applies them to its active output (soundbar via ARC). Upward bursts are bounded, mute toggles, and the box’s volume keys are not used.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-07 — TV speakers via UPnP (absolute)

- **Audit IDs:** BUG-003, UX-003
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Samsung paired, UPnP reachable; output = TV speakers; TV audio on its own speakers.
- **Steps:**
  1. Set the slider to roughly 25/50/75%.
  2. Change the TV volume with the Samsung hardware remote and wait for read-back.
  3. Press up/down once each; toggle mute.
- **Expected:** TV goes to the set level; the slider follows hardware-remote changes after read-back; up/down move ±1; mute toggles. Slider 0–100% maps to the TV’s calibrated range; a calibrated floor above 0 is not mute.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-08 — Shared slider position (Remote vs Now Playing)

- **Audit IDs:** BUG-002, UX-003
- **Devices:** iPhone, Box
- **Preconditions:** Box connected.
- **Steps:**
  1. Set the slider to about 60% on Remote.
  2. Swipe to Now Playing and read its slider.
  3. Change it there and swipe back.
- **Expected:** Both pages show one shared position and the same output name; a change on one appears on the other.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-09 — Assumed level resets only on route change

- **Audit IDs:** BUG-004, BUG-002
- **Devices:** iPhone, Box, Samsung TV, Soundbar
- **Preconditions:** Box and Samsung key routes both available.
- **Steps:**
  1. Set the slider to ~70% on the box route.
  2. Open and close the volume sheet without changing output; confirm nothing is sent.
  3. Switch to the Samsung key route and back; then sweep to 0 once.
- **Expected:** No volume commands are sent by opening the sheet or reselecting the same output; the assumed level resets only when the active command route changes.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-10 — Box route unavailable (box disconnected)

- **Audit IDs:** BUG-003, UX-003
- **Devices:** iPhone, Box, Samsung TV, Soundbar
- **Preconditions:** Output = box route. Cut the box’s network or power; wait for the app to show offline.
- **Steps:**
  1. Read the volume row.
  2. Try the slider and buttons.
  3. Watch the soundbar and TV.
- **Expected:** Slider disabled showing “Connect the TV box”, no fill or stale level; buttons send nothing; **nothing is sent to Samsung/UPnP**, TV and soundbar volume do not change.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-11 — Samsung routes unavailable (TV off / link off)

- **Audit IDs:** BUG-003, UX-003
- **Devices:** iPhone, Box, Samsung TV, Soundbar
- **Preconditions:** Output = Samsung soundbar route; TV in standby.
- **Steps:**
  1. Read the row; try slider and buttons.
  2. Repeat with output = TV speakers.
  3. Repeat with the Samsung link switched off in the app.
- **Expected:** Disabled with “Samsung TV not connected” (link on) or “Samsung TV is off” (link off); nothing is sent to the box/soundbar instead.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-12 — TV speakers: UPnP not answering, remote up

- **Audit IDs:** BUG-003, UX-003
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Output = TV speakers; induce UPnP silent while the remote WebSocket works (note how; skip as Blocked if not producible).
- **Steps:**
  1. Read the row; try slider/buttons.
- **Expected:** Reason “TV volume link not answering”; slider disabled; **no key fallback** (the old TV-speakers key fallback is gone); box volume unchanged.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-VOL-13 — Recovery after route returns

- **Audit IDs:** BUG-003, UX-001
- **Devices:** iPhone, Box, Samsung TV
- **Preconditions:** Continue from HW-VOL-10/11.
- **Steps:**
  1. Restore the box/TV and wait for connected.
- **Expected:** Slider re-enables without relaunching; commands go only to the chosen route.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 2. Samsung TV pairing and host

### HW-SAM-01 — Fresh install has no Samsung address

- **Audit IDs:** BUG-005, UX-001
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Delete the app, install the build.
- **Steps:**
  1. Launch and open the Samsung/Connection settings without entering anything.
  2. Watch the TV for a pairing prompt.
- **Expected:** No Samsung host is pre-filled or built in; Samsung link stays off until a host exists; the TV shows no pairing prompt.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SAM-02 — First pairing prompt and approval

- **Audit IDs:** BUG-005
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Host entered, no stored approval.
- **Steps:**
  1. Enter the TV’s IP and connect.
  2. Observe the iPhone status and the TV.
- **Expected:** Status “Samsung TV: approve Glass Remote on the TV”; the TV shows Allow; after Allow it connects and keys work; the approval is saved.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SAM-03 — Pairing denial and no-answer timeout

- **Audit IDs:** BUG-005, UX-001
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Pairing reset (HW-SAM-05).
- **Steps:**
  1. Connect; choose Deny on the TV.
  2. Repeat; ignore the prompt until the approval deadline.
- **Expected:** Denial shows a distinct reason (not “unreachable”) and auto-connect stops until you retry; timeout shows a timed-out state; no endless prompt loop on the TV.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SAM-04 — Saved host restore

- **Audit IDs:** BUG-005
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Paired once.
- **Steps:**
  1. Force-quit and relaunch.
  2. Toggle Wi-Fi off and on.
- **Expected:** Saved host is restored (preferred over the host associated with the token), reconnects with the saved approval, no new TV prompt.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SAM-05 — Reset pairing

- **Audit IDs:** BUG-005
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Paired.
- **Steps:**
  1. Use the reset pairing action.
  2. Reconnect.
- **Expected:** Saved approval is cleared (diagnostics show no saved approval); reconnect asks for approval again on the TV.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SAM-06 — Host change reconnects WebSocket and UPnP

- **Audit IDs:** BUG-004, BUG-005
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Paired to TV A; a second Samsung TV or an alternate address is available (otherwise use a wrong, then the correct, IP).
- **Steps:**
  1. Change the host to another/unreachable address and watch status.
  2. Change back to the real TV.
  3. Test a Samsung key and TV-speaker volume.
- **Expected:** Changing the host drops the old links and reconnects both the remote WebSocket and the UPnP volume link to the new host; volume row reflects the new state; the old TV is no longer controlled.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SAM-07 — Token never sent to a different address

- **Audit IDs:** BUG-005, SEC-001 (deferred, observation)
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Token saved for TV A. A LAN machine you control running a listener, or packet capture on the Wi-Fi.
- **Steps:**
  1. Change the host to the listener’s address.
  2. Capture the connection attempt (WebSocket URL).
- **Expected:** The stored TV A token is not sent to the new address (treated as first pairing). Note: token travels in the URL query to the paired TV and TLS accepts any certificate for the configured IP (SEC-001, deferred): record behaviour only.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SAM-08 — Standby and wake

- **Audit IDs:** UX-001
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Paired.
- **Steps:**
  1. Put the TV in standby; observe status.
  2. Wake the TV.
- **Expected:** Status honestly shows unavailable/unreachable, then recovers without a re-pairing prompt.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 3. Gestures and input interruption

Key repeat: tap fires once, hold repeats with acceleration, stops after 30 s, lost-touch cleanup after 120 ms. OK never repeats. A cancel-touches notification releases held touches.

### HW-GES-01 — D-pad hold repeats and stops on lift

- **Audit IDs:** BUG-006, UX-012
- **Devices:** iPhone, Box
- **Preconditions:** Box connected; focus a list on the box (e.g. Settings).
- **Steps:**
  1. Hold Down ~3 s, then lift.
  2. Tap Left once.
- **Expected:** Selection steps repeatedly (accelerating) while held and stops immediately on lift; a tap moves exactly once.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-02 — Repeat stops on Control Center pull-down

- **Audit IDs:** BUG-006
- **Devices:** iPhone, Box
- **Preconditions:** As above.
- **Steps:**
  1. Hold Down.
  2. Pull down Control Center (or Notification Center) while holding.
- **Expected:** Repeat stops within about 0.2 s and stays stopped afterwards; the TV does not keep scrolling.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-03 — Repeat stops on incoming call

- **Audit IDs:** BUG-006
- **Devices:** iPhone, Box
- **Preconditions:** A second phone to call the iPhone.
- **Steps:**
  1. Hold a direction key.
  2. Receive an incoming call.
- **Expected:** Repeat stops; no key stuck on the TV after answering or declining.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-04 — Repeat stops on app backgrounding

- **Audit IDs:** BUG-006
- **Devices:** iPhone, Box
- **Preconditions:** As above.
- **Steps:**
  1. Hold a direction key.
  2. Go Home / switch apps while holding.
- **Expected:** Repeat stops when the app leaves the foreground.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-05 — Repeat stops on rotation mid-press

- **Audit IDs:** BUG-006, BUG-007
- **Devices:** iPhone, Box
- **Preconditions:** Rotation lock off.
- **Steps:**
  1. Hold a direction key.
  2. Rotate to landscape and back.
- **Expected:** No stuck key or runaway repeat; controls respond normally afterwards.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-06 — Repeat stops on page swipe

- **Audit IDs:** BUG-006, BUG-007
- **Devices:** iPhone, Box
- **Preconditions:** Box connected.
- **Steps:**
  1. Hold a direction key while swiping to another page.
- **Expected:** Repeat stops when the page changes; no further input reaches the TV.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-07 — 30-second repeat cap

- **Audit IDs:** BUG-006
- **Devices:** iPhone, Box
- **Preconditions:** Box connected.
- **Steps:**
  1. Hold a direction key for more than 30 s without lifting.
- **Expected:** Repeat stops by itself at about 30 s even with the finger still down.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-08 — OK does not repeat Enter

- **Audit IDs:** BUG-009
- **Devices:** iPhone, Box
- **Preconditions:** A focused toggle on the box where repeated Enter is visible.
- **Steps:**
  1. Hold OK for 3 s.
  2. Tap OK once.
- **Expected:** Exactly one Enter per press; holding sends no repeats. (True long-press is not implemented; it needs helper protocol changes.)
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-09 — Two-finger scroll only on the visible Remote page

- **Audit IDs:** BUG-007
- **Devices:** iPhone, Box
- **Preconditions:** Box connected.
- **Steps:**
  1. On Remote, two-finger drag vertically on the trackpad and watch the TV.
  2. Swipe to Now Playing, Discover and Apps and repeat two-finger drags.
- **Expected:** Scroll works only on the visible Remote surface; hidden-page two-finger gestures send nothing.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-10 — Mouse button released on cancellation/background

- **Audit IDs:** BUG-008
- **Devices:** iPhone, Box
- **Preconditions:** A TV screen where a held click is visible (item drag or text selection).
- **Steps:**
  1. Press and hold on the trackpad to start a drag.
  2. Pull down Control Center.
  3. Repeat, backgrounding the app instead.
- **Expected:** Mouse button is released; no stuck drag on the TV and the cursor moves freely again.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-11 — Trackpad sanity

- **Audit IDs:** BUG-008
- **Devices:** iPhone, Box
- **Preconditions:** Mouse helper ready.
- **Steps:**
  1. Move the cursor, tap to click, two-finger scroll.
- **Expected:** Pointer follows the finger, a click lands once, scroll works.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-12 — Mode selector commits on release

- **Audit IDs:** BUG-015, UX-012
- **Devices:** iPhone, Box
- **Preconditions:** Mode selector visible (44 pt targets).
- **Steps:**
  1. Touch a segment and drag across others without lifting.
  2. Lift on another segment; also drag off the control and lift outside.
- **Expected:** Mode changes only on release at the final segment; lifting outside cancels; no mid-drag switching.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-13 — Trackpad VoiceOver actions

- **Audit IDs:** A11Y-001
- **Devices:** iPhone, Box
- **Preconditions:** VoiceOver on.
- **Steps:**
  1. Focus the trackpad and open the Actions rotor.
  2. Run Activate, Escape, Back, Scroll up, Scroll down, Move pointer left/right/up/down.
  3. On the Samsung directional pad run Activate, Escape and Move up/down/left/right.
- **Expected:** Each action works on the TV: click, Back, scroll, pointer nudge. Samsung pad: Activate = Enter, Escape = Back, Move actions send the matching arrow.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-GES-14 — Back/Home ordering after D-pad

- **Audit IDs:** BUG-011
- **Devices:** iPhone, Box
- **Preconditions:** Box connected.
- **Steps:**
  1. Tap Down several times quickly, then Back immediately, then Home.
- **Expected:** Back/Home execute after the queued D-pad presses, not before.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 4. Keyboard entry

Live typing sends each key through the virtual keyboard helper (plain ASCII only; Return = Enter). Send mode sends a whole string. History is optional (“Remember sent text”), keeps the last Sent texts on the iPhone, and live typing is never saved.

### HW-KEY-01 — Typing in YouTube search

- **Audit IDs:** BUG-019, BUG-020
- **Devices:** iPhone, Box
- **Preconditions:** Box connected, keyboard helper ready, field focused on the TV.
- **Steps:**
  1. Open the iPhone keyboard sheet; type `Hello World 123 .,;:!?-_/@#`.
  2. Use Send, Return and Backspace.
  3. Send a string longer than 400 characters.
- **Expected:** Letters, digits and ASCII punctuation arrive exactly; Backspace and Enter work. Text longer than 400 characters arrives whole (BUG-019: live typing is split into steps, never cut off). Note any dropped, doubled or mis-shifted characters.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-KEY-02 — Typing in Netflix search

- **Audit IDs:** BUG-019, BUG-020
- **Devices:** iPhone, Box
- **Preconditions:** Box connected, keyboard helper ready, field focused on the TV.
- **Steps:**
  1. Open the iPhone keyboard sheet; type `Hello World 123 .,;:!?-_/@#`.
  2. Use Send, Return and Backspace.
  3. Send a string longer than 400 characters.
- **Expected:** Letters, digits and ASCII punctuation arrive exactly; Backspace and Enter work. Text longer than 400 characters arrives whole (BUG-019: live typing is split into steps, never cut off). Note any dropped, doubled or mis-shifted characters.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-KEY-03 — Typing in Stremio and Nuvio search

- **Audit IDs:** BUG-019, BUG-020
- **Devices:** iPhone, Box
- **Preconditions:** Box connected, keyboard helper ready, field focused on the TV.
- **Steps:**
  1. Open the iPhone keyboard sheet; type `Hello World 123 .,;:!?-_/@#`.
  2. Use Send, Return and Backspace.
  3. Send a string longer than 400 characters.
- **Expected:** Letters, digits and ASCII punctuation arrive exactly; Backspace and Enter work. Text longer than 400 characters arrives whole (BUG-019: live typing is split into steps, never cut off). Note any dropped, doubled or mis-shifted characters.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-KEY-04 — Typing in Android Settings text field (e.g. Wi-Fi/device name)

- **Audit IDs:** BUG-019, BUG-020
- **Devices:** iPhone, Box
- **Preconditions:** Box connected, keyboard helper ready, field focused on the TV.
- **Steps:**
  1. Open the iPhone keyboard sheet; type `Hello World 123 .,;:!?-_/@#`.
  2. Use Send, Return and Backspace.
  3. Send a string longer than 400 characters.
- **Expected:** Letters, digits and ASCII punctuation arrive exactly; Backspace and Enter work. Text longer than 400 characters arrives whole (BUG-019: live typing is split into steps, never cut off). Note any dropped, doubled or mis-shifted characters.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-KEY-05 — Typing in Browser address or search field

- **Audit IDs:** BUG-019, BUG-020
- **Devices:** iPhone, Box
- **Preconditions:** Box connected, keyboard helper ready, field focused on the TV.
- **Steps:**
  1. Open the iPhone keyboard sheet; type `Hello World 123 .,;:!?-_/@#`.
  2. Use Send, Return and Backspace.
  3. Send a string longer than 400 characters.
- **Expected:** Letters, digits and ASCII punctuation arrive exactly; Backspace and Enter work. Text longer than 400 characters arrives whole (BUG-019: live typing is split into steps, never cut off). Note any dropped, doubled or mis-shifted characters.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-KEY-06 — Non-ASCII behaviour

- **Audit IDs:** BUG-019
- **Devices:** iPhone, Box
- **Preconditions:** Keyboard sheet open.
- **Steps:**
  1. Type `café ✓ 日本` in live mode.
  2. Read the on-sheet hint.
- **Expected:** Hint says only plain ASCII can be typed; non-ASCII is not sent as wrong characters (record what appears on the TV).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-KEY-07 — Helper unavailable

- **Audit IDs:** UX-001, BUG-020
- **Devices:** iPhone, Box
- **Preconditions:** Make the keyboard helper unavailable (disconnect box or stop the helper).
- **Steps:**
  1. Open the keyboard sheet and type.
  2. Read the menu/connection guidance.
- **Expected:** Honest degraded message (“Not working yet: D-pad … Reconnect the TV box to restart them.”); no claim of success and no nonexistent ADB text fallback.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-KEY-08 — History privacy

- **Audit IDs:** SEC-002
- **Devices:** iPhone
- **Preconditions:** Keyboard sheet open.
- **Steps:**
  1. With “Remember sent text” on, Send two texts and reopen.
  2. Turn it off and reopen.
  3. Turn on, Send, then Clear history and swipe-delete.
  4. Type a fake password in live mode and check history.
- **Expected:** History shows only Sent texts, newest first, within the stated limit; turning it off clears and stops recording; Clear/Delete work; live typing never appears.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 5. App discovery and launch

The catalogue comes from a scan of installed packages (Leanback launcher first, then non-system phone-launcher apps), merged with curated apps and an “Android TV Settings” tile. Discovered names are derived from package names, so labels are approximate.

### HW-APP-01 — List shows installed launchable apps

- **Audit IDs:** UX-004, BUG-023
- **Devices:** iPhone, Box
- **Preconditions:** Box connected.
- **Steps:**
  1. Open Apps and wait for the scan.
  2. Compare with the box’s own app list.
- **Expected:** Installed launchable apps appear; system apps do not flood the list; curated apps that are not installed do not pretend to launch.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-APP-02 — Leanback preferred; Settings tile

- **Audit IDs:** UX-004
- **Devices:** iPhone, Box
- **Preconditions:** An app with both Leanback and phone launcher entries (e.g. YouTube).
- **Steps:**
  1. Launch it from its tile.
  2. Tap the Android TV Settings tile.
- **Expected:** App opens its TV (Leanback) UI; Settings tile opens Android TV Settings.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-APP-03 — Launch YouTube

- **Audit IDs:** UX-004, BUG-020, BUG-023
- **Devices:** iPhone, Box
- **Preconditions:** YouTube installed (if not, expect an explicit failure).
- **Steps:**
  1. Tap the YouTube tile.
  2. Observe the TV and the app’s status line.
- **Expected:** App opens in the foreground; if it cannot start the app explains why (no silent no-op, no false success).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-APP-04 — Launch Netflix

- **Audit IDs:** UX-004, BUG-020, BUG-023
- **Devices:** iPhone, Box
- **Preconditions:** Netflix installed (if not, expect an explicit failure).
- **Steps:**
  1. Tap the Netflix tile.
  2. Observe the TV and the app’s status line.
- **Expected:** App opens in the foreground; if it cannot start the app explains why (no silent no-op, no false success).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-APP-05 — Launch Stremio

- **Audit IDs:** UX-004, BUG-020, BUG-023
- **Devices:** iPhone, Box
- **Preconditions:** Stremio installed (if not, expect an explicit failure).
- **Steps:**
  1. Tap the Stremio tile.
  2. Observe the TV and the app’s status line.
- **Expected:** App opens in the foreground; if it cannot start the app explains why (no silent no-op, no false success).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-APP-06 — Launch Nuvio

- **Audit IDs:** UX-004, BUG-020, BUG-023
- **Devices:** iPhone, Box
- **Preconditions:** Nuvio installed (if not, expect an explicit failure).
- **Steps:**
  1. Tap the Nuvio tile.
  2. Observe the TV and the app’s status line.
- **Expected:** App opens in the foreground; if it cannot start the app explains why (no silent no-op, no false success).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-APP-07 — Launch Browser

- **Audit IDs:** UX-004, BUG-020, BUG-023
- **Devices:** iPhone, Box
- **Preconditions:** Browser installed (if not, expect an explicit failure).
- **Steps:**
  1. Tap the Browser tile.
  2. Observe the TV and the app’s status line.
- **Expected:** App opens in the foreground; if it cannot start the app explains why (no silent no-op, no false success).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-APP-08 — Install/uninstall refresh

- **Audit IDs:** UX-004
- **Devices:** iPhone, Box
- **Preconditions:** A removable test app on the box.
- **Steps:**
  1. Install it; refresh/relaunch Apps.
  2. Uninstall it; refresh again.
- **Expected:** Tile appears after install and disappears after uninstall, no stale tile.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-APP-09 — Launch failure messaging

- **Audit IDs:** BUG-016, BUG-020
- **Devices:** iPhone, Box
- **Preconditions:** A tile for an app that cannot start (disabled app).
- **Steps:**
  1. Tap the tile.
  2. Run the launcher restart once.
- **Expected:** Failure text reports the Android error line, “no answer from the TV box” or “Android did not confirm the start”; launcher restart reports whether it really started.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-APP-10 — Back/Home do not overtake queued D-pad

- **Audit IDs:** BUG-011
- **Devices:** iPhone, Box
- **Preconditions:** Box connected.
- **Steps:**
  1. Queue several D-pad taps, then Back, then Home, quickly.
- **Expected:** Order on the TV equals tap order.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 6. Connection and readiness

States: connected; connecting; degraded (names missing paths: D-pad, trackpad, Back/Home/volume); reconnect needed (“A TV helper stopped. Reconnect the TV box to recreate it.”); offline (“Not connected. Check the TV box is on, on the same Wi-Fi, with network debugging allowed.”).

### HW-CON-01 — ADB unauthorised guidance

- **Audit IDs:** UX-015
- **Devices:** iPhone, Box
- **Preconditions:** Revoke USB debugging authorisations on the box (Developer options).
- **Steps:**
  1. Tap Connect.
  2. Read the guidance; accept on the TV; tap Connect again.
- **Expected:** App tells you to choose Allow on the “Allow USB debugging?” prompt (tick “Always allow from this computer”); the prompt is not re-raised on every retry; connects after Allow.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-CON-02 — Readiness reflects each input path

- **Audit IDs:** UX-001
- **Devices:** iPhone, Box
- **Preconditions:** Connected, healthy.
- **Steps:**
  1. Read the header/menu state.
  2. Where possible take down one path at a time (keyboard helper, mouse helper, command shell) and re-read.
- **Expected:** Connected only when D-pad, trackpad and Back/Home/volume are all ready; otherwise degraded naming the missing path(s). Record which paths you could induce.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-CON-03 — Box reboot, standby, wake

- **Audit IDs:** UX-001
- **Devices:** iPhone, Box
- **Preconditions:** Connected.
- **Steps:**
  1. Put the box in standby, then wake it.
  2. Reboot the box.
  3. Observe the app throughout.
- **Expected:** Status moves to connecting/offline honestly, then recovers with helpers recreated; no stale “Connected” while the box is down.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-CON-04 — Foreground refresh

- **Audit IDs:** UX-001, UX-006
- **Devices:** iPhone, Box
- **Preconditions:** Connected.
- **Steps:**
  1. Background the app for a minute, change box state, return.
- **Expected:** On foreground the status refreshes and is truthful.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-CON-05 — Launcher restart result

- **Audit IDs:** BUG-016
- **Devices:** iPhone, Box
- **Preconditions:** Connected.
- **Steps:**
  1. Run launcher restart.
  2. Repeat with the box disconnected.
- **Expected:** Success only when Android confirms the start; failures show the Android error or “no answer from the TV box”.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-CON-06 — Visible transport errors

- **Audit IDs:** UX-005
- **Devices:** iPhone, Box
- **Preconditions:** Connected.
- **Steps:**
  1. Cut the box’s network; press a key, a volume button and a media button.
  2. Restore the network.
- **Expected:** Each failure is visibly reported, not silent; the message clears on recovery.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 7. Media states and transport

Phases: Not connected, Connecting, Nothing playing, Playing, Paused, Buffering, “Waiting for the TV” (stale: sample older than 30 s). Polling: 1 s playing, 5 s idle. Allowlisted audio apps: Spotify, YouTube Music, Apple Music, Deezer, Tidal; Nuvio is always video.

### HW-MED-01 — Playing / paused / idle

- **Audit IDs:** UX-006
- **Devices:** iPhone, Box
- **Preconditions:** Play a video in YouTube on the box.
- **Steps:**
  1. Open Now Playing; pause and resume from the iPhone and from the box; stop playback.
- **Expected:** Phase text follows reality within a few seconds (Playing, Paused, Nothing playing); play/pause sends pause when playing and play otherwise.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-MED-02 — Buffering / transient

- **Audit IDs:** UX-006
- **Devices:** iPhone, Box
- **Preconditions:** A stream that buffers (or toggle Wi-Fi).
- **Steps:**
  1. Start playback and force a buffer.
- **Expected:** Buffering shows and counts as playing; no flicker to idle between transitions.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-MED-03 — Stale mini-player

- **Audit IDs:** UX-006, UX-005
- **Devices:** iPhone, Box
- **Preconditions:** Playback running.
- **Steps:**
  1. Cut the box’s network for over 30 s.
  2. Check the mini-player and Now Playing.
- **Expected:** Shows “Waiting for the TV” instead of a frozen Playing state; clears when the connection returns.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-MED-04 — Timeline has no scrubber

- **Audit IDs:** UX-006
- **Devices:** iPhone, Box
- **Preconditions:** Video with known duration.
- **Steps:**
  1. Drag on the timeline; read it with VoiceOver.
- **Expected:** Timeline is progress only (no scrub/seek drag) and appears only when duration is positive.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-MED-05 — Prev/next only for audio

- **Audit IDs:** UX-006
- **Devices:** iPhone, Box
- **Preconditions:** Spotify and a video app.
- **Steps:**
  1. Play Spotify; inspect controls.
  2. Play a video in YouTube or Nuvio; inspect controls.
- **Expected:** Previous/Next appear only for audio sessions that support them, never for video.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-MED-06 — Nuvio vs Spotify vs YouTube

- **Audit IDs:** UX-006
- **Devices:** iPhone, Box
- **Preconditions:** All three installed.
- **Steps:**
  1. Play each in turn; read app name, artwork and controls.
- **Expected:** Nuvio and YouTube are treated as video; Spotify as audio; app names are right.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 8. Nuvio and Discover

Stream picker shows “Open in Nuvio” first, then add-on streams. Handoff to Nuvio accepts only HTTPS add-on links; torrents and streams needing request headers are refused with direction to Open in Nuvio.

### HW-NUV-01 — Series handoff with selected episode

- **Audit IDs:** BUG-012
- **Devices:** iPhone, Box
- **Preconditions:** Nuvio on the box; account/add-ons set up; a series in Discover.
- **Steps:**
  1. Open a series and select a specific episode (not the first).
  2. Open the stream picker and note the episode shown.
  3. Choose Open in Nuvio and an add-on stream.
- **Expected:** Picker shows the selected episode; Nuvio on the TV opens that same episode, not episode 1.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-NUV-02 — Resume episode

- **Audit IDs:** BUG-012
- **Devices:** iPhone, Box
- **Preconditions:** A series with watch progress.
- **Steps:**
  1. Open the series and use Play/Resume.
- **Expected:** The resume episode reaches the stream picker and Nuvio.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-NUV-03 — Handoff status truthful

- **Audit IDs:** BUG-013, UX-010
- **Devices:** iPhone, Box
- **Preconditions:** Box connected.
- **Steps:**
  1. Hand off a stream and watch the status.
  2. Repeat with Nuvio missing, the box disconnected, and an HTTP-only add-on.
- **Expected:** Sent is reported only after the intent succeeds; failures distinguish missing app, permission denied and no connection; unsupported streams give a clear reason.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-NUV-04 — Sign-out during refresh

- **Audit IDs:** BUG-017
- **Devices:** iPhone
- **Preconditions:** Signed in to Nuvio.
- **Steps:**
  1. Start a refresh/sync and sign out immediately.
  2. Check Discover and the account sheet.
- **Expected:** No stale signed-in data returns; no crash.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-NUV-05 — Add-on repair after restore (missing secret)

- **Audit IDs:** BUG-018, SEC-003
- **Devices:** iPhone
- **Preconditions:** Device where the add-on link is missing from Keychain (restore to a new device or equivalent).
- **Steps:**
  1. Open Add-ons and the affected add-on.
  2. Paste the same install link as prompted.
- **Expected:** Page explains links are kept in the Keychain and may not return after a restore; pasting the same link restores it and nothing else changes; add-on works.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-NUV-06 — Add-on removal confirmation

- **Audit IDs:** UX-011
- **Devices:** iPhone
- **Preconditions:** At least one add-on installed.
- **Steps:**
  1. Swipe left to remove; cancel; repeat and confirm.
  2. Remove from the detail page (“Remove add-on”).
- **Expected:** Removal always asks “Remove …?” first; Cancel keeps the add-on.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-NUV-07 — Cinemeta partial failure

- **Audit IDs:** BUG-021, UX-017
- **Devices:** iPhone
- **Preconditions:** Block Cinemeta for part of the session (airplane mode mid-load or router block).
- **Steps:**
  1. Open Discover and scroll all rows.
- **Expected:** Loaded rows show; failed rows show an explicit unavailable state; no whole-page blank, no endless spinner.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-NUV-08 — Search history only intentional queries

- **Audit IDs:** BUG-022
- **Devices:** iPhone
- **Preconditions:** Discover search available.
- **Steps:**
  1. Type without submitting and leave.
  2. Submit one query and check history.
- **Expected:** Only submitted queries enter history.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-NUV-09 — Pull-to-refresh (deferred, observation)

- **Audit IDs:** Deferred
- **Devices:** iPhone
- **Preconditions:** Discover open.
- **Steps:**
  1. Pull down on a Discover page.
- **Expected:** Observation only: pull-to-refresh was deferred because of a gesture conflict; record that nothing misbehaves (no page switch).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 9. Accessibility

### HW-A11-01 — VoiceOver: Remote and trackpad

- **Audit IDs:** A11Y-001
- **Devices:** iPhone, Box
- **Preconditions:** VoiceOver on.
- **Steps:**
  1. Swipe through Remote: header status, D-pad, mode selector, volume row, trackpad.
- **Expected:** Every control has a sensible label, value and trait; the volume row speaks output name, relative or measured value, or “Unavailable, <reason>”.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-A11-02 — VoiceOver: Discover hero, artwork, progress

- **Audit IDs:** A11Y-003, A11Y-005
- **Devices:** iPhone
- **Preconditions:** VoiceOver on.
- **Steps:**
  1. Move through the Discover hero, a poster row and title detail.
  2. On Now Playing read artwork and progress.
- **Expected:** Hero and artwork have meaningful labels (decorative art hidden); progress reads position/duration; no unlabeled buttons.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-A11-03 — Reduce Motion (incl. new profiles)

- **Audit IDs:** A11Y-006
- **Devices:** iPhone, Box
- **Preconditions:** Reduce Motion on.
- **Steps:**
  1. Open Remote, Now Playing, Discover; pause/resume playback; switch profiles.
- **Expected:** Artwork scaling and animated backgrounds are reduced or replaced by non-motion transitions.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-A11-04 — Contrast

- **Audit IDs:** A11Y-006
- **Devices:** iPhone
- **Preconditions:** Light and dark appearance; Increase Contrast on and off.
- **Steps:**
  1. Inspect secondary text on Now Playing and Remote.
- **Expected:** Secondary text is readable over artwork-derived backgrounds (4.5:1 target); record low-contrast spots.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-A11-05 — Dynamic Type (A11Y-004 deferred, observation)

- **Audit IDs:** A11Y-004
- **Devices:** iPhone
- **Preconditions:** Smallest and largest accessibility text sizes.
- **Steps:**
  1. Visit every page and sheet; note truncation or overlap.
- **Expected:** Observation only: list screens and controls that clip or overlap.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 10. Privacy and security

### HW-SEC-01 — Keychain items survive update

- **Audit IDs:** SEC-003
- **Devices:** iPhone
- **Preconditions:** Previous build installed with add-ons, Nuvio sign-in and Samsung approval.
- **Steps:**
  1. Install the new build over it (no delete).
  2. Open Add-ons, the Nuvio account and Samsung.
- **Expected:** Add-ons, sign-in and Samsung approval persist.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SEC-02 — Add-on tokens not shown or logged

- **Audit IDs:** SEC-002, SEC-003
- **Devices:** iPhone
- **Preconditions:** An add-on whose link contains a secret.
- **Steps:**
  1. Check add-on list and detail show only the address.
  2. With the iPhone attached to Console, refresh add-ons and play a title.
- **Expected:** The full link/secret never appears in the UI or device logs.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SEC-03 — Keyboard history privacy

- **Audit IDs:** SEC-002
- **Devices:** iPhone
- **Preconditions:** See HW-KEY-08.
- **Steps:**
  1. Confirm nothing is stored when the toggle is off; read the on-screen privacy text.
- **Expected:** Matches HW-KEY-08; live typing never persisted.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SEC-04 — Samsung token isolation

- **Audit IDs:** BUG-005, SEC-001
- **Devices:** iPhone, Samsung TV
- **Preconditions:** See HW-SAM-07.
- **Steps:**
  1. Cross-reference HW-SAM-07; check Connection-sheet diagnostics.
- **Expected:** Token not sent to another address; diagnostics never show the token.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SEC-05 — TLS to Samsung (SEC-001 deferred, observation)

- **Audit IDs:** SEC-001
- **Devices:** iPhone, Samsung TV
- **Preconditions:** Optional capture on the LAN.
- **Steps:**
  1. Note the scheme and certificate handling of the Samsung WebSocket; do not alter anything.
- **Expected:** Observation only: record current behaviour (accepts any certificate for the configured IP; token in URL query). Do not weaken or change it.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SEC-06 — TV-side listener exposure (BUG-010 deferred, observation)

- **Audit IDs:** BUG-010
- **Devices:** Box, PC with adb
- **Preconditions:** PC on the same LAN with adb connected to the box (`adb connect <box>:5555`). Do not modify the helper.
- **Steps:**
  1. Run `adb shell ss -ltnp` (or `netstat -ltn`) on the box.
  2. Record the address and port of the helper’s input listener and whether it binds 127.0.0.1 or all interfaces.
  3. From another LAN host attempt a bare TCP connect to that port; send nothing.
  4. Audit §19.3 row 24 probe, with the Remote open on the D-pad: run `adb shell "echo 'K 82' | nc 127.0.0.1 47632"` and watch the TV.
- **Expected:** Observation only: record whether the listener is loopback-only, whether it is reachable from the LAN, and whether step 4 injected a key (a reaction on the TV means any local app on the box can inject input — the known BUG-010 gap). Also note whether the app's own input connection dropped afterwards ("newest connection wins").
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-SEC-07 — Box ABI and 32-bit mouse bridge (ARCH-003)

- **Audit IDs:** ARCH-003 (§19.3 row 25)
- **Devices:** Box, PC with adb, iPhone
- **Preconditions:** App connected to the box.
- **Steps:**
  1. Run `adb shell getprop ro.product.cpu.abi` and `adb shell getprop ro.product.cpu.abilist`.
  2. In Mouse mode, move the cursor, click and drag.
- **Expected:** ABI recorded; the mouse helper runs and the cursor works. If the box is 64-bit-only (no `armeabi-v7a` in the list), the 32-bit bridge cannot run: record as Fail.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 11. Rotation and layout on iPhone

### HW-LAY-01 — Remote page portrait/landscape

- **Audit IDs:** BUG-007, UX-014
- **Devices:** iPhone, Box
- **Preconditions:** Standard-size iPhone.
- **Steps:**
  1. Rotate through portrait, landscape left and right on Remote.
  2. Check D-pad, volume row and trackpad are reachable.
- **Expected:** No clipped controls; D-pad and trackpad usable; no stuck key on rotation.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-LAY-02 — Now Playing, Discover and Apps rotation

- **Audit IDs:** UX-014
- **Devices:** iPhone, Box
- **Preconditions:** Media playing.
- **Steps:**
  1. Rotate on Now Playing, Discover and Apps.
- **Expected:** Artwork scales for each orientation; transport and sliders remain visible and usable.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-LAY-03 — Small iPhone (SE-class)

- **Audit IDs:** UX-014
- **Devices:** iPhone, Box
- **Preconditions:** SE-class device.
- **Steps:**
  1. Repeat HW-LAY-01 and HW-LAY-02 in both orientations.
  2. Open the keyboard sheet, Samsung settings and Add-ons.
- **Expected:** No clipped or unreachable controls; sheets scroll; the volume row and slider stay visible.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-LAY-04 — Rotation mid-gesture

- **Audit IDs:** BUG-006, BUG-007, BUG-008
- **Devices:** iPhone, Box
- **Preconditions:** Box connected.
- **Steps:**
  1. Hold a D-pad key and rotate.
  2. Start a mouse drag and rotate.
- **Expected:** All input is cancelled safely (see HW-GES-05 and HW-GES-10).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## 12. Android TV Remote v2 (optional transport)

Status: **not tested on hardware.** Protocol and routing details: `audit/REMOTE_V2_PROTOCOL_NOTES.md`. Trust model: `audit/REMOTE_V2_SECURITY_REVIEW.md`. Full 12-step procedure (all NOT TESTED): `audit/REMOTE_V2_HARDWARE_TEST_PROCEDURE.md`.

### HW-RV2-01 — Pairing

- **Audit IDs:** Remote v2 (PR #10)
- **Devices:** iPhone, Box
- **Preconditions:** Remote v2 enabled in Connection settings; box address set.
- **Steps:**
  1. Tap Pair; read the code on the TV.
  2. Type a wrong code, then the correct code.
- **Expected:** The wrong code is refused locally without ending pairing; the correct code pairs and the status reads "Remote v2 connected" (not "TV identity changed": the TV key pinned at pairing must match the control port, HW-P03).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-RV2-02 — Reconnect after relaunch

- **Audit IDs:** Remote v2 (PR #10)
- **Devices:** iPhone, Box
- **Preconditions:** Paired (HW-RV2-01).
- **Steps:**
  1. Force-quit and relaunch the app.
- **Expected:** Remote v2 reconnects without pairing again.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-RV2-03 — Navigation over v2

- **Audit IDs:** Remote v2 (PR #10)
- **Devices:** iPhone, Box
- **Preconditions:** Remote v2 connected.
- **Steps:**
  1. Tap and hold each D-pad key, OK, Back and Home.
- **Expected:** One action per tap; holds repeat and stop on lift; OK never repeats Enter.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-RV2-04 — Media keys over v2

- **Audit IDs:** Remote v2 (PR #10)
- **Devices:** iPhone, Box
- **Preconditions:** Remote v2 connected; media playing.
- **Steps:**
  1. Use Play, Pause, Next, Previous, Rewind and Fast-forward from Now Playing and the compact now-playing bar (the Remote page has no media buttons).
  2. Disable ADB (USB/network debugging) with v2 still connected, open Now Playing, and use Rewind, Play/Pause and Fast-forward.
- **Expected:** Step 1: each tap acts once; the app log shows "sent over Remote v2"; an unconfirmed Play/Pause is reported as not accepted, with no ADB retry. Step 2: each tap acts once on the TV; the app shows "sent over Remote v2 · not confirmed"; the log shows no ADB attempt and no dispatch retry; with v2 also down the buttons are disabled and nothing is sent.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-RV2-05 — Link lost mid-hold

- **Audit IDs:** Remote v2 (PR #10)
- **Devices:** iPhone, Box
- **Preconditions:** Remote v2 connected.
- **Steps:**
  1. Hold a D-pad key, then turn the iPhone's Wi-Fi off and on.
- **Expected:** The hold stops; no stray or duplicate keys on ADB; v2 reconnects with backoff (1, 2, 4, 8, 16, 30 s).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-RV2-06 — ADB-only paths unchanged

- **Audit IDs:** Remote v2 (PR #10)
- **Devices:** iPhone, Box
- **Preconditions:** Remote v2 connected, then disabled.
- **Steps:**
  1. Use volume and mute, typing, trackpad and scroll, the app list and app launch, diagnostics, standby and wake.
- **Expected:** Identical with v2 on and off; volume still follows "Volume goes to" (soundbar via ADB 24/25/164 or the Samsung route).
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________

### HW-RV2-07 — Pairing removed on the TV

- **Audit IDs:** Remote v2 (PR #10)
- **Devices:** iPhone, Box
- **Preconditions:** Paired.
- **Steps:**
  1. Remove GlassRemote from the TV's remote settings; reopen the app.
  2. Pair again.
- **Expected:** The app shows "Remote v2 not paired" and pairing again works; every command falls back to ADB meanwhile.
- **Result:** ☐ Pass ☐ Fail ☐ Blocked  **Notes:** ________________________________


## Summary results

| § | Section | Checks | Pass | Fail | Blocked | Notes / issue refs |
|---|---|---|---|---|---|---|
| 1 | Volume | 13 | | | | |
| 2 | Samsung TV | 8 | | | | |
| 3 | Gestures and input | 14 | | | | |
| 4 | Keyboard entry | 8 | | | | |
| 5 | App discovery/launch | 10 | | | | |
| 6 | Connection/readiness | 6 | | | | |
| 7 | Media states | 6 | | | | |
| 8 | Nuvio/Discover | 9 | | | | |
| 9 | Accessibility | 5 | | | | |
| 10 | Privacy/security | 7 | | | | |
| 11 | Rotation/layout | 4 | | | | |
| 12 | Remote v2 | 7 | | | | |
| | **Total** | **97** | | | | |

**Release decision:** ☐ All non-deferred checks pass ☐ Failures filed (list): ____________

**Deferred observations recorded:** ☐ SEC-001 ☐ BUG-010 ☐ A11Y-004 ☐ Discover pull-to-refresh ☐ OK long-press

**Tester sign-off / date:** ____________
