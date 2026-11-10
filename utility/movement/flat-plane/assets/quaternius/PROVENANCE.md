# Quaternius Universal Animation Library - Standard

Official source: <https://quaternius.itch.io/universal-animation-library>.
Downloaded 2026-11-08 using the author's free Standard download (itch upload 17958403), not a third-party mirror/repack.
License: **CC0 1.0**, included verbatim in [License.txt](License.txt). Original instructions: [README.txt](README.txt).
Creators credited by the publisher: Quaternius and animator Gonzalo Furnier.

The smallest published package is one combined library, not separate per-action downloads. Its Godot/Unreal exports
contain **43 actual animations**, not the 120+ advertised for the full paid collection. No Blender/FBX conversion was used.
The GLBs below are byte-for-byte original. The 65-bone reference character is included in each.

| File | SHA-256 | Use |
|---|---|---|
| Downloaded Standard ZIP (not committed) | `cc73fc4e495b82958207316596317a3f40b9fa38065bde1027937452da537724` | Provenance |
| [UAL1_Standard.glb](UAL1_Standard.glb) | `69591853d817488edaa8fd9bf8fc1d821eaeaf789f8627b3cd23b41c4ed67997` | In-place source/reference |
| [UAL1_Standard_RM.glb](UAL1_Standard_RM.glb) | `be684571ed655a1b892c2c07e6e2aeca053b606c442d34004adaf1d944090d01` | Displacement calibration only; never drives a CharacterBody3D |

## Initial subset, inspected from the real files

| Exact GLB name | Godot imported name | Duration (s) | Intended role |
|---|---|---:|---|
| `Idle_Loop` | `Idle` | 2.5000 | Idle |
| `Jog_Fwd_Loop` | `Jog_Fwd` | 0.9333 | Run/jog |
| `Sprint_Loop` | `Sprint` | 0.6667 | Sprint |
| `Jump_Start` | `Jump_Start` | 1.3333 | Jump start, subject to physical-state timing |
| `Jump_Loop` | `Jump` | 2.5000 | Air loop; **there is no separately named Fall clip in Standard** |
| `Jump_Land` | `Jump_Land` | 1.2667 | Landing, subject to physical-state timing |
| `Crouch_Idle_Loop` | `Crouch_Idle` | Source duration retained | Preserve existing crouch |
| `Crouch_Fwd_Loop` | `Crouch_Fwd` | Source duration retained | Preserve existing crouch movement |

Godot's standard name-suffix import removes `_Loop` and enables looping. Runtime paths use the inspected imported names,
not the raw GLB names. The original source files are unmodified.

The root-motion counterpart travels 5.0 m per jog cycle (**5.357143 m/s**) and 5.5 m per sprint cycle (**8.25 m/s**).
The in-place counterparts have zero horizontal root displacement. These are source-scale speeds; retargeted proportions
must be considered before calibrating the primitive mannequin. No walking clips are selected for active gameplay.

Source verification scene: [animation_reference.tscn](../../scenes/animation_reference.tscn). It plays unretargeted,
uncorrected clips on the original character at 1x timing. It is not evidence that the final mannequin looks natural.

Native `BoneMap` / `SkeletonProfileHumanoid` import settings normalize rests and names without editing GLB bytes.
Position tracks use `Skeleton3D.motion_scale`. The 23-bone primitive target uniformly scales the normalized rig to
a 1.01 m hip height, drops unused finger tracks and keeps authentic core tracks. Source/target joint correspondence,
constant limb lengths and compatible normalized jog/sprint footstep phases are tested.
See the [3.0 audit and review checkpoint](../../../../../AGENT-WORKSHOP/DOCUMENTATION/MOVEMENT-LAB-3.md).

# Quaternius Universal Animation Library 2 - paid package (vault, climb, double jump)

Source: the author's paid UAL2 package, bought from the official itch page by the user and placed in
`AGENT-WORKSHOP/DOWNLOADS/` on 2026-11-08. That folder is **not committed** (it is git-ignored; it holds a 68 MB
`.blend`, Unity and Unreal/Godot exports). The package's `License.txt` is the same **CC0 1.0** text as above.
The free UAL2 Standard ZIP (`4008ea208a604773a2b2177d965f0f5d3195498b5bf838c3f5785d68e95f2a68`) has no vault clip.

The Unreal/Godot export has **134 animations**. `SafetyVault` (0.7333 s, 22 frames at 30 fps) is used since 4.0;
Movement Lab 5.0 adds `ClimbUp_1m` (0.6667 s, mantle and ledge grab) and `DoubleJump` (0.9 s, the spell's air jump)
in a separate extract, so the verified vault extract is unchanged.
[extract_glb_clips.py](../../tools/extract_glb_clips.py) copies the source GLB and keeps only the named animation.
Every node, skin, mesh and material is kept. It verifies that the kept sampler bytes are identical to the source:

`python tools/extract_glb_clips.py <source.glb> <output.glb> SafetyVault`

| File | Bytes | SHA-256 | Use |
|---|---:|---|---|
| `UAL2.glb` (source, not committed) | 20,717,364 | `ad3ae049c7d3d4846133b59dba6218fdabebe05d3aec646caef6665f6c540684` | In-place source |
| `UAL2_RM.glb` (source, not committed) | 20,756,380 | `a295ddb1fe171ed225517e88aa1baeaa3939cd00c775b39c75745c3e6a57060d` | Root-motion source |
| [UAL2_Traversal.glb](UAL2_Traversal.glb) | 720,416 | `2343c92472316f49455afebc46bc049539a4f7cdbbfdf6926947285f7d4b76d7` | Vault pose, retargeted like UAL1 |
| [UAL2_Traversal_RM.glb](UAL2_Traversal_RM.glb) | 720,416 | `a2f8b3309e546181b0b3b7b633eed061686d9c3f6de2e91b12cf580c18edef47` | Root path and contact timing only; never moves a body directly |
| [UAL2_Climb.glb](UAL2_Climb.glb) | 831,456 | `faaf743603048ab0b18e0e255d2d55692fcb3b160c0ec8ec6d0c2822634662f7` | `ClimbUp_1m` + `DoubleJump` in-place poses (5.0); `python tools/extract_glb_clips.py <UAL2.glb> assets/quaternius/UAL2_Climb.glb ClimbUp_1m DoubleJump` |

The climb's root motion (linear 1.0 m up, 1.676 m forward, source units) was read from `UAL2_RM.glb` and is recorded
as constants in `traversal/mantle_clip.gd`; no root-motion extract is committed for it.

Both extracts use the same 65-bone character as UAL1, so the existing `BoneMap` import settings apply unchanged.
Measured contact timing and root travel are documented in the
[4.0 vault checkpoint](../../../../../AGENT-WORKSHOP/DOCUMENTATION/MOVEMENT-LAB-4.md).
