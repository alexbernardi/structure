# Import stage (library -> Godot projects)

1. **Deploy**: `structure.py pipeline deploy <id>` (also done by `pipeline run`) copies `runtime/<id>.glb` into each
   folder listed in `asset.json` `consumers` and writes `<id>.asset.json` (id, version, dimensions, pivot, sha256).
2. **Import**: the consuming project is imported headless (`godot --headless --path <project> --import`), producing
   `<id>.glb.import` (committed) and cached data in `.godot/` (ignored). Godot's `.blend`/FBX importers are disabled
   in project settings so only validated GLBs enter projects.
3. **Validate in engine**: `SANDBOX/godot/tests/unit/test_assets.gd` loads every deployed asset, instantiates it and
   checks its bounds against the sidecar (size and pivot).

The sandbox uses `res://assets/common/models/resource_stone/resource_stone.glb` for gatherable resources
(`client/world_view.gd`, falls back to a box if the asset is missing).
