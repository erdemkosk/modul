class_name MachineGun
extends RefCounted
## A weapon on a Machine: its turret turns (about the part's up) and its gun elevates toward the
## aim point at the speeds a real mount turns at, and it fires only when it is on it.
##
##   minigun   barrels spin up first (0.5 s), then 40 rounds a second, hitscan out to 450 m with a
##             little spread, a tracer every fourth; each round takes 5 hp and pushes a little
##   cannon    one shell every 2.5 s at 230 m/s, falling under gravity (Combat flies it), bursting on
##             what it hits: 240 hp at the centre over 3 m, a heave, a crater in the ground; the recoil
##             shoves the machine that fires it
##   rockets   six in the pod: while firing and on, one every 0.2 s out of the next full tube (Combat
##             flies it: off at 45 m/s, its motor pushing it to ~150 m/s over a second with a little
##             wobble, then falling), bursting at 170 hp over 2.8 m; empty tubes refill one every 1.5 s
##             while it isn't firing (or once all are gone)
##
## How they feel: the cannon's barrel runs back in its cradle and returns, the pod kicks with each
## rocket, the minigun shivers; its motor whines up and down with the barrels and its empties spill
## out of the side and tinkle off what they land on; each shot shakes the view (Combat.shake) and a
## flash stands at the muzzle.
##
## Fire control: the cannon and the pod lay their gun over the aim by as much as their round will
## fall on the way there (its time of flight from the range, as a tank's ballistic computer does), so
## the shot lands where you look.
##
## Electric: the minigun's motor, the turrets' traverse and the loaders draw on the machine's battery
## (draw_kw); with it flat (`powered` false) nothing turns, spins up or loads.

const KINDS := {
	"minigun": {"yaw_rate": 3.0, "pitch_rate": 2.5, "pitch": Vector2(-0.25, 0.9), "on": 0.04},
	"cannon": {"yaw_rate": 0.9, "pitch_rate": 0.6, "pitch": Vector2(-0.12, 0.45), "on": 0.015},
	"rockets": {"yaw_rate": 1.4, "pitch_rate": 1.0, "pitch": Vector2(-0.1, 0.75), "on": 0.03},
}
## kW: the minigun's motor at full spin, each mount's traverse at full slew, a loader at work.
const DRAW := {"minigun": [4.0, 0.8, 0.0], "cannon": [0.0, 3.0, 1.5], "rockets": [0.0, 1.2, 1.0]}
const MINIGUN_RATE := 40.0
const MINIGUN_SPREAD := 0.012 ## rad
const MINIGUN_DAMAGE := 5.0
const MINIGUN_PUSH := 18.0 ## N s a round
const MINIGUN_RANGE := 450.0
const SPIN_UP := 0.5
const CANNON_RELOAD := 2.5
const CANNON_SPEED := 230.0
const CANNON_DAMAGE := 240.0
const CANNON_RADIUS := 3.0
const CANNON_PUSH := 3500.0
const CANNON_RECOIL := 1600.0
const SHELL_DROP := 9.8 ## m/s2 (Combat flies the shells under it)
const ROCKETS := 6
const ROCKET_GAP := 0.2 ## s between rockets in a salvo
const ROCKET_RELOAD := 1.5 ## s a tube
const ROCKET_SPEED := 45.0 ## m/s off the rail
const ROCKET_THRUST := 105.0 ## m/s2 while its motor burns
const ROCKET_BURN := 1.0 ## s
const ROCKET_AVG := 120.0 ## m/s over a fighting range (for leading a target)
const ROCKET_SPREAD := 0.008 ## rad
const ROCKET_WOBBLE := 2.5 ## m/s2 sideways, at random, while it burns (about a metre off at 45 m)
const ROCKET_DAMAGE := 170.0
const ROCKET_RADIUS := 2.8
const ROCKET_PUSH := 2600.0

var machine: Machine
var node: Node3D
var kind := "minigun"
var turret: Node3D
var gun: Node3D
var barrels: Node3D
var muzzle: Node3D
var yaw := 0.0
var pitch := 0.0
var on_target := false
var _spin := 0.0 ## barrels' speed 0..1
var _spin_angle := 0.0
var _cool := 0.0
var _round := 0
var _turret_rest := Transform3D.IDENTITY
var _gun_rest := Transform3D.IDENTITY
var _barrels_rest := Transform3D.IDENTITY
var _sound_t := 0.0
var _slew := 0.0 ## how hard the mount turned last step 0..1
var loaded := ROCKETS
var _rockets: Array[Node3D] = [] ## (the pod's rockets, hidden as they go)
var _reload_t := 0.0
var _loaded_sound := true
## What the machine lets it have while its battery runs low (Machine sheds the least needed first).
var can_spin := true ## the minigun's motor
var can_load := true ## the loader
var armed := true ## (you pick which of your guns fire: 1-9, 0 all)
var condition := 1.0 ## its share of hit points left: hurt, it turns slower; badly, it jams
var _jam_t := 0.0
var _recoil := 0.0 ## 0..1 how far back the barrel or the pod is
var _recoil_v := 0.0
var _motor: AudioStreamPlayer3D
var _brass: GPUParticles3D
var _flash: MeshInstance3D
var _flash_t := 0.0
const RECOIL := {"minigun": 0.006, "cannon": 0.28, "rockets": 0.05} ## m back at full recoil


