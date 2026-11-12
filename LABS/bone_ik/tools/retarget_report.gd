## Retargets every available authored clip onto the default Vitruvian rig and measures it against the original
## imported skeleton (tests/bone_ik/anim_measure.gd). Writes a Markdown table.
##   godot --headless --path LABS/bone_ik --script res://tools/retarget_report.gd -- --out=<absolute .md>
extends SceneTree

const Rig = preload("res://systems/bone_ik/vitruvian_rig.gd")
const ClipAdapter = preload("res://systems/bone_ik/animation/humanoid_clip_adapter.gd")
const Measure = preload("res://tests/bone_ik/anim_measure.gd")


func _initialize() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var rig = Rig.new()
	root.add_child(rig)
	rig.build()
	var lines := ["| Clip | Source | Frames | Orientation error (deg) | Length error (m) | Planted-toe error (m) | Lowest sole ours / source (m) | Axial transfer max (deg) | Raw violations (deg beyond hard) | After axial alignment |",
		"|---|---|---:|---:|---:|---:|---:|---:|---|---|"]
	var clean := 0
	var total := 0
	for path in ClipAdapter.SOURCES:
		var src: Node = (load(path) as PackedScene).instantiate()
		root.add_child(src)
		var ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
		var names := Array(ap.get_animation_list())
		names.sort()
		for name in names:
			if not rig.animation_reports.has(name) or rig.animation_reports[name].source != path:
				continue
			var m: Dictionary = Measure.measure(rig, src, name, 30)
			total += 1
			if m.violations.is_empty():
				clean += 1
			lines.append("| %s | %s | %d | %.4f | %.6f | %.3f | %.3f / %.3f | %.1f | %s | %s |" % [name, path.get_file(), m.frames,
				m.rotation_error_deg, m.length_error_m, m.stance_toe_error_m, m.min_sole_m, m.src_min_sole_m,
				m.max_hinge_transfer_deg, _fmt(m.raw_violations), _fmt(m.violations)])
		src.free()
	var text := "Clips within the hard limits after axial alignment: %d / %d\n\n" % [clean, total] + "\n".join(lines) + "\n"
	print(text)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	quit()


static func _fmt(v: Dictionary) -> String:
	if v.is_empty():
		return "none"
	var parts := []
	for k in v:
		parts.append("%s %.1f" % [k, v[k]])
	return ", ".join(parts)
