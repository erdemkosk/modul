class_name MachineTool
extends RefCounted
## A working tool on a Machine: what the valley's wood is got with.
##
##   saw        (the part "saw": R) a flat circular blade out in front, low, as a feller's head has.
##              R starts it (it runs up over a second, drawing SAW_KW off the battery) and stops it.
##              Spinning, driven into a tree it cuts through the trunk (the thicker the longer:
##              CUT_BASE + CUT_PER_M of trunk radius), and the tree goes over away from you and lies
##              as billets (Timber); a log lying in the forest or a stump it cuts into billets too.
##              What else it meets it cuts: a crate or a log in pieces quickly, stone and steel
##              slowly and in sparks, and another machine's parts.
##              Biting, it's felt: chips thrown out of the cut sideways, a spark off the teeth now
##              and then, the machine shuddering and the view with it, needles shaken down out of
##              the crown, and nearly through, the tree cracks.
## What it cuts lies as billets (Timber): a crane (MachineHoist) lifts them onto a bed.

const BLADE := Vector3(0.0, -0.4, -0.95) ## the blade's middle, in the part's space (low: under the bed, as a feller's is)
const BLADE_R := 0.55 ## m
const SAW_KW := 3.0
const CUT_BASE := 0.6 ## s to cut through the thinnest trunk
const CUT_PER_M := 7.0 ## s more for each m of trunk radius

var machine: Machine
var node: Node3D
var index := -1
var kind := "saw"
var key := 0
var condition := 1.0
var on := false
var spin := 0.0 ## 0..1 of the blade's speed
var cutting := -1 ## (the prop the blade's in, or -1)
var _progress := {} ## prop index -> s cut so far
var _kerfs := {} ## prop index -> Timber.kerf(): the cut in the trunk, where the blade went in
var _blade: Node3D
var _hum: AudioStreamPlayer3D ## the blade turning free
var _bite_snd: AudioStreamPlayer3D ## and biting into wood (a child of _hum)
var _in_wood := 0.0 ## (0..1: the free whine faded into the bite)
var _dust_t := 0.0
var _shake_t := 0.0
var _cracked := -1 ## (the prop that's cracked: once each)
var _shook := -1 ## (the prop whose crown's been shaken: once each)


static func make(m: Machine, part: Node3D, i: int, id: String) -> MachineTool:
	var t := MachineTool.new()
	t.machine = m
	t.node = part
	t.index = i
	t.kind = str(Parts.def(id).kind)
	t._blade = part.find_child("Blade", true, false) as Node3D
	var p: Dictionary = m.design[i]
	t.on = bool(p.get("tool_on", false))
	return t


## Of what's to cut, how far through (0..1; 0 when it's not cutting).
func cut_frac() -> float:
	if cutting < 0:
		return 0.0
	var props := Timber.props_of(machine)
	if props == null:
		return 0.0
	var info := props.prop_info(cutting)
	var need := CUT_BASE + CUT_PER_M * float(info.radius) * (0.7 if info.kind != "tree" else 1.0)
	return clampf(float(_progress.get(cutting, 0.0)) / need, 0.0, 1.0)


## R: the saw started or stopped. Says what happened.
func toggle() -> String:
	if kind != "saw":
		return ""
	on = not on
	machine.design[index].tool_on = on
	if on and not machine.powered:
		return "Akü bitti: testere dönmüyor"
	return "Testere çalışıyor" if on else "Testere durdu"


func draw_kw() -> float:
	return SAW_KW * spin if kind == "saw" and on else 0.0


