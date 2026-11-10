## One movement modifier: a named, sourced bundle of attribute effects and capability grants, optionally timed.
## Sources describe where it comes from (training, cybernetic, equipment, magic, injury, environment, buff, debuff);
## they are labels for the UI and for removing every modifier of one source, never special cases in the maths.
##
## Effect ops, applied per attribute in this fixed order (see MovementCapabilities.resolve):
##   add   +value                         (summed)
##   mul   x value                        (multiplied; applied to base + adds)
##   set   = value                        (overrides; the highest priority wins, ties by modifier id)
##   cap   min(result, value)             (upper bound; the lowest cap wins - e.g. an injured leg)
##   floor max(result, value)             (lower bound; the highest floor wins)
## The result is then clamped to the attribute's legal range. Every op but `set` commutes with its own kind, so the
## order modifiers were added in never matters.
extends RefCounted

const SOURCES := ["training", "cybernetic", "equipment", "magic", "injury", "environment", "buff", "debuff"]
const OPS := ["add", "mul", "set", "cap", "floor"]

var id := ""
var label := ""
var source := "buff"
var effects: Array[Dictionary] = []   ## {stat: String, op: String, value: float}
var grants: Array[String] = []        ## capabilities this modifier adds
var revokes: Array[String] = []       ## capabilities this modifier removes (wins over grants)
var duration := INF                   ## s; INF = until removed
var remaining := INF
var priority := 0


static func make(modifier_id: String, modifier_label: String, modifier_source: String, modifier_effects: Array, modifier_grants: Array = [],
		seconds := INF, modifier_revokes: Array = [], modifier_priority := 0):
	var m = load("res://capability/movement_modifier.gd").new()
	m.id = modifier_id
	m.label = modifier_label
	m.source = modifier_source
	for e in modifier_effects:
		m.effects.append({"stat": String(e[0]), "op": String(e[1]), "value": float(e[2])})
	for g in modifier_grants:
		m.grants.append(String(g))
	for r in modifier_revokes:
		m.revokes.append(String(r))
	m.duration = seconds
	m.remaining = seconds
	m.priority = modifier_priority
	return m


func timed() -> bool:
	return is_finite(duration)


## Problems with the definition (empty = valid).
func check() -> Array[String]:
	var problems: Array[String] = []
	if id == "":
		problems.append("modifier without id")
	if not SOURCES.has(source):
		problems.append("%s: unknown source %s" % [id, source])
	for e in effects:
		if not OPS.has(e.op):
			problems.append("%s: unknown op %s" % [id, e.op])
		if e.op == "mul" and float(e.value) < 0.0:
			problems.append("%s: negative multiplier on %s" % [id, e.stat])
	if timed() and duration <= 0.0:
		problems.append("%s: non-positive duration" % id)
	return problems


func describe() -> String:
	var parts: Array[String] = []
	for e in effects:
		var symbol: String = {"add": "+", "mul": "x", "set": "=", "cap": "<=", "floor": ">="}[e.op]
		parts.append("%s %s%s" % [e.stat, symbol, String.num(e.value, 2)])
	for g in grants:
		parts.append("+" + g)
	for r in revokes:
		parts.append("-" + r)
	return "%s [%s]%s: %s" % [label if label != "" else id, source, "" if not timed() else " %.0f/%.0f s" % [remaining, duration], ", ".join(parts)]
