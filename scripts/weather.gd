class_name Weather
extends Node3D
## Day/night cycle and weather for the whole map.
##
## Owns the WorldEnvironment (physically based sky shader with animated
## clouds, distance haze + volumetric fog, AgX tonemap, SSAO, glow), the sun
## and moon DirectionalLight3Ds, lightning, rain/snow GPU particles that follow
## the current camera, and procedurally synthesised rain/wind/thunder sound.
## Every frame it publishes the global shader uniforms weather_wetness,
## weather_snow, weather_rain and weather_wind (declared in project.godot)
## that the terrain, grass, tree and water shaders read.
##
##   var weather := Weather.new()
##   weather.hour = 17.5                 # 0-24, wraps
##   weather.day_length_minutes = 40.0   # real minutes per game day, 0 = frozen
##   weather.preset = "clear"            # clear cloudy overcast rain storm fog snow dynamic
##   add_child(weather)
##
## Fixed presets stay put; "dynamic" walks a Markov chain of presets on its
## own. All visible values glide toward the preset targets over
## transition_seconds, so set_preset() never pops (pass instant = true to snap).

const SUNRISE := 6.0
const SUNSET := 19.5
const SUN_MAX_ELEVATION := 1.15 ## rad (~66 deg) at solar noon.
const MOON_MAX_ELEVATION := 0.95
const WIND_NORM := 15.0 ## m/s that maps to 1.0 in the weather_wind shader global.

## Targets per preset. cover/dark/rain/snow/fog/haze/lightning 0..1 (haze is a
## Mie multiplier), wind in m/s, temp in deg C.
const PRESETS := {
	"clear":    {"cover": 0.24, "dark": 0.0,  "rain": 0.0, "snow": 0.0, "fog": 0.0,  "wind": 2.5,  "haze": 1.0, "lightning": 0.0, "temp": 18.0},
	"cloudy":   {"cover": 0.5,  "dark": 0.12, "rain": 0.0, "snow": 0.0, "fog": 0.05, "wind": 4.5,  "haze": 1.3, "lightning": 0.0, "temp": 15.0},
	"overcast": {"cover": 0.9,  "dark": 0.4,  "rain": 0.0, "snow": 0.0, "fog": 0.12, "wind": 5.5,  "haze": 1.8, "lightning": 0.0, "temp": 12.0},
	"rain":     {"cover": 0.97, "dark": 0.62, "rain": 0.6, "snow": 0.0, "fog": 0.1,  "wind": 6.5,  "haze": 2.2, "lightning": 0.0, "temp": 10.0},
	"storm":    {"cover": 1.0,  "dark": 0.85, "rain": 1.0, "snow": 0.0, "fog": 0.15, "wind": 13.0, "haze": 2.5, "lightning": 1.0, "temp": 9.0},
	"fog":      {"cover": 0.6,  "dark": 0.3,  "rain": 0.0, "snow": 0.0, "fog": 1.0,  "wind": 0.8,  "haze": 3.0, "lightning": 0.0, "temp": 8.0},
	"snow":     {"cover": 0.95, "dark": 0.35, "rain": 0.0, "snow": 0.8, "fog": 0.35, "wind": 4.0,  "haze": 2.0, "lightning": 0.0, "temp": -4.0},
	# A hard frost after a thaw: clear, still and bitter, last night's water frozen on the roads.
	"frost":    {"cover": 0.12, "dark": 0.0,  "rain": 0.0, "snow": 0.0, "fog": 0.08, "wind": 1.2,  "haze": 1.1, "lightning": 0.0, "temp": -7.0, "ground_wet": 0.9},
}

## "dynamic" mode: preset -> {next preset: weight}.
const CHAIN := {
	"clear":    {"cloudy": 0.8, "fog": 0.2},
	"cloudy":   {"clear": 0.35, "overcast": 0.5, "fog": 0.15},
	"overcast": {"rain": 0.45, "storm": 0.15, "cloudy": 0.25, "fog": 0.15},
	"rain":     {"overcast": 0.45, "storm": 0.25, "cloudy": 0.3},
	"storm":    {"rain": 0.65, "overcast": 0.35},
	"fog":      {"cloudy": 0.45, "clear": 0.35, "overcast": 0.2},
	"snow":     {"overcast": 0.5, "cloudy": 0.3, "frost": 0.2},
	"frost":    {"clear": 0.5, "cloudy": 0.3, "snow": 0.2},
}

# Atmosphere constants, identical to shaders/sky.gdshader.
const PR := 6360000.0
const AR := 6420000.0
const HR := 8000.0
const HM := 1200.0
const BR := Vector3(5.802e-6, 13.558e-6, 33.1e-6)
const BO := Vector3(0.65e-6, 1.881e-6, 0.085e-6)
const BM := 3.996e-6
const EYE_H := 250.0
const SUN_POWER := 22.0

const SKY_SHADER := preload("res://shaders/sky.gdshader")
const RAIN_SHADER := preload("res://shaders/rain.gdshader")
const FLAKE_SHADER := preload("res://shaders/snow.gdshader")

## Game hour, 0-24 (wraps).
var hour := 12.0:
	set(v):
		hour = fposmod(v, 24.0)
## Real minutes for 24 game hours. 0 freezes time.
@export var day_length_minutes := 40.0
## Real seconds a weather change takes to settle.
@export var transition_seconds := 90.0
## "dynamic": real seconds each state lasts (random in this range).
@export var dynamic_hold_min := 150.0
@export var dynamic_hold_max := 420.0
@export var allow_snow_in_dynamic := false
## World height below which the fog preset gets thick (valley fog).
@export var fog_base_height := 60.0
## Cloud drift speed multiplier (1 = true to the wind, more reads better on screen).
@export var cloud_speed_scale := 5.0
## Rain/snow stop on surfaces (a heightfield rendered around the camera), so none falls inside the cab.
@export var precipitation_collision := true
@export var audio_bus := &"Master"
@export var sound_volume_db := 0.0
@export var moon_phase := 0.75 ## 0 new .. 1 full.

var preset: String:
	get:
		return "dynamic" if _dynamic else _state
	set(v):
		set_preset(v, not is_inside_tree())

# Current (smoothed) weather. Read-only from outside.
var cloud_cover := 0.14
var rain_intensity := 0.0
var snow_intensity := 0.0
var fog_amount := 0.0
var wind := Vector3.ZERO ## x,z = direction * strength in m/s.
var gust := 0.0 ## 0..1 turbulence right now.
var wetness := 0.0 ## Ground wetness 0..1.
var snow_cover := 0.0 ## Ground snow 0..1.
var temperature := 15.0 ## deg C.
## 0..1: how much of the wet ground and the roads has frozen. Water left standing freezes to
## black ice below zero, and snow on the roads packs to a glaze. WorldTerrain reads `ice_now`
## for grip; shaders get weather_ice.
var ice := 0.0
static var ice_now := 0.0
static var wet_now := 0.0 ## `wetness`, for code that has no Weather node to hand (churning ground).
static var rain_now := 0.0 ## `rain_intensity`, the same way (rain washing the mud off a truck).
static var wind_now := Vector3.ZERO ## `wind` (m/s), the same way (a grass fire running before it: GrassFire).
static var snow_now := 0.0 ## `snow_intensity`, the same way (snowfall filling tracks back in).
static var snow_cover_now := 0.0 ## `snow_cover`, the same way (snow lying on firm ground: grip).
var lightning_flash := 0.0 ## 0..1 brightness of the current flash.

