extends SceneTree
## Headless check of the joints (Mode "arena"):
##   godot --headless --path . -s res://tests/joints_test.gd
## 1. A hinge on the nose with a plate on it: it carries the plate (only); E swings it up about 90°,
##    the plate's model and box with it; E again brings it down.
## 2. A rotor with a blade of plates out to one side, a steel post in its sweep: spun up, the blade
##    strikes the post and takes its hit points.
## 3. A piston with a plate on it pushes it up half a metre.
## 4. A hinge whose plate is also bolted to the machine another way can't move (locked).
## 5. Building puts every joint back at rest.

var _g: Node
var _m: Machine
var _frame := 0
var _fail := PackedStringArray()
var _step := ""
var _mark := 0
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
	Mode.current = "arena"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail.append(what)
		print("  FAIL: " + what)


func _next(s: String) -> void:
	_step = s
	_mark = _frame


func _idx(id: String, at: Vector3i) -> int:
	for i in _m.design.size():
		if _m.design[i].id == id and _m.design[i].at == at:
			return i
	return -1


## The starter without its lights (their corners free), and `extra`.
func _with(extra: Array) -> Array:
	var d := Designs.starter().filter(func(e: Array) -> bool: return e[0] != "light")
	d.append_array(extra)
	return d


func _physics_process(_d: float) -> bool:
	_frame += 1
	var since := (_frame - _mark) / 120.0
	if _frame == 60:
		_g.set("player_input", false)
		_m = _g.get("machine")
		_m.invulnerable = true
		_m.from_data(_with([["hinge", 0, 1, -2, 0], ["plate", 0, 2, -2, 0]]))
		var jt := _m.joints[0]
		var pi := _idx("plate", Vector3i(0, 2, -2))
		print("hinge: carries %s (the plate is %d), locked %s" % [jt.members, pi, jt.locked])
		_expect(jt.members == [pi], "the hinge carries the plate, only")
		_r.rest = _m.part_xform(pi)
		_expect(_m.joint_key(KEY_E), "E answers")
		_next("swing")
	match _step:
		"swing":
			if since < 1.0:
				return false
			var jt := _m.joints[0]
			var pi := _idx("plate", Vector3i(0, 2, -2))
			var now := _m.part_xform(pi)
			var turned := rad_to_deg(now.basis.y.angle_to(Vector3.UP))
			var shape_moved := false
			for e: Array in _m._shapes.get(pi, []):
				shape_moved = shape_moved or not (e[0] as CollisionShape3D).transform.is_equal_approx(e[1])
			print("swung: %.0f°, the plate's up turned %.0f°, its box moved %s" % [rad_to_deg(jt.angle), turned, shape_moved])
			_expect(absf(rad_to_deg(jt.angle) - 90.0) < 3.0 and turned > 80.0, "it swings the plate up about 90°")
			_expect(shape_moved, "the plate's box goes with it")
			_expect(_m.part_nodes[pi].transform.basis.y.angle_to(Vector3.UP) > 1.3, "and its model")
			_m.joint_key(KEY_E)
			_next("down")
		"down":
			if since < 1.0:
				return false
			_expect(absf(_m.joints[0].angle) < 0.01, "E again: back down")
			# 2. a rotor with a blade, a post in its sweep
			_m.from_data(_with([["rotor", -1, 1, -2, 0], ["plate", -1, 2, -2, 0], ["plate", 0, 2, -2, 0], ["plate", 1, 2, -2, 0],
				["plate", 2, 2, -2, 0], ["spike", 3, 2, -2, 0]]))
			var post := StructurePiece.make("box", Vector3(0.3, 1.2, 0.3), "steel",
				Transform3D(Basis.IDENTITY, _m.global_transform * Vector3(-1.2, 1.25, -1.4))) # (in the blade's sweep, clear of the machine)
			var s := Structure.new()
			s.terrain = _g.get("terrain")
			s.add(post)
			_g.add_child(s)
			_r.post = post
			_r.post_hp = post.hp
			print("rotor: carries %d parts, locked %s; the post %.0f hp" % [_m.joints[0].members.size(), _m.joints[0].locked, post.hp])
			_expect(_m.joints[0].members.size() == 5, "the rotor carries its blade (5 parts)")
			_m.joint_key(KEY_E)
			_next("spin")
		"spin":
			_m.throttle = 0.0
			_m.brake = 1.0
			if since < 3.0:
				return false
			var jt := _m.joints[0]
			var pv: Variant = _r.post
			var left := (pv as StructurePiece).hp if is_instance_valid(pv) else 0.0 # (gone: broken through)
			print("spinning at %.1f rad/s; the post %.0f -> %.0f hp" % [jt.rate, _r.post_hp, left])
			_expect(jt.rate > 14.0, "it spins up to speed")
			_expect(left < float(_r.post_hp) - 50.0, "the blade strikes the post and takes its hit points")
			# 3. a piston
			_m.from_data(_with([["piston", 1, 1, -2, 0], ["plate", 1, 2, -2, 0]]))
			_r.y0 = _m.part_xform(_idx("plate", Vector3i(1, 2, -2))).origin.y
			_m.joint_key(KEY_E)
			_next("push")
		"push":
			if since < 0.6:
				return false
			var y := _m.part_xform(_idx("plate", Vector3i(1, 2, -2))).origin.y
			print("piston: the plate %.2f -> %.2f m" % [_r.y0, y])
			_expect(absf(y - float(_r.y0) - MachineJoint.STROKE) < 0.02, "it pushes the plate up half a metre")
			# 5. building puts it back
			var b: Builder = _g.get("builder")
			b.set_active(true)
			_expect(absf(_m.joints[0].angle) < 1e-4 and not _m.joints[0].on, "building puts it back at rest")
			b.set_active(false)
			# 4. locked
			_m.from_data(_with([["hinge", 0, 1, -2, 0], ["plate", 0, 2, -2, 0], ["plate", 0, 2, -1, 0], ["frame", 0, 1, -1, 0]]))
			print("bolted round: locked %s" % _m.joints[0].locked)
			_expect(_m.joints[0].locked, "a hinge whose plate's bolted to the rest another way is locked")
			print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
			return true
	return _frame > 120 * 60
