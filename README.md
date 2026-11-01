# Glass Remote (iOS)

Native iPhone remote for the ARRIS VIP7802 Android TV box running Glass Launcher.
Black smoked-glass look using native Liquid Glass on iOS 26+ (your iOS 27 phone), always in Dark Mode.

## What is in this version
- **Mouse / D-pad** are still the two core modes. The selector now spans the full width (50% / 50%, capsule, selected glass pill that slides between segments).
- **Mouse**: unchanged engine (UHID bridge, ×2 movement, 8 pt tap threshold, 45 ms click, drag, two-finger scroll, white cursor).
- **Apps**: collapsed row by default; opens to the original 3×3 grid (same nine apps, order, artwork); collapses after a launch. While open, the mouse/D-pad surface is dimmed and the page scrolls.
- **Now Playing**: title, app, playback position. Controls appear only if the active media session advertises them (see "Media" below).
- **Power menu**: Standby, Wake, Restart launcher, Restart TV box (confirmation dialogs for the disruptive ones).
- **Quick Actions**: create/edit/reorder macros (open app, whitelisted key, wait, volume steps). Stored locally in UserDefaults. The three starter actions are examples you can change.
- **Keyboard sheet**: type + Send, system Paste button (clipboard is never read silently), Backspace, Enter, recent text history (Clear button).
- **Volume**: optional Samsung TV route (port 8002). Off by default. ADB volume remains the fallback.
- **Siri / Shortcuts**: "Open TV App" and "Run Quick Action" intents.

## Build (unchanged workflow, from Windows)
1. Upload the **contents** of this folder to your private GitHub repo `GlassRemote-iOS` (include `.github`).
2. Actions → `iOS build` → Run workflow. It now uses the `macos-26` runner (Xcode 26 SDK) because native `glassEffect` needs it.
3. Download `glassremote-unsigned-ipa` and sideload as before. If the build fails, download `glassremote-build-logs` and send the error.

The deployment target is still iOS 16. Liquid Glass is guarded with `#available(iOS 26, *)` and `#if compiler(>=6.2)`, so older SDKs/OS versions use a material fallback and still compile.

## Not touched
UHID report protocol and helpers, ADB identity/keys, Android packages (nothing is disabled or changed), TwoFingerScroll, VirtualKeyboard, connection recovery logic.

## Behaviour changes to know about
- Connects automatically on launch (the old top-right refresh button is replaced by the Power menu; tap the status pill to reconnect).
- `input text` escaping: spaces become `%s`; literal `%` is no longer rewritten to `%25` (Android's `input text` does not decode `%25`, so that would have typed "%25"); a literal "%s" is split so it is not turned into a space; newlines send Enter; long text is chunked. Non-ASCII characters cannot be typed over ADB.
- The old inline text field is now in the Keyboard sheet.

## Media details (from your `dumpsys media_session`)
Stremio advertises pause / play-pause / seek-to only, so Rewind and Fast-forward are shown dimmed and disabled. Spotify advertises previous/next/rewind/fast-forward, so those enable when it is the active session. No duration is reported, so there is no seek slider; a slider would need Android-side support.
Play/pause uses `KEYCODE_MEDIA_PLAY_PAUSE` (85), previous/next 88/87, rewind/FF 89/90.

## Samsung TV volume
Enable in Connection → Volume, enter the TV's IP. First connect shows an approval prompt on the TV; the token is stored on the phone. The TV's self-signed certificate is trusted only for that one IP. Your HDMI dump shows CEC is enabled and a CEC audio system answered "System Audio Mode: on", which is encouraging, but **nobody has verified that TV volume keys reach the soundbar**. The Mute label reads "SOUNDBAR" only while the TV route is connected; otherwise "MUTE" (ADB).

## Siri / Shortcuts
Intents set `openAppWhenRun`, so they bring the app to the foreground and reuse its ADB connection. A true background intent cannot hold the ADB socket, so full hands-free operation is not promised.
