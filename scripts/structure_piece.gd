class_name StructurePiece
extends RigidBody3D
## One piece of a Structure: a beam, a plank, a ring of a chimney, a sheet of a wall, a tank. It stands
## held in place (frozen) while what it rests on stands; rounds, bursts, rams and fire take its hit
## points, and at none it comes apart; left with too little under it, it's let go and falls as
## physics has it (and what rests on it after it).
##
## What it's made of decides how it goes: steel shrugs off rounds but goes under bursts and rams;
## concrete and brick chip under rounds and break under bursts into lumps; wood splinters and burns
## (a fire spreads to the wood touching it, slower wet, in the rain, in snow or mud); a fuel tank
## burns a moment and then goes up, lighting what's round it.

const GROUP := "pieces"
## stuff -> colour, density kg/m3 (as built: a lattice beam's mostly air), how tough (its hit points
## are this times the square root of its volume in m3: a big piece is tougher, not in proportion; at
## least MIN_HP), what a round does to it (x), what a burst does (x), burns, its chips (Combat's).
const STUFF := {
	"steel": {"color": Color(0.36, 0.38, 0.4), "density": 900.0, "tough": 700.0, "round": 0.18, "burst": 1.0, "burns": false, "chip": "metal"},
	"rust": {"color": Color(0.42, 0.22, 0.12), "density": 900.0, "tough": 600.0, "round": 0.25, "burst": 1.0, "burns": false, "chip": "metal"},
	"paint": {"color": Color(0.55, 0.36, 0.08), "density": 900.0, "tough": 650.0, "round": 0.2, "burst": 1.0, "burns": false, "chip": "metal"},
	"sheet": {"color": Color(0.5, 0.52, 0.5), "density": 400.0, "tough": 220.0, "round": 0.5, "burst": 1.2, "burns": false, "chip": "metal"},
	"concrete": {"color": Color(0.55, 0.53, 0.49), "density": 2300.0, "tough": 450.0, "round": 0.35, "burst": 1.0, "burns": false, "chip": "dirt"},
	"brick": {"color": Color(0.46, 0.22, 0.15), "density": 1900.0, "tough": 200.0, "round": 0.4, "burst": 1.1, "burns": false, "chip": "dirt"},
	"wood": {"color": Color(0.5, 0.36, 0.2), "density": 550.0, "tough": 160.0, "round": 0.8, "burst": 1.3, "burns": true, "chip": "dirt"},
	"fuel": {"color": Color(0.62, 0.6, 0.55), "density": 300.0, "tough": 110.0, "round": 1.0, "burst": 1.5, "burns": true, "chip": "metal"},
	"glass": {"color": Color(0.55, 0.65, 0.7), "density": 2500.0, "tough": 60.0, "round": 1.0, "burst": 2.0, "burns": false, "chip": "metal"},
}
const MIN_HP := 30.0
const BURN_DPS := 0.07 ## of its hit points a second while it burns (wood: ~14 s to burn through)
const SPREAD_EVERY := 1.2 ## s between tries at lighting the wood touching it
const FUEL_FUSE := 1.6 ## s a lit tank burns before it goes up

signal broke(piece: StructurePiece)

var stuff := "steel"
var hp := 100.0
var max_hp := 100.0
var size := Vector3.ONE
var shape := "box" ## box, cyl (round about y), xcyl (round about x)
var structure: Node ## (its Structure)
var touching: Array[StructurePiece] = []
var below: Array[StructurePiece] = [] ## (touching and lower: what it rests on)
var below_at_first := 0
var grounded := false
var standing := true
var burning := false
var burn_t := 0.0
var charred := 0.0
var _spread_t := 0.0
var _fire: Node3D
var _mat: Material


