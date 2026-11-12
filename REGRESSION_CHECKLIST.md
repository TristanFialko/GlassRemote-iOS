# Glass Remote – regression and hardware test checklist

## Must still work (existing behaviour)
- [ ] Connects to 192.168.1.70:5555 without a new ADB authorisation prompt (same key)
- [ ] Mouse moves at the same speed; tap clicks; drag works
- [ ] Two-finger scroll vertical and horizontal; no stray click when lifting
- [ ] White cursor still shown on the TV
- [ ] D-pad Up/Down/Left/Right/Select; Back; Home (there is no Android Menu key any more)
- [ ] Volume up/down/mute with the Samsung route off: nothing is sent, the slider is disabled and reads "Unavailable" (there is no ADB volume path)
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
- [ ] Samsung TV: pairing prompt, token reuse, VOLUP/VOLDOWN/MUTE, does the soundbar respond when Volume goes to the Samsung TV?
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
- A denied Samsung pairing prompt is not re-raised until Reconnect (reported as denied, not as a timeout).
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
- [ ] Dock shows exactly Remote, Discover, Profile, evenly spaced; the Remote icon is the Apple TV remote symbol; the selected item takes the theme accent under the Liquid Glass selector; switching cross-fades with a haptic. Now Playing is not in the dock.
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

## Phase 4.3 additions
- [ ] Discover: hold/press a recent-search chip, a genre chip and a poster; the expanded glass is not clipped top, bottom or at the screen edge.
- [ ] Continue Watching shows 16:9 cards (backdrop, or whole poster on a dark panel when there is no backdrop); never stretched.
- [ ] Detail sheet shows a 16:9 backdrop when one exists, otherwise the 2:3 poster.
- [ ] Remote, trackpad, mouse, keyboard, helpers, Samsung, volume, YouTube launch: unchanged (no input/helper files were edited).

## Phase 9 Now Playing (built and unit tested in CI only; nothing below has been run on a device)
- [ ] Opens from the mini-player (portrait), the rail tile (landscape) and the Remote page's Now Playing card; the grabber and any dock item close it. The mini-player appears within one poll of playback starting and goes when the session ends.
- [ ] Portrait: title artwork runs edge to edge from the top of the screen (under the status bar) and fades out behind the title; title and second line, timeline, transport and volume sit above the dock on an iPhone SE and a Pro Max; nothing overlaps the dock or the safe areas; no borders, cards or status dots.
- [ ] Landscape: a large rounded artwork card on the leading side; beside it the title lines up with the card's top and the volume row with its bottom; the rail stays visible and the background runs unbroken behind it.
- [ ] Without title artwork the app artwork (or a symbol) shows on a rounded card in both orientations.
- [ ] A new title cross-fades artwork and title together; position polls do not restart the fade. The card eases back slightly while paused (not with Reduce Motion).
- [ ] The background is made from the artwork; the dock stays legible over bright and dark posters, in dark and light themes; Adaptive takes its accent from the artwork.
- [ ] Play / pause sends explicit Play or Pause; buffering pauses. Rewind / fast-forward only when the session advertises them; Nuvio and other video apps never show previous / next.
- [ ] Timeline: the elapsed time ticks once a second while playing and freezes when stale; the track never fills and there is no scrubber or remaining time (no duration is reported). The caption under it shows Paused / Buffering / Waiting for the TV, or a confirmed seek ("+10 s") for a few seconds.
- [ ] States: not connected, connecting, nothing playing show a one-line hint instead of the timeline; backgrounding and returning, and an ADB reconnect, recover without a stuck state.
- [ ] Volume row: quiet speaker, neutral track, loud speaker; it drives the same volume route as the Remote slider and never fights a finger when a reading arrives.

## Samsung soundbar volume (needs the real TV box, TV and soundbar; none of this has been run on hardware)
- [ ] Box connected, Volume goes to: Soundbar, through the TV box (the default). The Remote and Now Playing sliders and mute change the SOUNDBAR, not the TV's built-in speakers. This is the Phase 7.2 route; confirm it on the real setup.
- [ ] Same setup with the box disconnected: the volume row is dimmed and says "Connect the TV box"; nothing changes on the TV or the soundbar.
- [ ] A full slider sweep moves the soundbar 20 levels (Phase 7.2's span); the slider shows no number because the soundbar's level cannot be read.
- [ ] Volume goes to: Soundbar, through the Samsung TV, remote paired: note which speakers move. With the remote unpaired volume is unavailable (never the TV's UPnP level).
- [ ] Volume goes to: TV speakers: the slider shows the real 0–100 read from the TV and follows changes made with the TV's own remote.
- [ ] "Soundbar max volume" (Samsung key route only): full slider reaches the soundbar's maximum.

## Phase 9 Samsung pairing
- [ ] First connection raises the TV prompt once; allowing it stores the token and later launches connect silently.
- [ ] Denying it is reported as denied, and the prompt is not raised again until Reconnect.
- [ ] Reset Samsung pairing… asks for confirmation, then the TV asks again; the Android connection and the volume link are untouched.
- [ ] A token issued by one TV is never offered to a different address.

## Phase 9 landscape Remote (layout unit tested; not run on a device)
- [ ] Landscape Remote is a console, not the portrait stack in columns: status pill top left, Mouse / D-pad selector centred over the pad, device switch and power top right; Back, Home, Apps on a rail under the left thumb; Search, Keyboard (and Sources when the Samsung link is on) under the right; volume runs along the foot of the pad.
- [ ] The trackpad is about 477 × 220 pt on a 6.1" iPhone (409 × 223 on an SE, 558 × 267 on a Pro Max) and is identical for the Android and Samsung remotes.
- [ ] Samsung landscape: Back, Home, Ch +, Ch − on the left rail; Rewind, Play/Pause, Fast forward, Mute on the right; the link banner floats over the disabled pad.
- [ ] Apps key on the left rail opens the folder beside it, over the pad; rotating with the folder open keeps it open.
- [ ] Rotating mid-touch: mouse movement, a touch-and-hold drag and a held D-pad key behave as before and stop on lift; nothing keeps repeating; two-finger scroll and two-finger Back still work afterwards.
