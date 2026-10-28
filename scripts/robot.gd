extends CharacterBody3D
## A works robot guarding a site (Missions puts them out, held till you start): built for the
## works, not for war, and turned on whoever comes in.
##
##   sentry   NÖBETÇİ: a perimeter gun on a bolted tripod; its head turns to you (slowly) once it
##            sees you within SIGHT, and it fires bursts (hitscan, a tracer every third). Rain on its
##            lens throws its aim off; at night its lamp is on you.
##   warden   BEKÇİ: a four-wheeled yard robot with a hydraulic arm and a cutting disc; it drives at
##            you and cuts at what it reaches. Mud and a bog slow it, snow too, on ice it slides; if
##            you're quick it can't catch you.
##
## Shot, burnt, caught in a burst (Combat calls take_hit) or run into by a machine (by how hard it
## came, its mass and speed: a heavy machine flattens it), it loses hit points; at none it shorts,
## sparks and goes over as a wreck that stays.

signal died(r: Node)

const SIGHT := 70.0 ## m a sentry sees you at (by day; half at night outside its lamp's reach)
const CHASE := 55.0 ## m a warden comes for you from
const SENTRY_TURN := 1.4 ## rad/s
const SENTRY_RATE := 9.0 ## rounds a second in a burst
const SENTRY_BURST := 1.1 ## s firing
const SENTRY_PAUSE := 1.4 ## s between
const SENTRY_DAMAGE := 4.0
const SENTRY_SPREAD := 0.02 ## rad (more in the rain)
const WARDEN_SPEED := 6.5 ## m/s on hard ground
const WARDEN_REACH := 2.4 ## m its disc reaches from its middle
const WARDEN_CUT := 22.0 ## hp a cut
const WARDEN_CUT_T := 0.55 ## s between cuts
const RAM_SAFE := 2.5 ## m/s a machine can lean on it at without hurting it
const HP := {"sentry": 170.0, "warden": 140.0}
const YELLOW := Color(0.72, 0.5, 0.07)
const STEEL := Color(0.16, 0.16, 0.17)
const BLACK := Color(0.03, 0.03, 0.03)

var kind := "sentry"
var game: Node
var terrain: Node
var hp := 100.0
var alive := true
var _head: Node3D ## (the sentry's head, the warden's arm)
var _muzzle: Node3D
var _disc: Node3D
var _beacon: Node3D
var _lamp: SpotLight3D
var _eye: MeshInstance3D
var _yaw := 0.0
var _pitch := 0.0
var _burst_t := 0.0
var _cool := 0.0
var _round := 0
var _ram_t := 0.0
var _knock := Vector3.ZERO
var _spark_t := 0.0
var _heading := 0.0
var _arm := 0.0
var _detour_t := 0.0 ## (going round something it ran into)
var _detour := 1.0


static func make(kind_: String, at: Transform3D, game_: Node, terrain_: Node) -> CharacterBody3D:
	var r: CharacterBody3D = load("res://scripts/robot.gd").new()
	r.set("kind", kind_)
	r.set("game", game_)
	r.set("terrain", terrain_)
	r.transform = at
	return r


func _ready() -> void:
	add_to_group("robots")
	hp = float(HP[kind])
	collision_layer = 4
	collision_mask = 1 | 2
	_heading = global_basis.get_euler().y
	if kind == "sentry":
		_build_sentry()
	else:
		_build_warden()


# --- How it looks: works yellow with black chevrons, steel, an orange beacon, a red eye ------------