## A piece of `p_stuff`, `p_size` (for a cylinder: x the diameter, y its length), at `xf` (its middle).
static func make(p_shape: String, p_size: Vector3, p_stuff: String, xf: Transform3D, colour := Color(0, 0, 0, 0)) -> StructurePiece:
	var s := StructurePiece.new()
	s.shape = p_shape
	s.size = p_size
	s.stuff = p_stuff
	s.transform = xf
	var k: Dictionary = STUFF[p_stuff]
	var vol := p_size.x * p_size.y * p_size.z * (0.785 if p_shape != "box" else 1.0)
	s.mass = maxf(vol * float(k.density), 5.0)
	s.max_hp = maxf(sqrt(vol) * float(k.tough), MIN_HP)
	s.hp = s.max_hp
	s.freeze = true
	s.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	s.collision_layer = 1
	s.collision_mask = 1 | 2 | 4
	s.continuous_cd = false
	var cs := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour if colour.a > 0.0 else k.color
	mat.roughness = 0.8 if p_stuff in ["wood", "concrete", "brick"] else 0.55
	mat.metallic = 0.4 if p_stuff in ["steel", "rust", "paint", "sheet", "fuel"] else 0.0
	if p_shape == "box":
		var b := BoxShape3D.new()
		b.size = p_size - Vector3.ONE * 0.02 # (a hair apart: let go, they don't spring off each other)
		cs.shape = b
		var bm := BoxMesh.new()
		bm.size = p_size
		bm.material = mat
		mi.mesh = bm
	else:
		var c := CylinderShape3D.new()
		c.radius = p_size.x * 0.5 - 0.01
		c.height = p_size.y - 0.02
		cs.shape = c
		var cm := CylinderMesh.new()
		cm.top_radius = p_size.x * 0.5
		cm.bottom_radius = p_size.x * 0.5
		cm.height = p_size.y
		cm.radial_segments = 20
		cm.material = mat
		mi.mesh = cm
		if p_shape == "xcyl":
			cs.rotation.z = PI * 0.5
			mi.rotation.z = PI * 0.5
	s.add_child(cs)
	s.add_child(mi)
	PaintedLook.apply(s)
	s._mat = mi.get_surface_override_material(0)
	s.add_to_group(GROUP)
	return s


## The box round it in the world (for working out what touches what).
func world_aabb() -> AABB:
	var e := size * 0.5
	if shape == "xcyl":
		e = Vector3(size.y, size.x, size.x) * 0.5
	elif shape == "cyl":
		e = Vector3(size.x, size.y, size.x) * 0.5
	var a := AABB(-e, e * 2.0)
	return global_transform * a


func chip_kind() -> String:
	return str(STUFF[stuff].chip)


## A round (`burst` false), a burst's share, a ram's blow: what it does to this stuff.
func hit(damage: float, at: Vector3, dir: Vector3, burst := false) -> void:
	if hp <= 0.0:
		return
	var k: Dictionary = STUFF[stuff]
	hp -= damage * float(k.burst if burst else k.round)
	if not standing and is_instance_valid(self):
		apply_impulse(dir * damage * 0.4, at - global_position)
	if hp <= 0.0:
		if stuff == "fuel":
			_go_up.call_deferred() # (holed and lit: it goes up)
		else:
			_come_apart(dir)
	elif burst and bool(k.burns) and randf() < 0.35:
		ignite()


## Flame on it: wood and fuel catch (less likely wet); anything else only scorches.
func heat(amount: float) -> void:
	if not bool(STUFF[stuff].burns):
		hit(amount * 0.15, global_position, Vector3.UP, true)
		return
	if randf() < 0.5 * (1.0 - _wet() * 0.8):
		ignite()


func ignite() -> void:
	if burning or hp <= 0.0 or not bool(STUFF[stuff].burns):
		return
	burning = true
	burn_t = 0.0
	_fire = _make_fire()


## How wet it is: the weather's rain and wet ground, and snow, mud or a bog under it.
func _wet() -> float:
	var w := maxf(Weather.wet_now, Weather.rain_now)
	var t: Node = structure.get("terrain") if structure else null
	if t and t.has_method("surface_at"):
		var lab := str((t.call("surface_at", global_position) as Surface).label)
		if lab in ["snow", "ice", "black_ice"]:
			w = maxf(w, 0.8)
		elif lab in ["mud", "bog", "wet"]:
			w = maxf(w, 0.5)
	return clampf(w, 0.0, 1.0)


func _physics_process(dt: float) -> void:
	if not burning:
		return
	burn_t += dt
	var wet := _wet()
	if stuff == "fuel":
		if burn_t > FUEL_FUSE:
			_go_up()
		return
	# the rain puts a fire out in time; it burns slower wet
	if wet > 0.6 and randf() < dt * wet * 0.08:
		_put_out()
		return
	hp -= max_hp * BURN_DPS * (1.0 - wet * 0.6) * dt
	charred = clampf(burn_t / 10.0, 0.0, 1.0)
	if _mat is ShaderMaterial and fmod(burn_t, 0.5) < dt:
		(_mat as ShaderMaterial).set_shader_parameter("albedo", Color(STUFF[stuff].color).lerp(Color(0.06, 0.05, 0.045), charred))
	_spread_t += dt
	if _spread_t >= SPREAD_EVERY:
		_spread_t = 0.0
		for n in touching:
			if is_instance_valid(n) and n.hp > 0.0 and randf() < 0.3 * (1.0 - wet * 0.85):
				n.ignite()
	if hp <= 0.0:
		_come_apart(Vector3.UP)


func _put_out() -> void:
	burning = false
	if is_instance_valid(_fire):
		_fire.queue_free()
	_fire = null


