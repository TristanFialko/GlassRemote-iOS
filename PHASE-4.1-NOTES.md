# Glass Remote Phase 4.1: notes

Static checks only (brace balance, reference search). Nothing here was built, run or tested on a device.

## 10-second seeking: findings
- `dumpsys media_session` prints playback state, position, speed and the `actions` bitmask, plus the
  metadata *description* only. It never prints duration, artwork or any seek target.
- `ACTION_SEEK_TO` (bit 256) may be advertised, but the only ADB routes into a session are key events and
  `cmd media_session dispatch <play|pause|next|previous|rewind|fast-forward|...>`. None takes a position, so
  arbitrary or exact seeking is NOT possible, and no confirmation of a target position exists.
- What is implemented: Rewind / Fast-forward are unchanged. Around each press the app reads the session
  position before and after (minus normal playback progress). If the jump measures about 10 s for that app and
  direction, the button is relabelled "Back / Forward 10 seconds" (gobackward.10 / goforward.10) and the
  measurement is remembered. Anything else keeps the plain rewind / fast-forward icon. Presses near the start,
  unchanged positions and other sessions are ignored. One command at a time (existing guard).
- Stremio: its only control surface found in this code is the media session plus deep links. A D-pad
  left/right fallback inside Stremio's player was NOT added: it is unverified and could navigate Stremio's UI.
- Unverified on device: whether YouTube's or Stremio's keys move 10 s. The measurement decides.

## Other limits
- Player thumbnails for non-film apps (YouTube etc.) are ONE screencap frame per title, taken ~2.5 s after
  playback starts, downscaled. It can include on-screen controls; protected video returns black and is discarded.
  Media sessions expose no artwork through ADB, so this is the only route.
- Film/series apps (Stremio, Netflix, Prime, Disney+, ...) use an exact-name Cinemeta poster.
