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
- [ ] Mouse/D-pad selector slides smoothly
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
- Switching pages never restarts helpers or changes Stremio playback.
- Live Typing toggle survives failed keystrokes.

## v0.4 additions
- Play and Pause each verified from the Player (explicit 126 / 127).
- Volume slider reaches 0 % and 100 %; TV readings never move it mid-drag.
- Android and Samsung targets never send one command to both devices, and a disconnected selected device never falls back to the other.
- A denied Samsung pairing prompt is not re-raised until Reconnect.
- The Remote Search button focuses Discover.

## v0.4 review additions
- Dock / selectors show no refraction artifacts; sliding a finger across them switches live.
- Samsung remote works with the UPnP volume link down, and the reverse.
- Reconnecting the remote does not restart the volume link (and vice versa).
- Samsung limit learning needs two confirmed attempts before it is saved; reset works.


## UI refactor checks (new)
- [ ] Header: menu button (top left), status-only Box/TV capsule, power button. Tapping the capsule does nothing.
- [ ] Menu: Connections and devices, Reconnect entries only when needed, Samsung TV > TV keys, Volume through Samsung TV, TV screenshot, Device information.
- [ ] Power button: Standby, Wake, Restart launcher, (TV power, Turn off box and TV when Samsung is on), Restart TV box last.
- [ ] Selector shows only Android TV and Samsung TV; an old saved "Auto" opens as Android TV.
- [ ] Android: pad is clearly larger than before on small and large iPhones; favourites (long-press an app) sort first.
- [ ] Samsung: only the trackpad plus Back/Home/Mute and Rewind/Play/Pause/Fast-forward; Input/Guide/Info/TV menu/Channel/Stop under Menu > Samsung TV > TV keys.
- [ ] Discover: titles without a Cinemeta poster show the placeholder or a Metahub poster.

## Discover / Stremio refactor (nothing below has been run on a device or built)
- [ ] Dock shows exactly Remote, Player, Discover, evenly spaced; the Remote icon is the Apple TV remote symbol; swiping pages still works and carousels scroll without changing page.
- [ ] Header button shows the Glass Remote logo and still opens the menu.
- [ ] Android: expanding Apps does not change the Samsung remote's size; switching Android -> Samsung -> Android keeps Apps expanded.
- [ ] Android nav row: Back, Home, Sources, Search, Keyboard. Sources opens the Samsung TV source menu (needs the Samsung link; otherwise the status line explains).
- [ ] Samsung: a single Play/Pause button; the icon is the last key sent, reset to the neutral glyph after changing target or reconnecting.
- [ ] Android D-pad: same commands, hit areas, repeat-on-hold and swipe; new glass depth, seams and centre button.
- [ ] Discover: search is always visible; Movies/Series/All filter; carousels, genre chips, recent searches, empty/error/loading states.
- [ ] Stremio sign-in: wrong password shows Stremio's own message; success shows Continue Watching and Library; Sign out removes them; an expired session shows "sign in again" and the stored key is gone.
- [ ] Open in Stremio (movie, series, an episode, Resume, Search in Stremio) each open the right place on the box. The deep-link shapes are from Stremio's docs but unconfirmed on this box's build.
- [ ] Player: start a title directly in Stremio; its poster (2:3) appears within a few seconds; a title with no exact catalogue match keeps the Stremio icon.
- [ ] Mouse (`M buttons dx dy wheel hscroll`, 45 ms click, x2 drag), keyboard (`K`/`C`), recovery (no HOME/BACK/STOP/PAUSE) and Samsung pairing/volume are unchanged.
