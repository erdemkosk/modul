class_name Expeditions
extends Node
## The valley's work: loads to carry from one of its places to another (Sefer). The places are the
## map's own (WarMap.places: the town, the hospital, the villages, the farms, the dam, the quarry, the
## pass tower...), each one's yard on the road nearest it (a lit pad, a crate or two, a lamp).
##
## Three jobs are offered at a time (the radio: J) from the places nearest you: what it is, how heavy
## (a medicine crate 150 kg, a generator 650, fuel drums 800, a pump 950, steel beams 1600), from where
## to where and how far, what it pays; some are urgent (the wounded, medicine: a time to be there by).
## Take one and its load waits on the pad it's to go from. Stop beside it (within LOAD_REACH, still)
## and it's lashed on top of your machine, if your machine can carry it (its wheels' rated load over
## its weight with the load: Machine.rated_kg); its weight is the machine's now (it sinks deeper,
## climbs slower, tips sooner). Every hard knock (Machine.struck) hurts what's carried, the fragile
## (the wounded) far more; roll over and it falls off where you are, hurt, to be picked up again; the
## machine carrying it gone, the same. Stop on the pad it's for and it's delivered: paid in parts
## (good ones: Inventory, CONDITION) and scrap, less for what's broken, half if late.
## The job, its load and where it is are kept (`path`).

signal changed ## (the job or the offers changed: the radio's page)

const LOAD_REACH := 7.0 ## m from the load
const DROP_REACH := 14.0 ## m from the pad it's for
const STILL := 1.2 ## m/s or slower counts as stopped
const HOLD := 1.5 ## s stopped to load or unload
const KNOCK := 5.0 ## m/s a knock changes speed by before what's carried feels it
const OFFERS := 3
const GOODS := {
	"medicine": {"name": "İlaç sandıkları", "kg": 150.0, "size": Vector3(1.2, 0.7, 0.9), "fragile": 1.5, "urgent": true, "pay": 1},
	"wounded": {"name": "Yaralılar", "kg": 260.0, "size": Vector3(1.6, 0.8, 1.1), "fragile": 3.0, "urgent": true, "pay": 2},
	"generator": {"name": "Jeneratör", "kg": 650.0, "size": Vector3(1.6, 1.1, 1.0), "fragile": 1.0, "urgent": false, "pay": 2},
	"fuel": {"name": "Yakıt varilleri", "kg": 800.0, "size": Vector3(1.4, 1.0, 1.4), "fragile": 0.6, "urgent": false, "pay": 2},
	"pump": {"name": "Su pompası", "kg": 950.0, "size": Vector3(1.8, 1.1, 1.2), "fragile": 0.8, "urgent": false, "pay": 3},
	"beams": {"name": "Çelik kirişler", "kg": 1600.0, "size": Vector3(1.0, 0.6, 3.2), "fragile": 0.3, "urgent": false, "pay": 4},
}
## What a job pays in, by how much it pays (better parts the more it's worth).
const PAY_PARTS := [["frame", "plate", "wheel_s", "light", "wedge"], ["plate", "wheel_l", "battery", "engine_s", "armor"],
	["wheel_l", "engine", "battery", "ammo", "minigun", "hinge"], ["engine", "track", "turret", "cannon", "piston", "barrel"],
	["engine_l", "track", "rockets", "turret", "rotor", "cannon"]]
const DEPOT_KINDS := ["depot", "town", "hospital", "village", "farm", "position", "station", "dam", "quarry"]

static var path := "user://valley_jobs.cfg" ## (tests point it elsewhere)

var game: Node
var terrain: Node
var depots: Array[Dictionary] = [] ## {id, name, at: Vector3 (its pad), nodes}
var offers: Array[Dictionary] = [] ## {goods, from, to, dist, pay, due}
var job: Dictionary = {} ## the one taken: as an offer, and {state: "waiting" | "carried" | "dropped", cond, left, at}
var carrier: Machine ## (the machine it's lashed on)
var done := 0 ## jobs delivered
var _crate: Node3D ## the load lying (waiting or dropped)
var _lashed: Node3D ## the load on the machine
var _beam: Node3D ## where to go
var _hold := 0.0
var _tipped := 0.0
var _told := ""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "Expeditions"
	_rng.randomize()
	_place_depots()
	_load()
	while offers.size() < OFFERS:
		var o := _offer()
		if o.is_empty():
			break
		offers.append(o)
	_show()