func _mat(c: Color, metal := 0.3, rough := 0.55, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = m
	mi.mesh = b
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r: float, h: float, at: Vector3, m: Material, rot := Vector3.ZERO, r2 := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r if r2 < 0.0 else r2
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 1
	c.material = m
	mi.mesh = c
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _shape(size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = at
	add_child(cs)


## Chevrons across a face: black bars slanted on the yellow.
func _chevrons(parent: Node3D, w: float, at: Vector3, normal_z: float) -> void:
	var m := _mat(BLACK, 0.1, 0.7)
	for k in 4:
		var x := -w * 0.5 + w * (k + 0.5) / 4.0
		_box(parent, Vector3(0.06, 0.2, 0.01), at + Vector3(x, 0, 0.006 * normal_z), m, Vector3(0, 0, 0.6))


func _beacon_on(parent: Node3D, at: Vector3) -> void:
	_beacon = Node3D.new()
	_beacon.position = at
	parent.add_child(_beacon)
	_cyl(_beacon, 0.07, 0.12, Vector3.ZERO, _mat(Color(1.0, 0.45, 0.05), 0.0, 0.3, 2.5))
	_box(_beacon, Vector3(0.16, 0.08, 0.02), Vector3(0, 0, 0.05), _mat(Color(0.9, 0.9, 0.85), 0.9, 0.15))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.1)
	l.omni_range = 5.0
	l.light_energy = 1.2
	l.position = Vector3(0, 0, 0.2)
	_beacon.add_child(l)


func _build_sentry() -> void:
	var yel := _mat(YELLOW)
	var st := _mat(STEEL, 0.7, 0.45)
	var root := Node3D.new()
	add_child(root)
	# the tripod and its feet, the post, a battery box
	for k in 3:
		var a := k * TAU / 3.0
		var foot := Vector3(sin(a), 0.0, cos(a)) * 0.9
		var top := Vector3(0, 1.15, 0)
		var along := (top - foot).normalized()
		var leg := _cyl(root, 0.05, foot.distance_to(top), (foot + top) * 0.5, st)
		leg.basis = Basis(Vector3.UP.cross(along).normalized(), Vector3.UP.angle_to(along))
		_box(root, Vector3(0.24, 0.05, 0.24), foot + Vector3.UP * 0.025, st)
	_cyl(root, 0.11, 0.6, Vector3(0, 1.2, 0), yel)
	_box(root, Vector3(0.4, 0.3, 0.26), Vector3(0, 0.75, -0.25), yel)
	_chevrons(root, 0.36, Vector3(0, 0.75, -0.381), -1.0)
	_cyl(root, 0.22, 0.08, Vector3(0, 1.52, 0), st)
	_shape(Vector3(0.9, 1.6, 0.9), Vector3(0, 0.8, 0))
	# the head: a sensor block and the gun in a cradle under a hood
	_head = Node3D.new()
	_head.position = Vector3(0, 1.62, 0)
	add_child(_head)
	var gun := Node3D.new()
	gun.name = "Gun"
	_head.add_child(gun)
	_box(gun, Vector3(0.5, 0.3, 0.62), Vector3(0, 0.12, 0.02), yel)
	_box(gun, Vector3(0.52, 0.04, 0.66), Vector3(0, 0.29, 0.02), st)
	_chevrons(gun, 0.44, Vector3(0, 0.12, 0.331), 1.0)
	_cyl(gun, 0.035, 0.75, Vector3(0.1, 0.08, -0.6), st, Vector3(PI * 0.5, 0, 0))
	_cyl(gun, 0.035, 0.75, Vector3(-0.1, 0.08, -0.6), st, Vector3(PI * 0.5, 0, 0))
	_box(gun, Vector3(0.18, 0.12, 0.1), Vector3(0, 0.2, -0.3), st)
	_eye = _cyl(gun, 0.045, 0.03, Vector3(0, 0.2, -0.36), _mat(Color(1.0, 0.08, 0.04), 0.0, 0.2, 4.0), Vector3(PI * 0.5, 0, 0))
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.08, -1.0)
	gun.add_child(_muzzle)
	_lamp = SpotLight3D.new()
	_lamp.position = Vector3(0, 0.3, -0.3)
	_lamp.spot_range = 45.0
	_lamp.spot_angle = 20.0
	_lamp.light_energy = 9.0
	_lamp.light_color = Color(1.0, 0.95, 0.85)
	_lamp.shadow_enabled = false # (a site has several: their shadows cost too much)
	gun.add_child(_lamp)
	_beacon_on(_head, Vector3(0, 0.38, 0.18))


