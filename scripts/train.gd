class_name Train
extends Node3D
## The train that brings the first settlers: a black engine, its tender, a coach and a boxcar, rolling
## in along the railway (Village.rail) to the station at its end. It slows to a stop beside the
## platform, the people step down from the coach, the boxcar's load is handed out onto the platform;
## then it backs out the way it came and is gone. Smoke from its stack, the chuff of each stroke,
## the whistle coming in and going out, the wheels turning as it rolls.

signal arrived
signal unloaded

const CARS := ["tren_lokomotif", "tren_tender", "tren_vagon", "tren_yuk"]
const TOP := 0.32 ## m from the ground to the rail's top
const MAX_SPEED := 9.0
const BRAKE := 0.55 ## m/s2

var line := PackedVector3Array() ## the rails' middle, on the ground
var nav: Nav ## (its cells shut while it stands: nobody walks through it)
var _shut: Array[Vector2i] = []
var stop_at := 0.0 ## m along the line where the engine's front stops
var _len := PackedFloat32Array() ## m along the line at each point
var _cars: Array[Node3D] = []
var _gap: Array[float] = [] ## m from the engine's front back to each car's middle
var _wheels: Array = [] ## per car: [wheel node, radius]
var _s := 0.0 ## the engine's front, m along the line
var _v := 0.0
var _state := "coming" ## coming, standing, going
var _smoke: GPUParticles3D
var _chuff_t := 0.0
var _whistle: AudioStreamPlayer3D
var armour := "" ## an armoured train's side ("merkez", "isyan"): plated over, a gun on its last car, its flag; "" a plain one
static var _whistle_wav: AudioStreamWAV


## Set on `line`, to stop with its coach level with `coach_at` m along it, its engine's front
## coming in from `from` m.
func setup(rail: PackedVector3Array, coach_at: float, from: float) -> void:
	line = rail
	_len.resize(line.size())
	_len[0] = 0.0
	for k in range(1, line.size()):
		_len[k] = _len[k - 1] + line[k].distance_to(line[k - 1])
	stop_at = coach_at # (moved on by the coach's place in the train once that's known: _ready)
	_s = maxf(from, 0.0)


