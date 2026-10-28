class_name Missions
extends Node
## GÖREVLER: an industrial site to bring down. Each mission lays a yard (its ground: gravel and
## concrete pads, its mud, snow or bog; its weather and hour), puts up what's to be destroyed (the
## targets, marked) and what's only in the way, and sometimes guards (Forge's machines, with
## crews) and the works' own robots turned on you (robot.gd: sentry guns, wardens with cutters). You build first (B), then start: the clock runs until every target's down (it's done,
## stars by the time it took) or your machine's gone or can't move (it's failed: try again).
##
## Progress (the best time and stars of each, and how far it's open) is kept in user://missions.cfg:
## a mission opens when the one before it's done.

signal finished(done: bool)

static var save_path := "user://missions.cfg" ## (tests point it elsewhere)
const COUNT_OUT := 8.0 ## s your machine can't move (no engine, nothing to run on) before it's failed
const LIST := [
	{"id": "iskele", "name": "ESKİ İSKELE", "brief": "Terk edilmiş şantiyede iki ahşap iskele kalmış. Yık ya da yak: ahşap tutuşur, ateş komşu tahtalara yayılır.",
		"weather": "clear", "hour": 10.0, "stars": [40.0, 90.0],
		"zones": [["mud", Rect2(-14, 6, 10, 10)]],
		"targets": [["scaffold", Vector2(-10, 24), 0.0], ["scaffold", Vector2(8, 30), 0.4]],
		"props": [["crate", Vector2(-4, 20)], ["crate", Vector2(-3, 21.5)], ["drum", Vector2(12, 22)], ["drum", Vector2(12.8, 22.4)]]},
	{"id": "su", "name": "SU KULELERİ", "brief": "Çamurlu avluda iki su kulesi. Ayaklarını kır: dört ayaktan ikisi giderse tank devrilir. Çamura dikkat, teker gömülür. Avluda iki bekçi robot dolaşıyor: kesici kollarıyla yaklaşırlar, üstlerinden geç.",
		"weather": "overcast", "hour": 15.0, "stars": [60.0, 130.0],
		"robots": [["warden", Vector2(-4, 34)], ["warden", Vector2(6, 38)]],
		"zones": [["mud", Rect2(-22, 10, 44, 26)], ["bog", Rect2(-4, 18, 8, 8)]],
		"targets": [["water_tower", Vector2(-12, 28), 0.0], ["water_tower", Vector2(13, 32), 0.3]],
		"props": [["container", Vector2(0, 42)], ["barrier", Vector2(-6, 14)], ["barrier", Vector2(6, 14)]]},
	{"id": "baca", "name": "FABRİKA BACASI", "brief": "Karlı fabrika avlusu: baca ve yanındaki depo. Bacayı dibinden kır, deponun iskeletini çökert. Karda ahşap zor tutuşur. Depo kapısında bir nöbetçi taret var.",
		"weather": "snow", "hour": 9.0, "stars": [90.0, 180.0],
		"robots": [["sentry", Vector2(4, 26)], ["warden", Vector2(-2, 40)]],
		"zones": [["snow", Rect2(-40, -10, 80, 60)], ["ice", Rect2(-8, 8, 16, 6)]],
		"targets": [["chimney", Vector2(-10, 34), 0.0], ["warehouse", Vector2(12, 34), 0.0]],
		"props": [["container", Vector2(-24, 22)], ["block", Vector2(2, 20)], ["block", Vector2(-2, 22)]]},
	{"id": "yakit", "name": "YAKIT SAHASI", "brief": "Üç yakıt tankı ve bir trafo. Delinen ya da tutuşan tank patlar ve çevresini yakar. İki bekçi araç ve iki nöbetçi taret sahayı koruyor; yağmurda taretlerin nişanı kayar.",
		"weather": "rain", "hour": 16.5, "stars": [80.0, 170.0],
		"robots": [["sentry", Vector2(-20, 36)], ["sentry", Vector2(16, 36)]],
		"zones": [["mud", Rect2(-6, 14, 12, 12)]],
		"targets": [["fuel_tank", Vector2(-14, 30), 0.0], ["fuel_tank", Vector2(-2, 34), 0.0], ["fuel_tank", Vector2(10, 30), 0.0],
			["transformer", Vector2(22, 40), 0.0]],
		"guards": [["gunner", 1, Vector2(-6, 44)], ["skirmisher", 1, Vector2(16, 48)]],
		"props": [["container", Vector2(-26, 40)], ["sandbags", Vector2(0, 22)], ["drum", Vector2(4, 24)], ["drum", Vector2(4.8, 24.3)]]},
	{"id": "santiye", "name": "ŞANTİYE", "brief": "Bataklığa kurulmuş şantiye: kule vinç ve silo. Vincin direğini kır, siloyu ayaklarından devir. Bekçiler sert. Bataklıkta robotlar ağır kalır: onları oraya çek.",
		"weather": "fog", "hour": 7.5, "stars": [110.0, 220.0],
		"robots": [["warden", Vector2(-10, 30)], ["warden", Vector2(12, 22)], ["sentry", Vector2(4, 42)]],
		"zones": [["mud", Rect2(-40, 0, 80, 50)], ["bog", Rect2(-18, 20, 14, 12)], ["bog", Rect2(8, 12, 10, 8)]],
		"targets": [["crane", Vector2(-4, 36), 0.6], ["silo", Vector2(18, 30), 0.0], ["scaffold", Vector2(-20, 18), 1.2]],
		"guards": [["rammer", 2, Vector2(-14, 48)], ["flipper", 2, Vector2(10, 46)]],
		"props": [["container", Vector2(26, 44)], ["crate", Vector2(-10, 14)], ["crate", Vector2(-9, 15.4)]]},
	{"id": "vardiya", "name": "SON VARDİYA", "brief": "Bütün fabrika: baca, iki su kulesi, iki yakıt tankı, depo. Gece, yağmurda; dört bekçi, nöbetçi taretler ve bekçi robotlar. Ne varsa kullan.",
		"robots": [["sentry", Vector2(-14, 38)], ["sentry", Vector2(12, 50)], ["sentry", Vector2(22, 32)],
			["warden", Vector2(0, 34)], ["warden", Vector2(-20, 50)]],
		"weather": "rain", "hour": 22.0, "stars": [200.0, 400.0],
		"zones": [["mud", Rect2(-10, 16, 20, 14)], ["bog", Rect2(24, 20, 10, 10)]],
		"targets": [["chimney", Vector2(-24, 44), 0.0], ["water_tower", Vector2(-8, 30), 0.0], ["water_tower", Vector2(26, 46), 0.0],
			["fuel_tank", Vector2(8, 40), 0.0], ["fuel_tank", Vector2(16, 26), 0.0], ["warehouse", Vector2(-2, 52), 0.0]],
		"guards": [["artillery", 3, Vector2(-16, 56)], ["gunner", 3, Vector2(14, 58)], ["flipper", 3, Vector2(30, 34)], ["brawler", 2, Vector2(-30, 30)]],
		"props": [["container", Vector2(-36, 52)], ["container", Vector2(36, 54)], ["sandbags", Vector2(-4, 22)], ["drum", Vector2(20, 34)]]},
]

