class_name EngineSound
extends Node3D
## A machine's engine heard: four loops of the same engine at rising revs (idle, low, middle, top),
## crossfaded by the revs, each pitched only a little either side of its own speed, so it never sounds
## like one recording sped up. Throttle (load) makes the upper ones louder; off it they fall back.
## Which engine it is follows the biggest engine part in the design (small single, diesel, V8 diesel).

## Per engine: its loops' firings a second (as recorded and re-timed: tools/audio/build_insa_sounds.py),
## and each loop's level.
const SETS := {
	"small": {"hz": [7.41, 10.74, 15.56, 22.23], "db": [-1.0, -1.5, -1.5, -1.0]}, # a 1903 De Dion single
	"diesel": {"hz": [28.4, 42.6, 62.48, 88.04], "db": [-2.0, -1.5, -1.0, 0.0]}, # an Iveco 3.0 four
	"big": {"hz": [40.1, 60.15, 90.2, 132.3], "db": [0.0, 0.0, 0.5, 1.0]}, # a Detroit 6.2 V8 diesel
}
const BY_PART := {"engine_s": "small", "engine": "diesel", "engine_l": "big"}

var kind := ""
var playing := false
var stream_paused := false:
	set(v):
		stream_paused = v
		for p in _players:
			p.stream_paused = v
var unit_size := 8.0
var base_db := -4.0

var _players: Array[AudioStreamPlayer3D] = []
var _hz: Array = []
var _db: Array = []
var _scan := 0.0 ## (the design looked at again this often: parts change while building)
var _miss := 0.0 ## (a hurt engine missing: how long the dip still lasts)
var _miss_in := 1.0


## The engine for `design` (the machine's parts): the biggest engine part's sound.
static func kind_of(design: Array) -> String:
	var best := ""
	var power := -1.0
	for p: Dictionary in design:
		var id := str(p.get("id", ""))
		if BY_PART.has(id):
			var w := float(Parts.def(id).get("power", 0.0))
			if w > power:
				power = w
				best = BY_PART[id]
	return best


func _set_kind(k: String) -> void:
	if k == kind:
		return
	kind = k
	for p in _players:
		p.queue_free()
	_players.clear()
	if k == "":
		return
	var s: Dictionary = SETS[k]
	_hz = s.hz
	_db = s.db
	for i in _hz.size():
		var p := AudioStreamPlayer3D.new()
		var st := load("res://assets/audio/engine/%s_%d.ogg" % [k, i]) as AudioStreamOggVorbis
		if st:
			st.loop = true
		p.stream = st
		p.unit_size = unit_size
		p.volume_db = -80.0
		p.stream_paused = stream_paused
		add_child(p)
		_players.append(p)
	if playing:
		_start()


func _start() -> void:
	if not is_inside_tree():
		return
	for p in _players:
		if p.stream and not p.playing:
			p.play(randf() * p.stream.get_length()) # (the loops not all from their tops at once)


func play() -> void:
	playing = true
	_start()


func stop() -> void:
	playing = false
	for p in _players:
		p.stop()


## Every frame: `rpm` 0 (idle) to 1 (flat out), `pull` 0..1 (the throttle), `rough` 0..1 (how badly the
## engine misses), for the machine `m`.
func update(m: Machine, rpm: float, pull: float, rough: float, dt: float) -> void:
	_scan -= dt
	if _scan <= 0.0 or kind == "":
		_scan = 0.5
		_set_kind(kind_of(m.design))
	if not playing or _players.is_empty():
		return
	if not stream_paused and not _players[0].playing and not _players[0].stream_paused:
		_start() # (it was made before it was in the tree)
	var n := _hz.size()
	var lo := float(_hz[0]) * 0.92
	var hi := float(_hz[n - 1]) * 1.1
	var f := lo * pow(hi / lo, clampf(rpm, 0.0, 1.0)) # (firings a second now)
	# which two loops it's between, and how far (in octaves)
	var i := 0
	while i < n - 2 and f >= float(_hz[i + 1]):
		i += 1
	var w := clampf(log(f / float(_hz[i])) / log(float(_hz[i + 1]) / float(_hz[i])), 0.0, 1.0)
	# a hurt engine misses now and then: a firing or two dropped
	var dip := 0.0
	if rough > 0.0:
		_miss = maxf(_miss - dt, 0.0)
		_miss_in -= dt
		if _miss_in <= 0.0:
			_miss_in = randf_range(0.15, 1.2) / rough
			_miss = randf_range(0.06, 0.16)
		if _miss > 0.0:
			dip = -10.0 * rough
	for k in n:
		var g := 0.0
		if k == i:
			g = cos(w * PI * 0.5)
		elif k == i + 1:
			g = sin(w * PI * 0.5)
		var p := _players[k]
		if g < 0.004:
			p.volume_db = -80.0
			p.stream_paused = true # (not heard: not decoded either)
			continue
		if p.stream_paused and not stream_paused:
			p.stream_paused = false
		var on_load := 0.0 if k == 0 else lerpf(-4.5, 0.0, clampf(pull, 0.0, 1.0))
		p.volume_db = base_db + float(_db[k]) + linear_to_db(g) + on_load + dip
		p.pitch_scale = clampf(f / float(_hz[k]), 0.6, 1.6)