func _build_warden() -> void:
	var yel := _mat(YELLOW)
	var st := _mat(STEEL, 0.7, 0.45)
	var rub := _mat(Color(0.03, 0.03, 0.03), 0.0, 0.9)
	var root := Node3D.new()
	add_child(root)
	# the chassis on four solid tyres, the body, the battery pack, a grille, the sensor mast
	_box(root, Vector3(1.1, 0.2, 1.5), Vector3(0, 0.32, 0), st)
	for x: float in [-0.62, 0.62]:
		for z: float in [-0.5, 0.5]:
			_cyl(root, 0.24, 0.18, Vector3(x, 0.24, z), rub, Vector3(0, 0, PI * 0.5))
			_cyl(root, 0.12, 0.19, Vector3(x, 0.24, z), st, Vector3(0, 0, PI * 0.5))
	_box(root, Vector3(1.0, 0.6, 1.2), Vector3(0, 0.72, 0.05), yel)
	_box(root, Vector3(0.9, 0.06, 1.1), Vector3(0, 1.05, 0.05), st)
	_chevrons(root, 0.9, Vector3(0, 0.6, -0.551), -1.0)
	_chevrons(root, 0.9, Vector3(0, 0.6, 0.651), 1.0)
	_box(root, Vector3(0.7, 0.3, 0.03), Vector3(0, 0.82, -0.56), _mat(Color(0.05, 0.05, 0.05), 0.5, 0.6))
	_cyl(root, 0.03, 0.5, Vector3(0.35, 1.3, 0.4), st)
	_eye = _cyl(root, 0.06, 0.05, Vector3(0.35, 1.55, 0.36), _mat(Color(1.0, 0.08, 0.04), 0.0, 0.2, 4.0), Vector3(PI * 0.5, 0, 0))
	_beacon_on(root, Vector3(-0.3, 1.14, 0.35))
	_shape(Vector3(1.4, 1.1, 1.6), Vector3(0, 0.55, 0))
	# the arm: a boom from the front of the body, a ram under it, the cutting disc at its end
	_head = Node3D.new()
	_head.position = Vector3(0, 0.95, -0.45)
	add_child(_head)
	_box(_head, Vector3(0.16, 0.16, 1.1), Vector3(0, 0, -0.5), yel)
	_cyl(_head, 0.05, 0.6, Vector3(0, -0.15, -0.25), st, Vector3(PI * 0.5 + 0.25, 0, 0))
	_disc = Node3D.new()
	_disc.position = Vector3(0, -0.05, -1.1)
	_head.add_child(_disc)
	_cyl(_disc, 0.32, 0.03, Vector3.ZERO, _mat(Color(0.55, 0.55, 0.55), 0.9, 0.3), Vector3(0, 0, PI * 0.5))
	_cyl(_disc, 0.08, 0.08, Vector3.ZERO, st, Vector3(0, 0, PI * 0.5))
	_box(_disc, Vector3(0.06, 0.36, 0.4), Vector3(0.06, 0.12, 0.08), yel) # (its guard)


# --- What it does ---------------------------------------------------------------------------------

func _target() -> Machine:
	if game == null:
		return null
	var m: Variant = game.get("machine")
	if is_instance_valid(m) and m is Machine and (m as Machine).alive: # (a freed one can't even be asked what it is)
		return m as Machine
	return null


func _physics_process(dt: float) -> void:
	if _beacon:
		_beacon.rotation.y += dt * 6.0
	if not alive:
		return
	_ram_t = maxf(_ram_t - dt, 0.0)
	_rammed()
	var t := _target()
	if kind == "sentry":
		_sentry(dt, t)
	else:
		_warden(dt, t)


## A machine leaning or driving into it: hurt by how hard (its mass and the speed it came at), and
## thrown aside.
func _rammed() -> void:
	if _ram_t > 0.0:
		return
	for n: Node in get_tree().get_nodes_in_group("machines"):
		var m := n as Machine
		if m == null or not is_instance_valid(m) or not m.alive:
			continue
		if m.global_position.distance_to(global_position) > 6.0:
			continue
		var rel := m.linear_velocity - velocity
		if rel.length() < RAM_SAFE:
			continue
		# touching: a short ray from its middle to the machine's
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.6,
			m.global_position + Vector3.UP * 0.3, 2)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or hit.collider != m or (hit.position as Vector3).distance_to(global_position + Vector3.UP * 0.6) > 1.3:
			continue
		var v := rel.length()
		var kj := 0.5 * minf(m.total_mass, 4000.0) * v * v / 1000.0
		_ram_t = 0.4
		_knock = rel * 0.9 + Vector3.UP * minf(v * 0.5, 5.0)
		take_hit(kj * 4.0, hit.position, rel.normalized())
		if Combat.current:
			Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), hit.position, 4.0, 0.7)
		return


