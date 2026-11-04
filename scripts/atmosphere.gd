class_name Atmosphere
extends Node3D
## What makes the valley feel like a place, laid over the weather (it runs after Weather each frame):
##   mist       valley mist at dawn and dusk (thickest in spring and autumn), the low sun's shafts
##              through it, the lamps haloed in it
##   colour     warmer and richer in the golden hours, colder and paler in winter; the corners of the
##              picture darkened a little; close in, what's far behind softly out of focus
##   life       birds wheeling over the woods by day, butterflies over the grass in summer, breath
##              smoking from the mouth in the cold, sawdust from the saw, chips from the chisel
## P hides the screen and deepens the focus, for pictures; again, and it's an old photograph of 1918:
## sepia, the grain of the plate, its corners dark, a little soft at the edges; again, back.
##   grade      each season its own cast laid over the picture (spring a pale green, summer gold,
##              autumn rust, winter a cold blue-grey), night bluer, a fire's town warmer

const BIRDS := 9

var weather: Weather
var cam: RtsCamera
var seasons: Seasons
var village: Village
var photo := false
var sepia := false ## (the photograph an old one)
var _grade := Color(1, 1, 1) ## the season's cast, eased toward
var _grade_s := Color(1, 1, 1) ## (its shadows')
var _glow := 0.0 ## a fire's glow on the sky, 0..1
var _glow_want := 0.0
var _glow_t := 0.0

var _attrs: CameraAttributesPractical
var _vignette: ColorRect
var _birds: Array[Node3D] = []
var _flock := Vector3.ZERO
var _flock_to := Vector3.ZERO
var _flock_t := 0.0
var _butterflies: GPUParticles3D
var _leaves: GPUParticles3D ## autumn: leaves coming down off the birches round the camera
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
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.4;
uniform vec3 tint = vec3(1.0); // the highlights' cast
uniform vec3 shade = vec3(1.0); // the shadows' cast
uniform float tint_amt = 0.0;
uniform vec3 glow = vec3(0.0); // a town burning: orange on the sky, thrown up from below
uniform float sepia = 0.0;
uniform float t = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float d = length((UV - 0.5) * vec2(1.0, 0.8)) * 1.45;
	vec3 c = texture(screen, uv).rgb;
	// the season's grade: the shadows toned one way, the lights another (winter's blue shade and
	// cold white, autumn's brown and gold, the night's ink blue), a gentle S of contrast
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 cast = mix(shade, tint, smoothstep(0.02, 0.6, lum));
	cast /= max(dot(cast, vec3(0.299, 0.587, 0.114)), 0.01); // (a shift of hue only: the night no darker for it)
	c = mix(c, c * cast, tint_amt * (1.0 - smoothstep(0.75, 1.1, lum) * 0.6));
	vec3 cc = clamp(c, 0.0, 1.0);
	c = mix(c, cc * cc * (3.0 - 2.0 * cc), 0.18 * tint_amt);
	// fire: the sky above it orange, more toward the top of the view, the dark lit most
	c += glow * (0.35 + 0.65 * (1.0 - uv.y)) * (1.0 - smoothstep(0.2, 0.9, lum) * 0.6);
	if (sepia > 0.0) {
		// an old plate: soft toward the edges, toned brown, faded, grained, a scratch or two
		vec3 soft = textureLod(screen, uv, 2.5).rgb;
		c = mix(c, soft, smoothstep(0.55, 1.1, d) * sepia);
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		l = pow(l, 0.92) * 0.92 + 0.05;
		vec3 tone = mix(vec3(0.16, 0.1, 0.06), vec3(1.0, 0.9, 0.72), l);
		float g = (h(floor(uv * vec2(900.0, 560.0)) + floor(t * 18.0)) - 0.5) * 0.09;
		float scratch = step(0.9985, h(vec2(floor(uv.x * 400.0), floor(t * 6.0)))) * 0.25;
		c = mix(c, tone + g + scratch, sepia);
	}
	float v = smoothstep(0.45, 1.15, d) * (amount + sepia * 0.35);
	COLOR = vec4(mix(c, vec3(0.02, 0.015, 0.01), v), 1.0);
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_vignette.material = sm
	layer.add_child(_vignette)
	_make_birds()
	_butterflies = _make_butterflies()
	add_child(_butterflies)
	_leaves = _make_leaves()
	add_child(_leaves)
	_breath = _puffer(Color(0.93, 0.95, 0.98, 0.5), 0.3, 1.8, Vector3(0, 0.22, 0))
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
	var sm := _vignette.material as ShaderMaterial
	sm.set_shader_parameter("amount", 0.6 if photo else 0.38)
	sm.set_shader_parameter("sepia", 1.0 if photo and sepia else 0.0)
	sm.set_shader_parameter("t", Time.get_ticks_msec() / 1000.0)
	# the season's cast, the night's blue
	var night := weather._night_factor()
	var want: Color = [Color(0.98, 1.03, 0.95), Color(1.06, 1.01, 0.88), Color(1.1, 0.96, 0.78), Color(0.95, 0.99, 1.07)][season]
	want = want.lerp(Color(0.86, 0.92, 1.12), night * 0.75)
	want = want.lerp(Color(1.12, 0.96, 0.8), golden * 0.6)
	var want_s: Color = [Color(0.92, 1.0, 1.02), Color(0.95, 0.97, 1.05), Color(0.98, 0.87, 0.8), Color(0.8, 0.9, 1.16)][season]
	want_s = want_s.lerp(Color(0.6, 0.72, 1.2), night * 0.8) # (the night's ink blue)
	want_s = want_s.lerp(Color(0.9, 0.86, 1.0), golden * 0.4)
	var k := clampf(dt * 0.5, 0.0, 1.0)
	_grade = _grade.lerp(want, k)
	_grade_s = _grade_s.lerp(want_s, k)
	sm.set_shader_parameter("tint", Vector3(_grade.r, _grade.g, _grade.b))
	sm.set_shader_parameter("shade", Vector3(_grade_s.r, _grade_s.g, _grade_s.b))
	sm.set_shader_parameter("tint_amt", 0.0 if photo and sepia else 0.75)
	# a fire in the town: its glow on the sky, the brighter the more is burning and the nearer, the
	# night more than the day
	_glow_t -= dt
	if _glow_t <= 0.0:
		_glow_t = 0.5
		var heat := 0.0
		for b in village.buildings:
			if b.state != "gone" and b.is_burning():
				var d := b.global_position.distance_to(cam.focus)
				heat += float(b.burning_count()) * 0.12 / (1.0 + d / 80.0)
		_glow_want = clampf(heat, 0.0, 1.0)
	_glow = move_toward(_glow, _glow_want, dt * 0.25)
	var gl := Color(1.0, 0.42, 0.12) * _glow * lerpf(0.06, 0.2, night)
	sm.set_shader_parameter("glow", Vector3(gl.r, gl.g, gl.b))
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
	_leaves.emitting = season == 2 and weather.rain_intensity < 0.6 and cam.dist < 140.0
	_leaves.global_position = Vector3(cam.focus.x, cam.focus.y + 14.0, cam.focus.z)
	(_leaves.process_material as ParticleProcessMaterial).gravity = Vector3(Weather.wind_now.x * 0.35, -0.9, Weather.wind_now.z * 0.35)
	_puff_t += dt
	if _puff_t > 0.35:
		_puff_t = 0.0
		_puffs()


