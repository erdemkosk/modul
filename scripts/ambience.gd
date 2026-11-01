class_name Ambience
extends Node3D
## What the valley sounds like, and the sounds of the work in it.
##   the beds   birds in the woods by day (less in rain, none in winter or at night), the cold wind
##              in winter and high up, the stream when the camera's by the river, crickets on warm
##              nights (made here: chirps of a sine, in trains, from several crickets at once)
##   the work   an axe biting (each blow of a woodcutter's swing), a tree cracking and coming down,
##              a log thrown down: from a small pool of players, only near the camera
## (The rain, the wind's own roar and the thunder are Weather's.)

const POOL := 10

var weather: Weather
var cam: RtsCamera
var seasons: Seasons
var terrain: WorldTerrain

static var _me: Ambience

var _birds: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _stream: AudioStreamPlayer3D
var _crickets: AudioStreamPlayer
var _cricket_pb: AudioStreamGeneratorPlayback
var _cricket_t := 0.0
var _chirps: Array[Dictionary] = [] ## {at (s), pitch}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _streams := {}
var _river: Array[Vector3] = []
var _river_t := 0.0


func _ready() -> void:
	_me = self
	_birds = _bed("res://assets/audio/nature/forest_birds_loop.ogg")
	_wind = _bed("res://assets/audio/nature/wind_cold_pass_loop.ogg")
	_stream = AudioStreamPlayer3D.new()
	_stream.stream = _looped("res://assets/audio/nature/stream_gentle_loop.ogg")
	_stream.unit_size = 25.0
	_stream.max_distance = 140.0
	_stream.volume_db = 2.0
	add_child(_stream)
	_stream.play()
	for p: Array in terrain.meta.river.points:
		_river.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.3
	_crickets = AudioStreamPlayer.new()
	_crickets.stream = gen
	_crickets.volume_db = -80.0
	add_child(_crickets)
	_crickets.play()
	_cricket_pb = _crickets.get_stream_playback() as AudioStreamGeneratorPlayback
	for k in POOL:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 10.0
		a.max_distance = 110.0
		add_child(a)
		_pool.append(a)


func _bed(path: String) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.stream = _looped(path)
	a.volume_db = -80.0
	add_child(a)
	a.play()
	return a


static func _looped(path: String) -> AudioStream:
	var s := load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


func _process(dt: float) -> void:
	var night := weather.is_night()
	var winter := seasons.season == 3
	var high := clampf((cam.dist - 40.0) / 300.0, 0.0, 1.0)
	var birds := 0.0 if night or winter else (1.0 - weather.rain_intensity * 0.8) * (1.0 - high * 0.6)
	var wind := clampf((0.8 if winter else 0.0) + high * 0.5 + weather.snow_intensity * 0.5, 0.0, 1.0)
	_fade(_birds, birds, -6.0, dt)
	_fade(_wind, wind, -8.0, dt)
	var warm_night := night and not winter and weather.temperature > 8.0 and weather.rain_intensity < 0.2
	_fade(_crickets, (1.0 - high * 0.7) if warm_night else 0.0, -14.0, dt)
	_fill_crickets()
	_river_t -= dt
	if _river_t <= 0.0:
		_river_t = 0.5
		var best := Vector3.ZERO
		var bd := INF
		for p in _river:
			var d := Vector2(p.x - cam.focus.x, p.z - cam.focus.z).length_squared()
			if d < bd:
				bd = d
				best = p
		_stream.global_position = best


func _fade(a: AudioStreamPlayer, k: float, top_db: float, dt: float) -> void:
	var want := linear_to_db(maxf(k, 0.0001)) + top_db
	a.volume_db = move_toward(a.volume_db, maxf(want, -80.0), dt * 20.0)


## Crickets: each chirp a few pulses of a high sine, in trains, the trains overlapping (several
## crickets), pushed into the generator as it asks.
func _fill_crickets() -> void:
	if _cricket_pb == null or _crickets.volume_db <= -79.0:
		return # (silent: let the buffer run dry rather than make sound nobody hears)
	var n := _cricket_pb.get_frames_available()
	var rate := 22050.0
	for i in n:
		_cricket_t += 1.0 / rate
		if randf() < 0.00012:
			var start := _cricket_t
			var pitch := randf_range(3900.0, 4700.0)
			for c in randi_range(3, 7):
				_chirps.append({"at": start + c * 0.32, "pitch": pitch})
		var s := 0.0
		var k := 0
		while k < _chirps.size():
			var ch: Dictionary = _chirps[k]
			var age := _cricket_t - float(ch.at)
			if age > 0.06:
				_chirps.remove_at(k)
				continue
			if age >= 0.0:
				var pulse := 0.5 + 0.5 * sin(age * TAU * 60.0) # (the wing's teeth)
				s += sin(age * TAU * float(ch.pitch)) * pulse * sin(age / 0.06 * PI) * 0.18
			k += 1
		_cricket_pb.push_frame(Vector2(s, s))


static func _stream_of(name: String) -> AudioStream:
	if not _me._streams.has(name):
		_me._streams[name] = load("res://assets/audio/wood/%s.wav" % name)
	return _me._streams[name]


## A sound at `at` (only if the camera's near enough to hear it).
static func play(name: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	if _me == null or not is_instance_valid(_me):
		return
	if at.distance_to(_me.cam.global_position) > 160.0:
		return
	var a := _me._pool[_me._next]
	_me._next = (_me._next + 1) % POOL
	a.stream = _stream_of(name)
	a.global_position = at
	a.max_distance = 110.0
	a.unit_size = 10.0
	a.volume_db = db
	a.pitch_scale = pitch * randf_range(0.93, 1.07)
	a.play()


## The bell, struck: made once here (a bronze bell's partials, the hum, the prime, the tierce, the
## quint, the nominal, each dying away at its own pace).
static var _bell: AudioStreamWAV


static func bell(at: Vector3) -> void:
	if _me == null or not is_instance_valid(_me):
		return
	if _bell == null:
		var rate := 22050
		var secs := 4.5
		var data := PackedByteArray()
		data.resize(int(rate * secs) * 2)
		var base := 330.0
		var partials := [[0.5, 0.35, 0.6], [1.0, 0.5, 1.0], [1.19, 0.3, 1.3], [1.5, 0.25, 1.6], [2.0, 0.35, 2.2], [2.5, 0.15, 3.0], [3.0, 0.1, 3.6]]
		for i in int(rate * secs):
			var t := float(i) / rate
			var s := 0.0
			for pt: Array in partials:
				s += sin(TAU * base * float(pt[0]) * t) * float(pt[1]) * exp(-t * float(pt[2]))
			s *= minf(t / 0.004, 1.0) * 0.55
			data.encode_s16(i * 2, clampi(int(s * 32767.0), -32768, 32767))
		_bell = AudioStreamWAV.new()
		_bell.format = AudioStreamWAV.FORMAT_16_BITS
		_bell.mix_rate = rate
		_bell.data = data
	var a := _me._pool[_me._next]
	_me._next = (_me._next + 1) % POOL
	a.stream = _bell
	a.global_position = at
	a.volume_db = 6.0
	a.max_distance = 600.0
	a.unit_size = 60.0
	a.pitch_scale = 1.0
	a.play()


## An axe or a pick biting.
static func knock(at: Vector3, pitch := 1.0) -> void:
	play("knock_0%d" % randi_range(1, 4), at, -3.0, pitch)


static func log_drop(at: Vector3) -> void:
	play("log_drop_0%d" % randi_range(1, 3), at, -4.0)