func _sentry(dt: float, t: Machine) -> void:
	var sees := false
	var aim := Vector3.ZERO
	if t:
		aim = t.com_global()
		var d := aim.distance_to(_head.global_position)
		var night := _night()
		sees = d < (SIGHT if not night else SIGHT * 0.5) and _clear_to(t, aim)
	if _lamp:
		_lamp.visible = _night()
	if not sees:
		_burst_t = 0.0
		_yaw += dt * 0.35 # (sweeping)
		_pitch = move_toward(_pitch, 0.0, dt * 0.5)
		_pose()
		return
	var local := global_basis.inverse() * (aim - _head.global_position)
	var want_yaw := atan2(-local.x, -local.z)
	var want_pitch := clampf(atan2(local.y, Vector2(local.x, local.z).length()), -0.5, 0.6)
	var turn := SENTRY_TURN * dt
	_yaw += clampf(angle_difference(_yaw, want_yaw), -turn, turn)
	_pitch += clampf(want_pitch - _pitch, -turn, turn)
	_pose()
	var on := absf(angle_difference(_yaw, want_yaw)) < 0.08
	# bursts: firing for a second, then a breath
	_burst_t += dt
	var cycle := SENTRY_BURST + SENTRY_PAUSE
	if fmod(_burst_t, cycle) > SENTRY_BURST or not on:
		return
	_cool -= dt
	while _cool <= 0.0:
		_cool += 1.0 / SENTRY_RATE
		_shot()


func _pose() -> void:
	_head.rotation = Vector3(0, _yaw, 0)
	(_head.get_node("Gun") as Node3D).rotation = Vector3(_pitch, 0, 0)


func _shot() -> void:
	var c := Combat.current
	if c == null:
		return
	var b := _muzzle.global_transform
	var spread := SENTRY_SPREAD * (1.0 + 2.0 * Weather.rain_now) # (rain on its lens)
	var dir := (-b.basis.z + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	_round += 1
	c.hitscan(b.origin, dir, 160.0, SENTRY_DAMAGE, 14.0, null, _round % 3 == 0)
	c.muzzle_flash(b.origin, dir, 0.5)
	if _round % 2 == 0:
		c.sound("res://assets/audio/weapons/close_0%d.wav" % randi_range(1, 3), b.origin, -2.0, randf_range(1.45, 1.6))


## Nothing between it and you (the ground, a wall, a tank).
func _clear_to(t: Machine, at: Vector3) -> bool:
	var from := _head.global_position + Vector3.UP * 0.2
	var q := PhysicsRayQueryParameters3D.create(from, at, 1 | 2)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == t


func _night() -> bool:
	var w: Variant = game.get("weather") if game else null
	return w is Weather and (w as Weather).is_night()


func _warden(dt: float, t: Machine) -> void:
	var g := _ground()
	var grip := 1.0
	var slow := 1.0
	if g:
		grip = clampf(g.grip, 0.15, 1.0)
		match g.label: # (a bog nearly stops it; mud slows it, snow less)
			"bog":
				slow = 0.35
			"mud":
				slow = 0.55
			"snow", "snowpack":
				slow = 0.7
			_:
				slow = 0.8 if g.is_soft() else 1.0
	slow *= 1.0 - 0.6 * Weather.snow_cover_now
	var want := Vector3.ZERO
	var close := false
	if t:
		var to := t.com_global() - global_position
		to.y = 0.0
		var d := to.length()
		if d < CHASE:
			# straight at you; run into something (a wall, a container), it goes round it a while
			_detour_t = maxf(_detour_t - dt, 0.0)
			var way := atan2(-to.x, -to.z) + (_detour * 1.1 if _detour_t > 0.0 else 0.0)
			_heading = lerp_angle(_heading, way, clampf(dt * 2.5, 0.0, 1.0))
			close = d < WARDEN_REACH + _radius_of(t)
			if not close:
				want = Vector3(-sin(_heading), 0.0, -cos(_heading)) * WARDEN_SPEED * slow
	rotation.y = _heading
	# its tyres take it there as far as the ground grips (on ice it slides on)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	flat = flat.move_toward(want, 14.0 * grip * dt)
	velocity.x = flat.x
	velocity.z = flat.z
	if _knock != Vector3.ZERO:
		velocity += _knock
		_knock = Vector3.ZERO
	velocity.y = velocity.y - 9.8 * dt if not is_on_floor() else maxf(velocity.y, -0.5)
	move_and_slide()
	if is_on_wall() and _detour_t <= 0.0 and want.length() > 1.0:
		_detour_t = 1.4
		_detour = 1.0 if randf() < 0.5 else -1.0
	# the arm: raised as it comes, brought down on what it reaches, the disc always running
	_disc.rotate_object_local(Vector3.RIGHT, dt * 40.0)
	_arm = move_toward(_arm, (1.0 if fmod(Time.get_ticks_msec() / 1000.0, WARDEN_CUT_T) < WARDEN_CUT_T * 0.5 else -0.2) if close else 0.5, dt * 6.0)
	_head.rotation.x = _arm * 0.5
	_cool -= dt
	if close and _cool <= 0.0:
		_cool = WARDEN_CUT_T
		_cut(t)


## How far a machine reaches out from its middle (roughly: its size).
func _radius_of(m: Machine) -> float:
	return clampf(sqrt(m.frontal) * 0.8, 1.0, 3.0)


func _cut(t: Machine) -> void:
	var from := _disc.global_position
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.2, t.com_global(), 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.collider != t or (hit.position as Vector3).distance_to(from) > 1.6:
		return
	var at: Vector3 = hit.position
	t.hit(at, (at - from).normalized(), WARDEN_CUT, 300.0, null)
	if Combat.current:
		Combat.current.muzzle_flash(at, Vector3.UP, 0.7) # (sparks off the disc)
		Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), at, 0.0, randf_range(1.6, 1.9))


