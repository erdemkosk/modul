extends Node
## The valley's works sites: old works out in the valley (a pump house's tower, a transformer yard,
## a store, a silo), each still guarded by its robots (robot.gd) turned on whoever comes. They're
## where they are for good (seeded: the same valley, the same sites), on open ground (no trees or
## rocks on it), dry (no water, mud or deep snow) and flat, away from where you start and from each
## other; the grass on a site is worn away.
##
## A site is there while you're within NEAR of it (taken away past FAR, as it was left); its robots
## that die stay dead (kept in `path`). A robot's wreck now and then leaves a part to take (Salvage);
## kill the last of a site's robots and it's cleared: its cache is left out to take (three or four
## parts, the better ones: turrets, ammo, barrels, guns, an engine), once.

const COUNT := 6 ## (at most: as many as there's open ground for)
const NEAR := 280.0
const FAR := 380.0
const NAMES := ["ESKİ POMPA İSTASYONU", "TRAFO SAHASI", "TERK EDİLMİŞ DEPO", "SİLO SAHASI", "SU DEPOSU", "MAKİNE ATÖLYESİ"]
const BUILDING := ["water_tower", "transformer", "warehouse", "silo", "water_tower", "warehouse"]
const CACHE := ["turret", "ammo", "barrel", "minigun", "armor", "engine", "battery", "rockets", "cannon", "flamer"]
const WRECK := {"sentry": ["ammo", "barrel", "light"], "warden": ["plate", "frame", "wheel_s", "battery"]}
const ROBOT := preload("res://scripts/robot.gd")

static var path := "user://valley_sites.cfg" ## (tests point it elsewhere)

var game: Node
var terrain: Node
var sites: Array[Dictionary] = [] ## {name, at, yaw, building, robots: [[kind, offset]], dead, cleared, nodes}
var _props: Node ## (WorldProps: the valley's trees and rocks)


func _ready() -> void:
	name = "WorksSites"
	var found := game.find_children("*", "WorldProps", true, false)
	_props = found[0] if not found.is_empty() else null
	_place()
	var cf := ConfigFile.new()
	cf.load(path)
	for i in sites.size():
		sites[i].dead = cf.get_value("site%d" % i, "dead", [])
		sites[i].cleared = bool(cf.get_value("site%d" % i, "cleared", false))


func _save() -> void:
	var cf := ConfigFile.new()
	for i in sites.size():
		cf.set_value("site%d" % i, "dead", sites[i].dead)
		cf.set_value("site%d" % i, "cleared", sites[i].cleared)
	cf.save(path)


## Where they are: seeded spots on dry, flat ground, clear of the start and of each other.
func _place() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var lim := float(terrain.get("half")) - 120.0 if terrain.get("half") != null else 900.0
	var start: Vector3 = (terrain.get("spawn") as Transform3D).origin if terrain.get("spawn") != null else Vector3.ZERO
	for tries in 3000:
		if sites.size() >= COUNT:
			break
		var p := Vector3(rng.randf_range(-lim, lim), 0.0, rng.randf_range(-lim, lim))
		if Vector2(p.x - start.x, p.z - start.z).length() < 220.0 or not _fits(p):
			continue
		var clear := true
		for s in sites:
			if (s.at as Vector3).distance_to(p) < 300.0:
				clear = false
		if not clear:
			continue
		p.y = float(terrain.call("height_at", p.x, p.z))
		var k := sites.size()
		var robots := []
		var n_sentry := 1 + rng.randi() % 2
		var n_warden := 1 + rng.randi() % 3
		for j in n_sentry:
			var a := rng.randf() * TAU
			robots.append(["sentry", Vector2(cos(a), sin(a)) * rng.randf_range(9.0, 14.0)])
		for j in n_warden:
			var a := rng.randf() * TAU
			robots.append(["warden", Vector2(cos(a), sin(a)) * rng.randf_range(6.0, 16.0)])
		var cache := []
		for j in 3 + rng.randi() % 2:
			cache.append(CACHE[rng.randi() % CACHE.size()])
		sites.append({"name": NAMES[k % NAMES.size()], "at": p, "yaw": rng.randf() * TAU, "building": BUILDING[k % BUILDING.size()],
			"robots": robots, "cache": cache, "dead": [], "cleared": false, "nodes": []})


## Open, flat, dry ground for a site: within 18 m no water, mud or deep snow and the ground less than
## 2.5 m up or down; no tree or rock within 24 m.
func _fits(p: Vector3) -> bool:
	var h := float(terrain.call("height_at", p.x, p.z))
	for k in 9:
		var a := k * TAU / 8.0
		var q := p + (Vector3(cos(a), 0.0, sin(a)) * 18.0 if k < 8 else Vector3.ZERO)
		if terrain.has_method("is_water") and bool(terrain.call("is_water", q.x, q.z)):
			return false
		if absf(float(terrain.call("height_at", q.x, q.z)) - h) > 2.5:
			return false
		if terrain.has_method("soft_at"):
			var soft: Vector2 = terrain.call("soft_at", q.x, q.z)
			if soft.x > 0.25 or soft.y > 0.4:
				return false
	return not _props_near(p, 24.0)


