class_name Inventory
extends RefCounted
## The parts you hold and haven't bolted on (the valley's way: you build only with what you have,
## and what you take off a wreck is yours). Kept in `path`.

static var path := "user://valley_inventory.cfg" ## (tests point it elsewhere)
static var counts := {}
static var _loaded := false
## What a new start in the valley has spare (with the starter machine on).
const START := {"frame": 6, "plate": 3, "wedge": 2}


static func load_all() -> void:
	_loaded = true
	counts.clear()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		counts = START.duplicate()
		save_all()
		return
	for k: String in cf.get_section_keys("parts") if cf.has_section("parts") else []:
		counts[k] = int(cf.get_value("parts", k, 0))


static func save_all() -> void:
	var cf := ConfigFile.new()
	for k: String in counts:
		if int(counts[k]) > 0:
			cf.set_value("parts", k, int(counts[k]))
	cf.save(path)


static func count(id: String) -> int:
	if not _loaded:
		load_all()
	return int(counts.get(id, 0))


static func add(id: String, n := 1) -> void:
	if not _loaded:
		load_all()
	counts[id] = count(id) + n
	save_all()


## One out, if there is one.
static func take(id: String) -> bool:
	if count(id) <= 0:
		return false
	counts[id] = count(id) - 1
	save_all()
	return true


## Swapping the machine's parts `old` (rows) for `new`: if what's held and what comes off cover the
## new, it's done (the difference kept) and true; else nothing changes, and what's short is said.
static func swap(old: Array, new: Array) -> Dictionary:
	var have := {}
	for k: String in counts:
		have[k] = int(counts[k])
	for e: Array in old:
		have[str(e[0])] = int(have.get(str(e[0]), 0)) + 1
	var short := {}
	for e: Array in new:
		var id := str(e[0])
		have[id] = int(have.get(id, 0)) - 1
		if int(have[id]) < 0:
			short[id] = -int(have[id])
	if not short.is_empty():
		return {"ok": false, "short": short}
	counts = have
	save_all()
	return {"ok": true, "short": {}}


static func reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_loaded = false
	counts.clear()