var game: Node
var terrain: Node
var def: Dictionary
var state := "prep" ## prep, run, done, failed
var time := 0.0
var targets: Array[Structure] = []
var guards: Array[Machine] = []
var robots: Array[Node] = []
const ROBOT := preload("res://scripts/robot.gd")
var stars := 0
var best := -1.0
var _ui: MissionUi
var _down_t := 0.0


static func find(id: String) -> Dictionary:
	for d: Dictionary in LIST:
		if d.id == id:
			return d
	return LIST[0]


## [best time (or -1), stars] for a mission; and whether it's open.
static func record(id: String) -> Array:
	var cf := ConfigFile.new()
	cf.load(save_path)
	return [float(cf.get_value(id, "best", -1.0)), int(cf.get_value(id, "stars", 0))]


static func is_open(i: int) -> bool:
	return i == 0 or float(record(str(LIST[i - 1].id))[0]) >= 0.0


## The yard's ground for `id` (game sets up its terrain with these before anything's put on it).
static func ground(id: String, t: TestTerrain) -> void:
	var d := find(id)
	t.default_surface = Surface.preset("gravel") # (outside the yard)
	t.noise_from = 70.0
	t.grid_strength = 0.0
	t.add_zone(Rect2(-60, -14, 120, 84), Surface.preset("concrete")) # (the works yard)
	t.add_zone(Rect2(-8, -12, 16, 14), Surface.preset("asphalt")) # (the pad you start on)
	# a road from it into the site, and a concrete pad under each target (the mission's own mud and
	# snow lie over them where they reach)
	var mid := Vector2.ZERO
	for tg: Array in d.targets:
		mid += tg[1]
		var c: Vector2 = tg[1]
		t.add_zone(Rect2(roundf(c.x) - 6.0, roundf(c.y) - 6.0, 12.0, 12.0), Surface.preset("asphalt"))
	mid /= d.targets.size()
	t.add_zone(Rect2(-3, -2, 6, roundf(mid.y) + 2.0), Surface.preset("asphalt"))
	t.add_zone(Rect2(minf(0.0, roundf(mid.x)) - 3.0, roundf(mid.y) - 3.0, absf(roundf(mid.x)) + 6.0, 6.0), Surface.preset("asphalt"))
	for z: Array in d.zones:
		t.add_zone(z[1], Surface.preset(z[0]))


