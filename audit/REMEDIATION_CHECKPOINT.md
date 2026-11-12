# Remediation checkpoint (branch `Phase-9-remediation`)

Nothing is merged. PR #9 is a draft against `Phase-9-gap-fixes`.

## Done
- Priorities A–E and the secondary fixes: see `audit/GLASSREMOTE_REMEDIATION_REPORT.md` for each audit ID, files, tests and evidence level.
- CI: `93f4a8d` green (615 tests, 0 failures, IPA built); no new compiler warnings versus the base branch.
- Continuation: `HeldTouchGate` stops a cancelled D-pad key restarting on the same touch (BUG-007, defeated the 30 s cap); app scan reports "app list unavailable on this box" when no launch activities are listed (UX-004); README, REGRESSION_CHECKLIST and a PHASE-7-NOTES "superseded" banner updated; report and `audit/GLASSREMOTE_HARDWARE_ACCEPTANCE_CHECKLIST.md` written.

## Deferred (rationale and next steps in the report)
SEC-001, BUG-010, BUG-009 long-press, ARCH-003, ARCH-005, VIS-001, A11Y-004, PERF-001–004, UX-009 pull-to-refresh.

## Next action
1. Confirm CI for the continuation commit (`gh run list --branch Phase-9-remediation`); expected 619 tests.
2. Run the hardware acceptance checklist on the iPhone, box, Samsung TV and soundbar.