## How far along the line (m, its own length) the point nearest `p` is.
func s_of(p: Vector3) -> float:
	var best := 0
	var bd := INF
	for k in line.size():
		var d := Vector2(line[k].x - p.x, line[k].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = k
	return _len[best]


func length() -> float:
	return _len[_len.size() - 1]


func _ready() -> void:
	var back := 0.0
	for kind: String in CARS:
		var scene := load("res://assets/buildings/%s.glb" % kind) as PackedScene
		var car := scene.instantiate() as Node3D
		add_child(car)
		# (its length along the track, from what it's made of)
		var box := AABB()
		var first := true
		var wheels: Array = []
		for n in car.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			# (its colours are in its vertices, as the buildings' are: "<stuff>-<tag>-<n>")
			var stuff := String(mi.name).split("-")[0]
			mi.material_override = Building.material((stuff if BuildingDefs.STUFF.has(stuff) else "dark") + "+")
			var b := mi.transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
			if String(mi.name).contains("wheel"):
				wheels.append([mi, maxf(mi.get_aabb().size.y * 0.5, 0.3)])
		var half := box.size.z * 0.5
		_gap.append(back + half)
		back += half * 2.0 + 0.5
		_cars.append(car)
		_wheels.append(wheels)
	_smoke = FireFx.smoke(false)
	_smoke.amount = 40
	_smoke.lifetime = 6.0
	(_smoke.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.2, 0.1, 0.2)
	(_smoke.process_material as ParticleProcessMaterial).color_ramp = FireFx._ramp([Color(0.08, 0.08, 0.08, 0.0),
		Color(0.12, 0.12, 0.12, 0.7), Color(0.35, 0.35, 0.36, 0.3), Color(0.5, 0.5, 0.5, 0.0)], [0.0, 0.1, 0.55, 1.0])
	_cars[0].add_child(_smoke)
	_smoke.position = Vector3(0, 4.7, 4.6) # (the stack: the model's -y is our +z)
	_whistle = AudioStreamPlayer3D.new()
	_whistle.stream = _whistle_sound()
	_whistle.max_distance = 900.0
	_whistle.unit_size = 40.0
	_whistle.volume_db = 2.0
	_cars[0].add_child(_whistle)
	_whistle.position = Vector3(0, 3.6, 1.0)
	if armour != "":
		_plate()
	stop_at = minf(stop_at + _gap[2], length() - 2.0)
	_s = minf(_s, stop_at)
	_place()
	_whistle.play()


## Plated over for the war: steel boxed round each car (a band of rivets, firing slits), a turret with
## its gun on the last, the side's flag on the engine.
func _plate() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.22, 0.24, 0.22)
	steel.metallic = 0.55
	steel.roughness = 0.55
	var slit := StandardMaterial3D.new()
	slit.albedo_color = Color(0.02, 0.02, 0.02)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.75, 0.72, 0.62) if armour == "merkez" else Color(0.62, 0.1, 0.08)
	for i in _cars.size():
		var car := _cars[i]
		var box := AABB()
		var first := true
		for n in car.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var b := car.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if i == 0:
			continue # (the engine stays black, its plating's its own)
		var c := box.get_center()
		var plate := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(box.size.x + 0.15, box.size.y * 0.62, box.size.z + 0.1)
		plate.mesh = pm
		plate.material_override = steel
		plate.position = Vector3(c.x, box.position.y + box.size.y * 0.55, c.z)
		car.add_child(plate)
		# a painted band, and slits along it
		var band := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(box.size.x + 0.17, 0.16, box.size.z * 0.9)
		band.mesh = bm
		band.material_override = paint
		band.position = plate.position + Vector3.UP * (pm.size.y * 0.5 - 0.25)
		car.add_child(band)
		for k in 4:
			for sx in [-1.0, 1.0]:
				var s := MeshInstance3D.new()
				var sm := BoxMesh.new()
				sm.size = Vector3(0.02, 0.12, 0.45)
				s.mesh = sm
				s.material_override = slit
				s.position = plate.position + Vector3(sx * (pm.size.x * 0.5 + 0.01), 0.1, (k - 1.5) * box.size.z * 0.22)
				car.add_child(s)
		if i == _cars.size() - 1:
			var tur := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.9
			tm.bottom_radius = 1.0
			tm.height = 0.8
			tur.mesh = tm
			tur.material_override = steel
			tur.position = plate.position + Vector3.UP * (pm.size.y * 0.5 + 0.4)
			car.add_child(tur)
			var gun := MeshInstance3D.new()
			var gm := CylinderMesh.new()
			gm.top_radius = 0.09
			gm.bottom_radius = 0.12
			gm.height = 2.4
			gun.mesh = gm
			gun.material_override = steel
			gun.rotation.x = PI * 0.5
			gun.position = tur.position + Vector3(0, 0.1, 1.5)
			car.add_child(gun)
	# the flag on the engine's cab
	var pole := MeshInstance3D.new()
	var polem := CylinderMesh.new()
	polem.top_radius = 0.03
	polem.bottom_radius = 0.03
	polem.height = 1.6
	pole.mesh = polem
	pole.material_override = Building.material("wood")
	pole.position = Vector3(0, 5.0, -1.2)
	_cars[0].add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.02, 0.5, 0.8)
	flag.mesh = fm
	flag.material_override = paint
	flag.position = pole.position + Vector3(0, 0.5, -0.42)
	_cars[0].add_child(flag)


## The whistle: a chord of two pipes with a breathy edge, swelling and dying (made once).
static func _whistle_sound() -> AudioStreamWAV:
	if _whistle_wav:
		return _whistle_wav
	var rate := 22050
	var secs := 2.2
	var data := PackedByteArray()
	data.resize(int(rate * secs) * 2)
	var noise := 0.0
	for i in int(rate * secs):
		var t := float(i) / rate
		var env := minf(t / 0.12, 1.0) * clampf((secs - t) / 0.5, 0.0, 1.0)
		var wob := 1.0 + 0.004 * sin(TAU * 5.0 * t)
		noise = noise * 0.9 + randf_range(-1.0, 1.0) * 0.1
		var s := 0.0
		for f in [392.0, 494.0, 587.0]:
			s += sin(TAU * f * wob * t) * 0.28 + sin(TAU * f * 2.0 * wob * t) * 0.06
		s = (s + noise * 0.35) * env * 0.5
		data.encode_s16(i * 2, clampi(int(s * 32767.0), -32768, 32767))
	_whistle_wav = AudioStreamWAV.new()
	_whistle_wav.format = AudioStreamWAV.FORMAT_16_BITS
	_whistle_wav.mix_rate = rate
	_whistle_wav.data = data
	return _whistle_wav


