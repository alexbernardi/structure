# movement_core - the approved movement character

Status: **stable 1.0.0**. A package room ([ADR-0010](../../AGENT-WORKSHOP/DECISIONS/ADR-0010-shared-systems-and-laboratories.md)):
the source lives in its workbench laboratory, `utility/movement/flat-plane/systems/movement_core/`, and every consumer
gets a pinned, hash-checked copy at `res://systems/movement_core/`.

- Interface: [CONTRACT.md](CONTRACT.md). Scope and behaviour: [SPEC.md](SPEC.md).
- Architecture, states, animation, IK, parameters, modifiers, inputs, examples, limitations:
  [MOVEMENT-CORE.md](../../AGENT-WORKSHOP/DOCUMENTATION/MOVEMENT-CORE.md).
- Develop it in the workbench (`utility/movement/flat-plane`, the movement laboratory), on a laboratory branch:
  [LABORATORY-PIPELINE.md](../../AGENT-WORKSHOP/PROTOCOLS/LABORATORY-PIPELINE.md).

```powershell
python TOOLS/cli/structure.py room status movement_core              # version, source hash, every consumer's pin
python TOOLS/cli/structure.py room install movement_core <project>   # pin the current version into a project
python TOOLS/cli/structure.py room install movement_core <project> --version 1.0.0   # an older release, from its tag
python TOOLS/cli/structure.py room bench movement_core               # measured against room.json targets
```

## Versions

Semantic versions; each release is the git tag `movement_core/v<version>`.

| Version | Date | Change | Compatibility |
|---|---|---|---|
| 1.0.0 | 2026-11-11 | First promoted release: Movement Lab 3.0 locomotion, 4.0 vault, 5.0-5.6 traversal (mantle, catch-and-hang, shimmy, corners, climber hang and shuffle, slide, flip), capabilities, authored animation, hand / foot IK, skeleton view. Public entry point `movement_character.gd`. | - |

Rules for the next version: additions to [CONTRACT.md](CONTRACT.md) (new members, signals, attributes, capabilities)
are a minor bump; fixes and tuning that keep the contract are a patch; removing or changing a contract member is a
major bump and needs migration notes here. Changing what a consumer sees on the network or in saves also follows
[VERSIONING.md](../../AGENT-WORKSHOP/PROTOCOLS/VERSIONING.md).
