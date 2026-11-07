class_name Train
extends Node3D
## The train that brings the first settlers: a black 0-8-0 engine, its tender, a coach, a teplushka and an
## open wagon of logs (assets/train, tools/blender/build_train.py), rolling
## in along the railway (Village.rail) to the station at its end. It slows to a stop beside the
## platform, the people step down from the coach, the boxcar's load is handed out onto the platform;
## then it backs out the way it came and is gone. Smoke from its stack, the chuff of each stroke,
## the whistle coming in and going out, the wheels turning as it rolls.

signal arrived
signal unloaded

const CARS := ["lokomotif", "tender", "vagon", "yuk", "platforma"] ## (the coach third, the boxcar fourth: door, cargo_door)
const PATH := "res://assets/train/%s.glb" ## (tools/blender/build_train.py)
const TOP := 0.32 ## m from the ground to the rail's top
const COUPLED := 0.06 ## m between one car's buffer heads and the next's
## The engine's motion, as it's built (build_train.py: DRIVER_R, CRANK, MAIN_ROD, DRIVERS, MAIN_AXLE):
## the drivers' radius, the crank's throw, the main rod's length between its pins, the main pair's axle
## (m back from the model's middle; Godot +z is the front)
const DRIVER_R := 0.65
const CRANK := 0.3
const MAIN_ROD := 3.3
const MAIN_AXLE_Z := -0.6
const MAX_SPEED := 9.0
const BRAKE := 0.55 ## m/s2
const HARD_BRAKE := 3.0 ## m/s2: pulled up short (the first train, stopped by hand)

