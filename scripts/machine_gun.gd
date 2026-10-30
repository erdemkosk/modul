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
## The wood age's (worked by hand: no battery):
##   ballista  a bolt every BOLT_RELOAD s at BOLT_SPEED m/s, falling a little (Combat flies it): it goes
##             through the part it hits into the one behind; with a cask of pitch beside it the bolt's
##             alight and sets wood burning; it sticks in what it hits
##   catapult  a stone every STONE_RELOAD s, lobbed high (STONE_ANGLE) and hard enough to come down
##             where you look (out to ~230 m, STONE_MAX m/s): what it lands on is battered, cover broken; with pitch beside it a pot of
##             burning pitch instead, and the ground there burns
##   oil       a cask of boiling oil tipped out on the ground ahead (to OIL_REACH m): it burns there
##             for a while and burns what's on it (Combat.oil_fire)
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
## What it carries (where ammunition's limited: everywhere but the proving ground): AMMO rounds of its
## own (the flamethrower: seconds of fuel), and as many again for each ammo box (cephane) bolted beside
## it (two at most); spent, it only clicks (the wood age's are stocked again at the workshop). A barrel
## kit (namlu takımı) beside it gives it a longer barrel, its round faster and truer, a flame further,
## a heavier gun turning slower. The long barrel shows on the gun.
##
## Electric: the minigun's motor, the turrets' traverse and the loaders draw on the machine's battery
## (draw_kw); with it flat (`powered` false) nothing turns, spins up or loads.

const KINDS := {
	"minigun": {"yaw_rate": 3.0, "pitch_rate": 2.5, "pitch": Vector2(-0.25, 0.9), "on": 0.04},
	"cannon": {"yaw_rate": 0.9, "pitch_rate": 0.6, "pitch": Vector2(-0.12, 0.45), "on": 0.015},
	"rockets": {"yaw_rate": 1.4, "pitch_rate": 1.0, "pitch": Vector2(-0.1, 0.75), "on": 0.03},
	"flamer": {"yaw_rate": 2.4, "pitch_rate": 2.0, "pitch": Vector2(-0.35, 0.6), "on": 0.14},
	"ballista": {"yaw_rate": 1.5, "pitch_rate": 1.1, "pitch": Vector2(-0.15, 0.5), "on": 0.02},
	"catapult": {"yaw_rate": 0.7, "pitch_rate": 1.4, "pitch": Vector2(0.05, 1.1), "on": 0.012},
	"oil": {"yaw_rate": 1.2, "pitch_rate": 1.5, "pitch": Vector2(-0.6, 0.3), "on": 0.2},
}
## The ones worked by hand (no battery: they turn and load with it flat).
const MANUAL := ["ballista", "catapult", "oil"]
## kW: the minigun's motor at full spin, each mount's traverse at full slew, a loader at work.
const DRAW := {"minigun": [4.0, 0.8, 0.0], "cannon": [0.0, 3.0, 1.5], "rockets": [0.0, 1.2, 1.0], "flamer": [1.2, 0.8, 0.0],
	"ballista": [0.0, 0.0, 0.0], "catapult": [0.0, 0.0, 0.0], "oil": [0.0, 0.0, 0.0]}
