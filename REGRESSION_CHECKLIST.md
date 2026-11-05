# Glass Remote – regression and hardware test checklist

## Must still work (existing behaviour)
- [ ] Connects to 192.168.1.70:5555 without a new ADB authorisation prompt (same key)
- [ ] Mouse moves at the same speed; tap clicks; drag works
- [ ] Two-finger scroll vertical and horizontal; no stray click when lifting
- [ ] White cursor still shown on the TV
- [ ] D-pad Up/Down/Left/Right/Select; Back; Home (there is no Android Menu key any more)
- [ ] Volume up/down/mute (ADB path, with Samsung route off)
- [ ] Each of the nine apps launches, in the original order
- [ ] Haptics on buttons, tap, launch
- [ ] Background → foreground recovers the session; kill ADB and see automatic reconnect
- [ ] Keyboard helper still reports running (Connection → Status)

## New UI
- [ ] Mouse/D-pad selector is compact beside the bolt (Quick Actions) button and slides smoothly
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

## v0.3 Phase 1 additions
- Switching pages never restarts helpers or changes Stremio playback (see V0_3_PHASE1.md checklist).
- Live Typing toggle survives failed keystrokes.

## v0.4 additions
- Play and Pause each verified from the Player (explicit 126 / 127).
- Volume slider reaches 0 % and 100 %; TV readings never move it mid-drag.
- Android and Samsung targets never send one command to both devices, and a disconnected selected device never falls back to the other.
- A denied Samsung pairing prompt is not re-raised until Reconnect.
- Recent Apps either works or expands the Apps launcher on the Remote page; the Remote Search button focuses Discover.
- See V0_4_NOTES.md.

## v0.4 review additions
- Dock / selectors show no refraction artifacts; sliding a finger across them switches live.
- Samsung remote works with the UPnP volume link down, and the reverse.
- Reconnecting the remote does not restart the volume link (and vice versa).
- Samsung limit learning needs two confirmed attempts before it is saved; reset works.
- Recent Apps reports opened / unchanged / unknown honestly.


## UI refactor checks (new)
- [ ] Header: menu button (top left), status-only Box/TV capsule, power button. Tapping the capsule does nothing.
- [ ] Menu: Connections and devices, Reconnect entries only when needed, Samsung TV > TV keys, Volume through Samsung TV, TV screenshot, Device information.
- [ ] Power button: Standby, Wake, Restart launcher, (TV power, Turn off box and TV when Samsung is on), Restart TV box last.
- [ ] Selector shows only Android TV and Samsung TV; an old saved "Auto" opens as Android TV.
- [ ] Android: pad is clearly larger than before on small and large iPhones; Quick Actions bolt menu runs and edits actions; favourites (long-press an app) sort first.
- [ ] Quick Action that used the old Menu key: its step is gone, a notice shows in the editor, the action still exists.
- [ ] Samsung: only the trackpad plus Back/Home/Mute and Rewind/Play/Pause/Fast-forward; Input/Guide/Info/TV menu/Channel/Stop under Menu > Samsung TV > TV keys.
- [ ] Google Play tab: "Search on the TV" opens Play's search results on the TV; a suggestion opens that app's listing; not-connected state is clear. (Needs the ARRIS box: not verified.)
- [ ] Discover: titles without a Cinemeta poster show the placeholder or a Metahub poster.