func _ground() -> Surface:
	if terrain and terrain.has_method("surface_at"):
		return terrain.call("surface_at", global_position) as Surface
	return null


## What it's called on the screen, and what's left of it 0..1 (CombatOverlay).
func title() -> String:
	return "NÖBETÇİ" if kind == "sentry" else "BEKÇİ ROBOT"


func hp_frac() -> float:
	return clampf(hp / float(HP[kind]), 0.0, 1.0)


# --- Hurt -----------------------------------------------------------------------------------------

## Hit (Combat: a round, a flame, a burst; or a machine running into it).
func take_hit(damage: float, at: Vector3, dir: Vector3, push := 0.0) -> void:
	if not alive:
		return
	hp -= damage
	if push > 0.0 and kind == "warden":
		_knock += dir * minf(push / 300.0, 8.0) + Vector3.UP * minf(push / 600.0, 4.0)
	if Combat.current and randf() < 0.3:
		Combat.current.muzzle_flash(at, -dir, 0.35) # (sparks)
	if hp <= 0.0:
		_die(dir)


func _die(dir: Vector3) -> void:
	alive = false
	collision_layer = 1 # (a wreck: still in the way, no longer a target)
	if _lamp:
		_lamp.visible = false
	if _eye:
		_eye.visible = false
	if _beacon:
		_beacon.visible = false
	var c := Combat.current
	if c:
		var at := global_position + Vector3.UP * 0.8
		c.muzzle_flash(at, Vector3.UP, 1.4)
		c.sound("res://assets/audio/explosion/debris_metal_0%d.wav" % randi_range(1, 2), at, 2.0, 1.1)
		c.call_deferred("explode", at, 1.8, 40.0, 900.0, null, true) # (its battery pack goes)
	# it goes over, away from what killed it, and stays
	var side := Vector3(dir.x, 0.0, dir.z).normalized()
	if side == Vector3.ZERO:
		side = Vector3.RIGHT
	var axis := side.cross(Vector3.UP).normalized()
	var tw := create_tween()
	tw.tween_property(self, "global_basis", Basis(axis, -1.25) * global_basis, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	died.emit(self)