const FLAME_RANGE := 14.0 ## m
const FLAME_DPS := 90.0 ## hp a second at the stream's heart
const MINIGUN_RATE := 40.0
const MINIGUN_SPREAD := 0.012 ## rad
const MINIGUN_DAMAGE := 4.0
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
const BOLT_RELOAD := 2.4
const BOLT_SPEED := 80.0
const BOLT_DAMAGE := 55.0
const BOLT_PUSH := 250.0
const STONE_RELOAD := 5.0
const STONE_ANGLE := 0.75 ## rad it's thrown up at
const STONE_MAX := 48.0 ## m/s the most it throws at
const STONE_UP := 1.0 ## m over its mount the stone leaves the arm
const STONE_DAMAGE := 170.0
const STONE_RADIUS := 1.8
const STONE_PUSH := 4500.0
const OIL_RELOAD := 4.0
const OIL_REACH := 8.0 ## m ahead it's tipped out at most

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
var key := 0 ## the key it fires on (0: the mouse's left button, with the rest)
var key_down := false
var feed := 0 ## ammo boxes beside it
const AMMO := {"minigun": 360.0, "cannon": 10.0, "rockets": 18.0, "flamer": 12.0, "ballista": 16.0, "catapult": 10.0, "oil": 6.0} ## its own (rounds; the flamer s of fuel)
var fiery := false ## (a cask of pitch beside it: its bolts and pots burn)
var limited := false ## (its ammunition runs out)
var ammo := 0.0 ## left (rockets: the ones in the pod too)
var ammo_max := 0.0
var entry: Dictionary ## (its part's design entry: what's left of its ammunition is kept on it)
var _dry_t := 0.0
var kit := 0 ## barrel kits beside it
var _kit_muzzle: Node3D ## (the long barrel's end)
var condition := 1.0 ## its share of hit points left: hurt, it turns slower; badly, it jams
var _jam_t := 0.0
var _recoil := 0.0 ## 0..1 how far back the barrel or the pod is
var _recoil_v := 0.0
var _motor: AudioStreamPlayer3D
var _brass: GPUParticles3D
var _fire: GPUParticles3D ## (a flamethrower's stream)
var _flash: MeshInstance3D
var _flash_t := 0.0
const RECOIL := {"minigun": 0.006, "cannon": 0.28, "rockets": 0.05, "flamer": 0.002, "ballista": 0.04, "catapult": 0.0, "oil": 0.0} ## m back at full recoil
var _arm := 0.0 ## (a catapult's arm: 0 lying back, 1 thrown over)
var _lob_v := 30.0 ## (a catapult's throw: m/s for where it's aimed)


static func make(m: Machine, part: Node3D, id: String, feed_ := 0, kit_ := 0) -> MachineGun:
	var g := MachineGun.new()
	g.machine = m
	g.node = part
	g.feed = feed_
	g.kit = kit_
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
	g._fit_kit()
	g._dress()
	return g


## How the boxes beside it change it (a box only carries more: see supply()).
func reload_k() -> float:
	return 1.0


func rate_k() -> float:
	return 1.0


## Its ammunition set up: limited or not, `k` times its load (a crew's carry more), what's left kept
## on its design entry (`e`) if it's been fighting.
func supply(limited_: bool, k: float, e: Dictionary) -> void:
	limited = limited_
	entry = e
	ammo_max = float(AMMO[kind]) * (1.0 + feed) * k
	ammo = minf(float(e.get("ammo", ammo_max)), ammo_max) if limited else ammo_max
	if kind == "rockets":
		loaded = mini(loaded, int(ammo))
		_rockets_shown()


## Its ammunition taken up by `frac` of a full load (a supply crate).
func refill(frac: float) -> void:
	ammo = minf(ammo + ammo_max * frac, ammo_max)
	_keep()


func has_ammo() -> bool:
	return not limited or ammo >= (0.05 if kind == "flamer" else 1.0)


func ammo_frac() -> float:
	return ammo / ammo_max if ammo_max > 0.0 else 1.0


func _spend(n: float) -> void:
	if limited:
		ammo = maxf(ammo - n, 0.0)
		_keep()


func _keep() -> void:
	if limited:
		entry["ammo"] = ammo


## Out, and the trigger's pulled: the click of an empty gun, now and then.
func _dry(dt: float) -> void:
	_dry_t -= dt
	if _dry_t <= 0.0 and Combat.current and muzzle:
		_dry_t = 0.6
		Combat.current.sound("res://assets/audio/build/tick.wav", muzzle.global_position, -6.0, 0.7)


func speed_k() -> float:
	return 1.0 + 0.3 * kit


func spread_k() -> float:
	return 1.0 / (1.0 + 0.7 * kit)


func flame_range() -> float:
	return FLAME_RANGE + 4.0 * kit