func _ready() -> void:
	name = "Missions"
	_ui = MissionUi.new()
	_ui.missions = self
	add_child(_ui)
	_lay_out()
	var r := record(str(def.id))
	best = float(r[0])
	_ui.show_prep()


func _lay_out() -> void:
	for t: Array in def.targets:
		var p: Vector2 = t[1]
		var at := Vector3(p.x, float(terrain.call("height_at", p.x, p.y)), p.y)
		var s := Structures.make(t[0], Transform3D(Basis(Vector3.UP, float(t[2])), at), terrain)
		game.add_child(s)
		targets.append(s)
		s.destroyed.connect(_on_target_down)
	# a lamp post by each target and at the pad (lit: the evening and night sites are dark)
	var lamps: Array[Vector2] = [Vector2(6.5, -3.0)]
	for t: Array in def.targets:
		lamps.append((t[1] as Vector2) + Vector2(6.5, -6.0))
	for p: Vector2 in lamps:
		var at := Vector3(p.x, float(terrain.call("height_at", p.x, p.y)), p.y)
		game.add_child(Structures.make("lamp", Transform3D(Basis(Vector3.UP, PI * 0.75), at), terrain))
	for pr: Array in def.get("props", []):
		var p: Vector2 = pr[1]
		var at := Vector3(p.x, float(terrain.call("height_at", p.x, p.y)), p.y)
		game.add_child(Breakable.make(pr[0], Transform3D(Basis(Vector3.UP, randf() * TAU), at)))
	# the yard's edge: barriers and containers in a ring, gaps between
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.id)
	for k in 28:
		var a := TAU * k / 28.0
		if rng.randf() < 0.35:
			continue
		var r := 64.0 + rng.randf_range(-2.0, 2.0)
		var at := Vector3(cos(a) * r, 0.0, sin(a) * r + 20.0)
		at.y = float(terrain.call("height_at", at.x, at.z))
		var kind := "container" if rng.randf() < 0.3 else "barrier"
		game.add_child(Breakable.make(kind, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), at)))
	for g: Array in def.get("guards", []):
		var made := Forge.make(hash(def.id) + guards.size() * 13, int(g[1]), str(g[0]))
		var p: Vector2 = g[2]
		var at := Vector3(p.x, float(terrain.call("height_at", p.x, p.y)) + 1.5, p.y)
		var e: Machine = game.call("_spawn", made.data, Transform3D(Basis(Vector3.UP, PI), at), 1, true)
		e.label = "BEKÇİ · %s" % made.name
		e.set_physics_process(false) # (held till you start)
		guards.append(e)
	for rb: Array in def.get("robots", []):
		var p: Vector2 = rb[1]
		var at := Vector3(p.x, float(terrain.call("height_at", p.x, p.y)), p.y)
		var r := ROBOT.make(str(rb[0]), Transform3D(Basis.IDENTITY, at), game, terrain) # (facing the pad)
		game.add_child(r)
		r.set_physics_process(false) # (held till you start)
		robots.append(r)


