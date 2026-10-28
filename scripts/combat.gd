class_name Combat
extends Node3D
## Everything weapons do to the world, pooled so a long fight costs no more than a short one:
## rounds (hitscan: a ray, a tracer now and then), shells in flight (stepped with gravity, swept
## so a fast one never passes through), bursts (damage and a heave falling off over the radius, a
## crater dug in the ground), impacts (sparks off metal, dirt off the ground), muzzle flashes, the
## parts that come off (debris that tumbles and lies there a while) and the sounds. Rockets fly
## under their motor's thrust and then fall, each a body, a flame, a light and a smoke trail
## (pooled). The arena's Breakables chip under rounds and come apart under bursts into chunks;
## a burst on the ground leaves its crater and a scorch.

static var current: Combat

## Something went off at `at`: the view shakes by `amount` (0..1) if it's yours, less the further off
## it is (`reach` m to nothing).
signal shook(at: Vector3, amount: float, owner: Machine, punch: float)
## A round, a shell or a burst of yours took something off a machine.
signal hit_confirmed(owner: Machine, killed: bool)
## A part of `victim` took `amount` at `at` (by `by`, maybe nobody); `broke`: it came off.
signal part_hit(victim: Machine, id: String, at: Vector3, amount: float, by: Machine, broke: bool)

const RAY_MASK := 1 | 2 | 4 ## the ground, machines, debris
const MAX_DEBRIS := 140
const DEBRIS_LIFE := 30.0
const TRACERS := 24
const SOUNDS := 24
const SHELL_GRAVITY := MachineGun.SHELL_DROP
const ROCKET_VIS := 18

var terrain: Node
var _shells: Array[Dictionary] = []
var _rockets: Array[Dictionary] = []
var _rocket_vis: Array[Node3D] = []
var _rocket_trails: Array[GPUParticles3D] = []
var _rocket_i := 0
var _clods: Array[GPUParticles3D] = []
var _clod_i := 0
const SCORCHES := 32
var _scorches: Array[Decal] = []
var _scorch_i := 0
static var _scorch_tex: ImageTexture
var _tracers: Array[MeshInstance3D] = []
var _tracer_life: Array[float] = []
var _tracer_i := 0
var _players: Array[AudioStreamPlayer3D] = []
var _player_i := 0
var _streams := {}
var _debris: Array[RigidBody3D] = []
var _fx: Array[GPUParticles3D] = []
var _fx_i := 0
var _flash: OmniLight3D
var _flash_t := 0.0
var _headless := false


func _ready() -> void:
	current = self
	name = "Combat"
	_headless = DisplayServer.get_name() == "headless"
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = Color(1.0, 0.75, 0.35)
	tmat.emission_enabled = true
	tmat.emission = Color(1.0, 0.6, 0.2)
	tmat.emission_energy_multiplier = 6.0
	var tmesh := BoxMesh.new()
	tmesh.size = Vector3(0.025, 0.025, 1.0)
	tmesh.material = tmat
	for i in TRACERS:
		var t := MeshInstance3D.new()
		t.mesh = tmesh
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		t.top_level = true
		add_child(t)
		_tracers.append(t)
		_tracer_life.append(0.0)
	for i in SOUNDS:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		p.max_polyphony = 1
		add_child(p)
		_players.append(p)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.7, 0.35)
	_flash.omni_range = 9.0
	_flash.visible = false
	_flash.top_level = true
	add_child(_flash)
	if not _headless:
		for i in 12:
			_fx.append(_make_fx())
		for i in ROCKET_VIS:
			_make_rocket_vis()


func _exit_tree() -> void:
	if current == self:
		current = null


# --- Rounds and shells ---------------------------------------------------------------------------

