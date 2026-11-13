# Android TV Remote v2 — security and trust-model review

Scope: `GlassRemote/RemoteV2/*`, the Remote v2 routing in `RemoteModel+RemoteV2.swift`, `RemoteModel+Features.swift`, `RemoteModel+Playback.swift`, and `RemoteModel.key(_:)`. Reviewed independently from scratch at branch head `4c488e5` (PR #10). Reference: tronikos/androidtvremote2 v0.3.3 (`f95bfb4046668dcd770e569479f645ded4530c28`), files `pairing.py`, `remote.py`, `certificate_generator.py`.

Status: software review and unit tests only. **Nothing here is verified on hardware** (see `REMOTE_V2_HARDWARE_TEST_PROCEDURE.md`).

## Findings and fixes

| # | Finding | Severity | Fix |
|---|---|---|---|
| F1 | The TLS verify block accepted any server certificate (`complete(true)`), and no TV identity was stored. Any host answering on 6466 at the box address was trusted for control sessions after pairing. | Medium | The TV's RSA public key proved during pairing is pinned per host (`RemoteV2PairingRecord`, SHA-256 fingerprint). Control connections compare the presented key before processing or writing any frame. A mismatch fails closed with **"Remote v2 blocked · TV identity changed, pair again"**, with no automatic retry. A missing pin is reported as not paired. |
| F2 | `RemoteOperation.power` and `.appLaunch` allowed `.remoteV2`, and `RemoteV2KeyMap.codes` contained `"POWER": 26`. `RemoteModel.key("POWER")` would therefore have sent KEYCODE_POWER over v2 whenever v2 was connected (unless the Samsung TV-only path caught it first). This contradicts the policy that power/wake and app launch are ADB-only. | Policy violation | Power and app launch are now `[.adb]` only, with no v2 feature. POWER has been removed from the v2 key map. The control connection also drops key codes 26/223/224 and every app-link message as a last line of defence. |
| F3 | TLS failures are all classified as `authenticationRejected`, so they show as "not paired" with no retry. | Low (UX) | Kept: fail closed is the safe direction, and pairing again recovers. Documented as a risk. |

Verified correct as-is (no change):
- **Volume/mute exclusion:** `key(_:)` sends volume keys to the volume output before any v2 routing. The forbidden set {24, 25, 164, 91} is enforced by the key map, by `discreteOperation`, and again in the control connection. `MediaRetryPolicy` never retries a v2 send. A held key stays pinned to its transport (`RemoteV2KeyGestureRouter`).
- **Framing:** varint length prefix, 64 KiB cap, a prefix longer than 5 bytes is treated as corrupt, and fragmented and coalesced frames are handled. A decode error drops the link and it reconnects with backoff.
- **Stale callbacks:** generation tokens in both pairing and control, and controller identity checks (`self.control === connection`).
- **Readiness:** commands are sent only after RemoteStart and only for negotiated features. Nothing is queued.
- **Keychain:** RSA-2048 key, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (not synced, not in backups to other devices). A Keychain failure means pairing fails as identity unavailable and the control state shows failed. No silent fallback key.
- **Secret lifecycle:** the code is held only in the text field and the pairing call. The secret is computed, sent once, and never stored. UserDefaults holds only host names and public-key fingerprints. Logs contain phase names and key codes only: no codes, secrets, keys or certificates.

## Trust model — answers

1. **What authenticates the TV at pairing?** Only the 6-hex-digit code shown on the TV screen. The first byte is a check byte, `SHA-256(client n, client e, server n, server e, nonce)[0]`. The client computes it with the server key from *this* TLS session and refuses to send the secret on mismatch (`RemoteV2PairingCode.secret`). There is no PKI: the TV certificate is self-signed.
2. **Is the code proof bound to the TV's RSA key and host?** It is bound to both RSA keys in the session, but only with 8 bits (the check byte). It is not bound to the host or IP. A pairing-time man-in-the-middle passes the check with probability 1/256 per attempt. After that it sees the secret, which lets it brute-force the 16-bit nonce offline. So pairing should be done on a trusted LAN; this is a protocol limitation, not an implementation bug.
3. **What stops impersonation on later control connections?** In the reference, nothing on the client side. The TV authenticates the client by its pinned client certificate, but the client accepts any server. GlassRemote now pins the TV key from pairing (F1), so an impostor on 6466 must hold the TV's private key.
4. **Is the TV key stable?** The Android TV Remote Service generates its key pair once and reuses it for both 6466 and 6467 until its data is cleared or the device is factory-reset. This is not verified on the ARRIS VIP7802 (hardware procedure item HW-P03).
5. **Should the app persist and compare a per-device fingerprint?** Yes. It costs nothing in the normal case. It turns "trust any host at this IP" into "trust the key that proved the code". Its failure mode (a false mismatch) is visible and recoverable by pairing again.
6. **What happens when the TV certificate changes?**
   - **Factory reset or Remote Service data cleared:** new key → mismatch → "TV identity changed, pair again". The TV has also forgotten the client, so pairing again is needed either way.
   - **Firmware update:** normally keeps the key. If it doesn't, the same recovery applies.
   - **Host or IP change:** the pin is per host, so a new IP shows "not paired". A *different* box that takes over the old IP shows a mismatch, which is exactly the impersonation case.
   - **Re-pair:** replaces the pin.
   - **Forget:** removes the pin and the host.
7. **What does the reference do?** `ssl.CERT_NONE` with no hostname check. It reads the peer certificate only to compute the pairing secret, and does not pin on control connections.
8. **What trade-off does the protocol require?** Self-signed certificates mean chain validation is impossible, so trust must come from the out-of-band code (weak, 8-bit binding) plus trust-on-pairing pinning. The residual risks are pairing on a hostile LAN, and a false mismatch if a device rotates its key without a reset (fails closed; recovery is pairing again).

## Residual risks

- **8-bit pairing binding** (protocol limitation; see answer 2).
- **Pin is keyed by host string:** DHCP changes require pairing again.
- **UserDefaults storage:** the pin is an integrity-relevant value but not a secret. An attacker who can write the app sandbox is out of scope.
- **Key stability on hardware:** if the ARRIS box presented different keys on 6466 and 6467, every control connection would show "TV identity changed". This must be checked first on hardware (HW-P03). The fix would be to pin per port.
- **TLS classification is broad** (F3).
