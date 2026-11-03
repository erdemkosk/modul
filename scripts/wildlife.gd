class_name Wildlife
extends Node3D
## The taiga's own: a few deer at the edge of the woods, grazing, heads coming up at a sound and away
## at a bound when someone comes near; hares about the clearings, sitting up, hopping off (white in
## the winter). Kept out from the town (they don't come in among the houses), each wandering its own
## ground. Built of a few shapes each, the legs swung as they go.

const DEER := 4
const HARES := 7
const SHY := 18.0 ## m: anyone of the town nearer than this and they're off
const KEEP_OFF := 55.0 ## m from the store they won't come inside

var village: Node
var nav: Nav
var _beasts: Array[Dictionary] = [] ## {node, legs, kind, home, to, speed, wait, flee, t, coat}
var _home := Vector3.ZERO
var _placed := false


func _ready() -> void:
	name = "Wildlife"


func _process(dt: float) -> void:
	if not _placed:
		var stores: Array = village.stores()
		if stores.is_empty():
			return
		_home = (stores[0] as Node3D).global_position
		_placed = true
		for k in DEER:
			_spawn("deer")
		for k in HARES:
			_spawn("hare")
	var winter: bool = village.seasons != null and village.seasons.winter()
	for b: Dictionary in _beasts:
		_step(b, dt, winter)


func _open_spot(near: Vector3, r0: float, r1: float) -> Vector3:
	for k in 30:
		var a := randf() * TAU
		var p := near + Vector3(cos(a), 0, sin(a)) * randf_range(r0, r1)
		if p.distance_to(_home) > KEEP_OFF and nav.is_open(p):
			p.y = nav.height(p.x, p.z)
			return p
	return Vector3.INF


func _spawn(kind: String) -> void:
	var home := _open_spot(_home, 90.0, 230.0)
	if home == Vector3.INF:
		return
	var node := Node3D.new()
	add_child(node)
	node.global_position = home
	var legs: Array[Node3D] = []
	var coat := StandardMaterial3D.new()
	coat.roughness = 1.0
	if kind == "deer":
		coat.albedo_color = Color(0.45, 0.3, 0.18)
		var pale := StandardMaterial3D.new()
		pale.albedo_color = Color(0.8, 0.72, 0.6)
		_box(node, Vector3(0.42, 0.45, 1.15), Vector3(0, 0.95, 0), coat)
		_box(node, Vector3(0.3, 0.2, 0.12), Vector3(0, 1.0, 0.6), pale) # (the white rump)
		var neck := Node3D.new()
		neck.name = "neck"
		node.add_child(neck)
		neck.position = Vector3(0, 1.1, -0.5)
		_box(neck, Vector3(0.18, 0.55, 0.2), Vector3(0, 0.22, -0.08), coat).rotation.x = -0.4
		_box(neck, Vector3(0.18, 0.18, 0.36), Vector3(0, 0.48, -0.25), coat)
		for s in [-1.0, 1.0]:
			_box(neck, Vector3(0.05, 0.14, 0.04), Vector3(s * 0.1, 0.62, -0.16), coat).rotation.z = s * 0.5
		if randf() < 0.5: # (a stag: antlers)
			var horn := StandardMaterial3D.new()
			horn.albedo_color = Color(0.62, 0.55, 0.42)
			for s in [-1.0, 1.0]:
				_box(neck, Vector3(0.03, 0.4, 0.03), Vector3(s * 0.12, 0.8, -0.12), horn).rotation.z = s * 0.4
				_box(neck, Vector3(0.03, 0.2, 0.03), Vector3(s * 0.2, 0.88, -0.2), horn).rotation.x = -0.6
		for p in [Vector3(-0.15, 0.75, -0.45), Vector3(0.15, 0.75, -0.45), Vector3(-0.15, 0.75, 0.45), Vector3(0.15, 0.75, 0.45)]:
			var leg := Node3D.new()
			node.add_child(leg)
			leg.position = p
			_box(leg, Vector3(0.07, 0.75, 0.07), Vector3(0, -0.375, 0), coat)
			legs.append(leg)
	else:
		coat.albedo_color = Color(0.5, 0.42, 0.32)
		_box(node, Vector3(0.18, 0.2, 0.34), Vector3(0, 0.16, 0), coat)
		_box(node, Vector3(0.12, 0.12, 0.14), Vector3(0, 0.26, -0.18), coat)
		for s in [-1.0, 1.0]:
			_box(node, Vector3(0.03, 0.16, 0.05), Vector3(s * 0.035, 0.38, -0.16), coat).rotation.x = 0.25
		_box(node, Vector3(0.07, 0.07, 0.06), Vector3(0, 0.2, 0.18), coat)
	_beasts.append({"node": node, "legs": legs, "kind": kind, "home": home, "to": home, "speed": 0.0,
		"wait": randf_range(2.0, 10.0), "flee": 0.0, "t": randf() * 10.0, "coat": coat, "graze": 0.0})


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.visibility_range_end = 160.0
	parent.add_child(mi)
	return mi