## A round from `from` along `dir`: what it hits takes `damage` and a push; a tracer if asked.
func hitscan(from: Vector3, dir: Vector3, reach: float, damage: float, push: float, owner: Machine, tracer: bool) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, RAY_MASK)
	if is_instance_valid(owner):
		q.exclude = [owner.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := from + dir * reach
	if not hit.is_empty():
		end = hit.position
		var body: Object = hit.collider
		if body is Machine:
			(body as Machine).hit(end, dir, damage, push, owner)
			_impact(end, hit.normal, "metal", 0.35)
			if is_instance_valid(owner) and (body as Machine).team != owner.team:
				hit_confirmed.emit(owner, false)
		elif body is Breakable:
			var br := body as Breakable
			br.hit(damage, end, dir)
			_impact(end, hit.normal, br.chip_kind(), 0.4)
		elif body is RigidBody3D:
			(body as RigidBody3D).apply_impulse(dir * push, end - (body as RigidBody3D).global_position)
			_impact(end, hit.normal, "metal", 0.3)
		else:
			_impact(end, hit.normal, "dirt", 0.35)
	if tracer:
		_tracer(from + dir * 2.0, end)


func fire_shell(from: Vector3, vel: Vector3, owner: Machine) -> void:
	_shells.append({"pos": from, "vel": vel, "owner": owner, "life": 6.0})


## A rocket off its rail at `from` along `dir`, carrying `inherit` (the launcher's own speed).
func fire_rocket(from: Vector3, dir: Vector3, inherit: Vector3, owner: Machine) -> void:
	var vis := -1
	if not _rocket_vis.is_empty():
		vis = _rocket_i
		_rocket_i = (_rocket_i + 1) % _rocket_vis.size()
		var tr := _rocket_trails[vis]
		tr.global_position = from
		tr.restart()
		tr.emitting = true
	_rockets.append({"pos": from, "vel": dir * MachineGun.ROCKET_SPEED + inherit, "owner": owner, "life": 7.0,
		"burn": MachineGun.ROCKET_BURN, "vis": vis, "wob": Vector3.ZERO})


func _physics_process(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	_fly_rockets(space, dt)
	for i in range(_shells.size() - 1, -1, -1):
		var s := _shells[i]
		var p: Vector3 = s.pos
		var v: Vector3 = s.vel + Vector3.DOWN * SHELL_GRAVITY * dt
		var n := p + v * dt
		var q := PhysicsRayQueryParameters3D.create(p, n, RAY_MASK)
		if is_instance_valid(s.owner):
			q.exclude = [(s.owner as Machine).get_rid()]
		var hit := space.intersect_ray(q)
		s.life = float(s.life) - dt
		if not hit.is_empty():
			explode(hit.position, MachineGun.CANNON_RADIUS, MachineGun.CANNON_DAMAGE, MachineGun.CANNON_PUSH, s.owner,
				hit.collider != terrain, v.normalized())
			_shells.remove_at(i)
			continue
		if float(s.life) <= 0.0:
			_shells.remove_at(i)
			continue
		s.pos = n
		s.vel = v
		if randf() < 0.5:
			_tracer(p, n + v.normalized() * 1.5, 0.04)


func _fly_rockets(space: PhysicsDirectSpaceState3D, dt: float) -> void:
	for i in range(_rockets.size() - 1, -1, -1):
		var r := _rockets[i]
		var p: Vector3 = r.pos
		var v: Vector3 = r.vel
		var burn: float = r.burn
		if burn > 0.0:
			# the motor along its nose, and a wander that changes a few times a second
			if randf() < dt * 6.0:
				r.wob = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * MachineGun.ROCKET_WOBBLE
			var wob: Vector3 = r.wob
			v += (v.normalized() * MachineGun.ROCKET_THRUST + wob - v.normalized() * wob.dot(v.normalized())) * dt
			r.burn = burn - dt
		v += Vector3.DOWN * SHELL_GRAVITY * dt
		v -= v * 0.03 * dt
		var n := p + v * dt
		var q := PhysicsRayQueryParameters3D.create(p, n, RAY_MASK)
		if is_instance_valid(r.owner):
			q.exclude = [(r.owner as Machine).get_rid()]
		var hit := space.intersect_ray(q)
		r.life = float(r.life) - dt
		var vis: int = r.vis
		if not hit.is_empty() or float(r.life) <= 0.0:
			if not hit.is_empty():
				explode(hit.position, MachineGun.ROCKET_RADIUS, MachineGun.ROCKET_DAMAGE, MachineGun.ROCKET_PUSH, r.owner,
					hit.collider != terrain, v.normalized())
			if vis >= 0:
				_rocket_vis[vis].visible = false
				_rocket_trails[vis].emitting = false
			_rockets.remove_at(i)
			continue
		r.pos = n
		r.vel = v
		if vis >= 0:
			var body := _rocket_vis[vis]
			body.visible = true
			body.global_transform = Transform3D(Basis.looking_at(v, Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT), n)
			var burning := float(r.burn) > 0.0
			body.get_child(1).visible = burning # (the flame and its light)
			body.get_child(2).visible = burning
			var tr := _rocket_trails[vis]
			tr.global_position = n - v.normalized() * 0.35
			if not burning and float(r.burn) < -0.4:
				tr.emitting = false


## The view shakes (Game listens): `amount` 0..1 at `at` (fully for its owner, less further off for
## anyone else), the field of view punched open `punch` degrees.
func shake(at: Vector3, amount: float, owner: Machine, punch := 0.0) -> void:
	shook.emit(at, amount, owner, punch)


## Lumps of earth thrown out of a crater, falling and bouncing (a pool of emitters).
func _throw_clods(at: Vector3, radius: float) -> void:
	if _headless:
		return
	if _clods.size() < 6:
		var p := GPUParticles3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.09, 0.1)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.24, 0.18, 0.12)
		m.roughness = 1.0
		bm.material = m
		p.draw_pass_1 = bm
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 50.0
		pm.gravity = Vector3(0, -9.8, 0)
		pm.angular_velocity_min = -400.0
		pm.angular_velocity_max = 400.0
		pm.scale_min = 0.5
		pm.scale_max = 2.2
		pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		pm.collision_bounce = 0.15
		pm.collision_friction = 0.8
		pm.particle_flag_rotate_y = true
		p.process_material = pm
		p.amount = 48
		p.lifetime = 4.0
		p.one_shot = true
		p.explosiveness = 0.95
		p.local_coords = false
		p.top_level = true
		p.visibility_aabb = AABB(Vector3(-20, -6, -20), Vector3(40, 30, 40))
		add_child(p)
		_clods.append(p)
	var e := _clods[_clod_i]
	_clod_i = (_clod_i + 1) % 6
	var pm2 := e.process_material as ParticleProcessMaterial
	pm2.initial_velocity_min = 4.0 + radius
	pm2.initial_velocity_max = 8.0 + radius * 2.5
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm2.emission_sphere_radius = radius * 0.4
	e.global_position = at + Vector3.UP * 0.2
	e.restart()
	e.emitting = true


