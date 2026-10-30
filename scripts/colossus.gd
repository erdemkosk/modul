class_name Colossus
extends Node
## The valley's giants: works machines gone wild, each the size of a house (Designs.giant), roaming
## slowly round its own places (ROUTES) whether you're there or not. KAZICI, a quarry's excavator on
## six tracks with a spiked arm on a turntable it swings at whatever comes close, a cannon and a
## minigun on turrets; KARA PALET, longer and lower, rockets on its back and two miniguns.
##
## They aren't shot down: their cab lies deep in armour. They're taken apart: their guns shot off,
## their tracks thrown, their engines holed, their skirts torn away (each part that comes off whole is
## salvage, as anything of theirs is), until there's a way in to the cab. One brought down leaves its
## heart: the rare parts (RARE: V8s, tracks, turrets, the arm's turntable, its gun) in good order and
## a lot of scrap; it's gone for RETURN days, then another comes.
##
## Each is out there while you're within NEAR (taken away past FAR, as hurt as it was, kept with
## where it got to); what's left of it and when it fell are kept (`path`).

const ROUTES := {"KAZICI": {"kind": "digger", "route": ["quarry", "village_e", "hospital", "town"]},
	"KARA PALET": {"kind": "crawler", "route": ["dam", "tower", "village_n", "farm_w"]}}
const NEAR := 480.0
const FAR := 620.0
const SEES := 110.0 ## m it turns on you from
const FIRES := 95.0
const ARM := 16.0 ## m: it swings its arm
const SPEED := 0.45 ## its throttle roaming
const RETURN := 3 ## days
const RARE := {"digger": ["engine_l", "engine_l", "track", "rotor", "turret", "cannon"],
	"crawler": ["engine_l", "track", "track", "turret", "rockets", "battery"]}

static var path := "user://valley_giants.cfg" ## (tests point it elsewhere)

var game: Node
var terrain: Node
var giants: Array[Dictionary] = [] ## {name, kind, route: [Vector3], leg, at: Vector3, yaw, data (worn), fell (day or 0), m}


func _ready() -> void:
	name = "Colossus"
	var cf := ConfigFile.new()
	cf.load(path)
	for n: String in ROUTES:
		var r: Dictionary = ROUTES[n]
		var pts: Array[Vector3] = []
		for id: String in r.route:
			for p: Dictionary in WarMap.places():
				if p.id == id:
					var road := WarMap.nearest_road(p.pos) # (on the road by the place: they keep to the roads, as works machines would)
					var q: Vector2 = road.at if float(road.dist) < float(p.radius) + 120.0 else p.pos
					pts.append(Vector3(q.x, 0.0, q.y))
		if pts.size() < 2:
			continue
		var g := {"name": n, "kind": r.kind, "route": pts, "leg": int(cf.get_value(n, "leg", 1)),
			"at": cf.get_value(n, "at", pts[0]), "yaw": float(cf.get_value(n, "yaw", 0.0)), "data": cf.get_value(n, "data", []),
			"fell": int(cf.get_value(n, "fell", 0)), "m": null, "stuck": 0.0, "back": 0.0, "arm": false}
		giants.append(g)


func _exit_tree() -> void:
	for g in giants:
		_keep(g)
	_save()


func _save() -> void:
	var cf := ConfigFile.new()
	for g in giants:
		cf.set_value(g.name, "leg", g.leg)
		cf.set_value(g.name, "at", g.at)
		cf.set_value(g.name, "yaw", g.yaw)
		cf.set_value(g.name, "data", g.data)
		cf.set_value(g.name, "fell", g.fell)
	cf.save(path)


## Where it is and what's left of it, from the machine (if it's out).
func _keep(g: Dictionary) -> void:
	var m: Machine = g.m if is_instance_valid(g.m) else null
	if m and m.alive and m.is_inside_tree():
		g.at = m.global_position
		g.yaw = m.global_basis.get_euler().y
		g.data = m.to_data(true)


func _physics_process(dt: float) -> void:
	var mv: Variant = game.get("machine")
	if not is_instance_valid(mv):
		return
	var me := mv as Machine
	for g in giants:
		if int(g.fell) > 0:
			if ValleyLife.day - int(g.fell) < RETURN:
				continue
			g.fell = 0 # (another has come)
			g.data = []
			_save()
		var m: Machine = g.m if is_instance_valid(g.m) else null
		var d := me.global_position.distance_to(m.global_position if m else Vector3(g.at))
		if m == null and d < NEAR:
			_raise(g)
		elif m and d > FAR:
			_keep(g)
			m.queue_free()
			g.m = null
			_save()
		elif m:
			_drive(g, m, me, dt)
		else:
			_roam_unseen(g, dt)


