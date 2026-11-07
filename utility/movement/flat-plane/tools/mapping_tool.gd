## Command-line view/edit of the saved MIDI mapping (uses the same code as the monitor).
##   godot --headless --path utility/movement/flat-plane --script res://tools/mapping_tool.gd -- <command> [args]
## Commands: summary | list | infer | unmap <control_id>... | behavior <control_id> <momentary|trigger>
extends SceneTree

const Config = preload("res://midi/midi_config.gd")
const Catalog = preload("res://midi/control_catalog.gd")
const Pattern = preload("res://midi/midi_pattern.gd")


func _initialize() -> void:
	var args: Array[String] = []
	var path := Config.DEFAULT_PATH
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--config="):
			path = String(a).substr(9)
		else:
			args.append(String(a))
	var cfg := Config.new()
	var r := cfg.load_file(path)
	if not r.ok and not r.get("missing", false):
		printerr("config rejected: ", r.errors)
		quit(1)
		return
	var cmd := args[0] if args.size() > 0 else "summary"
	var save := false
	match cmd:
		"summary":
			_summary(cfg)
		"list":
			for c in Catalog.all():
				var m: Dictionary = cfg.mapping_of(c.id)
				var state := "unmapped" if m.is_empty() else ("verified" if cfg.is_verified(c.id) else ("inferred" if cfg.is_inferred(c.id) else "mapped"))
				print("%-16s %-9s %s" % [c.id, state, JSON.stringify(m) if not m.is_empty() else ""])
		"infer":
			var proposals := Pattern.propose(cfg)
			print("inferred ", Pattern.apply(cfg, proposals), " controls (unverified)")
			save = true
		"unmap":
			for id in args.slice(1):
				cfg.clear_mapping(id)
				print("unmapped ", id)
			save = true
		"behavior":
			if args.size() == 3 and cfg.is_mapped(args[1]) and Config.BUTTON_BEHAVIORS.has(args[2]):
				cfg.mapping_of(args[1])["behavior"] = args[2]
				cfg.profile().verified.erase(args[1])
				print("set ", args[1], " -> ", args[2])
				save = true
			else:
				printerr("usage: behavior <mapped button id> <momentary|trigger>")
				quit(2)
				return
		_:
			printerr("unknown command ", cmd)
			quit(2)
			return
	if save:
		var s := cfg.save_file(path)
		if not s.ok:
			printerr(s.error)
			quit(1)
			return
		_summary(cfg)
	quit(0)


func _summary(cfg) -> void:
	var req := Catalog.required_ids()
	var mapped := 0
	var verified := 0
	var inferred := 0
	var missing: Array[String] = []
	for id in req:
		if cfg.is_mapped(id):
			mapped += 1
			verified += 1 if cfg.is_verified(id) else 0
			inferred += 1 if cfg.is_inferred(id) else 0
		else:
			missing.append(id)
	print("profile %s: mapped %d/%d (inferred %d), verified %d/%d" % [cfg.active_profile_name(), mapped, req.size(), inferred, verified, req.size()])
	if not missing.is_empty():
		print("unmapped: ", ", ".join(missing))