## The launcher's back-blast: a cloud of dust and smoke behind the pod.
func backblast(at: Vector3, dir: Vector3) -> void:
	_burst(at, "smoke", 0.45, dir)


func _make_rocket_vis() -> void:
	var root := Node3D.new()
	root.top_level = true
	root.visible = false
	add_child(root)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.2, 0.22, 0.13)
	bmat.roughness = 0.6
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.055
	cyl.bottom_radius = 0.06
	cyl.height = 0.75
	cyl.radial_segments = 10
	cyl.rings = 1
	cyl.material = bmat
	body.mesh = cyl
	body.rotation = Vector3(-PI * 0.5, 0.0, 0.0) # (along -z: its nose)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.albedo_texture = WheelSpray._puff()
	fmat.albedo_color = Color(1.0, 0.7, 0.35)
	var flame := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.material = fmat
	flame.mesh = q
	flame.position = Vector3(0, 0, 0.45)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 3.0
	light.omni_range = 5.0
	light.position = Vector3(0, 0, 0.6)
	root.add_child(light)
	_rocket_vis.append(root)
	# its smoke: a grey trail left in the air, thinning and spreading as it drifts up
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = WheelSpray._puff()
	mat.roughness = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = mat
	var m := ParticleProcessMaterial.new()
	var fade := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.82, 0.78, 0.55))
	g.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	fade.gradient = g
	m.color_ramp = fade
	var grow := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(1.0, 1.0))
	grow.curve = c
	m.scale_curve = grow
	m.scale_min = 1.2
	m.scale_max = 2.2
	m.spread = 180.0
	m.initial_velocity_min = 0.2
	m.initial_velocity_max = 0.8
	m.gravity = Vector3(0, 0.25, 0)
	m.damping_min = 0.3
	m.damping_max = 0.6
	var p := GPUParticles3D.new()
	p.process_material = m
	p.draw_pass_1 = quad
	p.amount = 300
	p.lifetime = 2.4
	p.fixed_fps = 60
	p.local_coords = false
	p.emitting = false
	p.top_level = true
	p.visibility_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(p)
	_rocket_trails.append(p)


