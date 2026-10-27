# PIPELINES - Specification -> Script -> Blender -> Validation -> GLB -> Godot

`python TOOLS/cli/structure.py pipeline run <asset_id>` runs every stage; `pipeline check` verifies without Blender.

| Stage | Folder / file | What happens |
|---|---|---|
| Specification | `COMMON-ASSETS/<category>/<id>/source/spec.json` | generator name, parameters (metres), pivot, tolerance, budgets |
| Script + Blender | `blender/generate_asset.py`, `blender/generators/<name>.py` | `blender --background --factory-startup --python ...`; generators are registered in `generators/__init__.py` |
| Export | `export/export_gltf.py` | one shared set of glTF settings (GLB, +Y up, applied transforms, no cameras/lights/animations) |
| Validation | `validation/validate_glb.py` | stdlib GLB parser: names, identity transforms, size, pivot, triangle/material/image/byte budgets, base colour vs spec |
| Library | `COMMON-ASSETS/.../runtime/` + `asset.json` + `manifests/assets.json` | sha256, size, tool versions, generation time recorded |
| Import into Godot | `import/README.md` | deploy to consumers + headless Godot import + in-engine dimension test |

Reproducibility: Blender version pinned (`INFRASTRUCTURE/builds/toolchain.json`, exact match required unless
`--allow-version-mismatch`); outputs were verified byte-identical on regeneration. Scratch output: `.runtime/pipeline/<id>/`
(includes `blender.log` and `blender-report.json`). Errors name the failing stage and point at the log.

Colours in specs are **display sRGB** (what you see on screen, like Godot's `Color` in the palette); generators convert
them to linear for Blender, and the validator checks the exported `baseColorFactor` (found in playtest 0002).

Adding an asset: create the folder with `asset.json` + `source/spec.json` (copy `resource_stone`), add a generator if
needed, run `pipeline run <id>`, commit spec + runtime + metadata + deployed copies.