## Each place's yard: the nearest road to it (within its reach), or the place itself.
func _place_depots() -> void:
	for p: Dictionary in WarMap.places():
		if not str(p.kind) in DEPOT_KINDS:
			continue
		var r := WarMap.nearest_road(p.pos)
		var at2: Vector2 = r.at if float(r.dist) < float(p.radius) + 60.0 else p.pos
		var at := Vector3(at2.x, float(terrain.call("height_at", at2.x, at2.y)), at2.y)
		depots.append({"id": p.id, "name": p.name, "at": at, "nodes": []})


func depot(id: String) -> Dictionary:
	for d in depots:
		if d.id == id:
			return d
	return {}


## A new job from one of the places nearest you to another 300..1500 m off.
func _offer() -> Dictionary:
	var me := _me()
	var here := me.global_position if me else Vector3.ZERO
	var near := depots.duplicate()
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.at as Vector3).distance_to(here) < (b.at as Vector3).distance_to(here))
	near = near.slice(0, 5)
	for tries in 40:
		var from: Dictionary = near[_rng.randi() % near.size()]
		var to: Dictionary = depots[_rng.randi() % depots.size()]
		var dist := Vector2(from.at.x, from.at.z).distance_to(Vector2(to.at.x, to.at.z))
		if to.id == from.id or dist < 300.0 or dist > 1500.0:
			continue
		var same := false
		for o in offers:
			same = same or (o.from == from.id and o.to == to.id)
		if same:
			continue
		var gid: String = GOODS.keys()[_rng.randi() % GOODS.size()]
		var g: Dictionary = GOODS[gid]
		var pay := clampi(int(g.pay) + int(dist / 600.0), 0, PAY_PARTS.size() - 1)
		var o := {"goods": gid, "from": from.id, "to": to.id, "dist": dist, "pay": pay, "due": 0.0}
		if bool(g.urgent):
			o.due = roundf(dist / 7.0 + 150.0) # (s: a steady drive and some)
		return o
	return {}


## Take offer `i`: its load waits on its pad. False if one's already taken.
func accept(i: int) -> bool:
	if not job.is_empty() or i < 0 or i >= offers.size():
		return false
	job = offers[i].duplicate()
	offers.remove_at(i)
	job.state = "waiting"
	job.cond = 1.0
	job.left = float(job.due)
	var f := depot(job.from)
	job.at = f.at
	var o := _offer()
	if not o.is_empty():
		offers.append(o)
	_say("SEFER: %s  ·  %s → %s" % [GOODS[job.goods].name, f.name, depot(job.to).name])
	_save()
	_show()
	return true


## Give the job up (the load left where it is).
func abandon() -> void:
	if job.is_empty():
		return
	_say("Sefer bırakıldı: %s" % GOODS[job.goods].name)
	_unlash()
	job = {}
	_save()
	_show()


func _me() -> Machine:
	var mv: Variant = game.get("machine") if game else null
	return mv as Machine if is_instance_valid(mv) else null


func _physics_process(dt: float) -> void:
	_yards()
	if job.is_empty():
		return
	var me := _me()
	if job.due > 0.0 and job.left > -9999.0:
		var was := float(job.left)
		job.left = was - dt
		if was > 0.0 and float(job.left) <= 0.0:
			_say("Geç kaldın: %s yine de götürülebilir, ama yarı ücrete" % GOODS[job.goods].name)
	match str(job.state):
		"waiting", "dropped":
			if _crate:
				job.at = _crate.global_position
			if me == null or not me.alive or me.building:
				_hold = 0.0
				return
			var d := me.global_position.distance_to(job.at)
			if d < LOAD_REACH and absf(me.speed) < STILL:
				_hold += dt
				if _hold >= HOLD:
					_hold = 0.0
					_lash(me)
			else:
				_hold = 0.0
				if d > LOAD_REACH + 4.0:
					_told = ""
		"carried":
			if not is_instance_valid(carrier) or not carrier.alive:
				_fall(carrier.global_position if is_instance_valid(carrier) else Vector3(job.at), 0.3)
				return
			job.at = carrier.global_position
			# rolled over (or on its side): it comes off
			_tipped = _tipped + dt if carrier.global_basis.y.y < 0.35 else 0.0
			if _tipped > 0.6:
				_fall(carrier.global_position + Vector3.UP * 1.5, 0.15)
				_say("Yük devrildi! %s yerde: yanına dur, yeniden yüklensin" % GOODS[job.goods].name)
				return
			var to := depot(job.to)
			if carrier == me and me.global_position.distance_to(to.at) < DROP_REACH and absf(me.speed) < STILL:
				_hold += dt
				if _hold >= HOLD:
					_hold = 0.0
					_deliver()
			else:
				_hold = 0.0