## A burst at `at`: every machine part within `radius` takes damage falling off with distance and
## is heaved away; on the ground a crater; flash, fire, smoke, dirt, the bang.
func explode(at: Vector3, radius: float, damage: float, push: float, owner: Machine, on_machine := false,
		dir := Vector3.DOWN) -> void:
	for m: Node in get_tree().get_nodes_in_group("machines"):
		var mach := m as Machine
		if not is_instance_valid(mach) or not mach.alive:
			continue
		if mach.global_position.distance_to(at) > radius + 6.0:
			continue
		var before := mach.health()
		var kind := "patlama"
		if is_equal_approx(radius, MachineGun.CANNON_RADIUS):
			kind = "top"
		elif is_equal_approx(radius, MachineGun.ROCKET_RADIUS):
			kind = "roket"
		mach.blast(at, radius, damage, push, owner, kind)
		if is_instance_valid(owner) and mach.team != owner.team and (not mach.alive or mach.health() < before):
			hit_confirmed.emit(owner, not mach.alive)
	for n: Node in get_tree().get_nodes_in_group(Breakable.GROUP):
		var br := n as Breakable
		if br.broken:
			continue
		var reach := br.size.length() * 0.5
		var d := maxf(br.center().distance_to(at) - reach * 0.6, 0.0)
		if d < radius:
			br.hit(damage * (1.0 - 0.5 * d / radius), at, (br.center() - at).normalized(), true)
	for d in _debris:
		if is_instance_valid(d) and d.global_position.distance_to(at) < radius * 2.0:
			var away := (d.global_position - at)
			d.apply_impulse(away.normalized() * push * 0.05 * (1.0 - away.length() / (radius * 2.0)) + Vector3.UP * 30.0)
	if not on_machine and terrain and terrain.has_method("dig_crater"):
		terrain.call("dig_crater", at, radius * 0.7, 0.2 + radius * 0.14)
		if terrain.has_method("commit_digs"):
			terrain.call("commit_digs")
		scorch(at, radius * 0.9)
	_burst(at, "explosion", 1.0)
	_burst(at, "dirt" if not on_machine else "metal", 1.0, -dir)
	# what's left hanging in the air after, the sparks thrown, the shock running out over the ground
	_burst(at + Vector3.UP * 0.6, "column", clampf(radius / 3.0, 0.4, 1.2))
	_burst(at, "embers", clampf(radius / 3.0, 0.4, 1.0), Vector3.UP)
	_shock(at, radius)
	if not on_machine:
		_throw_clods(at, radius)
	shake(at, clampf(radius / 3.0, 0.2, 1.0) * 0.9, null)
	_flash.global_position = at + Vector3.UP * 0.8
	_flash.light_energy = 14.0
	_flash.visible = true
	_flash_t = 0.12
	sound("res://assets/audio/explosion/close_0%d.wav" % randi_range(1, 3), at, 6.0, randf_range(0.9, 1.05))
	if on_machine:
		sound("res://assets/audio/explosion/debris_metal_0%d.wav" % randi_range(1, 2), at, 0.0, 1.0)


