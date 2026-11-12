## Analytic two-bone IK with skeleton-space targets (feet and the vault support hand).
## Godot 4.7's TwoBoneIK3D reads its target nodes and the skeleton through get_global_transform_interpolated(); with
## physics interpolation on, that cache is refreshed before _process, so targets set while presenting a frame were
## solved a rendered frame late (a planted foot or hand missed by one frame of travel). Plain positions set in the same
## frame have no node transform to lag.
extends SkeletonModifier3D


class Chain:
	var root: int
	var middle: int
	var end: int
	var target := Vector3.ZERO     ## skeleton space
	var pole := Vector3.ZERO       ## skeleton space; the middle joint bends toward it
	var influence := 1.0           ## blends the end from its authored position to the target
	var active := false

	func _init(root_bone: int, middle_bone: int, end_bone: int) -> void:
		root = root_bone
		middle = middle_bone
		end = end_bone


var chains: Array[Chain] = []


func add_chain(skeleton: Skeleton3D, root: int, middle: int, end: int) -> Chain:
	assert(skeleton.get_bone_parent(middle) == root and skeleton.get_bone_parent(end) == middle, "a parented chain")
	var chain := Chain.new(root, middle, end)
	chains.append(chain)
	return chain


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	for chain in chains:
		if chain.active and chain.influence > 0.0:
			_solve(skeleton, chain)


## Swing the root and middle bones (shortest arc, so the authored twist is kept) to put the end on the target with the
## middle joint in the plane of the root, target and pole. Out-of-reach targets are reached as far as the chain allows.
func _solve(skeleton: Skeleton3D, chain: Chain) -> void:
	var root_pose := skeleton.get_bone_global_pose(chain.root)
	var middle_pose := skeleton.get_bone_global_pose(chain.middle)
	var a := root_pose.origin
	var b := middle_pose.origin
	var c := skeleton.get_bone_global_pose(chain.end).origin
	var upper := a.distance_to(b)
	var lower := b.distance_to(c)
	var reach := c.lerp(chain.target, minf(chain.influence, 1.0)) - a
	if reach.length_squared() < 1e-10 or upper < 1e-5 or lower < 1e-5:
		return
	var axis := reach.normalized()
	var distance := clampf(reach.length(), absf(upper - lower) + 1e-5, upper + lower - 1e-5)
	var bend := _across(chain.pole - a, axis)
	if bend.length_squared() < 1e-10:
		bend = _across(b - a, axis)
		if bend.length_squared() < 1e-10:
			return
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var knee := a + axis * along + bend.normalized() * sqrt(maxf(0.0, upper * upper - along * along))
	var root_turn := Basis(Quaternion((b - a).normalized(), (knee - a).normalized()))
	var root_basis := root_turn * root_pose.basis
	var lower_now := root_turn * (c - b)
	var middle_basis := Basis(Quaternion(lower_now.normalized(), (a + axis * distance - knee).normalized())) * root_turn * middle_pose.basis
	var parent := skeleton.get_bone_parent(chain.root)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(chain.root, (parent_basis.inverse() * root_basis).get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(chain.middle, (root_basis.inverse() * middle_basis).get_rotation_quaternion())


static func _across(vector: Vector3, axis: Vector3) -> Vector3:
	return vector - axis * vector.dot(axis)