## Lashed on `m` if it can carry it.
func _lash(m: Machine) -> void:
	var g: Dictionary = GOODS[job.goods]
	var kg := float(g.kg)
	if m.total_mass + kg > m.rated_kg * 1.1:
		var why := "Bu yükü taşıyamaz: tekerleri %d kg taşır, yükle %d kg olur" % [roundi(m.rated_kg), roundi(m.total_mass + kg)]
		if _told != why:
			_told = why
			_say(why)
		return
	if is_instance_valid(_crate):
		_crate.queue_free()
	_crate = null
	carrier = m
	var size: Vector3 = g.size
	m.cargo_kg = kg
	m.cargo_at = Vector3(m.com.x, m.top_y + size.y * 0.5, m.com.z)
	m.rebuild()
	_lashed = _crate_node(size, job.goods)
	_lashed.position = m.cargo_at
	m.add_child(_lashed)
	if not m.struck.is_connected(_on_struck):
		m.struck.connect(_on_struck)
	job.state = "carried"
	_tipped = 0.0
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/heavy_01.wav", m.global_position, -2.0, 0.8)
	_say("Yüklendi: %s (%d kg)  ·  %s'a götür, %d m" % [g.name, roundi(kg), depot(job.to).name,
		roundi(m.global_position.distance_to(depot(job.to).at))])
	_save()
	_show()


## Off the machine (if it's on one).
func _unlash() -> void:
	if is_instance_valid(carrier):
		carrier.cargo_kg = 0.0
		carrier.rebuild()
		if carrier.struck.is_connected(_on_struck):
			carrier.struck.disconnect(_on_struck)
	carrier = null
	if is_instance_valid(_lashed):
		_lashed.queue_free()
	_lashed = null
	if is_instance_valid(_crate):
		_crate.queue_free()
	_crate = null


## It comes off at `at`, `hurt` more broken.
func _fall(at: Vector3, hurt: float) -> void:
	_unlash()
	job.cond = maxf(float(job.cond) - hurt, 0.0)
	if float(job.cond) <= 0.0:
		_lost()
		return
	job.state = "dropped"
	job.at = at
	_lay(at)
	_save()
	_show()


func _on_struck(_at: Vector3, dv: float, _other: Object) -> void:
	if job.is_empty() or str(job.state) != "carried" or dv < KNOCK:
		return
	var g: Dictionary = GOODS[job.goods]
	var was := float(job.cond)
	job.cond = maxf(was - (dv - KNOCK) * 0.05 * float(g.fragile), 0.0)
	if float(job.cond) <= 0.0:
		_unlash()
		_lost()
		return
	if was - float(job.cond) > 0.04:
		_say("▲ Yük sarsıldı: %s %%%d" % [g.name, roundi(float(job.cond) * 100.0)])


func _lost() -> void:
	_say("SEFER BAŞARISIZ: %s kullanılmaz hale geldi" % GOODS[job.goods].name)
	job = {}
	_save()
	_show()