## Smoke of breath in the cold, and sawdust and chips flying where the work is: from those near the
## camera.
func _puffs() -> void:
	# breath: below 5 degrees, a puff every breath (a breath's own rhythm each, quicker at work or
	# running), more and longer in the bitter cold
	var cold := clampf((5.0 - weather.temperature) / 15.0, 0.0, 1.0)
	var now := Time.get_ticks_msec() * 0.001
	for v in village.villagers:
		if v.dead or v.sleeping or not v.visible:
			continue
		if v.global_position.distance_to(cam.focus) > 70.0:
			continue
		var fwd := -v.global_basis.z
		if cold > 0.0 and v.inside == null:
			var pace := 1.0 if v._anim in ["walk", "idle", "sit", ""] else 1.7
			var ph := fmod(now * pace / 2.4 + float(v.get_instance_id() % 997) * 0.137, 1.0)
			if ph < 0.35 / 2.4 * pace + 0.02 and randf() < 0.35 + cold * 0.65:
				var mouth := v.global_position + Vector3.UP * (1.72 * v.scale.y) + fwd * 0.16
				_emit(_breath, mouth, fwd * (0.35 + 0.2 * cold) + Vector3.UP * 0.05)
				var ox: Node3D = v._ox_head
				if ox and is_instance_valid(ox) and ox.is_visible_in_tree():
					var nose := ox.global_position - ox.global_basis.z * 0.8 + Vector3.DOWN * 0.1
					_emit(_breath, nose, -ox.global_basis.z * 0.5 + Vector3.DOWN * 0.1)
					_emit(_breath, nose, -ox.global_basis.z * 0.45 + Vector3.DOWN * 0.05)
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


## Leaves twirling down in the autumn, gold and rust, drifting with the wind.
func _make_leaves() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(45, 4, 45)
	pm.gravity = Vector3(0, -0.9, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.15
	pm.turbulence_influence_max = 0.35
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -180.0
	pm.angular_velocity_max = 180.0
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.85, 0.62, 0.12), Color(0.78, 0.36, 0.1), Color(0.6, 0.18, 0.08), Color(0.7, 0.55, 0.2)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	var p := GPUParticles3D.new()
	p.amount = 140
	p.lifetime = 16.0
	p.preprocess = 8.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.08)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-50, -30, -50), Vector3(100, 40, 100))
	p.local_coords = false
	p.emitting = false
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