func _step(b: Dictionary, dt: float, winter: bool) -> void:
	var node: Node3D = b.node
	var deer: bool = b.kind == "deer"
	b.t = float(b.t) + dt
	if not deer:
		(b.coat as StandardMaterial3D).albedo_color = Color(0.9, 0.9, 0.88) if winter else Color(0.5, 0.42, 0.32)
	# anyone of the town close: off, away from them
	var p := node.global_position
	var near: Villager = null
	var bd := SHY
	for o: Villager in village.villagers:
		if not o.dead and not o.sleeping:
			var d := o.position.distance_to(p)
			if d < bd:
				bd = d
				near = o
	if near and float(b.flee) <= 0.0:
		var away := (p - near.position)
		away.y = 0.0
		var to := p + away.normalized() * randf_range(30.0, 50.0)
		if nav.is_open(to) and to.distance_to(_home) > KEEP_OFF * 0.8:
			to.y = nav.height(to.x, to.z)
			b.to = to
			b.flee = 4.0
	b.flee = maxf(float(b.flee) - dt, 0.0)
	var to: Vector3 = b.to
	var flat := Vector3(to.x - p.x, 0, to.z - p.z)
	var want := 0.0
	if flat.length() > 0.6:
		want = (7.5 if deer else 6.0) if float(b.flee) > 0.0 else (1.1 if deer else 0.0)
	else:
		b.wait = float(b.wait) - dt
		if float(b.wait) <= 0.0:
			var next := _open_spot(b.home, 2.0, 25.0 if deer else 12.0)
			if next != Vector3.INF:
				b.to = next
			b.wait = randf_range(4.0, 14.0)
	if not deer and flat.length() > 0.6 and want == 0.0:
		want = 2.5 # (a hare hops even at its ease)
	b.speed = move_toward(float(b.speed), want, dt * 6.0)
	var v: float = b.speed
	if v > 0.05 and flat.length() > 0.05:
		var dir := flat.normalized()
		p += dir * minf(v * dt, flat.length())
		p.y = nav.height(p.x, p.z)
		node.global_position = p
		var yaw := atan2(-dir.x, -dir.z)
		node.rotation.y = lerp_angle(node.rotation.y, yaw, minf(dt * 6.0, 1.0))
	# the gait: a deer's legs swing (a bound when it runs), a hare hops
	var ph := float(b.t) * (4.0 + v * 1.6)
	if deer:
		var legs: Array = b.legs
		for i in legs.size():
			(legs[i] as Node3D).rotation.x = sin(ph + (PI if i in [1, 2] else 0.0)) * clampf(v * 0.25, 0.0, 0.7)
		var neck := node.get_node_or_null("neck") as Node3D
		if neck:
			# grazing, head down; head up and looking when someone's about or it moves
			var down := 1.0 if v < 0.1 and near == null and fmod(float(b.t), 9.0) < 6.0 else 0.0
			b.graze = move_toward(float(b.graze), down, dt * 1.5)
			neck.rotation.x = -float(b.graze) * 1.1
		node.position.y = p.y + absf(sin(ph)) * (0.12 if v > 4.0 else 0.0)
	else:
		node.position.y = p.y + (absf(sin(ph * 1.3)) * 0.25 if v > 0.3 else 0.0)
