class_name Expeditions
extends Node
## The valley's work: loads to carry from one of its places to another (Sefer). The places are the
## map's own (WarMap.places: the town, the hospital, the villages, the farms, the dam, the quarry, the
## pass tower...), each one's yard on the road nearest it (a lit pad, a crate or two, a lamp).
##
## Three jobs are offered at a time (the radio: J) from the places nearest you: what it is, how heavy
## (a medicine crate 150 kg, a generator 650, fuel drums 800, a pump 950, steel beams 1600), from where
## to where and how far, what it pays; some are urgent (the wounded, medicine: a time to be there by).
## Take one and its load waits on the pad it's to go from: a real crate of its weight (a RigidBody,
## group "loads"), and getting it home is up to you and what you've built. A crane (MachineHoist: Y)
## lifts it and sets it down on your bed, where it rides as weight like any other (it slides if you
## brake hard, falls off if you roll); a winch (N) drags it along behind, or a light one's pushed. It
## feels every knock (a drop, a fall, a crash: a sudden change in its speed past KNOCK), the fragile
## (the wounded) far more, and broken through it's lost. Set it down within DROP_REACH of the pad
## it's for, let go of it and still, and it's delivered: paid in parts (good ones) and scrap, less for
## what's broken, half if late.
## The job, its load and where it is are kept (`path`).

signal changed ## (the job or the offers changed: the radio's page)

const DROP_REACH := 14.0 ## m from the pad it's for
const STILL := 0.5 ## m/s or slower the load counts as set down
const HOLD := 1.5 ## s set down on the pad to be delivered
const KNOCK := 4.0 ## m/s the load's speed changes by in a step (a drop, a crash) before it feels it
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
var job: Dictionary = {} ## the one taken: as an offer, and {state: "waiting" | "moved", cond, left, at, from_at}
var done := 0 ## jobs delivered
var crate: RigidBody3D ## the load (while it's near enough to be out)
var _beam: Node3D ## where to go
var _hold := 0.0
var _v := Vector3.ZERO ## (the load's speed last step)
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
	job.from_at = f.at
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
	_drop_crate()
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
	if float(job.due) > 0.0:
		var was := float(job.left)
		job.left = was - dt
		if was > 0.0 and float(job.left) <= 0.0:
			_say("Geç kaldın: %s yine de götürülebilir, ama yarı ücrete" % GOODS[job.goods].name)
	if not is_instance_valid(crate):
		return
	job.at = crate.global_position
	# what it feels: a sudden change in its speed (dropped, fallen, struck)
	var v := crate.linear_velocity
	var dv := (v - _v).length()
	_v = v
	if dv > KNOCK:
		var g: Dictionary = GOODS[job.goods]
		var was := float(job.cond)
		job.cond = maxf(was - (dv - KNOCK) * 0.06 * float(g.fragile), 0.0)
		if float(job.cond) <= 0.0:
			_lost()
			return
		if was - float(job.cond) > 0.03:
			_say("▲ Yük sarsıldı: %s %%%d" % [g.name, roundi(float(job.cond) * 100.0)])
	var from_at: Vector3 = job.from_at
	if str(job.state) == "waiting" and Vector2(crate.global_position.x - from_at.x, crate.global_position.z - from_at.z).length() > 4.0:
		job.state = "moved"
		_save()
	# set down on its pad, let go of, still: delivered
	var to: Vector3 = depot(job.to).at
	var flat := Vector2(crate.global_position.x - to.x, crate.global_position.z - to.z).length()
	if flat < DROP_REACH and v.length() < STILL and not hooked(crate):
		_hold += dt
		if _hold >= HOLD:
			_hold = 0.0
			_deliver()
	else:
		_hold = 0.0


## Something's rope is on `b`.
static func hooked(b: Node) -> bool:
	for n: Node in b.get_tree().get_nodes_in_group("machines"):
		for h: MachineHoist in (n as Machine).hoists:
			if h.hooked() == b:
				return true
	return false


func _lost() -> void:
	_say("SEFER BAŞARISIZ: %s kullanılmaz hale geldi" % GOODS[job.goods].name)
	_drop_crate()
	job = {}
	_save()
	_show()


func _drop_crate() -> void:
	if is_instance_valid(crate):
		crate.queue_free()
	crate = null


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
	if Combat.current and is_instance_valid(crate):
		Combat.current.sound("res://assets/audio/build/bolt_on_01.wav", crate.global_position, 2.0, 0.9)
	_drop_crate()
	done += 1
	_say("TESLİM EDİLDİ: %s%s  ·  +%s, +%d hurda" % [g.name, " (geç)" if late else "", ", ".join(got), scrap])
	job = {}
	_save()
	_show()


## The load out at `at`: a crate of its weight on the ground.
func _lay(at: Vector3) -> void:
	_drop_crate()
	var g: Dictionary = GOODS[job.goods]
	var size: Vector3 = g.size
	var b := RigidBody3D.new()
	b.name = "Load"
	b.mass = float(g.kg)
	b.collision_layer = 1 | 4 # (ground to wheels: it can ride on a bed and be driven over)
	b.collision_mask = 1 | 2
	b.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	b.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	b.add_child(_crate_node(size, job.goods))
	b.set_meta("size", size)
	b.set_meta("title", str(g.name))
	b.add_to_group("loads")
	b.position = Vector3(at.x, float(terrain.call("height_at", at.x, at.z)) + size.y * 0.5 + 0.05, at.z)
	game.add_child(b)
	crate = b
	_v = Vector3.ZERO


## What it looks like: a strapped crate, the drums, the beams, the stretcher.
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
		return
	if not is_instance_valid(crate) and me.global_position.distance_to(job.at) < 320.0:
		_lay(job.at)
	# the light over the load till you're with it, then over where it's to go
	var with_it := me.global_position.distance_to(Vector3(job.at)) < 20.0
	_mark(depot(job.to).at if with_it else Vector3(job.at))


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
	var to: Dictionary = depot(job.to)
	var d_load := here.distance_to(job.at)
	if d_load > 20.0:
		line = "%s %s · %d m" % [g.name, "yerde" if str(job.state) == "moved" else str(depot(job.from).name) + "'da bekliyor", roundi(d_load)]
	else:
		line = "%s → %s · %d m" % [g.name, to.name, roundi(Vector3(job.at).distance_to(to.at))]
	line += "  ·  yük %%%d" % roundi(float(job.cond) * 100.0)
	if float(job.due) > 0.0:
		var left := float(job.left)
		line += "  ·  " + ("GEÇ" if left <= 0.0 else "%d:%02d" % [int(left) / 60, int(left) % 60])
	return line


## An offer, in words (the radio).
func describe(o: Dictionary) -> String:
	var g: Dictionary = GOODS[o.goods]
	var s := "%s · %d kg%s\n%s → %s · %.1f km" % [g.name, roundi(float(g.kg)), " (vinç kaldırmaz: çeki vinciyle sürükle)" if float(g.kg) > 1500.0 else "",
		depot(o.from).name, depot(o.to).name, float(o.dist) / 1000.0]
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
		if not job.has("from_at"):
			job.from_at = depot(job.from).at
		if str(job.get("state", "")) != "waiting":
			job.state = "moved"


func _exit_tree() -> void:
	_save() # (where the load got to)
