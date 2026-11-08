# 0006 - Movement Lab 4.0: authored running vault

Status: implemented and validated; awaiting the user's vault review. Date: 2026-11-08.
Branch: `task/0006-fluid-traversal-vault`.

## Goal

Preserve the user-approved authored locomotion and prototype only Run -> Anticipate -> Vault -> Land -> Run.
The user explicitly approved the authored animation foundation in the 4.0 brief. Further traversal moves require
approval of this vault checkpoint; they are not part of this implementation.

## Impact

- Isolated movement utility, `utility/movement/flat-plane/`, and directly related workshop records.
- Preserve the current controller and authored clips; authoritative movement must remain collision-safe and
  independent of rendering/animation callbacks. No multiplayer, protocol, save-schema or sandbox integration changes.
- Keep both the procedural legacy and approved authored baseline recoverable.
- Four new traversal controls only: anticipation, transition response, contact correction, momentum continuity.
- Existing Godot, AnimationTree and SkeletonModifier3D APIs. No Docker, Blender, ML or new animation framework.
- New branch inherits the existing uncommitted 2.0/3.0 changes. Do not discard them or claim them as new vault work.

## Plan and gates

1. Research the five supplied papers and practical blending/warping/contact techniques. Record applicability and
   limitations in `AGENT-WORKSHOP/RESEARCH/fluid-traversal.md`.
2. Inventory source clips and preserve the approved baseline. Acquire and inspect an authentic, licensed vault clip.
   Verify the source and compatible target before enabling traversal. No fabricated replacement animation.
3. Implement a small perception/selection/planning layer with explicit feasibility and rejection reasons. Validate
   obstacle dimensions, approach angle, takeoff timing, body clearance and landing space.
4. Execute the physical plan through the existing CharacterBody3D collision system; animation follows its state.
   Integrate the authored vault into the current graph with bounded adaptation and contact corrections.
5. Add a primitive test wall, side/full-3D inspection, contact/trajectory/phase/velocity debugging and four MIDI controls.
   Preserve existing movement/animation presets and the original A/B scene.
6. Test slow/fast approaches, height/angle variations, cancellation, blocked/uneven landings, immediate run-out,
   resource integrity, continuity, momentum, collision safety and animation-disabled equivalence. Measure overhead.
7. Launch the verified vault checkpoint for human playtesting. Do not implement mantle/slide/climb/roll yet.

## Validation

Baseline: 479 utility tests pass; source GLBs, controller/collision/camera/MIDI mapping remain available.
Use focused tests while implementing, then full utility regressions, native side/full-3D captures, benchmarks and
repository static checks. Human visual acceptance of the vault remains a separate gate.

## Progress

- The approved 3.0 baseline was committed on its own first, from the pre-traversal snapshot (479/479 tests
  on that tree alone). The 4.0 vault work is committed on top of it.
- Source: the free UAL2 Standard download has no vault. The user supplied the paid UAL2 package (CC0). Its
  `SafetyVault` is the only running vault, and the only clip taken from it. Byte-verified 720 KB extracts are
  committed; the original download stays in the ignored `AGENT-WORKSHOP/DOWNLOADS/`. See the provenance file.
- Gates 3-6 are implemented: obstacle probe with explicit rejection reasons, pure planner over a measured clip
  profile, kinematic collider drive with an abort on blocked tracking, AnimationTree vault state with entry-foot
  cadence steering, planted-hand IK, cameras that ignore the collider hump, vault lanes A/B/C, F10 overlay,
  V side view, `--trial=vault` A/B and the Traversal MIDI bank.
- Full utility regression: 495/495 passed (13 vault tests plus the Traversal bank test). With traversal on but no
  vault, physics is bit-identical to traversal off. On open ground, traversal adds 0.014 ms to the mean
  physics + perception tick (0.062 vs 0.048 ms).
- Gate 7: the Playground checkpoint is launched for the user's review.

Diagnosis, measurements, limitations and commands: [Movement Lab 4.0](../DOCUMENTATION/MOVEMENT-LAB-4.md).
Open review items: KI-020 to KI-022 in [known issues](../INVENTORY/KNOWN-ISSUES.md).
No mantle, slide, climb or roll is implemented. They wait for the user to approve this vault.