# Nodes it owns (exposed for tweaking from main.gd).
var environment: Environment
var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var lightning_light: DirectionalLight3D

var _state := "clear"
var _dynamic := false
var _initialized := false
var _hold := 0.0
var _rng := RandomNumberGenerator.new()

var _cloud_dark := 0.0
var _wind_speed := 2.5
var _wind_angle := 0.6
var _haze := 1.0
var _lightning := 0.0
var _t_cover := 0.14
var _t_dark := 0.0
var _t_rain := 0.0
var _t_snow := 0.0
var _t_fog := 0.0
var _t_wind := 2.5
var _t_haze := 1.0
var _t_lightning := 0.0
var _t_temp := 18.0

var _sky: Sky
var _sky_mat: ShaderMaterial
var _cloud_offset := Vector2.ZERO
var _cirrus_offset := Vector2.ZERO
var _clock := 0.0
var _gust_noise := FastNoiseLite.new()
var _sun_dir := Vector3.UP
var _moon_dir := Vector3.DOWN
var _sun_light_dir := Vector3.DOWN ## Last direction pushed to the sun node (quantised to avoid shadow swim).
var _moon_light_dir := Vector3.DOWN
var _sky_step := 0 ## Which CPU sky colour gets recomputed this frame (spread over frames).
var _sky_full_dir := Vector3.ZERO ## Sun direction at the last full recompute.
var _h_side := Vector3.ZERO
var _h_toward := Vector3.ZERO
var _h_away := Vector3.ZERO
var _sun_t_ground := Vector3.ONE
var _sun_t_cloud := Vector3.ONE
var _zenith_col := Vector3(0.1, 0.2, 0.4)
var _horizon_col := Vector3(0.5, 0.6, 0.7)

# Lightning: up to 4 pulses per strike, times (s after strike) and strengths.
var _strike_timer := 8.0
var _strike_t := 99.0
var _pulse_t := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _pulse_a := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _thunder_delay := -1.0
var _thunder_gain := 1.0
var _thunder_close := false

# Precipitation.
var _rain: GPUParticles3D
var _rain_pm: ParticleProcessMaterial
var _rain_mat: ShaderMaterial
var _snow: GPUParticles3D
var _snow_pm: ParticleProcessMaterial
var _snow_mat: ShaderMaterial
var _collider: GPUParticlesCollisionHeightField3D
var _ground_fog: FogVolume
var _ground_fog_mat: FogMaterial
var _cam_prev := Vector3.ZERO
var _cam_vel := Vector3.ZERO
var _have_cam := false

# Sound.
var _rain_player: AudioStreamPlayer
var _wind_lo: AudioStreamPlayer
var _wind_hi: AudioStreamPlayer
var _thunder_players: Array[AudioStreamPlayer] = []
var _thunder_streams: Array[AudioStreamWAV] = []
var _thunder_next := 0
var _gen_task := -1
var _gen_out := {}


## Switch to a preset ("clear", "cloudy", "overcast", "rain", "storm", "fog",
## "snow" or "dynamic"). Values glide there over transition_seconds unless instant.
func set_preset(preset_name: String, instant := false) -> void:
	if preset_name == "dynamic":
		_dynamic = true
		_hold = _rng.randf_range(dynamic_hold_min, dynamic_hold_max)
		_apply_targets(_state)
	elif PRESETS.has(preset_name):
		_dynamic = false
		_state = preset_name
		_apply_targets(preset_name)
	else:
		push_warning("Weather: unknown preset '%s'" % preset_name)
		return
	if instant:
		_snap()
		# Clear drops/flakes left over from the previous weather.
		if _rain:
			_rain.restart()
			_snow.restart()


func is_night() -> bool:
	return _sun_for(hour).y < -0.05


## Unit vector pointing toward the sun (below the horizon at night).
func sun_direction() -> Vector3:
	return _sun_for(hour)


## Unit vector pointing toward the moon.
func moon_direction() -> Vector3:
	return _moon_for(hour)


## Fire a lightning strike now (storms do this on their own).
func strike_lightning() -> void:
	_strike_t = 0.0
	var n := _rng.randi_range(2, 4)
	var t := 0.0
	for i in 4:
		if i < n:
			_pulse_t[i] = t
			_pulse_a[i] = _rng.randf_range(0.5, 1.0) if i > 0 else 1.0
			t += _rng.randf_range(0.05, 0.16)
		else:
			_pulse_a[i] = 0.0
	var a := _rng.randf() * TAU
	var dir := Vector3(cos(a), -_rng.randf_range(0.5, 1.2), sin(a)).normalized()
	lightning_light.global_basis = Basis.looking_at(dir, Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP)
	var dist := _rng.randf_range(250.0, 3000.0)
	_thunder_delay = dist / 343.0
	_thunder_gain = clampf(1.0 - (dist - 250.0) / 3500.0, 0.25, 1.0)
	_thunder_close = dist < 900.0


func _init() -> void:
	_rng.randomize()
	_gust_noise.seed = _rng.randi()
	_gust_noise.frequency = 0.15
	_gust_noise.fractal_octaves = 3
	_wind_angle = _rng.randf() * TAU
	# Built here so environment / sun / moon can be tweaked right after Weather.new().
	_build_environment()
	_build_lights()


func _ready() -> void:
	_build_precipitation()
	_build_audio()
	if not _initialized:
		set_preset(_state if not _dynamic else "dynamic", true)
	_initialized = true
	_update(0.0)


func _exit_tree() -> void:
	if _gen_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	_clock += delta
	if day_length_minutes > 0.0:
		hour += delta * 24.0 / (day_length_minutes * 60.0)

	if _dynamic and delta > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			_advance_chain()

	_smooth_weather(delta)
	_sun_dir = _sun_for(hour)
	_moon_dir = _moon_for(hour)
	if _sun_dir.angle_to(_sky_full_dir) > 0.05:
		for i in 5:
			_refresh_sky_colors(i)
		_sky_full_dir = _sun_dir
	else:
		_refresh_sky_colors(_sky_step)
		_sky_step = (_sky_step + 1) % 5
	_update_ground(delta)
	_update_lightning(delta)
	_update_lights_and_env()
	_update_sky_uniforms(delta)
	_update_precipitation(delta)
	_update_audio(delta)
	_publish_globals()


