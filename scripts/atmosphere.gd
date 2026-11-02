class_name Atmosphere
extends Node3D
## What makes the valley feel like a place, laid over the weather (it runs after Weather each frame):
##   mist       valley mist at dawn and dusk (thickest in spring and autumn), the low sun's shafts
##              through it, the lamps haloed in it
##   colour     warmer and richer in the golden hours, colder and paler in winter; the corners of the
##              picture darkened a little; close in, what's far behind softly out of focus
##   life       birds wheeling over the woods by day, butterflies over the grass in summer, breath
##              smoking from the mouth in the cold, sawdust from the saw, chips from the chisel
## P hides the screen and deepens the focus, for pictures.

const BIRDS := 9

var weather: Weather
var cam: RtsCamera
var seasons: Seasons
var village: Village
var photo := false

var _attrs: CameraAttributesPractical
var _vignette: ColorRect
var _birds: Array[Node3D] = []
var _flock := Vector3.ZERO
var _flock_to := Vector3.ZERO
var _flock_t := 0.0
var _butterflies: GPUParticles3D
var _breath: GPUParticles3D
var _chips: GPUParticles3D
var _puff_t := 0.0
var _haze: FogVolume ## the stoves' smoke lying over the town on a still morning or evening


func _ready() -> void:
	process_priority = 100 # (after the weather has set the scene up for this frame)
	_attrs = CameraAttributesPractical.new()
	cam.attributes = _attrs
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.4;
void fragment() {
	float d = length((UV - 0.5) * vec2(1.0, 0.8)) * 1.45;
	COLOR = vec4(0.02, 0.015, 0.01, smoothstep(0.45, 1.15, d) * amount);
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_vignette.material = sm
	layer.add_child(_vignette)
	_make_birds()
	_butterflies = _make_butterflies()
	add_child(_butterflies)
	_breath = _puffer(Color(0.92, 0.94, 0.97, 0.35), 0.35, 1.6, Vector3(0, 0.25, 0))
	add_child(_breath)
	_chips = _puffer(Color(0.86, 0.74, 0.52, 0.9), 0.06, 0.9, Vector3(0, -6.0, 0))
	add_child(_chips)


## Smoke from every chimney settles over the roofs in a blue haze when the air's still, thickest in
## the cold of the morning and evening; a wind clears it.
func _update_haze(dt: float) -> void:
	if village == null:
		return
	if _haze == null:
		_haze = FogVolume.new()
		var m := FogMaterial.new()
		m.albedo = Color(0.62, 0.64, 0.7)
		m.height_falloff = 0.12
		m.edge_fade = 0.6
		m.density = 0.0
		_haze.material = m
		_haze.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		add_child(_haze)
	var n := 0
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for b in village.buildings:
		if b.def.role == "house" and b.state == "done":
			lo = lo.min(b.global_position)
			hi = hi.max(b.global_position)
			if b.smoking():
				n += 1
	var m := _haze.material as FogMaterial
	var want := 0.0
	if n > 0:
		var h := weather.hour
		var still := 1.0 - smoothstep(2.0, 7.0, Weather.wind_now.length())
		var cool := maxf(smoothstep(5.0, 7.0, h) * (1.0 - smoothstep(9.0, 11.0, h)), smoothstep(17.0, 19.0, h) * (1.0 - smoothstep(22.0, 24.0, h)))
		want = clampf(n * 0.0015, 0.0, 0.01) * still * (0.35 + 0.65 * cool) * (1.0 - weather.rain_intensity * 0.7)
		var mid := (lo + hi) * 0.5
		_haze.global_position = Vector3(mid.x, mid.y + 7.0, mid.z)
		_haze.size = Vector3(hi.x - lo.x + 50.0, 22.0, hi.z - lo.z + 50.0)
	m.density = move_toward(m.density, want, dt * 0.004)


func _process(dt: float) -> void:
	var env := weather.environment
	if env == null:
		return
	var h := weather.hour
	var season := maxi(seasons.season, 0)
	# Mist at dawn and dusk.
	var dawn := smoothstep(4.5, 6.0, h) * (1.0 - smoothstep(8.0, 10.5, h))
	var dusk := smoothstep(18.0, 19.5, h) * (1.0 - smoothstep(21.5, 23.5, h))
	var mist: float = (dawn + dusk * 0.6) * float([1.2, 0.55, 1.5, 0.8][season]) * (1.0 - weather.rain_intensity * 0.5)
	env.volumetric_fog_density += mist * 0.0006
	# Kept light, whatever the weather: the valley should read clearly from above, the mist a veil
	# at most, never a wall (the weather sets these afresh every frame, before this).
	env.volumetric_fog_density = minf(env.volumetric_fog_density * 0.3, 0.0018)
	env.fog_density = minf(env.fog_density * 0.3, 0.0009)
	env.fog_sky_affect = minf(env.fog_sky_affect, 0.25)
	if weather._ground_fog_mat:
		weather._ground_fog_mat.density = minf(weather._ground_fog_mat.density * 0.25, 0.004)
	env.volumetric_fog_anisotropy = maxf(env.volumetric_fog_anisotropy, 0.72 * dawn)
	# Colour: the golden hours warmer and richer, winter paler, night plain.
	var sun_y := weather.sun_direction().y
	var golden := smoothstep(-0.03, 0.08, sun_y) * (1.0 - smoothstep(0.12, 0.38, sun_y))
	env.adjustment_saturation = lerpf(1.22, 1.32, golden) * (0.86 if season == 3 else 1.0) * lerpf(1.0, 0.85, weather._night_factor())
	env.adjustment_brightness = 1.0 + golden * 0.04
	(_vignette.material as ShaderMaterial).set_shader_parameter("amount", 0.6 if photo else 0.38)
	# Focus: close in, the far distance softly out of focus.
	var close := clampf(1.0 - (cam.dist - 16.0) / 70.0, 0.0, 1.0)
	_attrs.dof_blur_far_enabled = close > 0.05 or photo
	_attrs.dof_blur_far_distance = cam.dist + (18.0 if photo else 30.0)
	_attrs.dof_blur_far_transition = 50.0
	_attrs.dof_blur_amount = (0.11 if photo else 0.07) * maxf(close, 0.6 if photo else 0.0)
	_update_haze(dt)
	_update_birds(dt)
	var day := not weather.is_night() and weather.rain_intensity < 0.3 and weather.snow_intensity < 0.3
	_butterflies.emitting = day and season in [0, 1] and weather.temperature > 12.0 and cam.dist < 120.0
	_butterflies.global_position = Vector3(cam.focus.x, cam.focus.y + 0.6, cam.focus.z)
	_puff_t += dt
	if _puff_t > 0.35:
		_puff_t = 0.0
		_puffs()


## Smoke of breath in the cold, and sawdust and chips flying where the work is: from those near the
## camera.
func _puffs() -> void:
	var cold := weather.temperature < 3.0
	for v in village.villagers:
		if v.dead or v.sleeping or not v.visible:
			continue
		if v.global_position.distance_to(cam.focus) > 45.0:
			continue
		var fwd := -v.global_basis.z
		if cold and randf() < 0.3:
			_emit(_breath, v.global_position + Vector3.UP * 1.72 + fwd * 0.18, fwd * 0.3 + Vector3.UP * 0.1)
		var anim: String = v._anim
		if anim in ["saw", "chisel", "chop", "limb", "mine"] and v.plan.size() > 0:
			for k in 3:
				_emit(_chips, v.global_position + Vector3.UP * (0.9 if anim in ["saw", "chisel"] else 1.0) + fwd * 0.7,
					Vector3(randf_range(-1, 1), randf_range(1.0, 2.2), randf_range(-1, 1)))


func _emit(p: GPUParticles3D, at: Vector3, vel: Vector3) -> void:
	p.emit_particle(Transform3D(Basis.IDENTITY, at), vel, Color.WHITE, Color.BLACK,
		GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY)


func _puffer(color: Color, size: float, life: float, gravity: Vector3) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.gravity = gravity
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.6 if size > 0.2 else 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var p := GPUParticles3D.new()
	p.amount = 160
	p.lifetime = life
	p.emitting = false
	p.process_material = pm
	p.draw_pass_1 = FireFx._quad(size, false)
	p.visibility_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 2000, 4000))
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _make_butterflies() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(35, 0.5, 35)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.direction = Vector3(1, 0.2, 0)
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.5
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.4
	pm.turbulence_influence_max = 0.7
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 0.85), Color(1.0, 0.85, 0.3), Color(0.9, 0.95, 1.0), Color(1.0, 0.6, 0.3)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 9.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.07)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 15, 80))
	p.local_coords = false
	return p