## The long barrel: a jacketed sleeve out of the muzzle (its end where the rounds now leave).
const KIT_LEN := {"minigun": 0.3, "cannon": 0.55, "rockets": 0.25, "flamer": 0.35, "ballista": 0.0, "catapult": 0.0, "oil": 0.0} ## m a kit
const KIT_R := {"minigun": 0.055, "cannon": 0.075, "rockets": 0.0, "flamer": 0.045, "ballista": 0.0, "catapult": 0.0, "oil": 0.0}


func _fit_kit() -> void:
	if kit <= 0 or muzzle == null or float(KIT_LEN[kind]) <= 0.0:
		return
	var l: float = float(KIT_LEN[kind]) * kit
	_kit_muzzle = Node3D.new()
	_kit_muzzle.name = "KitMuzzle"
	_kit_muzzle.position = Vector3(0, 0, -l)
	muzzle.add_child(_kit_muzzle)
	if DisplayServer.get_name() == "headless" or float(KIT_R[kind]) <= 0.0:
		return # (a pod's rails are longer: nothing that shows past its tubes)
	var rad := float(KIT_R[kind])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.13, 0.14)
	mat.metallic = 0.75
	mat.roughness = 0.45
	var sleeve := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rad
	cm.bottom_radius = rad * 1.15
	cm.height = l
	cm.radial_segments = 14
	cm.rings = 1
	cm.material = mat
	sleeve.mesh = cm
	sleeve.rotation.x = -PI * 0.5
	sleeve.position = Vector3(0, 0, -l * 0.5)
	muzzle.add_child(sleeve)
	# the cooling jacket's rings along it
	for k in maxi(int(l / 0.12), 1):
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = rad * 1.35
		rm.bottom_radius = rad * 1.35
		rm.height = 0.025
		rm.radial_segments = 14
		rm.rings = 1
		rm.material = mat
		ring.mesh = rm
		ring.rotation.x = -PI * 0.5
		ring.position = Vector3(0, 0, -0.06 - k * 0.12)
		muzzle.add_child(ring)


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
	(_kit_muzzle if _kit_muzzle else muzzle).add_child(_flash)
	if kind == "flamer":
		_flame_dress()
		return
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


