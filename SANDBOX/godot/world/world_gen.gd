## Deterministic world layout from a seed. Pure functions shared by the server (resource spawns) and
## clients (placeholder terrain), so both agree on geometry without transmitting it.
extends RefCounted

const SITE_ID := "site_0"
const SITE_POSITION := Vector3.ZERO
const SITE_HALF_EXTENT := 3.0
const INITIAL_RESOURCES := 12
const RESOURCE_RING := Vector2(8.0, 30.0)   # min/max distance from the site
const OBSTACLE_COUNT := 16
const OBSTACLE_RING := Vector2(16.0, 70.0)
const SPAWN_RADIUS := 12.0
const SPAWN_ANGLES_DEG := [0.0, 180.0, 90.0, 270.0, 45.0, 225.0, 135.0, 315.0]
const SALT_OBSTACLES := 101
const SALT_RESOURCES := 202
const MAX_SEED := 2147483646


## Engine-independent seed mixing (MINSTD steps), stable across platforms and Godot versions.
static func mix_seed(world_seed: int, salt: int, index: int) -> int:
	var h := posmod(world_seed, 2147483647)
	for v in [salt, index, 12345]:
		h = (h * 48271 + posmod(v, 2147483647)) % 2147483647
	return h


## Placeholder obstacles: [{pos: Vector3 (base centre), size: Vector3}].
static func obstacles(world_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = mix_seed(world_seed, SALT_OBSTACLES, 0)
	var out := []
	for i in OBSTACLE_COUNT:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(OBSTACLE_RING.x, OBSTACLE_RING.y)
		var size := Vector3(rng.randf_range(1.5, 5.0), rng.randf_range(1.0, 4.0), rng.randf_range(1.5, 5.0))
		out.append({"pos": Vector3(cos(angle) * dist, 0.0, sin(angle) * dist), "size": size})
	return out


## Position of the seq-th resource ever spawned in this world (initial scatter and replacements).
static func resource_position(world_seed: int, seq: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = mix_seed(world_seed, SALT_RESOURCES, seq)
	var obs := obstacles(world_seed)
	for attempt in 32:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(RESOURCE_RING.x, RESOURCE_RING.y)
		var p := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if not is_blocked(p, obs, 1.0):
			return p.snapped(Vector3(0.001, 0.001, 0.001))
	return Vector3(RESOURCE_RING.x, 0.0, 0.0)


static func is_blocked(p: Vector3, obs: Array, margin: float) -> bool:
	for o in obs:
		var half: Vector3 = o.size * 0.5
		if absf(p.x - o.pos.x) <= half.x + margin and absf(p.z - o.pos.z) <= half.z + margin:
			return true
	return false


static func spawn_point(slot: int) -> Vector3:
	var angle := deg_to_rad(SPAWN_ANGLES_DEG[slot % SPAWN_ANGLES_DEG.size()]) + (slot / SPAWN_ANGLES_DEG.size()) * 0.2
	return Vector3(cos(angle) * SPAWN_RADIUS, 0.0, sin(angle) * SPAWN_RADIUS)


## Yaw (rotation around +Y; forward is -Z) that faces the construction site from `pos`.
static func yaw_towards_site(pos: Vector3) -> float:
	var to := SITE_POSITION - pos
	return atan2(-to.x, -to.z)