# --- Weather state ---------------------------------------------------------

func _apply_targets(preset_name: String) -> void:
	var p: Dictionary = PRESETS[preset_name]
	_t_cover = p["cover"]
	_t_dark = p["dark"]
	_t_rain = p["rain"]
	_t_snow = p["snow"]
	_t_fog = p["fog"]
	_t_wind = p["wind"]
	_t_haze = p["haze"]
	_t_lightning = p["lightning"]
	_t_temp = p["temp"]


func _snap() -> void:
	cloud_cover = _t_cover
	_cloud_dark = _t_dark
	rain_intensity = _t_rain
	snow_intensity = _t_snow
	fog_amount = _t_fog
	_wind_speed = _t_wind
	_haze = _t_haze
	_lightning = _t_lightning
	temperature = _t_temp
	wetness = clampf(_t_rain * 1.5, wetness, 1.0)
	wetness = maxf(wetness, float(PRESETS.get(_state, {}).get("ground_wet", 0.0)))
	snow_cover = maxf(snow_cover, _t_snow)
	ice = _ice_target() # starting cold: it froze overnight
	ice_now = ice
	wet_now = wetness
	rain_now = rain_intensity
	snow_now = snow_intensity
	snow_cover_now = snow_cover
	_initialized = true


func _advance_chain() -> void:
	var options: Dictionary = CHAIN[_state]
	var total := 0.0
	for k: String in options:
		total += _chain_weight(k, options[k])
	var pick := _rng.randf() * total
	var next := _state
	for k: String in options:
		pick -= _chain_weight(k, options[k])
		if pick <= 0.0:
			next = k
			break
	if allow_snow_in_dynamic and next == "rain" and temperature < 4.0:
		next = "snow"
	_state = next
	_apply_targets(next)
	_hold = _rng.randf_range(dynamic_hold_min, dynamic_hold_max)
	if next == "storm" or next == "fog":
		_hold *= 0.6


func _chain_weight(next: String, w: float) -> float:
	if next == "fog" and (hour > 4.0 and hour < 9.5):
		return w * 3.0 # morning mist
	if next == "snow" and not allow_snow_in_dynamic:
		return 0.0
	return w


func _smooth_weather(delta: float) -> void:
	var k := 1.0 - exp(-delta * 4.0 / maxf(transition_seconds, 0.01))
	cloud_cover = lerpf(cloud_cover, _t_cover, k)
	_cloud_dark = lerpf(_cloud_dark, _t_dark, k)
	# Rain and snow only fall once the cloud deck has built up, and stop first.
	var deck := smoothstep(0.7, 0.92, cloud_cover)
	rain_intensity = lerpf(rain_intensity, _t_rain * deck, k)
	snow_intensity = lerpf(snow_intensity, _t_snow * deck, k)
	fog_amount = lerpf(fog_amount, _t_fog, k)
	_wind_speed = lerpf(_wind_speed, _t_wind, k)
	_haze = lerpf(_haze, _t_haze, k)
	_lightning = lerpf(_lightning, _t_lightning * deck, k)
	var diurnal := 4.0 * clampf(_sun_dir.y, -0.5, 1.0)
	temperature = lerpf(temperature, _t_temp + diurnal, 1.0 - exp(-delta * 2.0 / maxf(transition_seconds, 0.01)))

	# Wind: slowly wandering direction, noisy gusts that grow with strength.
	_wind_angle += (_gust_noise.get_noise_1d(_clock * 0.02 + 500.0)) * delta * 0.05
	var g := _gust_noise.get_noise_1d(_clock) * 0.5 + 0.5
	gust = clampf(g * g * 1.6, 0.0, 1.0) * clampf(_wind_speed / 10.0, 0.15, 1.0)
	var strength := _wind_speed * (0.7 + 0.6 * gust)
	wind = Vector3(cos(_wind_angle), 0.0, sin(_wind_angle)) * strength


func _update_ground(delta: float) -> void:
	var sun_heat := clampf(_sun_dir.y * 2.0, 0.0, 1.0) * (1.0 - 0.7 * cloud_cover)
	if rain_intensity > 0.02:
		wetness += rain_intensity * delta / 40.0
	else:
		var dry := (0.25 + 0.9 * sun_heat + 0.05 * _wind_speed) * (1.0 - 0.8 * fog_amount)
		wetness -= dry * delta / 900.0 * (1.0 - ice) # frozen water stays put
	if snow_intensity > 0.02:
		snow_cover += snow_intensity * delta / 100.0
	elif temperature > 1.0 and snow_cover > 0.0:
		var melt := (temperature - 1.0) * (0.4 + sun_heat) * delta / 1800.0 + rain_intensity * delta / 300.0
		snow_cover -= melt
		wetness += melt * 0.8
	wetness = clampf(wetness, 0.0, 1.0)
	snow_cover = clampf(snow_cover, 0.0, 1.0)
	# Below zero what is wet freezes over a few minutes; above it the ice turns back to water.
	var target := _ice_target()
	if target > ice:
		ice = move_toward(ice, target, delta / 180.0)
	else:
		var thaw := maxf(temperature - 0.5, 0.0) * (0.5 + sun_heat)
		ice = move_toward(ice, target, delta * maxf(thaw, 0.05) / 600.0)
		wetness = maxf(wetness, ice * 0.9) # melting ice leaves the road wet
	ice_now = ice
	wet_now = wetness
	rain_now = rain_intensity
	snow_now = snow_intensity
	snow_cover_now = snow_cover


## How much would be frozen at this temperature: standing water, and snow packed on the roads.
func _ice_target() -> float:
	var freeze := smoothstep(1.0, -2.5, temperature)
	return clampf(maxf(wetness, snow_cover * 0.6) * freeze, 0.0, 1.0)


# --- Sun, moon and atmosphere ---------------------------------------------

func _sun_for(h: float) -> Vector3:
	var phase: float
	if h >= SUNRISE and h <= SUNSET:
		phase = (h - SUNRISE) / (SUNSET - SUNRISE) * PI
	else:
		phase = PI + fposmod(h - SUNSET, 24.0) / (24.0 - (SUNSET - SUNRISE)) * PI
	# Rises in the east (+X), crosses the south (+Z) high up, sets in the west.
	var s := sin(phase)
	return Vector3(cos(phase), s * sin(SUN_MAX_ELEVATION), s * cos(SUN_MAX_ELEVATION) + 0.12).normalized()


func _moon_for(h: float) -> Vector3:
	# Roughly opposite the sun, a little behind it and on a lower arc.
	var phase := PI + (fposmod(h - SUNRISE, 24.0) / 24.0) * TAU + 0.35
	var s := sin(phase)
	return Vector3(cos(phase), s * sin(MOON_MAX_ELEVATION), s * cos(MOON_MAX_ELEVATION) - 0.2).normalized()