static func make(m: Machine, part: Node3D, id: String) -> MachineGun:
	var g := MachineGun.new()
	g.machine = m
	g.node = part
	g.kind = str(Parts.def(id).weapon)
	g.turret = part.find_child("Turret", true, false) as Node3D
	g.gun = part.find_child("Gun", true, false) as Node3D
	g.barrels = part.find_child("Barrels", true, false) as Node3D
	g.muzzle = part.find_child("Muzzle", true, false) as Node3D
	if g.turret:
		g._turret_rest = g.turret.transform
	if g.gun:
		g._gun_rest = g.gun.transform
	if g.barrels:
		g._barrels_rest = g.barrels.transform
	for k in ROCKETS:
		var r := part.find_child("Rocket%d" % k, true, false) as Node3D
		if r:
			g._rockets.append(r)
	g._dress()
	return g


## The minigun's motor and brass, a muzzle flash for each gun (not on a headless run).
func _dress() -> void:
	if DisplayServer.get_name() == "headless" or muzzle == null:
		return
	_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	var big := kind == "cannon"
	q.size = Vector2(1.6, 1.6) if big else Vector2(0.55, 0.55)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = _star()
	fm.albedo_color = Color(1.0, 0.75, 0.4)
	q.material = fm
	_flash.mesh = q
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_flash.position = Vector3(0, 0, -0.25 if big else -0.08)
	muzzle.add_child(_flash)
	if kind != "minigun":
		return
	_motor = AudioStreamPlayer3D.new()
	var s := (load("res://assets/audio/weapons/minigun_motor_loop.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = 44100
	_motor.stream = s
	_motor.unit_size = 6.0
	_motor.volume_db = -80.0
	gun.add_child(_motor)
	# the empties: brass out of the right of the receiver, tumbling, bouncing off what they hit
	_brass = GPUParticles3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0075
	cm.bottom_radius = 0.0075
	cm.height = 0.05
	cm.radial_segments = 6
	cm.rings = 1
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.78, 0.58, 0.25)
	bm.metallic = 0.9
	bm.roughness = 0.3
	cm.material = bm
	_brass.draw_pass_1 = cm
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1.0, 0.6, 0.2)
	pm.spread = 18.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 4.0
	pm.angular_velocity_min = -900.0
	pm.angular_velocity_max = 900.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.35
	pm.collision_friction = 0.4
	pm.particle_flag_rotate_y = true
	_brass.process_material = pm
	_brass.amount = 160
	_brass.lifetime = 3.0
	_brass.local_coords = false
	_brass.emitting = false
	_brass.position = Vector3(0.12, 0.0, 0.0)
	_brass.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	gun.add_child(_brass)


static var _star_tex: ImageTexture


## A muzzle flash's shape: a hot middle and five ragged spikes.
static func _star() -> ImageTexture:
	if _star_tex:
		return _star_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x - n * 0.5, y - n * 0.5) / (n * 0.5)
			var r := p.length()
			var a := atan2(p.y, p.x)
			var spikes := pow(absf(cos(a * 2.5)), 6.0) * 0.6 + 0.25
			var v := clampf(1.0 - r / spikes, 0.0, 1.0)
			v = maxf(v, clampf(1.0 - r * 2.2, 0.0, 1.0))
			img.set_pixel(x, y, Color(1.0, 0.85 + 0.15 * v, 0.6 + 0.4 * v, v * v))
	_star_tex = ImageTexture.create_from_image(img)
	return _star_tex


