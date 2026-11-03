class_name FireFx
extends RefCounted
## Flames and smoke for a burning building (Building._fire_fx) and a chimney: the flames tongues of
## fire added on bright (fire.gdshader), the smoke lit billows laid over (smoke.gdshader), both
## carried off by the wind. (_quad, a plain soft dot, is for dust and the like.)

const FIRE := preload("res://shaders/fire.gdshader")
const SMOKE := preload("res://shaders/smoke.gdshader")

static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_dot = t
	return _dot


static func _ramp(colors: Array[Color], offsets: Array[float]) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _quad(size: float, add: bool) -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	return q


static func _shaded_quad(shader: Shader, size: Vector2, params := {}) -> QuadMesh:
	var m := ShaderMaterial.new()
	m.shader = shader
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	var q := QuadMesh.new()
	q.size = size
	q.material = m
	return q


static func flames() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.5, 0.5, 0.5)
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(Weather.wind_now.x * 0.25, 3.0, Weather.wind_now.z * 0.25)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1, 0.35))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _ramp([Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 0.92, 0.8, 0.9), Color(1.0, 0.62, 0.38, 0.6), Color(0.7, 0.28, 0.15, 0.0)], [0.0, 0.1, 0.5, 1.0])
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.1
	p.process_material = pm
	p.draw_pass_1 = _shaded_quad(FIRE, Vector2(1.3, 2.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 12, 12))
	return p


## Sparks and embers thrown up from a fire and carried off on the wind, glowing out as they go.
static func embers() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2, 0.5, 2)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(Weather.wind_now.x * 0.6, 0.5, Weather.wind_now.z * 0.6)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 3.0
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = _ramp([Color(1.0, 0.95, 0.75, 1.0), Color(1.0, 0.6, 0.3, 0.9), Color(0.7, 0.2, 0.05, 0.0)], [0.0, 0.5, 1.0])
	var p := GPUParticles3D.new()
	p.amount = 70
	p.lifetime = 3.5
	p.process_material = pm
	p.draw_pass_1 = _shaded_quad(FIRE, Vector2(0.12, 0.12), {"tongue": 0.0, "energy": 5.0, "soft": 0.05})
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 60, 60))
	return p


## A blast at `at` (`size` 1 a mine, less a shell): a fireball that swells and goes, a ring of dust
## running out over the ground, earth and stones flung up and falling back, a column of dirty smoke
## left rising; the view shaken if it's near. Everything frees itself.
static func explosion(parent: Node, at: Vector3, size := 1.0) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = at
	# the fireball
	var ball := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 1.0
	bm.height = 2.0
	bm.radial_segments = 16
	bm.rings = 8
	ball.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(1.0, 0.88, 0.55, 1.0)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.15)
	fm.emission_energy_multiplier = 7.0
	ball.material_override = fm
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.scale = Vector3.ONE * 0.3 * size
	ball.position = Vector3.UP * 0.8 * size
	root.add_child(ball)
	var bt := ball.create_tween().set_parallel()
	bt.tween_property(ball, "scale", Vector3.ONE * 2.4 * size, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	bt.tween_property(fm, "albedo_color", Color(0.25, 0.18, 0.12, 0.0), 0.4).set_delay(0.2)
	bt.tween_property(fm, "emission_energy_multiplier", 0.0, 0.3).set_delay(0.18)
	# the ring of dust over the ground
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 24
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.55, 0.48, 0.38, 0.6)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.5, 0.3, 0.5) * size
	ring.position = Vector3.UP * 0.2
	root.add_child(ring)
	var rt := ring.create_tween().set_parallel()
	rt.tween_property(ring, "scale", Vector3(7.0, 0.6, 7.0) * size, 0.6).set_ease(Tween.EASE_OUT)
	rt.tween_property(rm, "albedo_color:a", 0.0, 0.6)
	# earth and stones flung up
	var dm := ParticleProcessMaterial.new()
	dm.direction = Vector3.UP
	dm.spread = 40.0
	dm.initial_velocity_min = 6.0 * size
	dm.initial_velocity_max = 13.0 * size
	dm.gravity = Vector3(0, -14.0, 0)
	dm.angular_velocity_min = -360.0
	dm.angular_velocity_max = 360.0
	dm.scale_min = 0.5
	dm.scale_max = 1.6
	dm.color = Color(0.24, 0.18, 0.12)
	var dirt := GPUParticles3D.new()
	dirt.amount = int(60 * size) + 10
	dirt.lifetime = 1.8
	dirt.one_shot = true
	dirt.explosiveness = 1.0
	dirt.process_material = dm
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.14, 0.1, 0.12)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 1.0
	chunk.material = cm
	dirt.draw_pass_1 = chunk
	dirt.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 30, 40))
	dirt.position = Vector3.UP * 0.3
	root.add_child(dirt)
	dirt.emitting = true
	# a column of dirty smoke
	var puff := smoke(true)
	puff.amount = int(26 * size) + 6
	puff.lifetime = 6.0
	(puff.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.8, 0.3, 0.8) * size
	(puff.process_material as ParticleProcessMaterial).initial_velocity_min = 3.0
	(puff.process_material as ParticleProcessMaterial).initial_velocity_max = 6.0
	puff.position = Vector3.UP * 0.6
	root.add_child(puff)
	puff.emitting = true
	var tw := root.create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func() -> void: puff.emitting = false)
	tw.tween_interval(7.0)
	tw.tween_callback(root.queue_free)
	var cam := root.get_viewport().get_camera_3d()
	if cam and cam.has_method("shake"):
		cam.shake(at, 0.9 * size)