## Delivered: paid in parts and scrap.
func _deliver() -> void:
	var g: Dictionary = GOODS[job.goods]
	var c := float(job.cond)
	var late := float(job.due) > 0.0 and float(job.left) <= 0.0
	var k := c * (0.5 if late else 1.0)
	var pool: Array = PAY_PARTS[int(job.pay)]
	var n := maxi(roundi((2 + int(job.pay)) * k), 1)
	var got := []
	for i in n:
		var id: String = pool[_rng.randi() % pool.size()]
		Inventory.add(id, 1, _rng.randf_range(0.85, 1.0))
		got.append(Parts.def(id).name)
	var scrap := roundi((4.0 + float(job.dist) / 100.0) * k)
	Inventory.add_scrap(scrap)
	_unlash()
	done += 1
	_say("TESLİM EDİLDİ: %s%s  ·  +%s, +%d hurda" % [g.name, " (geç)" if late else "", ", ".join(got), scrap])
	if Combat.current and is_instance_valid(_me()):
		Combat.current.sound("res://assets/audio/build/bolt_on_01.wav", _me().global_position, 2.0, 0.9)
	job = {}
	_save()
	_show()


## The load lying at `at` (a crate the size of it).
func _lay(at: Vector3) -> void:
	if is_instance_valid(_crate):
		_crate.queue_free()
	var size: Vector3 = GOODS[job.goods].size
	_crate = _crate_node(size, job.goods)
	_crate.position = Vector3(at.x, float(terrain.call("height_at", at.x, at.z)) + size.y * 0.5, at.z)
	game.add_child(_crate)


