class_name Inventory
extends RefCounted
## The parts you hold and haven't bolted on (the valley's way: you build only with what you have,
## and what you take off a wreck is yours). Kept in `path`.
##
## A part has a past: each one held has what's left of it (0..1: its hit points when it's bolted on).
## What comes off a wreck is rusted, bent, half burnt (Salvage); what a job pays is good. Bolting one
## on takes the best of that kind; one taken off comes back as it was. Scrap (`scrap`) is what
## mending is paid in (the workshop: Workshop). Wood (`wood`: billets felled with a saw, craned onto
## your bed and carried home) is what wooden parts are made of, beside the workshop (Parts.wood_cost);
## all the wood ever brought home (`delivered`) opens the builder's parts a few at a time (Parts.OPENS).

static var path := "user://valley_inventory2.cfg" ## (tests point it elsewhere; the 2: the wood age's start)
static var counts := {}
static var cond := {} ## id -> Array of 0..1, best first (as many as counts[id])
static var scrap := 0
static var wood := 0 ## billets in the workshop's store
static var delivered := 0 ## all the wood brought home, ever
static var plans: Array = [] ## the plans found (Parts.PLANS keys): what metal can be made
static var taken := 1.0 ## (what the part last taken had left)
static var _loaded := false
## What a new start in the valley has spare (little: the starter cart has its saw and its crane on,
## and the rest is cut out of the forest or taken off wrecks).
const START := {"wood_rail": 2}
## Given once each to a valley begun before there were any: flag -> parts.
const GIFTS := {}
const START_SCRAP := 0
const START_WOOD := 4


static func load_all() -> void:
	_loaded = true
	counts.clear()
	cond.clear()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		counts = START.duplicate()
		scrap = START_SCRAP
		wood = START_WOOD
		delivered = 0
		plans = []
		save_all()
		return
	for k: String in cf.get_section_keys("parts") if cf.has_section("parts") else []:
		counts[k] = int(cf.get_value("parts", k, 0))
		var c: Array = cf.get_value("cond", k, [])
		cond[k] = c.slice(0, counts[k])
	scrap = int(cf.get_value("res", "scrap", 0))
	wood = int(cf.get_value("res", "wood", 0))
	delivered = int(cf.get_value("res", "delivered", 0))
	plans = cf.get_value("res", "plans", [])
	var gave := false
	for flag: String in GIFTS:
		if not bool(cf.get_value("res", flag, false)):
			gave = true
			for k: String in GIFTS[flag]:
				counts[k] = int(counts.get(k, 0)) + int(GIFTS[flag][k])
	if gave:
		save_all()


static func save_all() -> void:
	var cf := ConfigFile.new()
	for k: String in counts:
		if int(counts[k]) > 0:
			cf.set_value("parts", k, int(counts[k]))
			cf.set_value("cond", k, _conds(k))
	cf.set_value("res", "scrap", scrap)
	cf.set_value("res", "wood", wood)
	cf.set_value("res", "delivered", delivered)
	cf.set_value("res", "plans", plans)
	for flag: String in GIFTS:
		cf.set_value("res", flag, true)
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


static func add_wood(n: int) -> void:
	if not _loaded:
		load_all()
	wood = maxi(wood + n, 0)
	save_all()


## Wood brought home (what opens parts as it adds up).
static func bring_wood(n: int) -> void:
	delivered += n
	add_wood(n)


## Is `id` offered in the valley's builder: held; wooden, once enough wood's come home for it
## (Parts.OPENS); metal, once its plan's known (the workshop's own scrap pieces in the metal age).
## What can't be had yet isn't shown at all.
static func shown(id: String) -> bool:
	if count(id) > 0:
		return true
	if Parts.is_cab(id):
		return false
	if Parts.wood_cost(id) > 0:
		return delivered >= int(Parts.OPENS.get(id, 0))
	var plan := Parts.plan_of(id)
	if plan != "":
		return knows(plan)
	return Parts.metal_cost(id) > 0 and age() >= 2


## One of `id` made of wood (if it's made so and there's wood enough): paid, and held. True if made.
static func make_wood(id: String) -> bool:
	var c := Parts.wood_cost(id)
	if c <= 0 or wood < c:
		return false
	wood -= c
	add(id, 1, 1.0)
	return true


## The age the valley's in: 1 wood, 2 metal (a plan's been found).
static func age() -> int:
	if not _loaded:
		load_all()
	return 2 if not plans.is_empty() else 1


static func knows(plan: String) -> bool:
	if not _loaded:
		load_all()
	return plan in plans


## A plan found: true if it's new (and kept).
static func learn(plan: String) -> bool:
	if knows(plan) or not Parts.PLANS.has(plan):
		return false
	plans.append(plan)
	save_all()
	return true


## The next plan not yet found (in Parts.PLAN_ORDER), or "".
static func next_plan() -> String:
	for k: String in Parts.PLAN_ORDER:
		if not knows(k):
			return k
	return ""


## One of `id` made of scrap (its plan known, scrap enough): paid, and held. True if made.
static func make_metal(id: String) -> bool:
	var plan := Parts.plan_of(id)
	var c := Parts.metal_cost(id)
	if c <= 0 or plan != "" and not knows(plan) or scrap < c:
		return false
	scrap -= c
	add(id, 1, 1.0)
	return true


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
	wood = 0
	delivered = 0
	plans = []
