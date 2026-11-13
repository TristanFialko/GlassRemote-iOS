# Remote v2 hardware test procedure — ARRIS VIP7802 (Android 11)

Every item below is **NOT TESTED**. These checks have no automated equivalent; unit tests cover the logic only. Record the build SHA, box firmware and iPhone/iOS version. Results also go into §12 of `GLASSREMOTE_HARDWARE_ACCEPTANCE_CHECKLIST.md`.

| ID | Check | Steps | Expected | Status |
|---|---|---|---|---|
| HW-P01 | Baseline, v2 off | Fresh install with Remote v2 left off. Use every remote control. | Identical to the previous build. No connections to 6466 or 6467. | NOT TESTED |
| HW-P02 | Pairing | Enable v2 and tap Pair. Type a wrong code, then the right one. | The wrong code is refused locally and pairing continues. The right code pairs. | NOT TESTED |
| HW-P03 | TV key stable across ports | Right after HW-P02, watch the status. | "Remote v2 connected", not "TV identity changed". This confirms the 6466 key matches the 6467 key. **Run this first: a failure blocks everything else.** | NOT TESTED |
| HW-P04 | Relaunch reconnect | Force-quit and relaunch the app. Reboot the box. | Reconnects without pairing again. | NOT TESTED |
| HW-P05 | Navigation | Tap and hold the D-pad keys, OK, Back and Home. | One action per tap. Holds repeat and stop when released. | NOT TESTED |
| HW-P06 | Media | Play/Pause, Play, Pause, Stop, Next, Previous, Rewind and Fast-forward from every surface. | Each acts once. The log shows "sent over Remote v2". | NOT TESTED |
| HW-P07 | Volume never over v2 | With v2 connected, use volume up/down/mute on every route (soundbar, Samsung). | Soundbar changes via ADB 24/25/164 over HDMI-CEC. Nothing is sent over v2. | NOT TESTED |
| HW-P08 | Power and app launch over ADB | With v2 connected, use standby/wake and launch an app. | Works over ADB. The log never shows these over v2. | NOT TESTED |
| HW-P09 | Link lost mid-hold | Hold a D-pad key, then toggle the iPhone's Wi-Fi. | The hold stops. No duplicate input on ADB. Backoff of 1/2/4/8/16/30 s. | NOT TESTED |
| HW-P10 | ADB down, v2 up | Stop ADB (disable debugging). Use the D-pad, OK, Back and Home, then the Now Playing Rewind / Play-Pause / Fast-forward row. | Navigation goes over v2. Each media tap is sent once over v2 and shows "sent over Remote v2 · not confirmed". The log shows no ADB attempt and no dispatch retry. Text, trackpad, apps and power report "unavailable". | NOT TESTED |
| HW-P11 | Pairing removed on TV | Remove GlassRemote in the TV's settings. | "Remote v2 not paired". Pairing again works. | NOT TESTED |
| HW-P12 | TV identity change | Factory-reset the box (or put a different box on the same IP). | "Remote v2 blocked · TV identity changed, pair again". No commands are sent. Pair again or Forget recovers. | NOT TESTED |
