# ADR-0007: Asset pipeline - Blender background scripts to validated GLB

Status: Accepted (2026-10-27)

## Context
Assets should be generated repeatably (Specification -> Script -> Blender -> Validation -> GLB -> Godot), with
metadata (origin, licence, editable source, runtime format, dimensions, hashes) and without committing caches.

## Decision
- Pin **Blender 5.0.1** (installed on the dev machine; 4.2.0 also present). The pipeline refuses other versions unless
  `--allow-version-mismatch` is given; the version used is recorded in `asset.json`.
- `blender --background --factory-startup --python PIPELINES/blender/generate_asset.py` builds the asset from
  `COMMON-ASSETS/<category>/<id>/source/spec.json` with a registered generator, exports through one shared function
  (`PIPELINES/export/export_gltf.py`), then `PIPELINES/validation/validate_glb.py` (stdlib) checks names, transforms,
  dimensions, pivot and budgets.
- The validated GLB is stored in the library (`runtime/<id>.glb`, committed - kilobytes), recorded in
  `asset.json` + `COMMON-ASSETS/manifests/assets.json`, and deployed to each consumer with a sidecar used by an
  in-engine test (Godot import + dimension check). Godot's own `.blend` import is disabled in projects.
- Large editable sources (`.blend`, textures, audio) go through Git LFS (`.gitattributes`).

## Consequences
+ Verified: identical bytes on regeneration with the pinned Blender (output is reproducible).
- Other Blender versions may produce different bytes (exporter version is embedded in the GLB).
- Blender is not containerised yet (only needed for asset work).