## One step: toward `aim` (world), firing if asked and on it (with the battery flat, nothing moves).
func update(dt: float, aim: Vector3, firing: bool, powered := true) -> void:
	if turret == null or gun == null or not is_instance_valid(node):
		return
	var k: Dictionary = KINDS[kind]
	if kind != "minigun":
		var t := flight_time(kind, aim.distance_to(turret.global_position))
		aim.y += 0.5 * SHELL_DROP * t * t
	var local := node.global_transform.basis.inverse() * (aim - turret.global_position)
	var want_yaw := atan2(-local.x, -local.z)
	var flat := Vector2(local.x, local.z).length()
	var lim: Vector2 = k.pitch
	var want_pitch := clampf(atan2(local.y, flat), lim.x, lim.y)
	var dyaw := 0.0
	var dpitch := 0.0
	if powered:
		var hurt := 0.35 + 0.65 * condition
		dyaw = clampf(angle_difference(yaw, want_yaw), -k.yaw_rate * hurt * dt, k.yaw_rate * hurt * dt)
		dpitch = clampf(want_pitch - pitch, -k.pitch_rate * hurt * dt, k.pitch_rate * hurt * dt)
	yaw += dyaw
	pitch += dpitch
	_slew = clampf(0.5 * (absf(dyaw) / (k.yaw_rate * dt) + absf(dpitch) / (k.pitch_rate * dt)), 0.0, 1.0)
	if not powered:
		firing = false
	# badly hurt, it jams now and then: a second and a half of nothing while it's cleared
	_jam_t = maxf(_jam_t - dt, 0.0)
	if _jam_t > 0.0:
		firing = false
	elif firing and condition < 0.35 and randf() < dt * 0.4:
		_jam_t = 1.5
		if Combat.current and muzzle:
			Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), muzzle.global_position, -4.0, 1.4)
	turret.transform = Transform3D(Basis(Vector3.UP, yaw) * _turret_rest.basis, _turret_rest.origin)
	# the recoil: a stiff spring back to battery (the cannon's barrel, the pod), a shiver for the minigun
	_recoil_v += (-_recoil * 260.0 - _recoil_v * 26.0) * dt
	_recoil = maxf(_recoil + _recoil_v * dt, 0.0)
	var gb := _gun_rest.basis * Basis(Vector3.RIGHT, pitch)
	var back := gb * Vector3(0.0, 0.0, float(RECOIL[kind]) * _recoil)
	if kind == "minigun" and _spin > 0.95 and firing:
		back += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.004
	gun.transform = Transform3D(gb, _gun_rest.origin + back)
	if _flash:
		_flash_t -= dt
		_flash.visible = _flash_t > 0.0
	if _motor:
		_motor.volume_db = linear_to_db(maxf(_spin * 0.7, 0.0001)) - 2.0
		_motor.pitch_scale = 0.4 + _spin * 0.75
		if _spin > 0.01 and not _motor.playing:
			_motor.play()
		elif _spin <= 0.01 and _motor.playing:
			_motor.stop()
	if _brass:
		_brass.emitting = firing and _spin > 0.95 and powered
	var err := absf(angle_difference(yaw, want_yaw)) + absf(pitch - atan2(local.y, flat))
	on_target = err < float(k.on) * (3.0 if local.length() < 15.0 else 1.0)
	_cool -= dt
	if kind == "minigun":
		_spin = move_toward(_spin, 1.0 if firing and can_spin else 0.0, dt / SPIN_UP)
		_spin_angle = fmod(_spin_angle + _spin * 40.0 * dt, TAU)
		if barrels:
			barrels.transform = Transform3D(_barrels_rest.basis * Basis(Vector3.BACK, _spin_angle), _barrels_rest.origin)
		if firing and on_target and _spin > 0.95:
			while _cool <= 0.0:
				_cool += 1.0 / MINIGUN_RATE
				_minigun_round()
		elif _cool < 0.0:
			_cool = 0.0
	elif kind == "rockets":
		if firing and on_target and loaded > 0 and _cool <= 0.0:
			_cool = ROCKET_GAP
			_rocket_shot()
		elif _cool < 0.0:
			_cool = 0.0
		if loaded < ROCKETS and powered and can_load and (not firing or loaded == 0):
			_reload_t += dt
			if _reload_t >= ROCKET_RELOAD:
				_reload_t = 0.0
				loaded += 1
				_rockets_shown()
				if Combat.current and _rockets.size() > 0:
					Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), _rockets[0].global_position, -10.0, 1.3)
		else:
			_reload_t = 0.0
	elif not powered or (not can_load and _cool > 0.0):
		_cool += dt # (the loader stops)
	elif firing and on_target and _cool <= 0.0:
		_cool = CANNON_RELOAD
		_loaded_sound = false
		_cannon_shot()
	if kind == "cannon" and not _loaded_sound and _cool <= 0.0:
		_loaded_sound = true # (the breech closes on the next round)
		if Combat.current and muzzle:
			Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), gun.global_position, -6.0, 0.8)


func _bore() -> Transform3D:
	return muzzle.global_transform if muzzle else gun.global_transform


