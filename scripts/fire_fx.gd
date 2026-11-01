class_name FireFx
extends RefCounted
## Flames and smoke for a burning building (Building._fire_fx): billboards on a soft round dot,
## the flames added on bright, the smoke laid over dark, both carried off by the wind.

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


static func flames() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.5, 0.5, 0.5)
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.8
	pm.gravity = Vector3(Weather.wind_now.x * 0.15, 2.5, Weather.wind_now.z * 0.15)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _ramp([Color(1.0, 0.95, 0.6, 0.9), Color(1.0, 0.55, 0.12, 0.8), Color(0.7, 0.15, 0.03, 0.4), Color(0.2, 0.05, 0.02, 0.0)], [0.0, 0.3, 0.65, 1.0])
	var p := GPUParticles3D.new()
	p.amount = 36
	p.lifetime = 0.9
	p.process_material = pm
	p.draw_pass_1 = _quad(1.3, true)
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
	pm.color_ramp = _ramp([Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.45, 0.1, 0.9), Color(0.6, 0.1, 0.02, 0.0)], [0.0, 0.5, 1.0])
	var p := GPUParticles3D.new()
	p.amount = 50
	p.lifetime = 3.5
	p.process_material = pm
	p.draw_pass_1 = _quad(0.14, true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 60, 60))
	return p


static func smoke() -> GPUParticles3D:
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
	pm.scale_min = 1.0
	pm.scale_max = 2.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 2.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _ramp([Color(0.12, 0.1, 0.09, 0.0), Color(0.14, 0.13, 0.12, 0.55), Color(0.3, 0.3, 0.3, 0.25), Color(0.4, 0.4, 0.4, 0.0)], [0.0, 0.12, 0.6, 1.0])
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 7.0
	p.process_material = pm
	p.draw_pass_1 = _quad(3.2, false)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 60, 60))
	return p