static func _exit_dist(o: Vector3, d: Vector3, r: float) -> float:
	var b := o.dot(d)
	var c := o.dot(o) - r * r
	return -b + sqrt(maxf(b * b - c, 0.0))


static func _v_exp(v: Vector3) -> Vector3:
	return Vector3(exp(v.x), exp(v.y), exp(v.z))


## Sunlight transmittance from a point at height `alt` toward `ldir`.
func _transmittance(ldir: Vector3, alt: float) -> Vector3:
	var o := Vector3(0.0, PR + alt, 0.0)
	var b := o.dot(ldir)
	if b < 0.0 and b * b - (o.dot(o) - PR * PR) > 0.0:
		return Vector3.ZERO
	var lt := _exit_dist(o, ldir, AR)
	var odr := 0.0
	var odm := 0.0
	for j in 12:
		var s0 := lt * pow(j / 12.0, 2.0)
		var s1 := lt * pow((j + 1) / 12.0, 2.0)
		var hq := (o + ldir * (0.5 * (s0 + s1))).length() - PR
		odr += exp(-hq / HR) * (s1 - s0)
		odm += exp(-hq / HM) * (s1 - s0)
	return _v_exp(-((BR + BO) * odr + Vector3.ONE * (BM * 1.11 * _haze * odm)))


## Same single-scattering as the sky shader, for a handful of CPU-side colours.
func _sky_radiance(dir: Vector3, ldir: Vector3) -> Vector3:
	if ldir.y < -0.3:
		return Vector3.ZERO
	var o := Vector3(0.0, PR + EYE_H, 0.0)
	var tmax := _exit_dist(o, dir, AR)
	var mu := dir.dot(ldir)
	var pr := 0.0596831 * (1.0 + mu * mu)
	var g := 0.76
	var pm := 0.1193662 * ((1.0 - g * g) * (1.0 + mu * mu)) / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5))
	var sr := Vector3.ZERO
	var sm := Vector3.ZERO
	var odr := 0.0
	var odm := 0.0
	for i in 10:
		var t0 := tmax * pow(i / 10.0, 2.0)
		var t1 := tmax * pow((i + 1) / 10.0, 2.0)
		var ds := t1 - t0
		var p := o + dir * (0.5 * (t0 + t1))
		var h := p.length() - PR
		var dr := exp(-h / HR) * ds
		var dm := exp(-h / HM) * ds
		odr += dr * 0.5
		odm += dm * 0.5
		var lb := p.dot(ldir)
		if not (lb < 0.0 and lb * lb - (p.dot(p) - PR * PR) > 0.0):
			var lt := _exit_dist(p, ldir, AR)
			var lodr := 0.0
			var lodm := 0.0
			for j in 4:
				var s0 := lt * pow(j * 0.25, 2.0)
				var s1 := lt * pow((j + 1) * 0.25, 2.0)
				var hq := (p + ldir * (0.5 * (s0 + s1))).length() - PR
				lodr += exp(-hq / HR) * (s1 - s0)
				lodm += exp(-hq / HM) * (s1 - s0)
			var att := _v_exp(-((BR + BO) * (odr + lodr) + Vector3.ONE * (BM * 1.11 * _haze * (odm + lodm))))
			sr += att * dr
			sm += att * dm
		odr += dr * 0.5
		odm += dm * 0.5
	return SUN_POWER * (sr * BR * pr + sm * (BM * _haze * pm))


## The few sky colours the CPU needs (sunlight, zenith, horizon), one piece per call.
func _refresh_sky_colors(step: int) -> void:
	var side := Vector3(-_sun_dir.z, 0.0, _sun_dir.x)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var toward := Vector3(_sun_dir.x, 0.0, _sun_dir.z)
	toward = toward.normalized() if toward.length_squared() > 1e-4 else side
	match step:
		0:
			_sun_t_ground = _transmittance(_sun_dir, EYE_H)
			_sun_t_cloud = _transmittance(_sun_dir, 1800.0)
		1:
			_zenith_col = _sky_radiance(Vector3.UP, _sun_dir)
		2:
			_h_side = _sky_radiance(side, _sun_dir)
		3:
			_h_toward = _sky_radiance(toward, _sun_dir)
		4:
			_h_away = _sky_radiance(-toward, _sun_dir)
	_horizon_col = (_h_side * 2.0 + _h_toward + _h_away) * 0.25


static func _luma(c: Vector3) -> float:
	return c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722


## Light falling on the cloud deck from the sky above it (also the base for overcast fog colour).
func _cloud_ambient() -> Vector3:
	return _zenith_col * 1.3 + _horizon_col * 0.45 + Vector3(0.012, 0.016, 0.03) * _night_factor()


## How much the moon lights the night: 0 a new moon under cloud .. 1 a full moon, clear.
func night_light() -> float:
	return clampf((0.1 + 0.9 * moon_phase) * (1.0 - 0.7 * smoothstep(0.35, 1.0, cloud_cover)) * (1.0 - 0.4 * fog_amount), 0.0, 1.0)


func _night_factor() -> float:
	return smoothstep(0.02, -0.2, _sun_dir.y)


