# Android TV Remote v2: protocol notes and acceptance checklist

Reference: tronikos/androidtvremote2 v0.3.3 (commit f95bfb4046668dcd770e569479f645ded4530c28).

## Transports
- Pairing: TLS on TCP 6467, Polo protocol v2, varint-length-prefixed protobuf frames.
- Control: TLS on TCP 6466, RemoteMessage protobuf, same framing (frames capped by RemoteV2FrameDecoder).
- Client identity: RSA 2048 in the Keychain (AfterFirstUnlockThisDeviceOnly, tag com.glassremote.remotev2.client-key) and a self-signed X.509 v3 certificate (CN=atvremote, SHA-256/RSA, 20 years). The TV's self-signed certificate is accepted without chain validation, and its leaf public key is captured per TLS session.

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
- Always ADB: text/IME, mouse/UHID, trackpad scroll, app discovery, diagnostics, helpers, soundbar volume.
- Volume and mute never use Remote v2: codes 24, 25, 164 and 91 are blocked in the key map and again in the control connection.
- A held key is pinned to the transport that started it; if that transport goes down, the rest of the hold is dropped.
- Not yet routed over v2: media keys, power and app launch (they still use their existing paths).

## Hardware acceptance (not yet done, requires a real Android TV / Google TV)
- [ ] Pair: the code appears on the TV; a mistyped code is refused without ending pairing; the correct code pairs.
- [ ] Relaunch the app: it reconnects without pairing again (Keychain identity persists).
- [ ] D-pad, OK, Back and Home act once per tap; holds repeat and stop on release.
- [ ] Turn Wi-Fi off and on mid-hold: no stray or duplicate keys; v2 reconnects with backoff.
- [ ] Remove the pairing on the TV: the app shows "not paired", and pairing again works.
- [ ] Volume and mute still follow "Volume goes to" (soundbar via ADB 24/25/164, or the Samsung route).
- [ ] Typing, trackpad, app list, diagnostics and helpers are unchanged with v2 on and off.
- [ ] The Samsung target is unaffected.