func _process(dt: float) -> void:
	for i in _tracers.size():
		if _tracer_life[i] > 0.0:
			_tracer_life[i] -= dt
			if _tracer_life[i] <= 0.0:
				_tracers[i].visible = false
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash.light_energy *= 0.8
		if _flash_t <= 0.0:
			_flash.visible = false
	for i in range(_debris.size() - 1, -1, -1):
		var d := _debris[i]
		if not is_instance_valid(d):
			_debris.remove_at(i)
			continue
		var age: float = d.get_meta("age", 0.0) + dt
		d.set_meta("age", age)
		if age > DEBRIS_LIFE or d.global_position.y < -200.0:
			d.queue_free()
			_debris.remove_at(i)


func _tracer(a: Vector3, b: Vector3, life := 0.05) -> void:
	var t := _tracers[_tracer_i]
	_tracer_life[_tracer_i] = life
	_tracer_i = (_tracer_i + 1) % TRACERS
	var len := a.distance_to(b)
	if len < 0.1:
		return
	t.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT),
		(a + b) * 0.5)
	t.scale = Vector3(1.0, 1.0, minf(len, 30.0))
	t.visible = true


func muzzle_flash(at: Vector3, dir: Vector3, size: float) -> void:
	_flash.global_position = at + dir * 0.2
	_flash.light_energy = maxf(_flash.light_energy, 3.0 * size)
	_flash.visible = true
	_flash_t = maxf(_flash_t, 0.05)
	if size > 1.0:
		_burst(at + dir * 0.3, "flash", size / 2.2, dir)


## The cannon's blast raising the ground's dust round the muzzle.
func dust_ring(at: Vector3, _owner: Machine) -> void:
	_burst(at + Vector3.DOWN * 1.0, "smoke", 0.6)


# --- Machines coming apart -----------------------------------------------------------------------

## A part off a machine: its model as a tumbling body, flung by what broke it.
func debris(id: String, xf: Transform3D, vel: Vector3, spin: Vector3, scene: PackedScene) -> void:
	var b := RigidBody3D.new()
	b.collision_layer = 4
	b.collision_mask = 1 | 2 | 4
	b.mass = float(Parts.def(id).mass)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(Parts.def(id).size) * Parts.CELL * 0.85
	cs.shape = box
	b.add_child(cs)
	var model := scene.instantiate() as Node3D
	PaintedLook.apply(model)
	b.add_child(model)
	add_child(b)
	b.global_transform = xf
	b.linear_velocity = vel
	b.angular_velocity = spin
	b.set_meta("age", 0.0)
	_debris.append(b)
	while _debris.size() > MAX_DEBRIS:
		var old: RigidBody3D = _debris.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## A Breakable come apart: chunks of what it was made of, flung from what broke it, dust; a drum