func _update_lights_and_env() -> void:
	var night := _night_factor()
	var overcast := smoothstep(0.35, 1.0, cloud_cover)
	var golden := smoothstep(-0.02, 0.06, _sun_dir.y) * (1.0 - smoothstep(0.12, 0.4, _sun_dir.y))

	# Sun: colour is the real atmospheric transmittance, energy dimmed by cloud/fog.
	var t := _sun_t_ground
	var tmax := maxf(maxf(t.x, t.y), maxf(t.z, 1e-5))
	var block := (1.0 - 0.9 * overcast * overcast) * (1.0 - 0.55 * fog_amount) * (1.0 - 0.3 * rain_intensity)
	var horizon_fade := smoothstep(-0.015, 0.04, _sun_dir.y)
	var sun_energy := 3.3 * tmax * block * horizon_fade
	sun.light_color = Color(t.x / tmax, t.y / tmax, t.z / tmax)
	sun.light_energy = sun_energy
	sun.shadow_opacity = lerpf(1.0, 0.45, overcast)
	# (low sun and forward-scattering air: shafts, not a wall of glare that washes the whole view
	# out when you look toward it)
	sun.light_volumetric_fog_energy = 1.0 + golden * 0.6
	sun.visible = sun_energy > 0.002
	if sun.visible and _sun_dir.angle_to(_sun_light_dir) > 0.0015:
		_sun_light_dir = _sun_dir
		sun.global_basis = Basis.looking_at(-_sun_dir, Vector3.UP)

	# Moon: weak, bluish, only when it is up and the sun is down.
	var moon_up := smoothstep(-0.03, 0.12, _moon_dir.y)
	var moon_energy := 0.2 * moon_up * night * (0.4 + 0.6 * moon_phase) * (1.0 - 0.75 * overcast) * (1.0 - 0.6 * fog_amount)
	moon.light_energy = moon_energy
	moon.visible = moon_energy > 0.003
	if moon.visible and _moon_dir.angle_to(_moon_light_dir) > 0.003:
		_moon_light_dir = _moon_dir
		moon.global_basis = Basis.looking_at(-_moon_dir, Vector3.UP)

	lightning_light.light_energy = lightning_flash * 3.5
	lightning_light.visible = lightning_flash > 0.01

	var env := environment
	# Ambient: sky radiance by day; at night a moonlit blue whose strength is the moon's: a
	# full moon on a clear night you can drive by, a new moon under cloud you can't without
	# lights (or night-vision goggles). That is what makes the lights a choice.
	env.ambient_light_sky_contribution = lerpf(1.0, 0.35, night)
	var twilight := smoothstep(0.3, 0.0, _sun_dir.y) * (1.0 - night)
	var moonlit := night_light()
	# Night is dark: under a full moon you make out shapes, the road, the skyline, not colours or
	# what stands in the trees; without one you see nothing past your own lights. (The eye's
	# adaptation, the exposure, lifts it far less than it did.)
	env.ambient_light_energy = lerpf(0.62, lerpf(0.015, 0.12, moonlit), night) + 0.35 * twilight + lightning_flash * 1.5
	env.tonemap_exposure = lerpf(0.9, lerpf(0.9, 1.15, moonlit), night) * (1.0 + 0.35 * twilight)

	# Distance fog: aerial-perspective haze over the 2 km map, thick valley fog for "fog".
	var hz := _horizon_col
	var fog_col := hz.lerp(Vector3.ONE * _luma(hz) * 0.95, clampf(fog_amount, 0.0, 1.0))
	# Under a cloud deck the haze takes the deck's (darker, greyer) colour.
	var ca := _cloud_ambient()
	var deck := ca.lerp(Vector3.ONE * _luma(ca), 0.5) * 0.62 * (1.0 - 0.6 * _cloud_dark) + _sun_t_ground * (0.12 * (1.0 - _cloud_dark))
	fog_col = fog_col.lerp(deck, smoothstep(0.5, 1.0, cloud_cover))
	var night_fog := Vector3(0.018, 0.024, 0.04) * (0.5 + moon_up * 0.5)
	fog_col = fog_col.lerp(night_fog, night * 0.85)
	var fcm := maxf(maxf(fog_col.x, fog_col.y), maxf(fog_col.z, 1e-4))
	env.fog_light_color = Color(fog_col.x / fcm, fog_col.y / fcm, fog_col.z / fcm)
	env.fog_light_energy = clampf(fcm, 0.02, 4.0)
	env.fog_density = 0.00013 * _haze + fog_amount * 0.006 + rain_intensity * 0.0005 + snow_intensity * 0.0022
	env.fog_sky_affect = clampf(fog_amount * 0.85 + rain_intensity * 0.35 + snow_intensity * 0.4, 0.0, 1.0)
	env.fog_sun_scatter = 0.12 * (1.0 - overcast) * (1.0 - 0.6 * golden)
	env.fog_aerial_perspective = lerpf(0.4, 0.2, clampf(fog_amount + overcast * 0.5, 0.0, 1.0))

	# Volumetric fog: a little air for sun shafts (more at golden hour), thick in fog/rain.
	env.volumetric_fog_density = 0.0008 + golden * 0.0008 * (1.0 - overcast) + fog_amount * fog_amount * 0.004 + rain_intensity * 0.0012 + snow_intensity * 0.006
	env.volumetric_fog_anisotropy = lerpf(0.65 - 0.15 * golden, 0.25, clampf(fog_amount + overcast, 0.0, 1.0))
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_emission = Color(night_fog.x, night_fog.y, night_fog.z) * night * 0.3
	env.volumetric_fog_ambient_inject = lerpf(0.4, 1.0, clampf(fog_amount + overcast * 0.5, 0.0, 1.0)) * (1.0 - 0.75 * night)


func _update_sky_uniforms(delta: float) -> void:
	var night := _night_factor()
	var drift := Vector2(wind.x, wind.z) * delta * cloud_speed_scale
	_cloud_offset += drift * 0.0006 * 2.0
	_cirrus_offset += drift * 0.00009 * 3.5
	# Keep offsets small so float precision never shows (noise has no period, so jump with care).
	if absf(_cloud_offset.x) > 4000.0 or absf(_cloud_offset.y) > 4000.0:
		_cloud_offset = Vector2.ZERO
	var amb := _cloud_ambient()
	var m := _sky_mat
	m.set_shader_parameter(&"sun_dir", _sun_dir)
	m.set_shader_parameter(&"moon_dir", _moon_dir)
	m.set_shader_parameter(&"sun_power", SUN_POWER)
	m.set_shader_parameter(&"moon_power", 0.4 + 0.6 * moon_phase)
	m.set_shader_parameter(&"sun_tint", _sun_t_cloud)
	m.set_shader_parameter(&"ambient_color", amb)
	m.set_shader_parameter(&"cloud_cover", cloud_cover)
	m.set_shader_parameter(&"cloud_dark", _cloud_dark)
	m.set_shader_parameter(&"cloud_offset", _cloud_offset)
	m.set_shader_parameter(&"cirrus_offset", _cirrus_offset)
	m.set_shader_parameter(&"haze", _haze)
	m.set_shader_parameter(&"night", night)
	m.set_shader_parameter(&"star_rotation", hour / 24.0 * TAU)
	m.set_shader_parameter(&"moon_phase", moon_phase)
	m.set_shader_parameter(&"flash", lightning_flash)
	m.set_shader_parameter(&"twinkle_time", _clock)
	m.set_shader_parameter(&"sky_grey", clampf(fog_amount * 0.6 + rain_intensity * 0.3 + snow_intensity * 0.3, 0.0, 1.0))