func update(dt: float) -> void:
	if not is_instance_valid(node):
		return
	var run := on and machine.powered
	spin = move_toward(spin, 1.0 if run else 0.0, dt * (1.0 if run else 0.5))
	if _blade:
		_blade.rotate_object_local(Vector3.UP, spin * 45.0 * dt)
	_sound()
	cutting = -1
	if spin < 0.5:
		return
	var c := node.global_transform * BLADE
	var bite := spin * maxf(condition, 0.3) # (a worn one cuts slower)
	_dust_t -= dt
	var props := Timber.props_of(machine)
	if props:
		var i := props.prop_near(Vector2(c.x, c.z), BLADE_R, ["tree", "log", "stump"])
		if i >= 0:
			var info := props.prop_info(i)
			var base: Vector3 = info.origin
			var low := base.y - (1.0 if info.kind == "log" else 0.6)
			var high := base.y + (float(info.radius) + 0.6 if info.kind == "log" else (0.5 if info.kind == "stump" else 3.0))
			if c.y > low and c.y < high:
				cutting = i
				var need := CUT_BASE + CUT_PER_M * float(info.radius) * (0.7 if info.kind != "tree" else 1.0)
				_progress[i] = float(_progress.get(i, 0.0)) + dt * bite
				# the wood holds the machine back as it bites
				machine.apply_central_force(-machine.linear_velocity * machine.total_mass * 1.5)
				_bite_feel(c, base, float(info.radius), float(_progress[i]) / need, i, str(info.kind) == "tree",
					float(info.get("height", 6.0)), dt)
				var cut_h := 0.3
				if str(info.kind) == "tree": # (the cut where the blade went in: the kerf opening in the trunk)
					if not _kerfs.has(i):
						_kerfs[i] = Timber.kerf(machine.get_tree(), base, c, float(info.radius))
					var k: Dictionary = _kerfs[i]
					Timber.kerf_grow(k, float(_progress[i]) / need)
					cut_h = float(k.h)
				if float(_progress[i]) >= need:
					_progress.erase(i)
					var away := Vector3(base.x - machine.global_position.x, 0.0, base.z - machine.global_position.z)
					if _kerfs.has(i):
						var k: Dictionary = _kerfs[i]
						away = k.dir # (it goes over away from the side it was cut from)
						Timber.kerf_free(k)
						_kerfs.erase(i)
					Timber.cut(machine, props, i, away.normalized() if away.length() > 0.1 else -machine.global_basis.z, cut_h)
				return
	# crates, logs and the like lying about; another machine
	for n: Node in machine.get_tree().get_nodes_in_group(Breakable.GROUP):
		var b := n as Breakable
		if b.broken:
			continue
		var l := b.global_transform.affine_inverse() * c
		var h := b.size * 0.5
		var near := Vector3(clampf(l.x, -h.x, h.x), clampf(l.y, 0.0, b.size.y), clampf(l.z, -h.z, h.z))
		if near.distance_to(l) < BLADE_R * 0.6:
			var soft := b.kind in ["log", "crate"]
			b.hit((220.0 if soft else 35.0) * bite * dt, c, -machine.global_basis.z)
			if _dust_t <= 0.0:
				_dust_t = 0.12
				if soft:
					Timber.sawdust(c)
				elif Combat.current:
					Combat.current._burst(c, "metal", 0.5, Vector3.UP)
			return
	for n: Node in machine.get_tree().get_nodes_in_group("machines"):
		var m := n as Machine
		if m == machine or not m.alive or m.global_position.distance_squared_to(c) > 64.0:
			continue
		var j := m._part_near(c)
		if j >= 0 and (m.global_transform * m.part_xform(j).origin).distance_to(c) < BLADE_R + 0.35:
			m.damage_part(j, 70.0 * (2.5 if Parts.burns(m.design[j].id) else 1.0) * bite * dt, c, machine) # (wood's cut through)
			if _dust_t <= 0.0:
				_dust_t = 0.1
				if Combat.current:
					Combat.current._burst(c, "metal", 0.6, Vector3.UP)
			return


func _sound() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _hum == null:
		_hum = _saw_loop("res://assets/audio/tools/saw_idle.ogg")
		node.add_child(_hum)
		_bite_snd = _saw_loop("res://assets/audio/tools/saw_cut.ogg")
		_hum.add_child(_bite_snd)
	if spin < 0.02:
		if _hum.playing:
			_hum.stop()
			_bite_snd.stop()
		return
	if not _hum.playing:
		_hum.play(randf() * 8.0)
		_bite_snd.play(randf() * 14.0)
	_in_wood = move_toward(_in_wood, 1.0 if cutting >= 0 else 0.0, machine.get_physics_process_delta_time() * 5.0)
	var s := spin * (1.0 - 0.1 * _in_wood) # (the blade slows a little as it labours in the wood)
	_hum.pitch_scale = 0.4 + 0.6 * s # (winding up from a growl to its whine)
	_bite_snd.pitch_scale = 0.55 + 0.45 * s
	_hum.volume_db = linear_to_db(clampf(spin, 0.03, 1.0) * (1.0 - 0.75 * _in_wood))
	_bite_snd.volume_db = linear_to_db(maxf(_in_wood * spin, 0.0001)) + 3.0


static func _saw_loop(path: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var s := load(path) as AudioStreamOggVorbis
	if s:
		s.loop = true
	p.stream = s
	p.unit_size = 7.0
	return p


## What biting into wood at `c` feels like: chips out of the kerf, now and then a spark off the teeth,
## the machine shuddering (and the view), needles out of the crown, the crack when it's nearly through.
func _bite_feel(c: Vector3, base: Vector3, r: float, frac: float, i: int, tree: bool, h: float, dt: float) -> void:
	if _dust_t <= 0.0:
		_dust_t = 0.06
		var side := machine.global_basis.x * (1.0 if randf() < 0.5 else -1.0) # (thrown off the blade's edge as it turns)
		var rim := c + (Vector3(base.x, c.y, base.z) - c).normalized() * minf(r, 0.4)
		Timber.sawdust(rim, side + Vector3.UP * 0.3)
		if Combat.current:
			Combat.current._burst(rim, "chips", 0.9, side - machine.global_basis.z * 0.3)
			if randf() < 0.18:
				Combat.current._burst(rim, "metal", 0.25, side + Vector3.UP * 0.5) # (a stone in the bark, a knot)
	_shake_t -= dt
	if _shake_t <= 0.0:
		_shake_t = 0.09
		var k := machine.total_mass * 0.35
		machine.apply_torque_impulse(Vector3(randf_range(-k, k), randf_range(-k, k) * 0.3, randf_range(-k, k)))
		if Combat.current:
			Combat.current.shook.emit(c, 0.05 + 0.06 * frac, machine, 0.0)
	if tree and _shook != i and frac > 0.15 and Combat.current:
		_shook = i
		Combat.current._burst(base + Vector3.UP * h * 0.7, "needles", 1.0, Vector3.DOWN)
	if tree and _cracked != i and frac > 0.82:
		_cracked = i
		if Combat.current:
			Combat.current._burst(base + Vector3.UP * h * 0.75, "needles", 1.0, Vector3.DOWN)
			Combat.current.sound("res://assets/audio/wood/tree_crack.wav", base + Vector3.UP * 1.5, 2.0, randf_range(0.9, 1.05))


func free_fx() -> void:
	if is_instance_valid(_hum):
		_hum.queue_free()