## goes up.
func shatter(br: Breakable, dir: Vector3, from_burst: bool) -> void:
	if not is_instance_valid(br):
		return
	var k: Dictionary = Breakable.KINDS[br.kind]
	var xf := br.global_transform
	var sz := br.size
	var n := int(k.chunks)
	var mass_total := sz.x * sz.y * sz.z * float(k.density)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = k.color
	mat.roughness = 0.9
	mat.metallic = 0.4 if br.kind in ["container", "drum"] else 0.0
	mat.vertex_color_use_as_albedo = br.kind in ["block", "barrier", "sandbags"] # (the lumps' faces shaded)
	if mat.vertex_color_use_as_albedo:
		mat.albedo_color = k.color
	# chunks over its volume: a grid of pieces, each a little smaller and off-square
	var cells: Array[Vector3] = []
	var nx := maxi(int(ceil(pow(n * sz.x * sz.x / (sz.y * sz.z), 1.0 / 3.0))), 1)
	var ny := maxi(int(ceil(pow(n * sz.y * sz.y / (sz.x * sz.z), 1.0 / 3.0))), 1)
	var nz := maxi(int(ceil(float(n) / (nx * ny))), 1)
	for ix in nx:
		for iy in ny:
			for iz in nz:
				cells.append(Vector3((ix + 0.5) / nx - 0.5, (iy + 0.5) / ny, (iz + 0.5) / nz - 0.5))
	cells.shuffle()
	var piece := Vector3(sz.x / nx, sz.y / ny, sz.z / nz)
	var flat := br.kind in ["container", "crate"] # (panels and planks: thin)
	for i in mini(n, cells.size()):
		var local := cells[i] * sz
		var csz := piece * Vector3(randf_range(0.6, 1.0), randf_range(0.6, 1.0), randf_range(0.6, 1.0))
		if flat:
			csz[randi() % 3] = 0.04 if br.kind == "container" else 0.03
		var at := xf * local
		var away := (at - (br.center() - dir * 0.5)).normalized()
		var v := away * randf_range(3.0, 9.0) * (1.4 if from_burst else 0.6) + Vector3.UP * randf_range(1.5, 5.0)
		_chunk(Transform3D(xf.basis * Basis.from_euler(Vector3(randf(), randf(), randf()) * 0.4), at), csz, mat,
			maxf(mass_total / n, 2.0), v, br.kind in ["block", "barrier", "sandbags"])
	var mid := br.center()
	_burst(mid, "smoke", clampf(sz.length() / 3.0, 0.4, 1.2))
	_burst(mid, br.chip_kind(), 1.0, Vector3.UP)
	var snd := "res://assets/audio/explosion/debris_metal_0%d.wav" % randi_range(1, 2)
	if br.kind in ["block", "barrier", "sandbags"]:
		snd = "res://assets/audio/impact/dirt_0%d.wav" % randi_range(1, 3)
	elif br.kind == "crate":
		snd = "res://assets/audio/impact/dirt_0%d.wav" % randi_range(1, 3)
	sound(snd, mid, 3.0, randf_range(0.7, 0.85))
	var is_drum := br.kind == "drum"
	br.queue_free()
	if is_drum:
		explode(mid, 4.0, 110.0, 2500.0, null, false)
		_burst(mid, "explosion", 1.6)


func _chunk(xf: Transform3D, csz: Vector3, mat: Material, mass_kg: float, vel: Vector3, rough := false) -> void:
	var b := RigidBody3D.new()
	b.collision_layer = 4
	b.collision_mask = 1 | 2 | 4
	b.mass = mass_kg
	var cs := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	if rough:
		# a broken lump: a box with its corners knocked about, faces flat-shaded
		var pts := PackedVector3Array()
		for x: float in [-0.5, 0.5]:
			for y: float in [-0.5, 0.5]:
				for z: float in [-0.5, 0.5]:
					pts.append(Vector3(x, y, z) * csz * Vector3(randf_range(0.6, 1.15), randf_range(0.6, 1.15), randf_range(0.6, 1.15)))
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		cs.shape = shape
		mi.mesh = _lump(pts, mat)
	else:
		var box := BoxShape3D.new()
		box.size = csz
		cs.shape = box
		var bm := BoxMesh.new()
		bm.size = csz
		bm.material = mat
		mi.mesh = bm
	b.add_child(cs)
	b.add_child(mi)
	add_child(b)
	b.global_transform = xf
	b.linear_velocity = vel
	b.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 6.0
	b.set_meta("age", 0.0)
	_debris.append(b)
	while _debris.size() > MAX_DEBRIS:
		var old: RigidBody3D = _debris.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## A lump's mesh from its eight corners (0..7 as x, y, z go -/+): six four-sided faces, flat-shaded,