func _publish_globals() -> void:
	wind_now = wind
	var w := Vector3(wind.x / WIND_NORM, gust, wind.z / WIND_NORM)
	var horiz := Vector2(w.x, w.z)
	if horiz.length() > 1.0:
		horiz = horiz.normalized()
		w.x = horiz.x
		w.z = horiz.y
	RenderingServer.global_shader_parameter_set(&"weather_wetness", wetness)
	RenderingServer.global_shader_parameter_set(&"weather_snow", snow_cover)
	RenderingServer.global_shader_parameter_set(&"weather_ice", ice)
	RenderingServer.global_shader_parameter_set(&"weather_rain", rain_intensity)
	RenderingServer.global_shader_parameter_set(&"weather_wind", w)
	# What the weather does to the senses (Hearing): rain and a gale drown sound out; the dark,
	# fog, rain and falling snow close in how far anyone sees.
	var gale := clampf((wind.length() - 5.0) / 10.0, 0.0, 1.0)
	Hearing.carry = clampf(1.0 - rain_intensity * 0.4 - gale * 0.25 - snow_intensity * 0.15, 0.45, 1.0)
	var see := lerpf(1.0, lerpf(0.22, 0.5, night_light()), _night_factor())
	see *= 1.0 - 0.6 * clampf(fog_amount, 0.0, 1.0)
	see *= 1.0 - 0.25 * rain_intensity - 0.3 * snow_intensity
	Hearing.visibility = clampf(see, 0.12, 1.0)
	# How much daylight there is (1 day .. a little moonlight at night): for what glows on its
	# own, like the water's colour, so it goes dark with the rest at night.
	RenderingServer.global_shader_parameter_set(&"weather_daylight", lerpf(1.0, 0.04 + 0.08 * night_light(), _night_factor()))


# --- Lightning -------------------------------------------------------------

func _update_lightning(delta: float) -> void:
	if _lightning > 0.05:
		_strike_timer -= delta
		if _strike_timer <= 0.0:
			_strike_timer = _rng.randf_range(4.0, 16.0) / _lightning
			strike_lightning()
	_strike_t += delta
	var f := 0.0
	if _strike_t < 1.5:
		for i in 4:
			var dt := _strike_t - _pulse_t[i]
			if _pulse_a[i] > 0.0 and dt >= 0.0:
				f = maxf(f, _pulse_a[i] * exp(-dt * 22.0))
	lightning_flash = f
	if _thunder_delay >= 0.0:
		_thunder_delay -= delta
		if _thunder_delay < 0.0:
			_play_thunder()


func _play_thunder() -> void:
	if _thunder_streams.is_empty():
		return
	var p := _thunder_players[_thunder_next]
	_thunder_next = (_thunder_next + 1) % _thunder_players.size()
	var idx := 0 if _thunder_close else _rng.randi_range(1, _thunder_streams.size() - 1)
	p.stream = _thunder_streams[idx]
	p.pitch_scale = _rng.randf_range(0.85, 1.1)
	p.volume_db = linear_to_db(_thunder_gain * 0.9) + sound_volume_db
	p.play()


# --- Building --------------------------------------------------------------

func _build_environment() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky = Sky.new()
	_sky.sky_material = _sky_mat
	_sky.radiance_size = Sky.RADIANCE_SIZE_256
	_sky.process_mode = Sky.PROCESS_MODE_REALTIME

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = _sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.3, 0.38, 0.58)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 7.0
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_intensity = 2.4
	env.ssao_power = 1.4
	env.ssao_detail = 0.5
	env.sdfgi_enabled = false
	env.ssil_enabled = false # its noise crawls frame to frame on grass and foliage
	# Puddles and flooded ruts mirror the trees, the truck and the sky (only smooth surfaces
	# take it: the water, wet tarmac).
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0003
	env.volumetric_fog_enabled = true
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.3
	env.adjustment_contrast = 1.06
	environment = env

	# Low-lying fog bank that rides with the camera: full density below its
	# centre, thinning out upward (FogMaterial height_falloff).
	_ground_fog_mat = FogMaterial.new()
	_ground_fog_mat.density = 0.0
	_ground_fog_mat.albedo = Color(0.92, 0.93, 0.95)
	_ground_fog_mat.height_falloff = 0.07
	_ground_fog_mat.edge_fade = 0.25
	_ground_fog = FogVolume.new()
	_ground_fog.name = "GroundFog"
	_ground_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	_ground_fog.size = Vector3(380.0, 260.0, 380.0)
	_ground_fog.material = _ground_fog_mat
	_ground_fog.visible = false
	add_child(_ground_fog)

	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = env
	# (No depth-of-field blur: driving, the road ahead has to stay sharp.)
	add_child(world_environment)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 200.0
	sun.directional_shadow_split_1 = 0.05 # 10 m
	sun.directional_shadow_split_2 = 0.15 # 30 m
	sun.directional_shadow_split_3 = 0.4  # 80 m
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 120.0
	moon.directional_shadow_split_1 = 0.2
	moon.shadow_bias = 0.05
	moon.shadow_normal_bias = 1.5
	moon.light_volumetric_fog_energy = 2.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	moon.visible = false
	add_child(moon)

	lightning_light = DirectionalLight3D.new()
	lightning_light.name = "Lightning"
	lightning_light.light_color = Color(0.78, 0.84, 1.0)
	lightning_light.shadow_enabled = false
	lightning_light.light_volumetric_fog_energy = 3.0
	lightning_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	lightning_light.visible = false
	add_child(lightning_light)


func _build_precipitation() -> void:
	var aabb := AABB(Vector3(-40.0, -45.0, -40.0), Vector3(80.0, 80.0, 80.0))

	# Rain streaks.
	_rain_pm = ParticleProcessMaterial.new()
	_rain_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_pm.emission_box_extents = Vector3(18.0, 12.0, 18.0)
	_rain_pm.direction = Vector3.DOWN
	_rain_pm.spread = 1.5
	_rain_pm.initial_velocity_min = 9.0
	_rain_pm.initial_velocity_max = 11.0
	_rain_pm.gravity = Vector3.ZERO
	_rain_pm.particle_flag_align_y = true
	_rain_pm.scale_min = 0.75
	_rain_pm.scale_max = 1.25
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = RAIN_SHADER
	var rain_mesh := QuadMesh.new()
	rain_mesh.material = _rain_mat
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 20000
	_rain.lifetime = 2.6
	_rain.randomness = 0.5
	_rain.fixed_fps = 60
	_rain.local_coords = false
	_rain.visibility_aabb = aabb
	_rain.process_material = _rain_pm
	_rain.draw_pass_1 = rain_mesh
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.emitting = false
	add_child(_rain)

	# Snow flakes.
	_snow_pm = ParticleProcessMaterial.new()
	_snow_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_pm.emission_box_extents = Vector3(18.0, 8.0, 18.0)
	_snow_pm.direction = Vector3.DOWN
	_snow_pm.spread = 15.0
	_snow_pm.initial_velocity_min = 0.8
	_snow_pm.initial_velocity_max = 1.4
	_snow_pm.gravity = Vector3(0.0, -0.15, 0.0)
	_snow_pm.damping_min = 0.3
	_snow_pm.damping_max = 0.6
	_snow_pm.scale_min = 0.6
	_snow_pm.scale_max = 1.4
	_snow_pm.turbulence_enabled = true
	_snow_pm.turbulence_noise_strength = 1.2
	_snow_pm.turbulence_noise_scale = 6.0
	_snow_pm.turbulence_noise_speed_random = 0.4
	_snow_pm.turbulence_influence_min = 0.03
	_snow_pm.turbulence_influence_max = 0.08
	_snow_mat = ShaderMaterial.new()
	_snow_mat.shader = FLAKE_SHADER
	var snow_mesh := QuadMesh.new()
	snow_mesh.material = _snow_mat
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = 14000
	_snow.lifetime = 11.0
	_snow.randomness = 0.5
	_snow.fixed_fps = 30
	_snow.local_coords = false
	_snow.visibility_aabb = aabb
	_snow.process_material = _snow_pm
	_snow.draw_pass_1 = snow_mesh
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow.emitting = false
	add_child(_snow)

	if not precipitation_collision:
		return
	# Drops and flakes end on whatever is under them (ground, truck roof, cab):
	# a heightfield of the area around the camera, re-rendered when it moves.
	_rain_pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.collision_base_size = 0.02
	_snow_pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_snow.collision_base_size = 0.02

	_collider = GPUParticlesCollisionHeightField3D.new()
	_collider.name = "PrecipitationCollision"
	_collider.size = Vector3(56.0, 90.0, 56.0)
	_collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_collider.position = Vector3(0.0, -100000.0, 0.0) # so the first snap to the camera counts as a move
	add_child(_collider)


