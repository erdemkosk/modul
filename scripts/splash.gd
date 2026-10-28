class_name Splash
extends RefCounted
## One-off bursts of muddy water and mud: a boot into a flooded footprint, a tyre
## hitting a puddle. A small pool of particle emitters is shared by everyone and
## reused oldest first.

const WATER := Color(0.25, 0.19, 0.12) ## Muddy water, brown and opaque.
const MUD := Color(0.17, 0.12, 0.08)
const SNOW := Color(0.9, 0.92, 0.96)
const POOL := 10

static var _pool: Array[GPUParticles3D] = []
static var _next := 0


## A burst at `at`, 0..1 strong (a footstep is ~0.4, a tyre into a deep puddle 1).
## `push` tips it along a direction (a tyre throws it forward and out).
static func burst(at: Vector3, color: Color, strength: float, push := Vector3.ZERO) -> void:
	var p := _take()
	if p == null:
		return
	var m := p.process_material as ParticleProcessMaterial
	p.global_position = at + Vector3.UP * 0.03
	m.color = color
	m.direction = (Vector3.UP + push * 0.8).normalized()
	m.spread = 40.0 if push == Vector3.ZERO else 30.0
	var powder := color == SNOW # fine dry grains, not drops: smaller, slower, hanging longer
	m.initial_velocity_min = (0.8 + 1.5 * strength) * (0.6 if powder else 1.0)
	m.initial_velocity_max = 1.6 + 3.2 * strength
	m.scale_min = 0.2 if powder else 0.5 + strength * 0.4
	m.scale_max = 0.55 if powder else 1.4 + strength * 1.4
	m.damping_min = 2.0 if powder else 0.2
	m.damping_max = 4.0 if powder else 0.8
	p.amount_ratio = clampf(0.25 + strength * 0.75, 0.0, 1.0)
	p.restart()
	p.emitting = true


static func _take() -> GPUParticles3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless":
		return null
	if _pool.is_empty() or not is_instance_valid(_pool[0]) or not _pool[0].is_inside_tree():
		_pool.clear()
		for i in POOL:
			var e := _make()
			tree.root.add_child.call_deferred(e)
			_pool.append(e)
		return null # ready from the next one on
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	return p


static func _make() -> GPUParticles3D:
	var look := StandardMaterial3D.new()
	look.roughness = 0.12 # wet: each drop flashes in the light
	look.vertex_color_use_as_albedo = true
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.012
	mesh.height = 0.05
	mesh.radial_segments = 6
	mesh.rings = 2
	mesh.material = look
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.08
	m.gravity = Vector3(0.0, -9.8, 0.0)
	m.particle_flag_align_y = true
	m.damping_min = 0.2
	m.damping_max = 0.8
	var p := GPUParticles3D.new()
	p.name = "Splash"
	p.process_material = m
	p.draw_pass_1 = mesh
	p.amount = 36
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 5, 6))
	return p
