# 0003 - MIDI Movement Lab

Status: in progress     Owner: agent + Alex (hardware owner)     Date: 2026-11-06

## Goal
A development utility, `utility/movement/flat-plane/`, to tune character-movement physics live with the user's
M-VAVE SMC-Mixer. Five phases, sequential, each with verification: (1) MIDI integration with MIDI Learn and physical
verification, (2) flat-plane sandbox with a primitive third-person humanoid, (3) configurable fixed-timestep movement core,
(4) live MIDI parameter tuning with banks and presets, (5) telemetry, tests, input record/playback.
Constraints from the brief: Godot primitives only; no Docker, Blender, third-party assets or new dependencies;
isolated git branch (`task/0003-midi-movement-lab`); do not claim hardware/interactive behaviour from headless tests.

## Impact
- New top-level tree `utility/` (layout change; approved by the brief; [ADR-0009](../DECISIONS/ADR-0009-utility-tree.md)).
- `TOOLS/cli`: utility projects join `godot.all_projects()`; new suite `utility` in `structure.py test`.
- Docs: `DOCUMENTATION/SMC-MIXER-HARDWARE.md`, COMMANDS/TESTING updates, START-HERE state, KNOWN-ISSUES.
- No change to the sandbox, rooms, protocol (v1) or world schema (v1). The movement room is only *read* for reference.

## Supplies (step 2)
Godot 4.7.2 native MIDI (`OS.open_midi_inputs`, `InputEventMIDI`), shared runner `TESTING/harness/run_gd_tests.gd`,
ADR-0002 (no `class_name`), CONVENTIONS (metres/seconds, tabs, snake_case), the existing `SYSTEM-ROOMS/movement`
model as a reference for the first-person model (kept untouched).

## Phase 1 findings so far (verified vs assumed)
| Finding | Status |
|---|---|
| Layout 8 knobs / 8 faders / 32 strip buttons (M S R select) / 11 global buttons = 43 buttons; BT and SHIFT extra | verified from the official photo + manual + spec |
| Godot (headless and windowed) lists `SMC-Mixer` and `MIDIIN2 (SMC-Mixer)` | verified on this machine |
| Every message arrives twice (one per port) | verified (950 events, dev0 == dev1 counts exactly) |
| Device currently in DAW (Mackie) mode: faders pitch bend, knob CC16 relative 1/65, buttons notes (M1 = 16, Play = 94) | verified for fader 1, knob 1, M1, Play only |
| Reconnect detection needs re-enumeration (`close_midi_inputs` + `open_midi_inputs`) | assumed from Godot's API; to be verified by unplugging |

## Design (Phase 1)
Modules under `utility/movement/flat-plane/midi/` (pure `RefCounted` logic unit-tested headless, one `Node` for I/O):
`midi_events` (normalise `InputEventMIDI` -> dict + signature `kind:channel:number`), `control_catalog` (59 logical
controls + 2 optional), `behavior_detector` (absolute vs relative; relative encoding sign-magnitude / two's complement /
binary offset / fixed), `midi_learn` (state machine), `midi_config` (JSON profiles, validation, atomic save),
`midi_manager` (discovery, port filter, hot-plug polling, mapping -> control events). UI: `scenes/midi_monitor`.
Mappings are data (`config/midi_mapping.json`); no control identifier is hardcoded.

## Acceptance criteria (Phase 1)
1. Device discovery/initialisation works natively in Godot; status visible.
2. Live monitor shows every incoming event (port, type, channel, number, value) and flags port duplicates.
3. MIDI Learn can map each of the 59 catalog controls; absolute/relative detected automatically; button release behaviour detected.
4. Config saved to JSON, editable, validated on load (bad files rejected with a reason, never silently).
5. Unplug/replug handled without restart; status updates.
6. Each mapped control gives visual feedback and a "verified" mark after an independent physical actuation.
7. Automated: unit tests (events, detector, learn, config, manager routing via synthetic `InputEventMIDI`, real-capture replay).
8. **Physical**: user maps all controls and confirms; unplug/replug confirmed. Phase 2 does not start before that.

## Validation
### Phase 1 (done 2026-11-07)
| Criterion | Evidence | Result |
|---|---|---|
| Discovery / init native in Godot | `OS.open_midi_inputs()`; both ports listed headless and windowed; status line in the monitor | verified on hardware |
| Live monitor, duplicates flagged | Every message arrives on both ports (950 events, equal counts); auto mode accepts one port; log greys the other | verified on hardware + test |
| MIDI Learn for every control | User learned strips 1-3 and Play with the wizard; the 10 remaining global buttons learned from real presses (Stop 93, Record 95, Rewind 91, Fast fwd 92, Bank prev 46, Bank next 47, Up 96, Down 97, Left 98, Right 99). Strips 4-8 (30 controls) were **inferred** from the constant step in strips 1-3 (`midi_pattern.gd`, >= 2 strips, flagged `inferred`) | learned 29 / inferred 30 |
| Absolute vs relative detection | Fader = absolute pitch bend 0..16256; knob = relative sign-magnitude (1 / 65); detector tested on the real capture and synthetic streams | verified |
| Saved, editable config | `config/midi_mapping.json` (sorted, tab-indented, validated on load, atomic save with `.bak`); invalid files are reported and never overwritten | tests + used on hardware |
| Disconnect / reconnect | Unplugged and replugged while running: log `connected=false ports=[]` then `connected=true` with both ports, then live pitch-bend data | verified on hardware |
| Visual feedback + physical verification | Saved file after the user's pass: **mapped 59/59, verified 59/59, 0 inferred**, 59 timestamps over 32 s | verified on hardware |
| Automated tests | `structure.py test utility`: 70 tests (events, catalog, behaviour, learn, config, pattern, manager routing via synthetic `InputEventMIDI`, scene) | pass |

Problems found by the hardware checkpoints (all fixed): the first "all green" report was contradicted by the saved file
(0 verified) - verification was then redone and confirmed from disk; buttons held > 0.8 s were learned as `trigger`
(release window now 2.5 s); a rescan during a gesture could swallow its first message (no rescan while learning);
`validate()` crashed on a non-string `ports` value and corrupt JSON logged an engine error (both fixed with tests).

Measured: a hot-plug rescan (`close` + `open` inputs) costs ~41 ms, almost all in `open`.

## Outcome
(filled in at the end)