## A flamethrower's stream (fire thrown forward, slowing and rising and going to smoke) and its roar.
func _flame_dress() -> void:
	_fire = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 7.0
	pm.initial_velocity_min = 17.0 * (1.0 + 0.25 * kit)
	pm.initial_velocity_max = 21.0 * (1.0 + 0.25 * kit)
	pm.damping_min = 6.0
	pm.damping_max = 9.0
	pm.gravity = Vector3(0, 2.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	var grow := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.25))
	c.add_point(Vector2(1.0, 3.2))
	grow.curve = c
	pm.scale_curve = grow
	var fade := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.55, 1.0))
	g.add_point(0.35, Color(1.0, 0.45, 0.1, 0.9))
	g.add_point(0.7, Color(0.35, 0.18, 0.1, 0.5))
	g.set_color(g.get_point_count() - 1, Color(0.15, 0.14, 0.13, 0.0))
	fade.gradient = g
	pm.color_ramp = fade
	_fire.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = WheelSpray._puff()
	q.material = fm
	_fire.draw_pass_1 = q
	_fire.amount = 220
	_fire.lifetime = 0.9
	_fire.local_coords = false
	_fire.emitting = false
	_fire.visibility_aabb = AABB(Vector3(-10, -6, -20), Vector3(20, 14, 24))
	(_kit_muzzle if _kit_muzzle else muzzle).add_child(_fire)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.omni_range = 7.0
	l.light_energy = 0.0
	l.position = Vector3(0, 0, -2.5)
	l.name = "FlameLight"
	muzzle.add_child(l)
	_motor = AudioStreamPlayer3D.new()
	var s := (load("res://assets/audio/weapons/flame_loop.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = 74970
	_motor.stream = s
	_motor.unit_size = 9.0
	_motor.volume_db = -80.0
	gun.add_child(_motor)


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
	if kind in MANUAL:
		powered = true # (a crew winds it, loads it, swings it)
	var k: Dictionary = KINDS[kind]
	if kind in ["ballista", "rockets", "cannon"]:
		var t := flight_time(kind, aim.distance_to(turret.global_position), speed_k())
		aim.y += 0.5 * SHELL_DROP * t * t
	var local := node.global_transform.basis.inverse() * (aim - turret.global_position)
	var want_yaw := atan2(-local.x, -local.z)
	var flat := Vector2(local.x, local.z).length()
	var lim: Vector2 = k.pitch
	var want_pitch := clampf(atan2(local.y, flat), lim.x, lim.y)
	if kind == "catapult":
		want_pitch = STONE_ANGLE
		var off := aim - turret.global_position # (by the world's level and up: the machine may be leaning)
		_lob_v = minf(lob_speed(Vector2(off.x, off.z).length(), off.y - STONE_UP, STONE_ANGLE), STONE_MAX)
	var aim_pitch := want_pitch if kind == "catapult" else atan2(local.y, flat)
	var dyaw := 0.0
	var dpitch := 0.0
	if powered:
		var hurt := (0.35 + 0.65 * condition) / (1.0 + 0.2 * kit) # (a long barrel's heavier to swing)
		dyaw = clampf(angle_difference(yaw, want_yaw), -k.yaw_rate * hurt * dt, k.yaw_rate * hurt * dt)
		dpitch = clampf(want_pitch - pitch, -k.pitch_rate * hurt * dt, k.pitch_rate * hurt * dt)
	yaw += dyaw
	pitch += dpitch
	_slew = clampf(0.5 * (absf(dyaw) / (k.yaw_rate * dt) + absf(dpitch) / (k.pitch_rate * dt)), 0.0, 1.0)
	if not powered:
		firing = false
	if firing and not has_ammo():
		_dry(dt)
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
	var gb := _gun_rest.basis * Basis(Vector3.RIGHT, 0.0 if kind == "catapult" else pitch) # (a catapult's laid by its arm's throw, not by tilting it)
	var back := gb * Vector3(0.0, 0.0, float(RECOIL[kind]) * _recoil)
	if kind == "minigun" and _spin > 0.95 and firing:
		back += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.004
	gun.transform = Transform3D(gb, _gun_rest.origin + back)
	if _flash:
		_flash_t -= dt
		_flash.visible = _flash_t > 0.0
	if kind == "flamer" and muzzle and muzzle.has_node("FlameLight"):
		(muzzle.get_node("FlameLight") as OmniLight3D).light_energy = _spin * randf_range(3.0, 5.0)
	if _motor:
		_motor.volume_db = linear_to_db(maxf(_spin * 0.7, 0.0001)) - 2.0
		_motor.pitch_scale = 0.4 + _spin * 0.75
		if _spin > 0.01 and not _motor.playing:
			_motor.play()
		elif _spin <= 0.01 and _motor.playing:
			_motor.stop()
	if _brass:
		_brass.emitting = firing and _spin > 0.95 and powered
	var err := absf(angle_difference(yaw, want_yaw)) + absf(pitch - (aim_pitch if kind != "oil" else pitch))
	on_target = err < float(k.on) * (3.0 if local.length() < 15.0 else 1.0)
	_cool -= dt
	if kind == "minigun":
		_spin = move_toward(_spin, 1.0 if firing and can_spin else 0.0, dt / SPIN_UP)
		_spin_angle = fmod(_spin_angle + _spin * 40.0 * dt, TAU)
		if barrels:
			barrels.transform = Transform3D(_barrels_rest.basis * Basis(Vector3.BACK, _spin_angle), _barrels_rest.origin)
		if firing and on_target and _spin > 0.95:
			while _cool <= 0.0 and has_ammo():
				_cool += 1.0 / (MINIGUN_RATE * rate_k())
				_spend(1.0)
				_minigun_round()
		elif _cool < 0.0:
			_cool = 0.0
	elif kind == "flamer":
		# the pump and the pilot: the stream comes up in a moment and dies as fast
		_spin = move_toward(_spin, 1.0 if firing and on_target and powered else 0.0, dt * 5.0)
		if _fire:
			_fire.emitting = _spin > 0.3
		if _motor:
			_motor.volume_db = linear_to_db(maxf(_spin, 0.0001)) + 2.0
			if _spin > 0.05 and not _motor.playing:
				_motor.play()
			elif _spin <= 0.05 and _motor.playing:
				_motor.stop()
		if _spin > 0.5:
			_spend(dt)
			if _cool <= 0.0:
				_cool = 0.1
				if Combat.current:
					Combat.current.flame(_bore().origin, -_bore().basis.z, flame_range(), FLAME_DPS * 0.1 * rate_k(), machine)
	elif kind == "rockets":
		if firing and on_target and loaded > 0 and _cool <= 0.0:
			_cool = ROCKET_GAP
			_spend(1.0)
			_rocket_shot()
		elif _cool < 0.0:
			_cool = 0.0
		if loaded < ROCKETS and loaded < int(ammo) and powered and can_load and (not firing or loaded == 0):
			_reload_t += dt
			if _reload_t >= ROCKET_RELOAD * reload_k():
				_reload_t = 0.0
				loaded += 1
				_rockets_shown()
				if Combat.current and _rockets.size() > 0:
					Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), _rockets[0].global_position, -10.0, 1.3)
		else:
			_reload_t = 0.0
	elif kind in MANUAL:
		_hand_work(dt, firing, local)
	elif not powered or (not can_load and _cool > 0.0):
		_cool += dt # (the loader stops)
	elif firing and on_target and _cool <= 0.0:
		_cool = CANNON_RELOAD * reload_k()
		_loaded_sound = false
		_spend(1.0)
		_cannon_shot()
	if kind == "cannon" and not _loaded_sound and _cool <= 0.0:
		_loaded_sound = true # (the breech closes on the next round)
		if Combat.current and muzzle:
			Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), gun.global_position, -6.0, 0.8)