var line := PackedVector3Array() ## the rails' middle, on the ground
var nav: Nav ## (its cells shut while it stands: nobody walks through it)
var _shut: Array[Vector2i] = []
var stop_at := 0.0 ## m along the line where the engine's front stops
var _len := PackedFloat32Array() ## m along the line at each point
var _cars: Array[Node3D] = []
var _gap: Array[float] = [] ## m from the engine's front back to each car's middle
var _wheels: Array = [] ## every carrying wheel: [node, radius]
var _drivers: Array[Node3D] = [] ## the engine's driving wheels (turned together, the cranks on them)
var _rods: Array = [] ## the motion, each side: {kind: siderod/mainrod/crosshead, node, rest (its rest position), side (+1 right, -1 left)}
var _steam: GPUParticles3D ## white steam: from the cylinder cocks getting under way, a wisp off the safety valves standing
var _metal: Material ## the engine's black iron, a little sheen on it
var _s := 0.0 ## the engine's front, m along the line
var _v := 0.0
var _state := "coming" ## coming, standing, going
var _bar_s := INF ## m along the line where something across it stops the engine's front (a wall, a barred gate)
var _bar_t := 0.0
var _bar_said := false
var _smoke: GPUParticles3D
var _chuff_t := 0.0
var _whistle: AudioStreamPlayer3D
var _sparks: GPUParticles3D ## from the stack at night, working hard
var _lamp: SpotLight3D ## the headlamp, lit after dark
var brake := BRAKE
var quiet := false ## (the first train, at the start: no whistle over the opening)
var armour := "" ## an armoured train's side ("merkez", "isyan"): plated over, a gun on its last car, its flag; "" a plain one


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
	var stack := Vector3(0, 4.7, 4.0)
	for kind: String in CARS:
		var scene := load(PATH % kind) as PackedScene
		var car := scene.instantiate() as Node3D
		add_child(car)
		# (its length along the track, from what it's made of)
		var box := AABB()
		var first := true
		for n in car.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			# (its colours are in its vertices, as the buildings' are: "<stuff>-<tag>-<n>")
			var parts := String(mi.name).split("-")
			var stuff := parts[0]
			var tag := parts[1] if parts.size() >= 3 else ""
			mi.material_override = _metal_look() if stuff == "dark" else Building.material((stuff if BuildingDefs.STUFF.has(stuff) else "dark") + "+")
			var b := mi.transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
			match tag:
				"wheel":
					_wheels.append([mi, maxf(mi.get_aabb().size.y * 0.5 - 0.03, 0.3)])
				"driver":
					_drivers.append(mi)
				"siderod", "mainrod", "crosshead":
					_rods.append({"kind": tag, "node": mi, "rest": mi.position, "side": signf(mi.position.x)})
				"stack":
					stack = Vector3(b.get_center().x, b.end.y - 0.1, b.get_center().z)
		var half := box.size.z * 0.5
		_gap.append(back + box.end.z)
		back += half * 2.0 + COUPLED
		_cars.append(car)
	_smoke = FireFx.smoke(false)
	_smoke.amount = 70
	_smoke.lifetime = 6.0
	(_smoke.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.2, 0.1, 0.2)
	(_smoke.process_material as ParticleProcessMaterial).color_ramp = FireFx._ramp([Color(0.08, 0.08, 0.08, 0.0),
		Color(0.12, 0.12, 0.12, 0.7), Color(0.35, 0.35, 0.36, 0.3), Color(0.5, 0.5, 0.5, 0.0)], [0.0, 0.1, 0.55, 1.0])
	_cars[0].add_child(_smoke)
	_smoke.position = stack
	# steam, white and quick to go: the cylinder cocks blowing as it gets under way, the valves
	# simmering while it stands
	_steam = FireFx.smoke(false)
	_steam.amount = 40
	_steam.lifetime = 2.2
	var stm := _steam.process_material as ParticleProcessMaterial
	stm.emission_box_extents = Vector3(1.1, 0.1, 0.3)
	stm.direction = Vector3(0, 0.4, 1.0)
	stm.spread = 35.0
	stm.initial_velocity_min = 1.0
	stm.initial_velocity_max = 2.4
	stm.scale_min = 0.18
	stm.scale_max = 0.34
	stm.color_ramp = FireFx._ramp([Color(0.9, 0.9, 0.88, 0.0), Color(0.92, 0.92, 0.9, 0.55), Color(0.86, 0.86, 0.84, 0.25), Color(0.85, 0.85, 0.84, 0.0)], [0.0, 0.12, 0.5, 1.0])
	_steam.emitting = false
	_cars[0].add_child(_steam)
	_steam.position = Vector3(0, 0.45, 4.2)
	# sparks thrown up the stack, seen only by night
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3.UP
	spm.spread = 25.0
	spm.initial_velocity_min = 4.0
	spm.initial_velocity_max = 8.0
	spm.gravity = Vector3(0, -3.0, 0)
	spm.damping_min = 0.5
	spm.damping_max = 1.5
	var sg := Gradient.new()
	sg.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	sg.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	spm.color_ramp = sgt
	_sparks = GPUParticles3D.new()
	_sparks.amount = 40
	_sparks.lifetime = 1.4
	_sparks.process_material = spm
	var dot := QuadMesh.new()
	dot.size = Vector2(0.06, 0.06)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.vertex_color_use_as_albedo = true
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.emission_enabled = true
	dm.emission = Color(1.0, 0.5, 0.15)
	dm.emission_energy_multiplier = 3.0
	dot.material = dm
	_sparks.draw_pass_1 = dot
	_sparks.local_coords = false
	_sparks.emitting = false
	_cars[0].add_child(_sparks)
	_sparks.position = _smoke.position
	# the headlamp: the model's own lamp on the smokebox (its glass lit at night with the windows),
	# and its beam down the line after dark
	_lamp = SpotLight3D.new()
	_lamp.light_color = Color(1.0, 0.86, 0.6)
	_lamp.light_energy = 0.0
	_lamp.spot_range = 60.0
	_lamp.spot_angle = 22.0
	_lamp.light_volumetric_fog_energy = 1.5
	_lamp.shadow_enabled = false
	_cars[0].add_child(_lamp)
	_lamp.position = Vector3(0, 3.45, 4.85)
	_lamp.rotation = Vector3(-0.08, PI, 0) # (pointing down +z, the way it runs)
	_whistle = AudioStreamPlayer3D.new()
	_whistle.stream = load("res://assets/audio/war/whistle.wav") as AudioStream
	_whistle.max_distance = 900.0
	_whistle.unit_size = 40.0
	_whistle.volume_db = 2.0
	_cars[0].add_child(_whistle)
	_whistle.position = Vector3(0, 3.7, -2.35)
	if armour != "":
		_plate()
	stop_at = minf(stop_at + _gap[2], length() - 2.0)
	_s = minf(_s, stop_at)
	_place()
	_turn()
	if not quiet:
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
	pole.position = Vector3(0.9, 4.95, -3.7) # (up from the cab roof)
	_cars[0].add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.02, 0.5, 0.8)
	flag.mesh = fm
	flag.material_override = paint
	flag.position = pole.position + Vector3(0, 0.5, -0.42)
	_cars[0].add_child(flag)


## The engine's black: the models' "dark" (vertex colours, snow and wet on it) with a dull sheen.
func _metal_look() -> Material:
	if _metal == null:
		_metal = (Building.material("dark+") as ShaderMaterial).duplicate()
		(_metal as ShaderMaterial).set_shader_parameter("roughness_base", 0.6)
	return _metal


