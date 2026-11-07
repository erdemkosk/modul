class_name Wildlife
extends Node3D
## The taiga's own: a few deer at the edge of the woods, grazing, heads coming up at a sound and away
## at a bound when someone comes near; hares about the clearings, sitting up, hopping off (white in
## the winter). Kept out from the town (they don't come in among the houses), each wandering its own
## ground. Roe deer and mountain hares made in Blender (assets/animals, scripts/animal_body.gd), going
## in their own gaits, their coats turning with the season.

const DEER := 4
const HARES := 7
const SHY := 18.0 ## m: anyone of the town nearer than this and they're off
const KEEP_OFF := 55.0 ## m from the store they won't come inside

var village: Node
var nav: Nav
var _beasts: Array[Dictionary] = [] ## {node (AnimalBody), kind, home, to, speed, wait, flee, t, graze, coat (0 summer .. 1 winter)}
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
	var body: AnimalBody
	if kind == "deer":
		# a roe: foxy red in the summer, grey-brown in its winter coat; half of them bucks
		var red := Color(0.6, 0.5, 0.42).lerp(Color(0.56, 0.49, 0.43), randf())
		body = AnimalBody.make("deer", red, Color(0.47, 0.43, 0.38), randf() < 0.5, 170.0)
	else:
		# a mountain hare: grey-brown, white in the winter
		body = AnimalBody.make("hare", Color(0.56, 0.5, 0.42).lerp(Color(0.52, 0.48, 0.42), randf()), Color(1.06, 1.06, 1.04), false, 110.0)
	add_child(body)
	body.global_position = home
	body.rotation.y = randf() * TAU
	_beasts.append({"node": body, "kind": kind, "home": home, "to": home, "speed": 0.0,
		"wait": randf_range(2.0, 10.0), "flee": 0.0, "t": randf() * 10.0, "graze": 0.0,
		"coat": 1.0 if village.seasons != null and village.seasons.winter() else 0.0})


func _step(b: Dictionary, dt: float, winter: bool) -> void:
	var node: Node3D = b.node
	var deer: bool = b.kind == "deer"
	b.t = float(b.t) + dt
	var body := node as AnimalBody
	b.coat = move_toward(float(b.coat), 1.0 if winter else 0.0, dt * 0.05) # (the coat turns over some days)
	body.set_winter(float(b.coat))
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
	# the gait (AnimalBody: a walk, a trot, a bound; a hare's hops), the trunk to the lie of the ground
	body.fit_ground(func(q: Vector3) -> float: return nav.height(q.x, q.z), dt)
	body.step(dt, v)
	if deer:
		# grazing, head down; head up and looking when someone's about or it moves
		var down := 1.0 if v < 0.1 and near == null and fmod(float(b.t), 9.0) < 6.0 else 0.0
		b.graze = move_toward(float(b.graze), down, dt * 1.5)
		body.graze = float(b.graze)
		body.look = sin(float(b.t) * 0.7) * 0.5 if near == null and down == 0.0 and v < 0.1 else 0.0
	else:
		# a hare at rest nibbles, and now and then sits up on its haunches, ears up, to look about
		var up := 1.0 if v < 0.1 and fmod(float(b.t), 11.0) > 8.0 else 0.0
		body.rear = move_toward(body.rear, up, dt * 3.0)
		body.graze = 0.5 if v < 0.1 and up == 0.0 else 0.0