func _bore() -> Transform3D:
	if _kit_muzzle:
		return _kit_muzzle.global_transform
	return muzzle.global_transform if muzzle else gun.global_transform


func _minigun_round() -> void:
	var c := Combat.current
	if c == null:
		return
	var b := _bore()
	var fwd := -b.basis.z
	var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * MINIGUN_SPREAD * spread_k()
	var dir := (fwd + spread).normalized()
	_round += 1
	c.hitscan(b.origin, dir, MINIGUN_RANGE, MINIGUN_DAMAGE * (1.0 + 0.15 * kit), MINIGUN_PUSH, machine, _round % 2 == 0)
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
	c.fire_shell(b.origin + dir * 0.1, dir * CANNON_SPEED * speed_k() + machine.velocity_at(b.origin), machine)
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
	var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * ROCKET_SPREAD * spread_k()
	dir = (dir + spread).normalized()
	c.fire_rocket(from + dir * 0.15, dir, machine.velocity_at(from) + dir * ROCKET_SPEED * (speed_k() - 1.0), machine) # (longer rails: off them faster)
	c.shake(from, 0.18, machine, 1.5)
	_recoil_v = 18.0
	c.sound("res://assets/audio/rocket/launch.wav", from, 0.0, randf_range(0.92, 1.08))
	c.muzzle_flash(from, dir, 1.2)
	c.backblast(from - dir * 0.9, -dir)


## The wood age's: loaded by hand, loosed when it's on and loaded (`local`: the aim, in the part's space).
func _hand_work(dt: float, firing: bool, local: Vector3) -> void:
	var reload: float = {"ballista": BOLT_RELOAD, "catapult": STONE_RELOAD, "oil": OIL_RELOAD}[kind]
	if firing and on_target and _cool <= 0.0:
		_cool = reload * reload_k()
		_spend(1.0)
		match kind:
			"ballista":
				_bolt_shot()
			"catapult":
				_stone_shot()
			"oil":
				_oil_shot(Vector2(local.x, local.z).length())
	elif _cool < 0.0:
		_cool = 0.0
	# what's loaded shows: the bolt in its groove, the stone in its bucket (once it's wound back)
	if not _rockets.is_empty():
		_rockets[0].visible = _cool <= reload * 0.35 and has_ammo()
	if kind == "catapult" and barrels:
		_arm = move_toward(_arm, 0.0, dt / (reload * 0.6)) if _arm < 0.99 or _cool < reload * 0.85 else _arm
		barrels.transform = Transform3D(Basis(Vector3.RIGHT, -2.1 * ease(_arm, 0.4)) * _barrels_rest.basis, _barrels_rest.origin)


