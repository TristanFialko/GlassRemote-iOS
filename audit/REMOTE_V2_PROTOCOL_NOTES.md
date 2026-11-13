# Android TV Remote v2: protocol notes and acceptance checklist

Reference: tronikos/androidtvremote2 v0.3.3 (commit f95bfb4046668dcd770e569479f645ded4530c28).

## Transports
- Pairing: TLS on TCP 6467, Polo protocol v2, varint-length-prefixed protobuf frames.
- Control: TLS on TCP 6466, RemoteMessage protobuf, same framing (frames capped by RemoteV2FrameDecoder).
- Client identity: RSA 2048 in the Keychain (AfterFirstUnlockThisDeviceOnly, tag com.glassremote.remotev2.client-key) and a self-signed X.509 v3 certificate (CN=atvremote, SHA-256/RSA, 20 years). The TV's self-signed certificate has no chain to validate; instead its leaf RSA key is captured per TLS session, checked against the pairing code's check byte, pinned per host at pairing (SHA-256 fingerprint), and required to match on every control connection (mismatch: "TV identity changed, pair again", no retry). See `REMOTE_V2_SECURITY_REVIEW.md`.

## Pairing (RemoteV2PairingSession)
1. PairingRequest(service "atvremote", client "GlassRemote") -> ack
2. Options(input hex 6, role input) -> options
3. Configuration(hex 6, role input) -> ack: the TV shows a code
4. The user types the code. Its first byte must equal byte 0 of SHA-256(client n, client e, server n, server e, code[1..2]). A mismatch is rejected locally and nothing is sent.
5. Secret(SHA-256 digest) -> secret ack: paired. A 402 status means the TV rejected the code.

## Control (RemoteV2ControlConnection)
- TV configure -> reply with configure (features requested 611, intersected with the TV's set) and device info. TV set-active -> reply with set-active(features). Ping -> pong.
- Ready only after RemoteStart. Keys and app links are sent only while ready and only for negotiated features; nothing is queued.
- 16 s idle timeout. Reconnect backoff is 1, 2, 4, 8, 16, then 30 s. A TLS handshake failure is reported as not paired, with no retry.

## Routing
- Remote v2 is opt-in (off by default). When enabled and connected, D-pad, OK, Back and Home use v2; otherwise they use ADB.
- Media transport keys (PLAY_PAUSE 85, STOP 86, NEXT 87, PREVIOUS 88, REWIND 89, FAST_FORWARD 90, PLAY 126, PAUSE 127) sent through `androidKey(_:)` (Player, now-playing card, Remote media buttons) use v2 when it is enabled, connected and has negotiated the key feature; otherwise ADB `input keyevent`. Each tap goes over exactly one transport (`RemoteTransportPolicy`, `RemoteV2KeyMap.discreteMediaCodes`).
- Play/pause verification still reads the media session over ADB. The `cmd media_session dispatch` retry runs only when the key itself went over ADB (`MediaRetryPolicy`); a key handed to v2 is never re-sent on ADB, so an unconfirmed v2 play/pause is reported as not accepted.
- Media commands still require the ADB connection (unchanged guard in `sendMedia`), because their result is checked against the ADB media session.
- Always ADB: text/IME, mouse/UHID, trackpad scroll, app discovery, diagnostics, helpers, soundbar volume.
- Volume and mute never use Remote v2: codes 24, 25, 164 and 91 are blocked in the key map and again in the control connection.
- A held key is pinned to the transport that started it; if that transport goes down, the rest of the hold is dropped.
- Power stays on its existing paths by design: standby/wake send SLEEP 223 / WAKEUP 224 over ADB (idempotent), and "turn everything off" adds the Samsung TV_POWER key. Remote v2's POWER 26 is a toggle, which would change the meaning of standby/wake, so it is not used. SLEEP/WAKEUP over v2 is not enabled until verified on hardware. Enforced in code: `RemoteOperation.power`/`.appLaunch` allow ADB only, POWER is not in the v2 key map, and the control connection drops codes 26/223/224 and app links.
- App launch stays on ADB by design: the app launches by package/activity over ADB with its existing feedback, while v2 offers only an app-link URI (`RemoteV2Outbound.appLink`) with no launch result. App discovery is ADB-only.

## Hardware acceptance (not yet done, requires a real Android TV / Google TV)
- [ ] Pair: the code appears on the TV; a mistyped code is refused without ending pairing; the correct code pairs.
- [ ] Relaunch the app: it reconnects without pairing again (Keychain identity persists).
- [ ] D-pad, OK, Back and Home act once per tap; holds repeat and stop on release.
- [ ] With v2 connected: Play, Pause, Next, Previous, Rewind and Fast-forward act once per tap (log shows "sent over Remote v2"); Play/Pause are confirmed by the session, or reported as not accepted with no ADB retry.
- [ ] With v2 off or disconnected: the same media buttons behave exactly as before (ADB keyevent, dispatch retry for play/pause).
- [ ] Standby, wake and "turn everything off" behave exactly as before with v2 on and off.
- [ ] Turn Wi-Fi off and on mid-hold: no stray or duplicate keys; v2 reconnects with backoff.
- [ ] Remove the pairing on the TV: the app shows "not paired", and pairing again works.
- [ ] Volume and mute still follow "Volume goes to" (soundbar via ADB 24/25/164, or the Samsung route).
- [ ] Typing, trackpad, app list, diagnostics and helpers are unchanged with v2 on and off.
- [ ] The Samsung target is unaffected.