func _minigun_round() -> void:
	var c := Combat.current
	if c == null:
		return
	var b := _bore()
	var fwd := -b.basis.z
	var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * MINIGUN_SPREAD
	var dir := (fwd + spread).normalized()
	_round += 1
	c.hitscan(b.origin, dir, MINIGUN_RANGE, MINIGUN_DAMAGE, MINIGUN_PUSH, machine, _round % 3 == 0)
	machine.apply_impulse(-dir * MINIGUN_PUSH * 0.3, b.origin - machine.global_position)
	if _round % 3 == 0:
		c.sound("res://assets/audio/weapons/close_0%d.wav" % randi_range(1, 3), b.origin, -4.0, randf_range(1.2, 1.35))
	if _round % 23 == 0:
		c.sound("res://assets/audio/weapons/casings/brass_metal_0%d.wav" % randi_range(1, 3), b.origin + Vector3.DOWN, -14.0, randf_range(0.9, 1.2))
	c.muzzle_flash(b.origin, dir, 0.6)
	c.shake(b.origin, 0.03, machine)
	_flash_t = 0.02
	if _flash:
		_flash.rotation.z = randf() * TAU


func _cannon_shot() -> void:
	var c := Combat.current
	if c == null:
		return
	var b := _bore()
	var dir := -b.basis.z
	c.fire_shell(b.origin + dir * 0.1, dir * CANNON_SPEED + machine.velocity_at(b.origin), machine)
	machine.apply_impulse(-dir * CANNON_RECOIL, b.origin - machine.global_position)
	c.sound("res://assets/audio/explosion/close_0%d.wav" % randi_range(1, 3), b.origin, 2.0, randf_range(1.5, 1.7))
	c.sound("res://assets/audio/weapons/tail_01.wav", b.origin, 0.0, 0.7)
	c.muzzle_flash(b.origin, dir, 2.2)
	c.dust_ring(b.origin, machine)
	c.shake(b.origin, 0.55, machine, 6.0)
	_recoil_v = 34.0 # (the barrel slams back)
	_flash_t = 0.05
	if _flash:
		_flash.rotation.z = randf() * TAU


func _rocket_shot() -> void:
	var c := Combat.current
	var tube := ROCKETS - loaded
	loaded -= 1
	_rockets_shown()
	if c == null:
		return
	var dir := -gun.global_basis.z
	var from := _bore().origin
	if tube < _rockets.size():
		from = _rockets[tube].global_position
	var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * ROCKET_SPREAD
	dir = (dir + spread).normalized()
	c.fire_rocket(from + dir * 0.15, dir, machine.velocity_at(from), machine)
	c.shake(from, 0.18, machine, 1.5)
	_recoil_v = 18.0
	c.sound("res://assets/audio/rocket/launch.wav", from, 0.0, randf_range(0.92, 1.08))
	c.muzzle_flash(from, dir, 1.2)
	c.backblast(from - dir * 0.9, -dir)


## Seconds a round of `kind` takes to go `dist` m: a shell at its muzzle speed; a rocket off the rail,
## speeding up while its motor burns, then on at the speed it had.
static func flight_time(kind: String, dist: float) -> float:
	if kind == "cannon":
		return dist / CANNON_SPEED
	if kind == "rockets":
		var burn_d := ROCKET_SPEED * ROCKET_BURN + 0.5 * ROCKET_THRUST * ROCKET_BURN * ROCKET_BURN
		if dist <= burn_d:
			return (-ROCKET_SPEED + sqrt(ROCKET_SPEED * ROCKET_SPEED + 2.0 * ROCKET_THRUST * dist)) / ROCKET_THRUST
		return ROCKET_BURN + (dist - burn_d) / (ROCKET_SPEED + ROCKET_THRUST * ROCKET_BURN)
	return dist / 900.0


## The pod's rockets: the first `ROCKETS - loaded` tubes empty.
func _rockets_shown() -> void:
	for k in _rockets.size():
		_rockets[k].visible = k >= ROCKETS - loaded


## kW it draws now: the minigun's motor as it spins, the mount as it turns, the loader as it loads.
func draw_kw() -> float:
	var d: Array = DRAW[kind]
	var loading := 0.0
	if kind == "cannon" and _cool > 0.0 and can_load:
		loading = 1.0
	elif kind == "rockets" and loaded < ROCKETS and can_load:
		loading = 1.0
	return float(d[0]) * _spin + float(d[1]) * _slew + float(d[2]) * loading


## Reloading: 0 ready .. 1 just fired / empty (the HUD).
func reload_frac() -> float:
	if kind == "cannon":
		return clampf(_cool / CANNON_RELOAD, 0.0, 1.0)
	if kind == "rockets":
		return 1.0 - float(loaded) / ROCKETS
	return 0.0