## each a shade off the next (broken faces catching the light differently).
static func _lump(p: PackedVector3Array, mat: Material) -> ArrayMesh:
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var d: Vector3 = p[f[3]]
		var shade := randf_range(0.75, 1.0)
		st.set_color(Color(shade, shade, shade))
		st.set_normal((b - a).cross(c - a).normalized())
		for v: Vector3 in [a, b, c, a, c, d]:
			st.add_vertex(v)
	st.generate_normals()
	st.set_material(mat)
	var m := st.commit()
	return m


## The shock of a burst: a pale ring running out over the ground and fading.
func _shock(at: Vector3, radius: float) -> void:
	if _headless:
		return
	if _ring_tex == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var r := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
				var a := clampf(1.0 - absf(r - 0.85) / 0.12, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 0.95, 0.85, a * a))
		_ring_tex = ImageTexture.create_from_image(img)
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _ring_tex
	m.albedo_color = Color(1, 1, 1, 0.6)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	mi.global_position = at + Vector3.UP * 0.25
	mi.scale = Vector3.ONE * 0.5
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 5.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)


static var _ring_tex: ImageTexture


## A blackened patch on the ground where a burst went off (pooled: the oldest goes).
func scorch(at: Vector3, radius: float) -> void:
	if _headless:
		return
	if _scorch_tex == null:
		_scorch_tex = _make_scorch()
	var d: Decal
	if _scorches.size() < SCORCHES:
		d = Decal.new()
		d.texture_albedo = _scorch_tex
		d.modulate = Color(1, 1, 1, 0.9)
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.cull_mask = 1
		add_child(d)
		_scorches.append(d)
	else:
		d = _scorches[_scorch_i]
		_scorch_i = (_scorch_i + 1) % SCORCHES
	d.size = Vector3(radius * 2.4, 3.0, radius * 2.4)
	d.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), at)


