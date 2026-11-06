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
- [ ] Media: Nuvio play/pause; title and position correct; Spotify enables prev/next
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
- Switching pages never restarts helpers or changes Nuvio playback.
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

## Discover / Nuvio migration (nothing below has been run on a device or built)
- [ ] Dock shows exactly Remote, Player, Discover, evenly spaced; the Remote icon is the Apple TV remote symbol; swiping pages still works and carousels scroll without changing page.
- [ ] Header button shows the Glass Remote logo and still opens the menu.
- [ ] Android: expanding Apps does not change the Samsung remote's size; switching Android -> Samsung -> Android keeps Apps expanded.
- [ ] Android nav row: Back, Home, Sources, Search, Keyboard. Sources opens the Samsung TV source menu (needs the Samsung link; otherwise the status line explains).
- [ ] Samsung: a single Play/Pause button; the icon is the last key sent, reset to the neutral glyph after changing target or reconnecting.
- [ ] Android D-pad: same commands, hit areas, repeat-on-hold and swipe; new glass depth, seams and centre button.
- [ ] Discover: search is always visible; Movies/Series/All filter; carousels, genre chips, recent searches, empty/error/loading states.
- [ ] Nuvio device-link sign-in: code appears, approving on nuvio.tv signs in, cancel works, a rejected/expired code shows a clear message; success shows Continue Watching; Sign out removes the Keychain session and leaves Nuvio on the TV signed in; an expired session shows "sign in again". FIRST RUN: confirm https://nuvio.tv/config.js is parsed (the backend URL/key are read at runtime).
- [ ] Open in Nuvio (movie, series) and Search in Nuvio: either the title/search opens, or the result line says Nuvio was launched instead. Link shapes are unverified on this box (check `am start` output).
- [ ] Player: start a title directly in Nuvio; its poster (2:3) appears within a few seconds and is larger than in 4.2; a title with no exact catalogue match keeps the Nuvio icon; the Nuvio package on the box is confirmed to be com.nuvio.app.
- [ ] Mouse (`M buttons dx dy wheel hscroll`, 45 ms click, x2 drag), keyboard (`K`/`C`), recovery (no HOME/BACK/STOP/PAUSE) and Samsung pairing/volume are unchanged.

## Phase 4: themes, Discover, Player (nothing below has been run on a device or built)
- [ ] Logo menu -> Themes opens a picker with a live preview per theme; the current one is marked; switching animates and survives an app restart.
- [ ] Every theme: Remote, Player, Discover, dock, header, menus, sheets (detail, account, connection, keyboard, theme picker), segmented controls and the Samsung panel all restyle. Light Glass and Glass White: all text and icons readable.
- [ ] Switching theme does not reconnect ADB, restart helpers, or change playback state.
- [ ] Adaptive: featured artwork on Discover tints accents; a Player poster takes over on the Player/Remote pages; greyscale artwork falls back to neutral; no flashing when posters change. Auto follows the system setting and is NOT artwork-driven.
- [ ] Ambient backgrounds: each style can be chosen and turned Off; text and glass stay legible; scrolling stays smooth.
- [ ] Mouse/D-pad selector: tap each half; swipe LEFT -> D-pad, swipe RIGHT -> Mouse; haptic once per change. Dragging and two-finger scrolling inside the trackpad never changes the mode; cursor, clicks (45 ms), drag x2 unchanged.
- [ ] Discover: vertical scroll works when a swipe starts on a poster or carousel; horizontal carousel scroll works; tapping a poster opens details; carousels do not change the page; genre rows load as they scroll into view.
- [ ] See All (Popular / Top rated / Newest, genres, library rows): grid, sort and genre menus, Movies/Series switch, loads more at the bottom, empty/error states, tap opens details.
- [ ] Account: Continue Watching and history match the Nuvio app on the TV (same profile; profile selection is unverified and defaults to the lowest id).
- [ ] Player: poster no taller than ~1/3 of the screen, transport bar sits above the dock on small iPhones, nothing overlaps.

## Phase 4.3 additions
- [ ] Discover: hold/press a recent-search chip, a genre chip and a poster; the expanded glass is not clipped top, bottom or at the screen edge.
- [ ] Continue Watching shows 16:9 cards (backdrop, or whole poster on a dark panel when there is no backdrop); never stretched.
- [ ] Detail sheet shows a 16:9 backdrop when one exists, otherwise the 2:3 poster.
- [ ] Remote, trackpad, mouse, keyboard, helpers, Samsung, volume, YouTube launch: unchanged (no input/helper files were edited).