## What it looks like: a lashed crate (strapped), the drums, the beams, the stretcher.
func _crate_node(size: Vector3, gid: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Load"
	if DisplayServer.get_name() == "headless":
		return n
	var col: Color = {"medicine": Color(0.75, 0.74, 0.7), "wounded": Color(0.35, 0.4, 0.3), "generator": Color(0.55, 0.42, 0.08),
		"fuel": Color(0.42, 0.1, 0.06), "pump": Color(0.15, 0.3, 0.45), "beams": Color(0.3, 0.3, 0.32)}.get(gid, Color(0.4, 0.3, 0.2))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.75
	mat.metallic = 0.3 if gid in ["generator", "fuel", "pump", "beams"] else 0.0
	if gid == "fuel":
		for x in 2:
			for z in 2:
				var c := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = size.x * 0.22
				cm.bottom_radius = size.x * 0.22
				cm.height = size.y
				cm.material = mat
				c.mesh = cm
				c.position = Vector3((x - 0.5) * size.x * 0.5, 0.0, (z - 0.5) * size.z * 0.5)
				n.add_child(c)
	elif gid == "beams":
		for k in 3:
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(size.x * 0.3, size.y * 0.3, size.z)
			bm.material = mat
			b.mesh = bm
			b.position = Vector3((k - 1) * size.x * 0.33, -size.y * 0.3 + (k % 2) * size.y * 0.3, 0.0)
			n.add_child(b)
	else:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		b.mesh = bm
		n.add_child(b)
	# the straps
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color(0.85, 0.45, 0.08)
	for k in 2:
		var s := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(size.x + 0.04, size.y + 0.04, 0.06)
		sm.material = strap
		s.mesh = sm
		s.position.z = (k - 0.5) * size.z * 0.5
		n.add_child(s)
	return n


## The yards of the places near you put up (a pad, a lamp, some crates), those far off taken down;
## the light over where to go now.
func _yards() -> void:
	var me := _me()
	if me == null:
		return
	for d in depots:
		var near := me.global_position.distance_to(d.at) < 320.0
		var up := not (d.nodes as Array).is_empty()
		if near and not up:
			_raise(d)
		elif not near and up:
			for n: Variant in d.nodes:
				if is_instance_valid(n):
					(n as Node).queue_free()
			d.nodes = []
	if job.is_empty():
		_mark(Vector3.INF)
	elif str(job.state) == "carried":
		_mark(depot(job.to).at)
	else:
		_mark(job.at)
		if str(job.state) == "waiting" and not is_instance_valid(_crate) and me.global_position.distance_to(job.at) < 320.0:
			_lay(job.at)


func _raise(d: Dictionary) -> void:
	var at: Vector3 = d.at
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(d.id)
	for k in 3:
		var a := rng.randf() * TAU
		var q := at + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(8.0, 11.0)
		q.y = float(terrain.call("height_at", q.x, q.z))
		var br := Breakable.make(["crate", "drum", "crate"][k], Transform3D(Basis(Vector3.UP, rng.randf() * TAU), q))
		game.add_child(br)
		d.nodes.append(br)
	if DisplayServer.get_name() == "headless":
		return
	var pad := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = DROP_REACH - 0.6
	tm.outer_radius = DROP_REACH
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.75, 0.2, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = m
	pad.mesh = tm
	pad.scale.y = 0.05
	pad.position = at + Vector3.UP * 0.15
	game.add_child(pad)
	d.nodes.append(pad)
	var lamp := Structures.make("lamp", Transform3D(Basis.IDENTITY, at + Vector3(DROP_REACH + 1.5, 0.0, 0.0)), terrain)
	lamp.position.y = float(terrain.call("height_at", lamp.position.x, lamp.position.z))
	game.add_child(lamp)
	d.nodes.append(lamp)


## A tall light where to go (INF: none).
func _mark(at: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if at == Vector3.INF:
		if _beam:
			_beam.visible = false
		return
	if _beam == null:
		_beam = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 1.4
		cm.height = 120.0
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(0.3, 0.75, 1.0, 0.16)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		cm.material = m
		(_beam as MeshInstance3D).mesh = cm
		(_beam as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		game.add_child(_beam)
	_beam.visible = true
	_beam.global_position = at + Vector3.UP * 60.0


## The line for the HUD: what's carried, where to, how far, how it is, how long left.
func status() -> String:
	if job.is_empty():
		return "Sefer yok  ·  J: telsiz, iş al"
	var g: Dictionary = GOODS[job.goods]
	var me := _me()
	var here := me.global_position if me else Vector3.ZERO
	var line := ""
	match str(job.state):
		"waiting":
			line = "%s %s'da seni bekliyor · %d m" % [g.name, depot(job.from).name, roundi(here.distance_to(job.at))]
		"dropped":
			line = "%s yerde · %d m" % [g.name, roundi(here.distance_to(job.at))]
		"carried":
			line = "%s → %s · %d m" % [g.name, depot(job.to).name, roundi(here.distance_to(depot(job.to).at))]
	line += "  ·  yük %%%d" % roundi(float(job.cond) * 100.0)
	if float(job.due) > 0.0:
		var left := float(job.left)
		line += "  ·  " + ("GEÇ" if left <= 0.0 else "%d:%02d" % [int(left) / 60, int(left) % 60])
	return line


## An offer, in words (the radio).
func describe(o: Dictionary) -> String:
	var g: Dictionary = GOODS[o.goods]
	var s := "%s · %d kg\n%s → %s · %.1f km" % [g.name, roundi(float(g.kg)), depot(o.from).name, depot(o.to).name, float(o.dist) / 1000.0]
	if float(o.due) > 0.0:
		s += " · ACİL %d dk" % ceili(float(o.due) / 60.0)
	s += "\nÖdül: %d parça (%s…), %d hurda" % [2 + int(o.pay), Parts.def(PAY_PARTS[int(o.pay)][0]).name, roundi(4.0 + float(o.dist) / 100.0)]
	return s


func _say(t: String) -> void:
	if game and game.has_method("say"):
		game.call("say", t)


func _show() -> void:
	changed.emit()


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("jobs", "offers", offers)
	cf.set_value("jobs", "done", done)
	cf.set_value("jobs", "job", job)
	cf.save(path)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	done = int(cf.get_value("jobs", "done", 0))
	for o: Dictionary in cf.get_value("jobs", "offers", []):
		if GOODS.has(str(o.get("goods", ""))) and not depot(str(o.get("from", ""))).is_empty() and not depot(str(o.get("to", ""))).is_empty():
			offers.append(o)
	var j: Dictionary = cf.get_value("jobs", "job", {})
	if not j.is_empty() and GOODS.has(str(j.get("goods", ""))) and not depot(str(j.get("to", ""))).is_empty():
		job = j
		if str(job.state) == "carried":
			_relash.call_deferred() # (back on the machine you start in)


func _relash() -> void:
	var me := _me()
	if me:
		job.state = "waiting"
		_lash(me)
		if str(job.state) != "carried": # (it can't now: it's beside you)
			job.state = "dropped"
			job.at = me.global_position + me.global_basis.x * 5.0
			_lay(job.at)