## Dust thrown up where something heavy comes down (a wall, a roof): a low brown cloud that rolls
## out and settles. Frees itself.
static func dust(parent: Node, at: Vector3, size := 1.0) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8 * size
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.5 * size
	pm.gravity = Vector3(Weather.wind_now.x * 0.3, 0.15, Weather.wind_now.z * 0.3)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 1.0
	pm.scale_max = 2.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 2.4))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _ramp([Color(0.45, 0.38, 0.3, 0.0), Color(0.45, 0.38, 0.3, 0.55), Color(0.5, 0.45, 0.38, 0.0)], [0.0, 0.15, 1.0])
	var p := GPUParticles3D.new()
	p.amount = int(18 * size) + 6
	p.lifetime = 3.0
	p.one_shot = true
	p.explosiveness = 0.9
	p.process_material = pm
	p.draw_pass_1 = _shaded_quad(SMOKE, Vector2(1.8, 1.8) * size, {"glow_below": 0.0})
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-15, -3, -15), Vector3(30, 15, 30))
	parent.add_child(p)
	p.global_position = at + Vector3.UP * 0.4
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(p.queue_free)


## Smoke over a fire (lit orange from under), or with `fire` false a hearth's, from a chimney.
static func smoke(fire := true) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2, 0.5, 2)
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(Weather.wind_now.x * 0.35, 0.8, Weather.wind_now.z * 0.35)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -12.0
	pm.angular_velocity_max = 12.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.08
	pm.scale_min = 1.0
	pm.scale_max = 2.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(0.3, 1.1))
	sc.add_point(Vector2(1, 2.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _ramp([Color(0.1, 0.09, 0.08, 0.0), Color(0.13, 0.12, 0.11, 0.8), Color(0.3, 0.3, 0.3, 0.45), Color(0.42, 0.42, 0.42, 0.0)], [0.0, 0.1, 0.55, 1.0])
	var p := GPUParticles3D.new()
	p.amount = 56
	p.lifetime = 7.0
	p.process_material = pm
	p.draw_pass_1 = _shaded_quad(SMOKE, Vector2(3.2, 3.2), {"glow_below": 1.2 if fire else 0.0})
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 60, 60))
	return p