## A tree or a rock (standing) within `r` m of `p`.
func _props_near(p: Vector3, r: float) -> bool:
	if _props == null:
		return false
	var grid: Dictionary = _props.get("_grid")
	var xf: Array = _props.get("_xf")
	var cut: Dictionary = _props.get("cut")
	var cell := WorldProps.CELL
	var c0 := Vector2i(floori((p.x - r) / cell), floori((p.z - r) / cell))
	var c1 := Vector2i(floori((p.x + r) / cell), floori((p.z + r) / cell))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for i: int in grid.get(Vector2i(cx, cz), []):
				if cut.has(i):
					continue
				var o: Vector3 = (xf[i] as Transform3D).origin
				if Vector2(o.x - p.x, o.z - p.z).length() < r:
					return true
	return false


func _physics_process(_dt: float) -> void:
	var mv: Variant = game.get("machine")
	if not is_instance_valid(mv):
		return
	var me := mv as Machine
	for i in sites.size():
		var s: Dictionary = sites[i]
		var d := me.global_position.distance_to(s.at)
		var up := not (s.nodes as Array).is_empty()
		if d < NEAR and not up:
			_raise(i)
			if not s.cleared and game.has_method("say"):
				game.call("say", "Korunan saha yakında: %s" % s.name)
		elif d > FAR and up:
			_lower(i)


## A site put up: its building, and its robots still alive.
func _raise(i: int) -> void:
	var s: Dictionary = sites[i]
	var at: Vector3 = s.at
	if terrain.has_method("clear_grass"):
		terrain.call("clear_grass", at, 16.0) # (a works yard: trodden bare)
		terrain.call("commit_digs")
	var b := Structures.make(s.building, Transform3D(Basis(Vector3.UP, float(s.yaw)), at), terrain)
	game.add_child(b)
	s.nodes.append(b)
	# the yard round it: containers, drums, barriers (where they were left: the same each time)
	var rng := RandomNumberGenerator.new()
	rng.seed = 977 + i
	for k in 7:
		var a := rng.randf() * TAU
		var o := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(9.0, 15.0)
		var clash := false
		for r: Array in s.robots:
			clash = clash or Vector2(o.x, o.z).distance_to(r[1]) < 3.5
		if clash:
			continue # (not on top of a robot's post)
		var q := at + o
		q.y = float(terrain.call("height_at", q.x, q.z))
		var kind: String = ["container", "drum", "drum", "barrier", "crate", "barrier", "drum"][k]
		var br := Breakable.make(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), q))
		game.add_child(br)
		s.nodes.append(br)
	var lamp := Structures.make("lamp", Transform3D(Basis(Vector3.UP, float(s.yaw)), at + Vector3(7.0, 0.0, -5.0)), terrain)
	lamp.position.y = float(terrain.call("height_at", lamp.position.x, lamp.position.z))
	game.add_child(lamp)
	s.nodes.append(lamp)
	for j in (s.robots as Array).size():
		if j in s.dead:
			continue
		var r: Array = s.robots[j]
		var o: Vector2 = r[1]
		var p := at + Vector3(o.x, 0.0, o.y)
		p.y = float(terrain.call("height_at", p.x, p.z))
		var rb := ROBOT.make(str(r[0]), Transform3D(Basis(Vector3.UP, atan2(o.x, o.y)), p), game, terrain)
		rb.set_meta("site", i)
		rb.set_meta("slot", j)
		rb.connect("died", _on_robot_died)
		game.add_child(rb)
		s.nodes.append(rb)


func _lower(i: int) -> void:
	for n: Variant in sites[i].nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	sites[i].nodes = []


## One down: it stays dead; now and then its wreck leaves a part; the last of them clears the site.
func _on_robot_died(r: Node) -> void:
	var i := int(r.get_meta("site", -1))
	if i < 0:
		return
	var s: Dictionary = sites[i]
	s.dead.append(int(r.get_meta("slot")))
	var at := (r as Node3D).global_position
	if Salvage.current and randf() < 0.6:
		var pool: Array = WRECK[str(r.get("kind"))]
		Salvage.current.drop(str(pool[randi() % pool.size()]), at)
	Inventory.add_scrap(2) # (what's left of it: scrap)
	if (s.dead as Array).size() >= (s.robots as Array).size() and not s.cleared:
		s.cleared = true
		if Salvage.current:
			for id: String in s.cache:
				Salvage.current.drop(id, (s.at as Vector3) + Vector3(randf_range(-2, 2), 0.0, randf_range(-2, 2)), randf_range(0.75, 1.0)) # (kept: in good order)
		Inventory.add_scrap(6)
		if game.has_method("say"):
			game.call("say", "%s TEMİZLENDİ  ·  zulası orada, al" % s.name)
	_save()


## How many sites there are and how many are cleared (the HUD, the tests).
func cleared_count() -> int:
	var n := 0
	for s in sites:
		if s.cleared:
			n += 1
	return n