## Out there.
func _raise(g: Dictionary) -> void:
	var at: Vector3 = g.at
	at.y = float(terrain.call("height_at", at.x, at.z)) + 2.6
	var data: Array = g.data if not (g.data as Array).is_empty() else Designs.giant(str(g.kind))
	var m: Machine = game.call("_spawn", data, Transform3D(Basis(Vector3.UP, float(g.yaw)), at), 1)
	m.label = str(g.name)
	m.ammo_k = 3.0
	m.keyed = true
	m.add_to_group("giants")
	m.died.connect(_fell.bind(g))
	g.m = m
	if game.has_method("say"):
		game.call("say", "DEV MAKİNE yakında: %s" % g.name)


## Unseen, it still goes on its way (slowly: a few metres a second).
func _roam_unseen(g: Dictionary, dt: float) -> void:
	var to: Vector3 = g.route[int(g.leg) % (g.route as Array).size()]
	var at: Vector3 = g.at
	var flat := Vector3(to.x - at.x, 0.0, to.z - at.z)
	if flat.length() < 20.0:
		g.leg = (int(g.leg) + 1) % (g.route as Array).size()
		return
	g.at = at + flat.normalized() * 2.5 * dt
	g.yaw = atan2(-flat.x, -flat.z)


## Its crew: on round its route; you near, it turns on you, its guns on you, its arm swung.
func _drive(g: Dictionary, m: Machine, me: Machine, dt: float) -> void:
	var p := m.global_position
	var to: Vector3 = g.route[int(g.leg) % (g.route as Array).size()]
	var d := p.distance_to(me.global_position)
	var hunting := d < SEES and me.alive
	if hunting:
		to = me.global_position
	elif Vector2(to.x - p.x, to.z - p.z).length() < 20.0:
		g.leg = (int(g.leg) + 1) % (g.route as Array).size()
	var fwd := -m.global_basis.z
	var want := Vector3(to.x - p.x, 0.0, to.z - p.z).normalized()
	var err := atan2(fwd.cross(want).y, fwd.dot(want))
	if float(g.back) > 0.0: # (stuck: backing off, turned)
		g.back = float(g.back) - dt
		m.throttle = -0.6
		m.steer = 0.8
		m.brake = 0.0
	else:
		m.steer = clampf(-err * 1.6, -1.0, 1.0)
		# far off its way it turns on the spot (its tracks one forward, one back), then goes
		m.throttle = (0.0 if absf(err) > 0.7 else SPEED) * (0.0 if hunting and d < ARM * 0.6 else 1.0)
		m.brake = 0.0
		g.stuck = float(g.stuck) + dt if absf(m.speed) < 0.3 and m.throttle > 0.1 else 0.0
		if float(g.stuck) > 5.0:
			g.stuck = 0.0
			g.back = 3.0
	m.aim_point = me.global_position + Vector3.UP * 0.8
	m.firing = hunting and d < FIRES and _clear(m, me)
	# the arm: swung while you're close, stopped when you're not
	var swing := hunting and d < ARM
	if swing != bool(g.arm):
		g.arm = swing
		m.joint_key(KEY_E)


func _clear(m: Machine, me: Machine) -> bool:
	var from := m.global_transform * Vector3(0.0, m.top_y, 0.0) # (from its top: its guns ride high)
	var q := PhysicsRayQueryParameters3D.create(from, me.global_position + Vector3.UP, 1)
	q.exclude = [m.get_rid(), me.get_rid()]
	return m.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Brought down: its heart left out to take, and scrap; gone for RETURN days.
func _fell(g: Dictionary) -> void:
	var m: Machine = g.m
	var at := m.global_position if is_instance_valid(m) else Vector3(g.at)
	g.fell = ValleyLife.day
	g.data = []
	g.m = null
	if Salvage.current:
		for id: String in RARE[str(g.kind)]:
			Salvage.current.drop(id, at + Vector3(randf_range(-4, 4), 1.0, randf_range(-4, 4)), randf_range(0.8, 1.0))
	Inventory.add_scrap(40)
	var plan := Inventory.next_plan()
	if Salvage.current and plan != "":
		Salvage.current.drop_plan(plan, at + Vector3(0, 1.0, 0))
	if game.has_method("say"):
		game.call("say", "%s DEVRİLDİ  ·  kalbi orada: nadir parçalar, +40 hurda" % g.name)
	_save()


## The nearest giant out and about, in words (the HUD); "" if none's near.
func status() -> String:
	var mv: Variant = game.get("machine")
	if not is_instance_valid(mv):
		return ""
	var me := mv as Machine
	var best := ""
	var bd := INF
	for g in giants:
		if int(g.fell) > 0:
			continue
		var m: Machine = g.m if is_instance_valid(g.m) else null
		var at := m.global_position if m else Vector3(g.at)
		var d := me.global_position.distance_to(at)
		if d < 700.0 and d < bd:
			bd = d
			var to := at - me.global_position
			var hurt := ""
			if m:
				hurt = "  ·  %%%d sağlam" % roundi(m.health() * 100.0)
			best = "DEV MAKİNE %s  ·  %d m %s%s" % [g.name, roundi(d), Workshop.compass(atan2(to.x, -to.z)), hurt]
	return best