## The wheels turned to how far it's come (each by its own radius), the drivers together, and their
## motion with them: the side rod carried round on the crank pins, the crosshead sliding in its
## guides, the main rod between the two. The right side's crank is a quarter turn ahead of the left.
func _turn() -> void:
	for w: Array in _wheels:
		(w[0] as Node3D).basis = Basis(Vector3.RIGHT, _s / float(w[1]))
	var a := _s / DRIVER_R
	var turn := Basis(Vector3.RIGHT, a)
	for d in _drivers:
		d.basis = turn
	for r: Dictionary in _rods:
		var side: float = r.side
		# (the pin's place on the crank at rest: forward on the right, up on the left)
		var rest := Vector3(0, 0, CRANK) if side > 0.0 else Vector3(0, CRANK, 0)
		var pin := turn * rest
		var node: Node3D = r.node
		var at: Vector3 = r.rest
		match str(r.kind):
			"siderod":
				node.position = at + pin - rest
			"crosshead", "mainrod":
				var p := Vector3(at.x, DRIVER_R, MAIN_AXLE_Z) + pin
				var dy := p.y - DRIVER_R
				var x := Vector3(at.x, DRIVER_R, p.z + sqrt(maxf(MAIN_ROD * MAIN_ROD - dy * dy, 0.0)))
				if r.kind == "crosshead":
					node.position = x
				else:
					node.position = (p + x) * 0.5
					node.basis = Basis(Vector3.RIGHT, atan2(-(x.y - p.y), x.z - p.z))


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


## The line ahead looked over: a gate on it is opened for the train; a palisade across it, or a gate
## barred, and the train will stop short of it and stand till the way's clear.
func _look_ahead() -> void:
	_bar_s = INF
	var v: Node = get_parent()
	if v == null or not v.has_method("rail_block") or v.walls.is_empty():
		return
	var reach := _s + 90.0
	var k := 1
	while k < line.size() and _len[k] < _s - 2.0:
		k += 1
	while k < line.size() and _len[k - 1] < reach:
		var hit: Dictionary = v.rail_block(line[k - 1], line[k])
		if not hit.is_empty():
			var g: Gate = hit.get("gate")
			if g == null or (g.locked and not g.broken):
				_bar_s = maxf(_len[k - 1] - 5.0, _s)
				if not _bar_said and _s > _bar_s - 40.0:
					_bar_said = true
					v.message.emit("Tren önündeki sura dayandı: geçmesi için kapı koy ya da kilidi aç", "bad")
					_whistle.play()
				return
			if _len[k - 1] - _s < 40.0:
				g.pass_train()
		k += 1
	_bar_said = false


func _process(dt: float) -> void:
	var was := _s
	if _state != "standing":
		_bar_t -= dt
		if _bar_t <= 0.0:
			_bar_t = 0.4
			_look_ahead()
	match _state:
		"coming":
			var end := minf(stop_at, _bar_s)
			var left := end - _s
			_v = minf(minf(_v + 1.2 * dt, MAX_SPEED), sqrt(maxf(2.0 * brake * left, 0.0)) + 0.15)
			_s = minf(_s + _v * dt, end)
			if _bar_s < stop_at and _s >= _bar_s - 0.01:
				_v = 0.0 # (stopped short: it waits there, and comes on when the way's clear)
			elif _s >= stop_at - 0.01:
				_state = "standing"
				_v = 0.0
				if not quiet:
					_whistle.play()
				Ambience.hiss(_cars[0].global_position + Vector3.UP * 1.0)
				_block(true)
				arrived.emit()
		"standing":
			pass
		"going":
			# on, the way it was going, out of the valley
			_v = minf(_v + 0.7 * dt, MAX_SPEED * 1.4)
			if _bar_s < INF:
				_v = minf(_v, sqrt(maxf(2.0 * BRAKE * (_bar_s - _s), 0.0)))
				_s = minf(_s + _v * dt, _bar_s)
			else:
				_s += _v * dt
			if _s - _gap[_gap.size() - 1] >= length() - 3.0:
				queue_free()
				return
	var moved := _s - was
	if absf(moved) > 0.0001:
		_place()
		_turn()
	# the cocks open as it starts and as it draws up; a simmer off the valves standing
	if absf(_v) > 0.05 and absf(_v) < 3.0:
		_steam.position = Vector3(0, 0.45, 4.2)
		(_steam.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(1.1, 0.1, 0.3)
		_steam.amount_ratio = 1.0
		_steam.emitting = true
	elif _state == "standing":
		_steam.position = Vector3(0, 3.65, -2.1)
		(_steam.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.12, 0.05, 0.12)
		_steam.amount_ratio = 0.12
		_steam.emitting = true
	else:
		_steam.emitting = false
	# the stack: thick when it works, a wisp standing still; a chuff a stroke
	_smoke.amount_ratio = clampf(0.25 + absf(_v) / MAX_SPEED, 0.25, 1.0)
	var stack := _cars[0].global_position
	_smoke.emitting = nav == null or nav.height(stack.x, stack.z) < stack.y + 3.0 # (none through a hillside)
	var dark := Weather.night_now
	_sparks.emitting = dark > 0.5 and absf(_v) > 1.5
	_lamp.light_energy = dark * 6.0
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
