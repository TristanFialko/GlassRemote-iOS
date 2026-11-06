# 10-second seeking: technical report (Phase 4.1)

**Result: a precise 10-second skip is not possible with the mechanisms this app has, so it was not faked.**
Everything below is from reading the code and from knowledge of Android's tooling. Nothing was run
against your box. Items marked *(unverified)* need a test on the device.

## What the app can genuinely do today
| Need | Available? | How / why |
|---|---|---|
| Read current position | Yes | `dumpsys media_session` `PlaybackState` (position, speed, updated time), extrapolated to the box's uptime in `MediaSession.swift` |
| Read duration | **No** | `dumpsys` prints only a short metadata description (title / subtitle), never `METADATA_KEY_DURATION`; `durationMs` stays nil |
| Request an arbitrary seek | **No** | `cmd media_session` has `dispatch`, `list-sessions`, `monitor`, `volume`; there is no `seek`. `input keyevent` carries no position. `ACTION_SEEK_TO` being *advertised* (`advertisesSeekTo`) only means the app could accept it from a `MediaController`, which an ADB shell cannot call |
| Send a relative key | Yes | `KEYCODE_MEDIA_REWIND` (89) / `KEYCODE_MEDIA_FAST_FORWARD` (90). The **playing app** decides the distance (ExoPlayer's defaults are 5 s back / 15 s forward, not 10) *(unverified for Stremio)* |
| Confirm a seek happened | Yes, after the fact | Compare position before and after, minus normal playback |

## What Phase 4.1 implements (`Seeking.swift`, `RemoteModel+Playback.swift`, `PlayerPage.swift`)
1. After Rewind / Fast-forward the app reads the session again and computes
   `(position after - position before) - elapsed device time x speed`, using the box's own uptime for
   both samples (phone clock as fallback). One extra read after 0.9 s covers a slow session update.
2. The Player shows only what the TV confirmed: "Rewind: -5 s, confirmed by the TV", or "the TV reported
   no position change". The position display is never changed by the app itself.
3. Duplicate commands are blocked while one is pending (existing `mediaCommandPending`).
4. A step is "learned" only after two consecutive confirmed measurements agree within 1.5 s (rewind
   clipped at the start is ignored). If **both** directions are measured at about 10 s (10 +/- 1.5), the
   two buttons switch to `gobackward.10` / `goforward.10` and read "Back 10 seconds" / "Forward 10
   seconds". Otherwise they stay plain rewind / fast-forward and the Player lists the measured steps
   (e.g. "rewind ~5 s, fast-forward ~15 s"). This is relabelling by evidence, not an assumption.
5. Boundaries: the app never computes a target position, so the player clamps at start / end itself.

## Other control paths considered for Stremio
* **D-pad LEFT / RIGHT while Stremio's player is focused**: many Android TV players seek a fixed step on
  these keys. Untested *(unverified)*. It would reuse the measurement harness, but the keys can also move
  focus or show controls, so it is not wired up automatically.
* **Deep links** (`stremio:///detail/...`): open titles; no seek parameter is known.
* **Resume offset**: Stremio resumes from the library item's `timeOffset`. Writing it means modifying the
  account via the API and restarting the stream. Not a live seek; not recommended.
* **Stremio's local streaming server** serves streams, it does not control the player.

## What would make exact seeking possible
A small helper run on the box (like the existing `app_process` helpers) that obtains the active
session's `MediaController` and calls `transportControls.seekTo(positionMs)`, and reads
`METADATA_KEY_DURATION` from `MediaMetadata`. That needs hidden-API access to the media session service
from the shell user *(unverified: depends on Android 11's permission set for uid 2000)*, a new Java
artefact built with the Android SDK, and a protocol line from the app. None of that can be built or
tested here, so it is documented rather than shipped. Once it exists, `SeekMeasurement` already
provides the confirmation step (compare position after the call).
