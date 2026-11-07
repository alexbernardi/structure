# M-VAVE SMC-Mixer - hardware reference

Everything here is either from the manufacturer or **measured on the user's unit**. Nothing is inferred from
illustrations. Control identifiers are never hardcoded in the lab: MIDI Learn records them from the device.

## Sources

| Source | What it gave |
|---|---|
| Official product data, `https://www.m-vave.com/products-data.js` (entry `smc-mixer`) | 8 touch-sensitive faders, 8 rotary encoders, **43 programmable LED buttons**, USB-C / Bluetooth 5.0, 256 x 122 x 40 mm, 445 g |
| Official manual PDF `SMC-MIXER_ZE.pdf` (`manualf.oss-cn-hongkong.aliyuncs.com/manual/MIDI-KEYBOARD/`) | Modes, connection, control groups, "43 assignable control buttons; 8 assignable endless 360 degree encoders" |
| Official product photos `images/productInfo/smc-mixer-1.webp` / `-2.webp` (m-vave.com) | Physical layout (below) |
| Community protocol notes: `deadjoe/SMC-Mixer-Tool` README (captured on the USB-C Master port) | Message types of the **User** (CC) profile; the unit sends on Master, Private and Bluetooth ports simultaneously |
| Measured capture on this unit, 2026-11-06 (task 0003, checkpoint 1) | Real messages in DAW mode, port duplication (below) |

## Physical layout (from the official photo)

```
 (K1) (K2) (K3) (K4) (K5) (K6) (K7) (K8)                      [BT]
  ..   ..   ..   ..   ..   ..   ..   ..   <- 8 endless knobs, each with a status LED [SHIFT]
  |    |    |    |    |    |    |    |
  F1   F2   F3   F4   F5   F6   F7   F8   <- 8 vertical faders, each next to 4 buttons:  [M] mute
  |    |    |    |    |    |    |    |                                                   [S] solo
  |    |    |    |    |    |    |    |                                                   [R] record
  v    v    v    v    v    v    v    v                                                   [ ] select
 [>] [||] [o] [<<] [>>] [<<<] [>>>] [^] [v] [<] [>]   <- 11 global buttons
```

- 8 strips x (1 knob + 1 fader + 4 buttons M / S / R / select) = 8 + 8 + 32.
- 11 global buttons, left to right as printed: play, stop (icon looks like pause; the manual says stop), record,
  rewind, fast forward, previous 8-track group (`<<`), next 8-track group (`>>`), up, down, left, right.
- 32 + 11 = **43 buttons**, matching the manufacturer's count. **BT** and **SHIFT** sit beside the knobs and are not part of the 43;
  BT (long press) toggles wireless and SHIFT is a firmware modifier (Shift + Left/Right switches mode). Whether they
  emit MIDI is checked during verification (catalog marks them `optional`).
- Knobs are smooth endless encoders (no detents); faders are touch-sensitive.

## Modes

DAW mode (Mackie Control protocol) and User mode (configurable CC profile): hold SHIFT and press Left or Right to
switch. Over USB the unit enumerates as `SMC-Mixer` and `MIDIIN2 (SMC-Mixer)` (seen by Godot on Windows).
**Every message arrives on both ports** (~40-110 microseconds apart): the lab accepts one port by default.

## Measured: DAW mode, 2026-11-06 (Godot 4.7.2, Windows)

| Control (as exercised) | Message as seen by Godot | Notes |
|---|---|---|
| Fader 1 sweep | Pitch bend, channel 0, `pitch` 0..16256 in steps of 128 | low data byte is always 0 -> 7 effective bits; full travel reaches 16256, not 16383 |
| Knob 1 spin | Control change, channel 0, CC 16, values `1` and `65` | relative, sign-magnitude (Mackie V-Pot: bit 6 = direction); each message is one step; a slow turn repeats the same value |
| Strip 1 "M" button | Note On 127 then Note Off (vel 0), channel 0, note 16 | Mackie "mute 1" = note 16 |
| Play button | Note On 127 / Note Off, channel 0, note 94 | Mackie "play" = note 94 |
| Fader touch | not observed (no Note 104+ seen while moving fader 1) | do not rely on it |

Raw capture used as a test fixture: `utility/movement/flat-plane/tests/fixtures/smc_mixer_daw_capture.json`.

## Known behaviours to respect

- Note Off arrives as a real Note Off message (`msg=8`), not Note On with velocity 0; both are handled.
- User-mode knob types: CC absolute, aftertouch, note (+pitch bend), CC relative; faders: CC, aftertouch, pitch bend;
  buttons: CC single / toggle / push, program, custom, note. Learn records whatever the unit currently sends.
- A mapping learned in one mode does not apply in the other: the lab stores named profiles.
