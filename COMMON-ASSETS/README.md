# COMMON-ASSETS - shared asset library

```
COMMON-ASSETS/
  manifests/assets.json          generated index (id, version, path, runtime sha256, licence)
  <category>/<asset_id>/
    asset.json                   metadata (origin, licence, editable source, runtime, dimensions, consumers, ...)
    source/                      original editable source: generator spec, .blend (Git LFS), raw textures/audio
    runtime/                     processed runtime file(s) produced by PIPELINES (e.g. <asset_id>.glb)
```

Categories: `models/` exists today; `textures/`, `materials/`, `animations/`, `shaders/`, `audio/`, `scripts/`
(reusable scripts/procedural configs) are created with their first asset.

## Conventions

| Topic | Rule |
|---|---|
| Ids and files | `lower_snake_case`; runtime file named after the id |
| Units / axes | metres; glTF/Godot +Y up, -Z forward (the pipeline converts from Blender's Z-up) |
| Pivot | base centre unless the spec says otherwise |
| Source vs runtime | editable sources in `source/` (large binaries via Git LFS); processed outputs in `runtime/`; never edit runtime files by hand |
| Metadata | every asset has `asset.json` (fields: `AGENT-WORKSHOP/BLUEPRINTS/ASSET-INVENTORY.md`); licence + origin are mandatory |
| Consumers | Godot projects get deployed copies (`structure.py pipeline deploy`); copies are hash-checked by `structure.py check` |
| Ownership | `owner` field in `asset.json`; changes to someone else's asset go through them / a task note |
| Budgets | per-asset limits in `source/spec.json` (`budget`), enforced by validation |

Inventory: `AGENT-WORKSHOP/INVENTORY/ASSETS.md`. Pipeline: `PIPELINES/README.md`.
