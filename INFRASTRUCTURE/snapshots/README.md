# Snapshots (local data, git-ignored)

`INFRASTRUCTURE/snapshots/<env>/<UTC stamp>-<label>/`
- `world.json` - exact copy of the environment's world file at that moment
- `snapshot.json` - id, env, label, created_at, world_id, seed, schema_version, revision, site_progress, saved_at,
  server_build, sha256, bytes, server_was_running
- optional `world.json.bak` / `.tmp` moved here by a restore (state of the replaced world)

Commands: `structure.py snapshot create|list|restore` (rules in `AGENT-WORKSHOP/PROTOCOLS/VERSIONING.md`).
Tooling never deletes snapshots; remove old ones by hand when you are sure. Automatic snapshots are labelled
`pre-restore` and `pre-purge`. Only this README is committed.