# --- birds ----------------------------------------------------------------------------------------

func _make_birds() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.11, 0.1)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in BIRDS:
		var b := Node3D.new()
		add_child(b)
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.06, 0.3)
		body.mesh = bm
		body.material_override = m
		b.add_child(body)
		for s in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.38, 0.01, 0.14)
			w.mesh = wm
			w.material_override = m
			w.position = Vector3(s * 0.2, 0, 0)
			w.name = "Wing%d" % (0 if s < 0 else 1)
			b.add_child(w)
		b.set_meta("phase", randf() * TAU)
		b.set_meta("orbit", Vector3(randf_range(8, 18), randf_range(-3, 3), randf_range(0.4, 0.8)))
		_birds.append(b)


## The flock wheels over the woods near where the camera is looking, now and then making off
## somewhere else; by night, or in rain or snow, it's gone.
func _update_birds(dt: float) -> void:
	var out := not weather.is_night() and weather.rain_intensity < 0.3 and weather.snow_intensity < 0.4
	_flock_t -= dt
	if _flock_t <= 0.0:
		_flock_t = randf_range(12.0, 30.0)
		var a := randf() * TAU
		_flock_to = cam.focus + Vector3(cos(a), 0, sin(a)) * randf_range(30.0, 90.0)
		_flock_to.y = cam.focus.y + randf_range(22.0, 38.0)
	_flock = _flock.lerp(_flock_to, 1.0 - exp(-dt * 0.25)) if _flock != Vector3.ZERO else _flock_to
	var t := Time.get_ticks_msec() * 0.001
	for b in _birds:
		b.visible = out
		if not out:
			continue
		var ph: float = b.get_meta("phase")
		var o: Vector3 = b.get_meta("orbit")
		var ang := t * o.z + ph
		var p := _flock + Vector3(cos(ang) * o.x, o.y + sin(t * 0.7 + ph) * 1.5, sin(ang) * o.x)
		var dir := Vector3(-sin(ang), 0, cos(ang))
		b.global_position = p
		b.look_at(p + dir, Vector3.UP)
		var flap := sin(t * 11.0 + ph * 3.0) * 0.7 if fmod(t + ph, 4.0) < 2.5 else 0.12 # (flapping, then gliding)
		(b.get_node("Wing0") as Node3D).rotation.z = flap
		(b.get_node("Wing1") as Node3D).rotation.z = -flap