func start() -> void:
	if state != "prep":
		return
	var b := game.get("builder") as Builder
	if b.active:
		b.set_active(false)
	state = "run"
	time = 0.0
	for e in guards:
		if is_instance_valid(e):
			e.set_physics_process(true)
	for r in robots:
		r.set_physics_process(true)
	_ui.show_run()


func can_build() -> bool:
	return state == "prep"


func panel_up() -> bool:
	return _ui.panel_up()


func targets_down() -> int:
	var n := 0
	for s in targets:
		if not is_instance_valid(s) or s.down:
			n += 1
	return n


func _on_target_down(s: Structure) -> void:
	if state != "run" and state != "prep":
		return
	_ui.target_down(s)
	if targets_down() >= targets.size() and state == "run":
		_done()


func _physics_process(dt: float) -> void:
	_ui.tick(dt)
	if state != "run":
		return
	time += dt
	var me: Machine = game.get("machine")
	if not is_instance_valid(me) or not me.alive:
		return
	# (on its back it's only T: a site has a crane; with no engine or nothing to run on, it's over)
	_down_t = _down_t + dt if me.immobile() else 0.0
	if _down_t >= COUNT_OUT:
		_failed("ARACIN HAREKET EDEMİYOR")


func on_player_died() -> void:
	if state == "run":
		_failed("ARACIN PARÇALANDI")


func _done() -> void:
	state = "done"
	var st: Array = def.stars
	stars = 3 if time <= float(st[0]) else (2 if time <= float(st[1]) else 1)
	var cf := ConfigFile.new()
	cf.load(save_path)
	var was := float(cf.get_value(def.id, "best", -1.0))
	var record_time := was < 0.0 or time < was
	if record_time:
		cf.set_value(def.id, "best", time)
	cf.set_value(def.id, "stars", maxi(stars, int(cf.get_value(def.id, "stars", 0))))
	cf.save(save_path)
	best = time if record_time else was
	for e in guards:
		if is_instance_valid(e):
			e.set_physics_process(false)
	for r in robots:
		r.set_physics_process(false)
	_ui.show_done(record_time)
	finished.emit(true)


func _failed(why: String) -> void:
	if state != "run":
		return
	state = "failed"
	_ui.show_failed(why)
	finished.emit(false)


## The next mission's index (or -1 at the last).
func next_index() -> int:
	for i in LIST.size():
		if LIST[i].id == def.id:
			return i + 1 if i + 1 < LIST.size() else -1
	return -1


func restart() -> void:
	game.get_tree().reload_current_scene()


func go_to(i: int) -> void:
	Mode.mission = str(LIST[i].id)
	game.get_tree().reload_current_scene()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not k or not k.pressed or k.echo:
		return
	if (game.get("builder") as Builder).active:
		return
	if k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if state == "prep":
			start()
		elif state == "done" and next_index() >= 0:
			go_to(next_index())
		elif state == "failed":
			restart()
	elif k.keycode == KEY_R and state in ["run", "failed"]:
		restart()