func _update_precipitation(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_rain.emitting = false
		_snow.emitting = false
		return
	var pos := cam.global_position
	_update_ground_fog(pos)
	if not _have_cam or pos.distance_to(_cam_prev) > 60.0:
		_cam_vel = Vector3.ZERO
		_have_cam = true
	elif delta > 0.0:
		var v := (pos - _cam_prev) / delta
		_cam_vel = _cam_vel.lerp(v.limit_length(45.0), 1.0 - exp(-delta * 3.0))
	_cam_prev = pos

	var light := clampf(sun.light_energy * 0.3 + _luma(_zenith_col) * 1.2 * (1.0 - 0.5 * _cloud_dark) + moon.light_energy * 1.5 + 0.04 + lightning_flash * 2.0, 0.05, 1.3)

	# Brightness is kept current even while not emitting: drops/flakes already in the air live on.
	_rain_mat.set_shader_parameter(&"brightness", light)
	_snow_mat.set_shader_parameter(&"brightness", minf(light * 1.6 + 0.15, 1.6))

	# Rain: the box rides ahead of the camera by where it will be mid-way through a drop's life.
	var raining := rain_intensity > 0.01
	_rain.emitting = raining
	if raining:
		_rain.amount_ratio = clampf(rain_intensity, 0.0, 1.0)
		_rain.global_position = pos + _cam_vel * 1.0 + Vector3(0.0, 9.0, 0.0)
		var fall := Vector3(wind.x, -10.0, wind.z)
		var speed := fall.length()
		_rain_pm.direction = fall / speed
		_rain_pm.initial_velocity_min = speed * 0.9
		_rain_pm.initial_velocity_max = speed * 1.1
		_rain_mat.set_shader_parameter(&"opacity", 0.32 + 0.25 * rain_intensity)

	var snowing := snow_intensity > 0.01
	_snow.emitting = snowing
	if snowing:
		_snow.amount_ratio = clampf(snow_intensity, 0.0, 1.0)
		_snow.global_position = pos + _cam_vel * 3.0 + Vector3(0.0, 4.0, 0.0)
		var drift := Vector3(wind.x * 0.8, -1.1, wind.z * 0.8)
		_snow_pm.direction = drift.normalized()
		_snow_pm.initial_velocity_min = drift.length() * 0.8
		_snow_pm.initial_velocity_max = drift.length() * 1.2
		_snow_pm.gravity = Vector3(wind.x * 0.15, -0.15, wind.z * 0.15)

	if _collider:
		var active := raining or snowing
		_collider.visible = active
		if active:
			var snapped_pos := Vector3(snappedf(pos.x, 2.0), snappedf(pos.y, 8.0), snappedf(pos.z, 2.0))
			if not _collider.global_position.is_equal_approx(snapped_pos):
				_collider.global_position = snapped_pos


func _update_ground_fog(cam_pos: Vector3) -> void:
	var density := fog_amount * fog_amount * 0.07 + snow_intensity * 0.004
	_ground_fog.visible = density > 0.0005
	if not _ground_fog.visible:
		return
	_ground_fog_mat.density = density
	# Fog lies in the valleys (below fog_base_height) but always reaches the player.
	var layer := maxf(fog_base_height, cam_pos.y - 4.0)
	_ground_fog.global_position = Vector3(snappedf(cam_pos.x, 4.0), layer, snappedf(cam_pos.z, 4.0))


# --- Sound -----------------------------------------------------------------

func _build_audio() -> void:
	_rain_player = _make_player("RainSound")
	_wind_lo = _make_player("WindSound")
	_wind_hi = _make_player("WindWhistle")
	for i in 2:
		_thunder_players.append(_make_player("Thunder%d" % i))
	_gen_task = WorkerThreadPool.add_task(_synthesise_sounds, false, "Weather sound synthesis")


func _make_player(n: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	p.bus = audio_bus
	p.volume_db = -80.0
	add_child(p)
	return p


func _update_audio(delta: float) -> void:
	if _gen_task >= 0:
		if not WorkerThreadPool.is_task_completed(_gen_task):
			return
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1
		_on_sounds_ready()
	if _rain_player.stream == null:
		return
	var storm := clampf(_lightning, 0.0, 1.0)
	var rain_lin := rain_intensity * (0.55 + 0.25 * storm)
	_set_loop_volume(_rain_player, rain_lin, delta)
	_rain_player.pitch_scale = lerpf(1.05, 0.9, rain_intensity)
	var w := clampf(_wind_speed / 14.0, 0.0, 1.0)
	var lo := (0.08 + 0.55 * w) * (0.55 + 0.45 * gust)
	var hi := w * w * (0.15 + 0.6 * gust) * 0.55
	_set_loop_volume(_wind_lo, lo, delta)
	_set_loop_volume(_wind_hi, hi, delta)
	_wind_lo.pitch_scale = 0.85 + 0.3 * gust
	_wind_hi.pitch_scale = 0.9 + 0.25 * gust + 0.1 * w


func _set_loop_volume(p: AudioStreamPlayer, lin: float, _delta: float) -> void:
	if lin < 0.003:
		if p.playing and not p.stream_paused:
			p.stream_paused = true
		return
	p.volume_db = linear_to_db(lin) + sound_volume_db
	if not p.playing:
		p.play(_rng.randf() * 2.0)
	p.stream_paused = false


func _on_sounds_ready() -> void:
	_rain_player.stream = _gen_out["rain"]
	_wind_lo.stream = _gen_out["wind_lo"]
	_wind_hi.stream = _gen_out["wind_hi"]
	_thunder_streams.clear()
	for s: AudioStreamWAV in _gen_out["thunder"]:
		_thunder_streams.append(s)
	_gen_out.clear()


## Runs on a worker thread: synthesises every weather sound into looping PCM.
## Done once up front so nothing per-sample runs during gameplay.
func _synthesise_sounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7_211_017
	var out := {}
	out["rain"] = _synth_rain(rng, 22050, 5.0)
	out["wind_lo"] = _synth_wind(rng, 22050, 8.0, false)
	out["wind_hi"] = _synth_wind(rng, 22050, 7.0, true)
	var thunder: Array[AudioStreamWAV] = []
	thunder.append(_synth_thunder(rng, 16000, 7.0, true))
	thunder.append(_synth_thunder(rng, 16000, 8.0, false))
	thunder.append(_synth_thunder(rng, 16000, 9.0, false))
	out["thunder"] = thunder
	_gen_out = out


static func _synth_rain(rng: RandomNumberGenerator, rate: int, seconds: float) -> AudioStreamWAV:
	var frames := int(rate * seconds)
	var xf := rate / 4
	var n := frames + xf
	var buf := PackedFloat32Array()
	buf.resize(n * 2)
	for ch in 2:
		var b0 := 0.0
		var b1 := 0.0
		var b2 := 0.0
		var hp := 0.0
		var hp_in := 0.0
		var lp := 0.0
		var drop := 0.0
		var drop_decay := 0.0
		var body := 0.0
		for i in n:
			var w := rng.randf() * 2.0 - 1.0
			# Pink noise (Paul Kellet, economy) for the steady hiss of distant rain.
			b0 = 0.99765 * b0 + w * 0.0990460
			b1 = 0.96300 * b1 + w * 0.2965164
			b2 = 0.57000 * b2 + w * 1.0526913
			var pink := (b0 + b1 + b2 + w * 0.1848) * 0.11
			hp = 0.94 * (hp + pink - hp_in)
			hp_in = pink
			# Brownish body under it.
			body = body * 0.995 + w * 0.02
			# Individual close drops: sparse short crackles.
			if rng.randf() < 0.0035:
				drop = rng.randf() * rng.randf() * 1.1
				drop_decay = rng.randf_range(0.86, 0.95)
			drop *= drop_decay
			var s := hp * 0.75 + body * 0.35 + drop * w * 0.9
			lp += (s - lp) * 0.6
			buf[i * 2 + ch] = lp
	return _to_wav(buf, 2, rate, frames, xf, true)


static func _synth_wind(rng: RandomNumberGenerator, rate: int, seconds: float, whistle: bool) -> AudioStreamWAV:
	var frames := int(rate * seconds)
	var xf := rate / 2
	var n := frames + xf
	var buf := PackedFloat32Array()
	buf.resize(n * 2)
	var period := float(frames) / rate
	for ch in 2:
		var ph := rng.randf() * TAU
		var lo := 0.0
		var lo2 := 0.0
		var brown := 0.0
		var svf_low := 0.0
		var svf_band := 0.0
		for i in n:
			var t := float(i) / rate
			var w := rng.randf() * 2.0 - 1.0
			var s: float
			if whistle:
				# Resonant band-pass sweeping slowly: the whistle through trees and the cab.
				var fc := 560.0 + 220.0 * sin(TAU * t * 2.0 / period + ph) + 90.0 * sin(TAU * t * 5.0 / period + ph * 1.7)
				var f := 2.0 * sin(PI * fc / rate)
				var high := w - svf_low - 0.12 * svf_band
				svf_band += f * high
				svf_low += f * svf_band
				s = svf_band * 0.09
			else:
				# Low roar: brown noise through two one-pole low-passes.
				brown = (brown + w * 0.05) * 0.997
				lo += (brown - lo) * 0.08
				lo2 += (lo - lo2) * 0.08
				s = lo2 * 2.2 + w * 0.012
			var amp := 0.7 + 0.2 * sin(TAU * t * 3.0 / period + ph) + 0.1 * sin(TAU * t * 7.0 / period + ph * 2.3)
			buf[i * 2 + ch] = s * amp
	return _to_wav(buf, 2, rate, frames, xf, true)


static func _synth_thunder(rng: RandomNumberGenerator, rate: int, seconds: float, close: bool) -> AudioStreamWAV:
	var n := int(rate * seconds)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# Rolling bursts: start (s), amplitude, decay (s).
	var count := rng.randi_range(5, 9)
	var starts := PackedFloat32Array()
	var amps := PackedFloat32Array()
	var decays := PackedFloat32Array()
	for b in count:
		starts.append(0.03 if b == 0 else rng.randf_range(0.1, seconds * 0.45))
		amps.append(1.0 if b == 0 else rng.randf_range(0.35, 0.95))
		decays.append(rng.randf_range(0.4, 1.6))
	var brown := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	var crack_lp := 0.0
	var env := 0.0
	var cutoff := 0.04 if close else 0.025
	for i in n:
		var t := float(i) / rate
		if i % 32 == 0:
			env = 0.0
			for b in count:
				var dt := t - starts[b]
				if dt > 0.0:
					env += amps[b] * (1.0 - exp(-dt * 18.0)) * exp(-dt / decays[b])
			env *= exp(-t / 3.2)
		var w := rng.randf() * 2.0 - 1.0
		brown = (brown + w * 0.08) * 0.996
		lp1 += (brown - lp1) * cutoff
		lp2 += (lp1 - lp2) * cutoff
		var s := lp2 * 6.0 * env
		if close and t < 0.4:
			# Sharp tearing crack of a nearby strike.
			crack_lp += (w - crack_lp) * 0.35
			s += crack_lp * exp(-t * 9.0) * 0.8 * (0.6 + 0.4 * sin(t * 260.0))
		buf[i] = s
	# Fade in/out and normalise.
	var peak := 0.0001
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	var fade_out := rate / 2
	for i in n:
		var g := 0.9 / peak
		if i > n - fade_out:
			g *= float(n - i) / fade_out
		buf[i] *= g
	return _to_wav(buf, 1, rate, n, 0, false)


## Packs float samples into 16-bit PCM. For loops, the first `xf` frames are
## cross-faded with the `xf` frames generated past the loop end so the seam is silent.
static func _to_wav(buf: PackedFloat32Array, channels: int, rate: int, frames: int, xf: int, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for i in frames * channels:
		peak = maxf(peak, absf(buf[i]))
	var gain := 0.85 / peak
	var bytes := PackedByteArray()
	bytes.resize(frames * channels * 2)
	for f in frames:
		for c in channels:
			var v := buf[f * channels + c]
			if loop and f < xf:
				var a := float(f) / xf
				var tail := buf[(frames + f) * channels + c]
				v = v * sqrt(a) + tail * sqrt(1.0 - a)
			bytes.encode_s16((f * channels + c) * 2, int(clampf(v * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = channels == 2
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = frames
	return wav