## A scorch: a dark, soot-black middle, broken and streaked toward its edge, fading out.
static func _make_scorch() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.06
	var rays := FastNoiseLite.new()
	rays.frequency = 2.5
	for y in n:
		for x in n:
			var p := Vector2(x - n * 0.5, y - n * 0.5) / (n * 0.5)
			var r := p.length()
			var ang := atan2(p.y, p.x)
			var edge := 0.75 + 0.25 * rays.get_noise_1d(ang * 3.0) + 0.15 * noise.get_noise_2d(x, y)
			var a := clampf(1.0 - smoothstep(edge * 0.4, edge, r), 0.0, 1.0)
			a *= 0.75 + 0.25 * noise.get_noise_2d(x * 2.0, y * 2.0)
			var c := lerpf(0.03, 0.12, smoothstep(0.0, 0.9, r))
			img.set_pixel(x, y, Color(c, c * 0.95, c * 0.9, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## All the wreckage gone.
func clear_debris() -> void:
	for d in _debris:
		if is_instance_valid(d):
			d.queue_free()
	_debris.clear()


# --- Effects and sound ---------------------------------------------------------------------------

func _impact(at: Vector3, normal: Vector3, kind: String, strength: float) -> void:
	_burst(at + normal * 0.03, kind, strength, normal)
	if randf() < 0.25:
		var path := "res://assets/audio/impact/%s_0%d.wav" % ["metal" if kind == "metal" else "dirt", randi_range(1, 3)]
		if kind == "metal" and randf() < 0.3:
			path = "res://assets/audio/impact/ricochet_0%d.wav" % randi_range(1, 2)
		sound(path, at, -6.0, randf_range(0.9, 1.1))


## What a burst looks like: "dirt" clods and dust, "metal" sparks, "explosion" fire and smoke,
## "smoke" a dusty cloud, "flash" a cannon's muzzle fire.
const LOOKS := {
	"dirt": {"color": Color(0.3, 0.23, 0.15), "amount": 0.6, "speed": Vector2(2.0, 6.0), "life": 1.0, "size": Vector2(0.4, 1.0), "gravity": 9.8, "glow": 0.0},
	"metal": {"color": Color(1.0, 0.7, 0.3), "amount": 0.5, "speed": Vector2(3.0, 9.0), "life": 0.35, "size": Vector2(0.15, 0.35), "gravity": 9.8, "glow": 8.0},
	"explosion": {"color": Color(1.0, 0.55, 0.15), "amount": 1.0, "speed": Vector2(3.0, 9.0), "life": 0.7, "size": Vector2(2.0, 4.5), "gravity": -1.0, "glow": 5.0},
	"smoke": {"color": Color(0.45, 0.42, 0.38), "amount": 0.8, "speed": Vector2(1.0, 3.0), "life": 2.5, "size": Vector2(2.5, 5.0), "gravity": -0.4, "glow": 0.0},
	"flash": {"color": Color(1.0, 0.75, 0.4), "amount": 0.5, "speed": Vector2(4.0, 10.0), "life": 0.15, "size": Vector2(1.0, 2.0), "gravity": 0.0, "glow": 6.0},
	"column": {"color": Color(0.2, 0.19, 0.18), "amount": 0.7, "speed": Vector2(1.0, 3.5), "life": 7.0, "size": Vector2(3.0, 7.0), "gravity": -0.7, "glow": 0.0},
	"embers": {"color": Color(1.0, 0.55, 0.15), "amount": 0.8, "speed": Vector2(6.0, 15.0), "life": 1.6, "size": Vector2(0.08, 0.18), "gravity": 9.8, "glow": 10.0},
}


func _burst(at: Vector3, kind: String, strength: float, dir := Vector3.UP) -> void:
	if _fx.is_empty():
		return
	var p := _fx[_fx_i]
	_fx_i = (_fx_i + 1) % _fx.size()
	var look: Dictionary = LOOKS[kind]
	var m := p.process_material as ParticleProcessMaterial
	var sp: Vector2 = look.speed
	var sz: Vector2 = look.size
	m.color = look.color
	m.direction = (dir + Vector3.UP * 0.4).normalized()
	m.spread = 35.0 if kind in ["dirt", "metal", "flash"] else 180.0
	m.initial_velocity_min = sp.x * strength
	m.initial_velocity_max = sp.y * strength
	m.gravity = Vector3(0, -float(look.gravity), 0)
	m.scale_min = sz.x * maxf(strength, 0.4)
	m.scale_max = sz.y * maxf(strength, 0.4)
	var mat := (p.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	mat.emission_energy_multiplier = float(look.glow)
	mat.emission_enabled = float(look.glow) > 0.0
	p.lifetime = float(look.life)
	p.amount_ratio = clampf(float(look.amount) * strength, 0.1, 1.0)
	p.global_position = at
	p.restart()
	p.emitting = true


func _make_fx() -> GPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = WheelSpray._puff()
	mat.emission = Color(1.0, 0.6, 0.25)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = mat
	var m := ParticleProcessMaterial.new()
	var fade := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	fade.gradient = g
	m.color_ramp = fade
	m.damping_min = 0.5
	m.damping_max = 1.5
	var p := GPUParticles3D.new()
	p.process_material = m
	p.draw_pass_1 = quad
	p.amount = 40
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.emitting = false
	p.top_level = true
	p.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 16, 24))
	add_child(p)
	return p


func sound(path: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	var s: AudioStream = _streams[path]
	if s == null:
		return
	var p := _players[_player_i]
	_player_i = (_player_i + 1) % SOUNDS
	p.stream = s
	p.global_position = at
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
