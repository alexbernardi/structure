# Fluid traversal: research, asset audit and first-vault architecture

Task: [0006](../TASKS/0006-fluid-traversal-vault.md). Reviewed 2026-11-08.

## Decision and current gate

Build on the **user-approved authored 3.0 locomotion**, not another procedural gait.
Prototype one running vault before implementing mantle, slide, climb or roll.
Use the existing AnimationTree, native humanoid retargeting and CharacterBody3D.
No new animation framework, machine learning, Docker or Blender is justified.

**Source gate: passed.** The free Quaternius UAL2 Standard archive has no vault. The user then supplied the paid
UAL2 package (CC0). Its `SafetyVault` (22 frames, 0.7333 s, in-place and root-motion exports) was inspected,
extracted byte-for-byte and verified on the original rig before retargeting. It is the only running vault in the
package and the only new clip used. No climb or jump stands in for it, and no clip timing is invented: takeoff,
hand plant/release, landing and root speed are measured from the clip (see "New source inspection").

Implemented and validated as the [Movement Lab 4.0 checkpoint](../DOCUMENTATION/MOVEMENT-LAB-4.md); it awaits the
user's visual and MIDI review. Mantle, slide, climb and roll stay out of scope until that review approves the vault.

## Research and practical application

Scope of review: the papers' public project/abstract pages, the linked EMM repository
README/data description, the Godot motion-matching README, and the documentation/articles
below. This is not a full implementation reproduction, review of all source code, or
claim that the learned controllers run in Godot.

