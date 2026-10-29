class_name Inventory
extends RefCounted
## The parts you hold and haven't bolted on (the valley's way: you build only with what you have,
## and what you take off a wreck is yours). Kept in `path`.
##
## A part has a past: each one held has what's left of it (0..1: its hit points when it's bolted on).
## What comes off a wreck is rusted, bent, half burnt (Salvage); what a job pays is good. Bolting one
## on takes the best of that kind; one taken off comes back as it was. Scrap (`scrap`) is what
## mending is paid in (the workshop: Workshop).

static var path := "user://valley_inventory.cfg" ## (tests point it elsewhere)
static var counts := {}
static var cond := {} ## id -> Array of 0..1, best first (as many as counts[id])
static var scrap := 0
static var taken := 1.0 ## (what the part last taken had left)
static var _loaded := false
## What a new start in the valley has spare (with the starter machine on).
const START := {"frame": 6, "plate": 3, "wedge": 2}
const START_SCRAP := 20


static func load_all() -> void:
	_loaded = true
	counts.clear()
	cond.clear()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		counts = START.duplicate()
		scrap = START_SCRAP
		save_all()
		return
	for k: String in cf.get_section_keys("parts") if cf.has_section("parts") else []:
		counts[k] = int(cf.get_value("parts", k, 0))
		var c: Array = cf.get_value("cond", k, [])
		cond[k] = c.slice(0, counts[k])
	scrap = int(cf.get_value("res", "scrap", 0))


static func save_all() -> void:
	var cf := ConfigFile.new()
	for k: String in counts:
		if int(counts[k]) > 0:
			cf.set_value("parts", k, int(counts[k]))
			cf.set_value("cond", k, _conds(k))
	cf.set_value("res", "scrap", scrap)
	cf.save(path)


## Every one of `id` held, what each has left, best first (one with no record is whole).
static func _conds(id: String) -> Array:
	var c: Array = cond.get(id, [])
	while c.size() < int(counts.get(id, 0)):
		c.append(1.0)
	c.resize(int(counts.get(id, 0)))
	c.sort()
	c.reverse()
	cond[id] = c
	return c


static func count(id: String) -> int:
	if not _loaded:
		load_all()
	return int(counts.get(id, 0))


## The best of `id` held (0..1), or -1 with none.
static func best(id: String) -> float:
	if count(id) <= 0:
		return -1.0
	return float(_conds(id)[0])


static func add(id: String, n := 1, c := 1.0) -> void:
	if not _loaded:
		load_all()
	var cs := _conds(id)
	for i in n:
		cs.append(clampf(c, 0.02, 1.0))
	counts[id] = count(id) + n
	_conds(id)
	save_all()


## One out (the best), if there is one: what it has left is in `taken`.
static func take(id: String) -> bool:
	if count(id) <= 0:
		return false
	var cs := _conds(id)
	taken = float(cs.pop_front())
	counts[id] = count(id) - 1
	save_all()
	return true


static func add_scrap(n: int) -> void:
	if not _loaded:
		load_all()
	scrap = maxi(scrap + n, 0)
	save_all()


## Swapping the machine's parts `old` (rows, worn as Machine.to_data(true) gives them) for `new`: if
## what's held and what comes off cover the new, it's done (the difference kept, each part as worn as
## it was; the new ones the best there are) and true, `rows` being `new` with its parts' wear; else
## nothing changes, and what's short is said.
static func swap(old: Array, new: Array) -> Dictionary:
	if not _loaded:
		load_all()
	var have := {}
	for k: String in counts:
		have[k] = _conds(k).duplicate()
	for e: Array in old:
		var id := str(e[0])
		if not have.has(id):
			have[id] = []
		(have[id] as Array).append(float(e[6]) if e.size() >= 7 else 1.0)
	var short := {}
	var worn := []
	for e: Array in new:
		var id := str(e[0])
		var pool: Array = have.get(id, [])
		if pool.is_empty():
			short[id] = int(short.get(id, 0)) + 1
			continue
		pool.sort()
		pool.reverse()
		var c := float(pool.pop_front())
		var row := e.duplicate()
		row.resize(mini(row.size(), 6))
		if c < 0.995:
			if row.size() < 6:
				row.append(0)
			row.append(snappedf(c, 0.01))
		worn.append(row)
	if not short.is_empty():
		return {"ok": false, "short": short}
	counts.clear()
	cond.clear()
	for k: String in have:
		if not (have[k] as Array).is_empty():
			counts[k] = (have[k] as Array).size()
			cond[k] = have[k]
	save_all()
	return {"ok": true, "short": {}, "rows": worn}


static func reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_loaded = false
	counts.clear()
	cond.clear()
	scrap = 0
