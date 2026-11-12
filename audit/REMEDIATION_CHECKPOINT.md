# Remediation checkpoint (branch `Phase-9-remediation`)

Saved because usage was running out. Code is pushed; nothing is merged.

## Done (code + unit tests, CI-verified only where a green run exists)
- **A (volume):** BUG-001/002/003/004/005, UX-002/003/008 — `RemediationVolumeTests`.
- **B (gestures):** BUG-006/007/008/015, UX-012; BUG-009 partial (OK no longer repeats; real long-press needs key-down/up in the UHID keyboard helper) — `RemediationGestureTests`.
- **C (feedback):** UX-001/005/006/007/013/014/015, BUG-011/016, A11Y-002 — `RemediationFeedbackTests`. BUG-020 by the apps work.
- **D (Discover/Nuvio):** BUG-012/013/014/017/018/021/022, UX-009 (pull-to-refresh deferred: clashes with the hero's pull gesture), UX-010/011/017, A11Y-003/005 — `RemediationDiscoverTests`.
- **E (apps):** UX-004, BUG-019/020/023, SEC-002 — `RemediationAppsTests`.
- **Secondary (last commit, not yet CI-verified):** A11Y-001 trackpad VoiceOver actions, A11Y-006 Reduce Motion copied to new profiles, SEC-003 Keychain update-in-place with status checks, UX-016 label, ARCH-002 removed unused `NowPlayingSheet.swift`.

## Not done / deferred
- SEC-001 Samsung TLS pinning (trust-on-first-use): protected pairing path, needs a real TV to confirm the certificate is stable; deferred.
- BUG-010 TV-side loopback listener auth: protected C helper protocol, needs the box; deferred.
- ARCH-003 helper provenance doc, ARCH-005 snapshot comparison, VIS-001 trackpad ghost investigation, A11Y-004 Dynamic Type sweep, PERF-*.
- Docs: README and REGRESSION_CHECKLIST still describe the old TV-speakers key fallback and the 192.168 default; update them.
- Deliverables still to write: `audit/GLASSREMOTE_REMEDIATION_REPORT.md`, `audit/GLASSREMOTE_HARDWARE_ACCEPTANCE_CHECKLIST.md` (derive from audit §19.3).

## Next action
1. Check CI for the latest commit: `gh run list --branch Phase-9-remediation`. Fix any compile/test failures (nothing was compiled locally; there is no Xcode in the sandbox).
2. Update README / REGRESSION_CHECKLIST, then write the two deliverables above.

## Hardware still required for everything
Volume direction and sweep on the real soundbar, gesture interruption (Control Center, calls), rotation, app launching (YouTube, Stremio, Netflix, Settings), text entry, playback states, Samsung reconnect after an address change, VoiceOver.
