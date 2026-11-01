# Glass Remote – regression and hardware test checklist

## Must still work (existing behaviour)
- [ ] Connects to 192.168.1.70:5555 without a new ADB authorisation prompt (same key)
- [ ] Mouse moves at the same speed; tap clicks; drag works
- [ ] Two-finger scroll vertical and horizontal; no stray click when lifting
- [ ] White cursor still shown on the TV
- [ ] D-pad Up/Down/Left/Right/Select; Back; Home; Menu
- [ ] Volume up/down/mute (ADB path, with Samsung route off)
- [ ] Each of the nine apps launches, in the original order
- [ ] Haptics on buttons, tap, launch
- [ ] Background → foreground recovers the session; kill ADB and see automatic reconnect
- [ ] Keyboard helper still reports running (Connection → Status)

## New UI
- [ ] Mouse/D-pad selector fills the full width, 50/50, slides smoothly
- [ ] App stays Dark Mode with the phone set to Light
- [ ] Apps collapsed by default; expands; collapses after launching; page scrolls while open
- [ ] Native Liquid Glass visible on iOS 27 (not the flat fallback)
- [ ] Power menu items and confirmation dialogs look dark/native

## Needs hardware testing (not verified)
- [ ] Standby (keyevent 223): does the box sleep? Does ADB survive?
- [ ] Wake (keyevent 224): does it work while the box sleeps, or is ADB unreachable?
- [ ] Restart launcher: launcher returns, Utility Hub unaffected
- [ ] Restart box: shell `reboot` works for the shell user; app reconnects by itself (~1–2 min)
- [ ] Media: Stremio play/pause; title and position correct; Spotify enables prev/next
- [ ] Quick Actions: starter actions run in order; editor saves; delays honoured
- [ ] Keyboard: text, spaces, quotes, URLs, `%s`, newline, Backspace, Paste button
- [ ] Samsung TV: pairing prompt, token reuse, VOLUP/VOLDOWN/MUTE, does the soundbar respond? ADB fallback when TV is off
- [ ] Siri/Shortcuts intents launch the app and perform the action

## Added in this pass
- Whole Now Playing card opens the player; media buttons never open it.
- Background/surface separation looks right on OLED; pointer stays smooth.
- AppIcon and the nine app tiles unchanged.
- Nine tiles use the supplied transparent PNGs, centred and balanced; launch targets unchanged.
- Cursor feel unchanged after PointerBox change.