## A fuel tank going up: a big burst, everything round it lit.
func _go_up() -> void:
	if not is_inside_tree() or get_meta("gone_up", false):
		return
	set_meta("gone_up", true)
	burning = false
	hp = 0.0
	var at := global_position
	var c := Combat.current
	if c:
		c.explode(at, 6.0 + size.length() * 0.6, 420.0, 9000.0, null, false, Vector3.DOWN)
		c.explode.call_deferred(at + Vector3.UP * 1.5, 4.0, 120.0, 4000.0, null, true)
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 9.0
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = 1
	for h: Dictionary in get_world_3d().direct_space_state.intersect_shape(q, 64):
		var p := h.collider as StructurePiece
		if p and p != self and randf() < 0.7:
			p.ignite()
	_come_apart(Vector3.UP)


## Out of hit points: in splinters, lumps or panels, flung on along `dir`.
func _come_apart(dir: Vector3) -> void:
	hp = 0.0
	_put_out()
	var c := Combat.current
	if c and is_inside_tree():
		var n := clampi(int(size.length() * 3.0), 2, 7)
		var csz := (size / maxf(float(n) * 0.6, 1.0)).clamp(Vector3.ONE * 0.08, Vector3.ONE * 1.4)
		if shape == "xcyl":
			csz = Vector3(csz.y, csz.x, csz.x)
		for k in n:
			var off := Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)) * size * 0.7
			var v := (dir * randf_range(2.0, 6.0) + Vector3(randf_range(-2, 2), randf_range(1, 4), randf_range(-2, 2)))
			c._chunk(Transform3D(global_basis, global_transform * off), csz, _mat, mass / float(n), v, stuff in ["concrete", "brick"])
		c._impact(global_position, Vector3.UP, chip_kind(), 0.8)
		if stuff in ["concrete", "brick"]:
			c._burst(global_position, "dirt", 0.8)
		var snd := "res://assets/audio/explosion/debris_metal_0%d.wav" % randi_range(1, 2)
		c.sound(snd, global_position, 0.0, randf_range(0.6, 0.9) if stuff in ["steel", "rust", "paint", "sheet"] else 1.2)
	broke.emit(self)
	queue_free()


## Let go: falls from here as physics has it, turning about `pivot` at `spin` (rad/s) to start.
func let_go(pivot: Vector3, spin: Vector3) -> void:
	if not standing:
		return
	standing = false
	freeze = false
	sleeping = false
	linear_velocity = spin.cross(global_position - pivot)
	angular_velocity = spin
	set_meta("age", 0.0)


static var _fires := 0 ## (how many fires are being drawn: past MAX_FIRES a fire's only its light)
const MAX_FIRES := 40


func _make_fire() -> Node3D:
	if DisplayServer.get_name() == "headless":
		return null
	var f := Node3D.new()
	add_child(f)
	f.top_level = true
	f.global_position = global_position + Vector3.UP * size.y * 0.3
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.18)
	l.light_energy = 2.5
	l.omni_range = 5.0
	f.add_child(l)
	if _fires >= MAX_FIRES:
		return f
	_fires += 1
	f.tree_exiting.connect(func() -> void: StructurePiece._fires -= 1)
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = (size * 0.4).clamp(Vector3.ONE * 0.1, Vector3(1.5, 1.0, 1.5))
	m.direction = Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 2.2
	m.gravity = Vector3(0, 1.5, 0)
	m.scale_min = 0.6
	m.scale_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
	g.add_point(0.35, Color(1.0, 0.35, 0.08, 0.7))
	g.set_color(g.get_point_count() - 1, Color(0.15, 0.12, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 1.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = WheelSpray._puff()
	q.material = mat
	p.draw_pass_1 = q
	p.amount = 24
	p.lifetime = 0.9
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 10, 8))
	f.add_child(p)
	# smoke over it
	var sm := GPUParticles3D.new()
	var smm := ParticleProcessMaterial.new()
	smm.direction = Vector3.UP
	smm.spread = 15.0
	smm.initial_velocity_min = 1.2
	smm.initial_velocity_max = 2.4
	smm.gravity = Vector3(0.3, 0.8, 0.0)
	smm.scale_min = 1.2
	smm.scale_max = 2.4
	var sg := Gradient.new()
	sg.set_color(0, Color(0.1, 0.09, 0.08, 0.0))
	sg.add_point(0.15, Color(0.1, 0.09, 0.08, 0.6))
	sg.set_color(sg.get_point_count() - 1, Color(0.2, 0.19, 0.18, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	smm.color_ramp = sgt
	sm.process_material = smm
	var sq := QuadMesh.new()
	sq.size = Vector2(1.4, 1.4)
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_texture = WheelSpray._puff()
	sq.material = smat
	sm.draw_pass_1 = sq
	sm.amount = 18
	sm.lifetime = 4.0
	sm.local_coords = false
	sm.position = Vector3.UP * 1.0
	sm.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 20, 16))
	f.add_child(sm)
	return f