func _bolt_shot() -> void:
	var c := Combat.current
	if c == null:
		return
	var b := _bore()
	var dir := -gun.global_basis.z
	c.fire_bolt(b.origin + dir * 0.1, dir * BOLT_SPEED * speed_k() + machine.velocity_at(b.origin), machine, fiery)
	machine.apply_impulse(-dir * 120.0, b.origin - machine.global_position)
	c.sound("res://assets/audio/weapons/flip_air.wav", b.origin, -2.0, randf_range(1.6, 1.8))
	c.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), b.origin, -6.0, 0.6)
	_recoil_v = 22.0


## The arm thrown over: the stone (or the pot) off on the arc the arm's laid for.
func _stone_shot() -> void:
	var c := Combat.current
	_arm = 1.0
	if c == null:
		return
	var from := turret.global_position + Vector3.UP * STONE_UP
	var fwd := -turret.global_basis.z
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var dir := (fwd * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	c.fire_stone(from, dir * _lob_v + machine.velocity_at(from), machine, fiery)
	machine.apply_impulse(-dir * 900.0 + Vector3.DOWN * 600.0, from - machine.global_position)
	c.shake(from, 0.25, machine, 1.0)
	c.sound("res://assets/audio/build/heavy_01.wav", from, 2.0, 0.7)
	c.sound("res://assets/audio/weapons/flip_air.wav", from, 0.0, 0.7)


## The cask tipped: burning oil out on the ground ahead, as far as it's aimed (OIL_REACH at most).
func _oil_shot(dist: float) -> void:
	var c := Combat.current
	if c == null:
		return
	var b := _bore()
	var fwd := -turret.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at := b.origin + fwd * clampf(dist, 2.5, OIL_REACH)
	c.oil_fire(at, 2.2, 8.0, machine)
	c.sound("res://assets/audio/weapons/flame_loop.wav", at, 0.0, 0.8)


## The speed (m/s) a throw at `angle` (rad) up needs to come down `x` m off and `y` m up (INF: it can't).
static func lob_speed(x: float, y: float, angle: float) -> float:
	var c := cos(angle)
	var drop := x * tan(angle) - y
	if drop <= 0.01 or x < 0.01:
		return INF
	return sqrt(SHELL_DROP * x * x / (2.0 * c * c * drop))


## Seconds a round of `kind` takes to go `dist` m: a shell at its muzzle speed; a rocket off the rail,
## speeding up while its motor burns, then on at the speed it had. (k: a barrel kit's speed-up.)
static func flight_time(kind: String, dist: float, k := 1.0) -> float:
	if kind == "cannon":
		return dist / (CANNON_SPEED * k)
	if kind == "ballista":
		return dist / (BOLT_SPEED * k)
	if kind == "catapult":
		return dist / (minf(lob_speed(dist, 0.0, STONE_ANGLE), STONE_MAX) * cos(STONE_ANGLE))
	if kind == "oil":
		return 0.0
	if kind == "rockets":
		var v0 := ROCKET_SPEED * k
		var burn_d := v0 * ROCKET_BURN + 0.5 * ROCKET_THRUST * ROCKET_BURN * ROCKET_BURN
		if dist <= burn_d:
			return (-v0 + sqrt(v0 * v0 + 2.0 * ROCKET_THRUST * dist)) / ROCKET_THRUST
		return ROCKET_BURN + (dist - burn_d) / (v0 + ROCKET_THRUST * ROCKET_BURN)
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
		return clampf(_cool / (CANNON_RELOAD * reload_k()), 0.0, 1.0)
	if kind == "rockets":
		return 1.0 - float(loaded) / ROCKETS
	if kind in MANUAL:
		var reload: float = {"ballista": BOLT_RELOAD, "catapult": STONE_RELOAD, "oil": OIL_RELOAD}[kind]
		return clampf(_cool / (reload * reload_k()), 0.0, 1.0)
	return 0.0
