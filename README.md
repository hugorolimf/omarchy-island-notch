<div align="center">

# Island Notch

**A Dynamic Island for the Omarchy bar.**
Music, screen recording, dictation, notifications and the volume and brightness
indicators grow out of a notch in the middle of the bar, and fold back into it.

![Island Notch](preview.png)

</div>

## Why this one

- 🎵 **Music.** The album art and live waves while something plays (any MPRIS
  player); hover to expand into a player with progress, previous, play/pause and next.
- 🔴 **Screen recording.** A red dot and the elapsed time while Omarchy's screen
  recorder runs; hover for a stop button.
- 🎙️ **Dictation.** Listening and transcribing states for Omarchy's voice dictation
  (voxtype), in place of a separate pill.
- 🔔 **Notifications.** Each one drops in from the notch, expanded long enough to
  read, then shrinks to a one-line mini view. Hover to expand, click to keep it open
  with its actions (reply, open, copy a code, close). Needs a notifications plugin
  that hands them over (see below).
- 🔊 **Volume, brightness, microphone, keyboard.** Omarchy's on-screen indicators
  show in the notch instead of a card of their own; enabling this plugin takes over
  `omarchy.osd`, disabling it gives it back.
- 🌤️ **Weather card** on demand, from Omarchy's own weather location.
- 🌍 English and Portuguese, following your system language. Sized per monitor,
  drawn natively (no scaling blur).

## Install

```bash
omarchy plugin add https://github.com/hugorolimf/omarchy-island-notch --enable
omarchy-restart-shell
```

It takes the centre of the bar. Works with Omarchy's own bar and with
[Island Bar](https://github.com/hugorolimf/omarchy-bar).

## Talking to it

```bash
omarchy-shell io.github.hugorolimf.island notify '{"app":"Mail","title":"Ana","body":"Lunch?","icon":"mail"}'
omarchy-shell io.github.hugorolimf.island hud '{"key":"volume","value":0.4}'
omarchy-shell io.github.hugorolimf.island card weather
```

`notify` is how a notifications plugin (or a script) shows something in the notch;
`hud` is what the bundled on-screen display sends; `card weather` opens the weather
card.

## Files it writes

- `~/.cache/island-notch/`: the weather forecast and detected location (10-minute
  and one-day caches).
- `~/.local/state/omarchy/io.github.hugorolimf.island/cover-<monitor>`: the height
  the notch takes at the top of each monitor, for window managers that keep windows
  clear of it.

## Requirements

- Omarchy with the Quattro shell (Quickshell).
- Optional, each for its own part: an MPRIS player, Omarchy's screen recorder, Omarchy's
  voice dictation, `wl-copy` (copying codes).

## Remove

```bash
omarchy plugin remove io.github.hugorolimf.island
omarchy-restart-shell
rm -rf ~/.cache/island-notch ~/.local/state/omarchy/io.github.hugorolimf.island
```

Omarchy's own on-screen display comes back.

## Credits

The on-screen display model (`OsdModel.js`) and IPC are Omarchy's `omarchy.osd` by
David Heinemeier Hansson and the [Omarchy](https://github.com/basecamp/omarchy)
contributors (MIT). Weather data from [Open-Meteo](https://open-meteo.com) (and
[wttr.in](https://wttr.in) to find your location when Omarchy has none).

## License

[MIT](LICENSE)