| Work | Relevant finding | Application to this prototype |
|---|---|---|
| [Terrain Runner (2012)](https://www.cs.ubc.ca/~van/papers/2012-TOG-TerrainRunner/index.html) | Example motions, transition-specific control and online step planning compose obstacle traversal; entering an action in a compatible state matters | Plan takeoff/contact/run-out together. Retain appropriate incoming momentum instead of stopping to start a clip. Do not port its learned dynamics |
| [PRECISION (2016)](https://cgl.ethz.ch/publications/papers/paperKap16a.php) | Contact/motion semantics and environmental affordances constrain interactions | Measure actual support surfaces and clearance; require contact and landing feasibility before selecting the vault |
| [Neural State Machine (2019)](https://www.research.ed.ac.uk/en/publications/neural-state-machine-for-character-scene-interactions/) | Goal/environment-conditioned character interaction coordinates locomotion with nonperiodic actions | Represent approach, action and target in a common obstacle-relative frame. One explicit action does not need a neural network |
| [Environment-aware Motion Matching (2025)](https://upc-virvig.github.io/Environment-aware-Motion-Matching/) / [repository](https://github.com/UPC-ViRVIG/Environment-aware-Motion-Matching) | Pose/trajectory/environment features and obstacle penalties link motion selection to space, not just animation names | Score/reject candidate entry trajectories against geometry and exit intent. A one-clip selector needs feasibility checks, not a large search database |
| [Perceptive Humanoid Parkour (2026)](https://roboticsproceedings.org/rss22/p020.html) | Motion matching composes skills; learned tracking/distillation supports perceptive robot execution | Preserve compatible entry/exit conditions and contact semantics. Its robotics/RL stack is not an appropriate dependency for this kinematic game prototype |

### Blending, matching and correction

- **Inertialization:** preserve pose/velocity offsets at a switch and decay them into
  the destination motion. It can reduce dual-pose evaluation, but adds a pose writer
  and can overshoot contacts. Begin with the existing native crossfades; add a bounded,
  isolated inertialization modifier only if measured transition discontinuity warrants it.
  Reviewed [Holden's inertialization discussion](https://theorangeduck.com/page/spring-roll-call#inertialization).
- **Phase synchronization:** the approved 3.0 baseline used Godot's cyclic-mutable synchronization.
  The 4.0 implementation instead seeks jog/sprint from one script-owned distance-aware clock, with bounded
  anticipation steering. Initialize that clock on logical Run entry, not on the graph's delayed transition state.
  A nonperiodic vault cannot simply share a normalized loop phase. Inspect source takeoff
  and run-out support legs, select a compatible entry phase, and preserve run phase through
  anticipation. Godot's [state-machine transition](https://docs.godotengine.org/en/stable/classes/class_animationnodestatemachinetransition.html)
  sync seeks the destination to the old playback time; that alone is not contact matching.
- **Root alignment/warping:** align the source reference frame to the measured obstacle
  and distribute small endpoint changes outside firm contact windows. Warp the reference
  trajectory, not arbitrary individual limb cycles. Reject adjustments beyond the verified
  source envelope. [Code vs Data Driven Displacement](https://theorangeduck.com/page/code-vs-data-driven-displacement)
  explains why simulation and visible motion must be reconciled, rather than blindly
  allowing animation to move the physical entity.
- **Distance matching:** use remaining physical distance to the verified takeoff/contact
  event to prepare timing. Actual displacement, not desired velocity, remains authoritative.
  Bound time adjustment; do not pause/reverse a clip to compensate for a blocked body.
- **Stride adaptation:** retain the current conservative run cadence/stride bounds.
  Use the approach distance and compatible foot phase to select an entry; do not stretch
  limbs or create dozens of takeoff tuning parameters.
- **Predictive traversal:** predict a short horizon from current velocity and intent,
  then revalidate geometry and intent before commitment. A prediction is not permission
  to bypass collision. Stop/turn input cancels anticipation without restarting locomotion.
- **Contact-aware IK:** use source-labelled hand/foot contact windows, not a sine weight.
  Clamp target displacement and check anatomical reach and actual support surfaces.
  Disable conflicting flat-floor foot correction during traversal; one ordered correction
  chain owns the final skeleton.
- **Motion graphs:** explicit Run -> Anticipate -> Vault -> Land -> Run is sufficient.
  Anticipate may remain phased running until source timing requires a distinct clip.
  Do not invent an anticipation animation. Preserve source landing/run-out frames rather
  than unconditionally restarting the existing full landing clip.
- **Trajectory/pose matching:** compare entry speed, heading, support leg and obstacle
  frame; compare exit pose/velocity to the destination run. A larger motion database
  can be evaluated after the single-vault human checkpoint, not before.

[Godot Motion Matching](https://github.com/GuilhermeGSousa/godot-motion-matching) is a
Godot 4.4 GDExtension integrated with AnimationTree and assumes root-motion data with a
foot-level root. It was not installed or executed. Replacing the successful graph for
one vault would introduce unnecessary compatibility and ownership risk.

## Existing authored library audit

The original [3.0 audit and measurements](../DOCUMENTATION/MOVEMENT-LAB-3.md) remain the
baseline. The 4.0 brief explicitly approves the authored visual result; it does not
independently confirm every hardware control or resolve measured sliding.

- Original UAL1 Standard: 43 animations in the CC0 GLBs. Original bytes and hashes remain
  in [provenance](../../utility/movement/flat-plane/assets/quaternius/PROVENANCE.md).
- Curated runtime: `Idle`, `Jog_Fwd`, `Sprint`, `Jump_Start`, `Jump`, `Jump_Land`,
  `Crouch_Idle`, `Crouch_Fwd`. Fall uses the real Jump air loop, not a fabricated clip.
- Native BoneMap/SkeletonProfileHumanoid normalizes the source's 65 bones. Primitive
  target uses 23 mapped bones and uniform translation scale (hip rest height 1.01 m).
  Preserve `Skeleton3D.motion_scale` when sampling source positions.
- Root-motion references: jog 5 m / (28/30 s) = 5.357143 m/s; sprint
  5.5 m / (20/30 s) = 8.25 m/s, before target proportion scaling.
- Jog/sprint footstep phase correlation was tested. Exact hand-contact metadata and
  vault takeoff/landing phases do not exist yet. Near-floor shoe samples are not
  equivalent to labelled stance contacts.
- AnimationPlayer stores clips but its automatic playback is disabled. AnimationTree
  mixes the pose; bounded chest lean and leg IK follow. The final modifier preserves
  authored ankle orientation. Legacy gait/body systems are inactive in authored mode.
- Cadence 0.8-1.45x; total stride 0.9-1.1x; foot correction <= 0.10 m; torso lean
  <= 0.10 rad. No unlimited playback multiplier or limb scaling.
- Physical movement remains 6 m/s run and 12 m/s Shift. The existing root-motion
  library has no physical-position consumer. Recorded legacy/authored physical
  trajectories are bit-identical.

Recovery: the approved utility (excluding `.godot`) and 3.0 records were archived in
the current session before traversal code changes: `ml4-authored-baseline.zip`,
250 files. That snapshot was then committed alone on `task/0006-fluid-traversal-vault`
as the 3.0 baseline (479/479 tests on that tree), and the 4.0 work was committed on top.

## New source inspection and licensing

Official source: [Quaternius Universal Animation Library 2](https://quaternius.itch.io/universal-animation-library-2).
The official free-download flow supplied `Universal Animation Library 2[Standard].zip`.
Archive SHA-256: `4008ea208a604773a2b2177d965f0f5d3195498b5bf838c3f5785d68e95f2a68`.
Its included License.txt explicitly grants **CC0 1.0**. Original archive retained in
session files; unused UAL2 assets are not added to the runtime repository.

Both `Unreal-Godot/UAL2_Standard.glb` (8,091,444 bytes) and
`UAL2_Standard_RM.glb` (8,095,936 bytes) were inspected directly as GLB JSON.
Each declares 43 animation entries: one `A_TPose` plus 42 actions.
Traversal-related entries are `ClimbUp_1m`, `NinjaJump_Start`,
`NinjaJump_Idle_Loop`, `NinjaJump_Land`, `Slide_Start`, `Slide_Loop`, `Slide_Exit`.
**Neither contains a vault.** Do not confuse the advertised 130+ full collection
with the free package or treat `ClimbUp_1m` as a running vault.

Other sources checked:

- [KayKit Character Animations](https://kaylousberg.itch.io/kaykit-animations):
  CC0, but its published full list has no vault; these are older legless-character
  animations, so this is not a suitable source for the required human vault.
- [CMU database](https://mocap.cs.cmu.edu/search.php?subjectnumber=&motion=vault):
  the keyword search returned no vault results, not proof the entire database lacks
  any relevant motion. Its [FAQ](https://mocap.cs.cmu.edu/faqs.php) permits copying,
  modifying and redistribution, but no suitable clip was identified.
- EMM's [published BVH dataset](https://zenodo.org/records/17220516) is CC BY 4.0
  according to the record API; the implementation repository is MIT. Those are
  separate licenses. No vault clip was verified, no code executed and no new BVH
  conversion/framework introduced merely to avoid the requested source gate.

### Paid UAL2 package (delivered)

The user bought the full UAL2 package from the official page and placed it in the git-ignored
`AGENT-WORKSHOP/DOWNLOADS/`. Its License.txt is the same CC0 1.0 text. `Unreal-Godot/UAL2.glb` and
`UAL2_RM.glb` were inspected directly as GLB JSON: **134 animations**, one of them `SafetyVault`
(0.7333 s, 22 frames at 30 fps). It uses the same 65-joint skeleton as UAL1, so the 3.0 `BoneMap` import
settings apply unchanged. Only that clip, with its skeleton and mesh, is committed (720 KB per extract).
Hashes and the extraction command are in the
[provenance file](../../utility/movement/flat-plane/assets/quaternius/PROVENANCE.md).

Measured on the original rig at mannequin scale (`tools/audit_vault_clip.gd`, re-measured by the tests):

- Root travel is linear at 4.358 m/s; no other speed is authored.
- The clip starts on a left-foot run contact. The left foot leaves at 0.05 s and lands at 0.69 s.
- The right (support) hand is lowest at 0.13 s and lifts from 0.30 s.
- No obstacle is authored. The hand sits about 0.1 m above any top the knees clear, so low walls need a
  bounded dip and torso lean to reach the top (KI-022).

## Small architecture and authority boundary

1. **Perception:** read-only Godot rays/shape queries measure static obstacle face,
   top, depth, approach angle and landing support/headroom. Return explicit partial
   observations/rejection reasons. Query mask/exclusions come from the physical body.
   Geometry eligibility is separate from clip compatibility.
2. **Selection:** require input intent, grounded running, a verified source clip and
   compatible entry speed/phase/geometry. Reject rather than fabricate missing motion.
3. **Planning:** source metadata supplies takeoff/contact/landing events, reference
   root trajectory, contact offsets and body envelope. Fit only within measured limits.
   Validate the complete swept body path, landing footprint and expected exit velocity.
4. **Execution/blending:** an explicit fixed-tick physical action consumes the validated
   plan through CharacterBody3D collision queries/motion. Rendering follows action
   state/time; it cannot move the body. No root-motion teleport, collision disabling,
   or second independent body-position writer. Any temporary collision envelope must
   be derived from the verified pose profile and swept before use.
5. **Contact/recovery:** bounded source-windowed hand correction, physical landing,
   and a compatible run-out blend. New obstruction interrupts safely; clear the
   action without carrying stale contact targets into ordinary running.

The geometry preview is not a planner/executor. No physical-action implementation is
permitted to infer the missing clip's trajectory from arbitrary parabolas.

**Implemented** (`utility/movement/flat-plane/traversal/`): `obstacle_probe.gd` (1),
`vault_planner.gd` over `vault_profile.gd` and `vault_clip.gd` (2-3), `vault_action.gd`
(4), and the vault state, entry-foot cadence steering and planted-hand IK in
`animation/authored_animation.gd` (5). The collider's travel timing comes from the
measured clip. Its height is a smooth clearance hump derived from the collider size and
the measured top. Before arming and again at takeoff, a crouch-height cylinder is overlap-tested
at sampled points along it (`path_clear`). It is then driven with full collision response. Tracking
error beyond 0.15 m horizontal or 0.25 m vertical aborts to the movement core.
The drawn body follows the authored clip, warped only to keep every limb above the top.

## Validation and checkpoint

Independent probe tests cover dimensions/angles, absent/too-tall/thick obstacles,
partial top support, moving bodies, blocked/missing/uneven landings, query budgets and
unchanged physical body state. A standalone diagnostic scene may use the approved
Playground as-is; do not change its defaults.

After source delivery: verify original playback first, then native retarget/pose
envelope, contact timestamps and root displacement. Test the actual source-derived
path with slow/fast/angled approaches, modest height changes, interrupted preparation,
uneven/blocked landing and immediate run-out. Compare animation-enabled/disabled
physical trajectories, transition pose deltas, hand/foot errors and CPU distributions.

Only then expose the four traversal controls: **Anticipation, Transition Response,
Contact Correction, Momentum Continuity**, using the existing SMC-MIXER mappings and
preserving presets. Keep the 3.0 A/B and an approved-authored/no-traversal baseline.
Run focused and full regressions, native side/full-3D captures and a genuine playtest.
Human approval of the vault remains mandatory before the next traversal move.

**Status:** done, except human approval. The source was verified first, then the retarget, contacts and root
travel. Approach speeds of 3, 6 and 12 m/s, angled and too-angled walls, deep and too-deep walls, a raised
deck, a drop landing, interrupted approaches, a missing clip and traversal off are covered by 13 vault tests.
The four controls are on MIDI bank 5. The 3.0 A/B is kept, and `--trial=vault` compares traversal off and on.
Results: [Movement Lab 4.0](../DOCUMENTATION/MOVEMENT-LAB-4.md).