## The point and the way along the line `s` m in.
func _at(s: float) -> Array:
	s = clampf(s, 0.0, length())
	var lo := 0
	var hi := _len.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _len[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := maxf(_len[hi] - _len[lo], 0.001)
	var p := line[lo].lerp(line[hi], (s - _len[lo]) / seg)
	var dir := (line[hi] - line[lo]).normalized()
	return [p, dir]


## Each car where it stands: on the rails, along them, tilted to their slope.
func _place() -> void:
	for i in _cars.size():
		var s := _s - _gap[i]
		var fwd: Array = _at(s + 2.0)
		var aft: Array = _at(s - 2.0)
		var mid: Array = _at(s)
		var dir: Vector3 = (fwd[0] as Vector3) - (aft[0] as Vector3)
		if dir.length() < 0.01:
			dir = mid[1]
		var p: Vector3 = mid[0]
		_cars[i].global_transform = Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), p + Vector3.UP * TOP)


func _process(dt: float) -> void:
	var was := _s
	match _state:
		"coming":
			var left := stop_at - _s
			_v = minf(minf(_v + 1.2 * dt, MAX_SPEED), sqrt(maxf(2.0 * BRAKE * left, 0.0)) + 0.15)
			_s = minf(_s + _v * dt, stop_at)
			if _s >= stop_at - 0.01:
				_state = "standing"
				_v = 0.0
				_whistle.play()
				_block(true)
				arrived.emit()
		"standing":
			pass
		"going":
			# on, the way it was going, out of the valley
			_v = minf(_v + 0.7 * dt, MAX_SPEED * 1.4)
			_s += _v * dt
			if _s - _gap[_gap.size() - 1] >= length() - 3.0:
				queue_free()
				return
	var moved := _s - was
	if absf(moved) > 0.0001:
		_place()
		for car in _wheels:
			for w: Array in car:
				(w[0] as Node3D).rotate_object_local(Vector3.RIGHT, moved / float(w[1]))
	# the stack: thick when it works, a wisp standing still; a chuff a stroke
	_smoke.amount_ratio = clampf(0.25 + absf(_v) / MAX_SPEED, 0.25, 1.0)
	if absf(_v) > 0.3:
		_chuff_t -= dt
		if _chuff_t <= 0.0:
			_chuff_t = clampf(3.2 / absf(_v), 0.18, 1.2)
			Ambience.knock(_cars[0].global_position + Vector3.UP * 3.0, 0.35)


## The coach's door on `side` (a world direction across the track), on the ground below it.
func door(side: Vector3) -> Vector3:
	var c := _cars[2].global_position
	var p := c + side.normalized() * 2.7 + _cars[2].global_basis.z * 4.4
	return p


## The boxcar's door on `side` (where the load's handed down: beside it, clear of its cells).
func cargo_door(side: Vector3) -> Vector3:
	return _cars[3].global_position + side.normalized() * 2.7 + Vector3.UP * 1.6


## The ground under it, while it stands, shut to walking (nobody goes through it; round the ends).
func _block(on: bool) -> void:
	if nav == null:
		return
	if not on:
		if not _shut.is_empty():
			nav.set_building(_shut, false)
			_shut.clear()
		return
	var back := _s - _gap[_gap.size() - 1] - 5.0
	var s := back
	while s <= _s:
		var at: Array = _at(s)
		var c := Nav.cell_of(at[0])
		if not c in _shut:
			_shut.append(c)
		s += 1.0
	nav.set_building(_shut, true)


func _exit_tree() -> void:
	_block(false)


## Off again: on the way it was going.
func leave() -> void:
	_block(false)
	_state = "going"
	_whistle.play()


## Where the engine is (the view rides with it).
func engine_at() -> Vector3:
	return _cars[0].global_position if not _cars.is_empty() else global_position


func is_standing() -> bool:
	return _state == "standing"
