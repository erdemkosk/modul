extends SceneTree
## Headless check of the flipper (Mode "arena"):
##   godot --headless --path . -s res://tests/flipper_test.gd
## 1. A machine with a flipper, a light rival standing across its flap: F throws it up and over
##    (on its back or side after a couple of seconds); the flap comes up and down again; the air's
##    spent (a second flip at once does nothing) and comes back in RECHARGE s; the battery pays.
## 2. On its own back: the flipper rights it.
## 3. A Forge flipper rival with its crew, at a machine that doesn't move: it drives under it and
##    throws it.

var _g: Node
var _frame := 0
var _fail := PackedStringArray()
var _a: Machine
var _b: Machine
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


func _ground(x: float, z: float) -> float:
	return float(_g.get("terrain").call("height_at", x, z))


func _next(s: String) -> void:
	_step = s
	_mark = _frame


func _physics_process(_d: float) -> bool:
	_frame += 1
	var since := (_frame - _mark) / 120.0
	if _frame == 60:
		_g.set("player_input", false)
		(_g.get("machine") as Machine).global_position = Vector3(60, _ground(60, 60) + 2.0, 60) # (out of the way)
		var data := Designs.starter()
		data.append(["flipper", 0, 0, -5, 0])
		var at := Vector3(0, 0, 20)
		at.y = _ground(at.x, at.z) + 1.2
		_a = _g.call("_spawn", data, Transform3D(Basis.IDENTITY, at), 0, false)
		_a.invulnerable = true
		# the rival side-on across the flap, its near side over it
		var bt := Vector3(at.x + 0.3, 0.0, at.z - 3.2)
		bt.y = _ground(bt.x, bt.z) + 1.2
		_b = _g.call("_spawn", Designs.raider(), Transform3D(Basis(Vector3.UP, PI * 0.5), bt), 1, false)
		_b.invulnerable = true
		_next("settle")
	match _step:
		"settle":
			if since < 2.0:
				return false
			print("flipper: %d on it (%s), air %.1f, %.0f kJ" % [_a.flippers.size(), _a.flippers[0].over_it().map(func(m: Machine) -> String: return m.label),
				_a.flippers[0].air, _a.energy_kj])
			_expect(_a.flippers.size() == 1, "the machine has its flipper")
			_expect(_b in _a.flippers[0].over_it(), "the rival's over the flap")
			_r.kj = _a.energy_kj
			_r.y0 = _b.global_position.y
			_expect(_a.flip(), "F fires it")
			_expect(not _a.flip(), "a second flip at once does nothing (the air's spent)")
			_expect(_a.energy_kj < float(_r.kj) - MachineFlipper.FLIP_KJ + 1.0, "the battery paid for it")
			_r.peak = 0.0
			_r.flap = 0.0
			_next("thrown")
		"thrown":
			_r.peak = maxf(float(_r.peak), _b.global_position.y - float(_r.y0))
			_r.lowest = minf(float(_r.get("lowest", 1.0)), _b.global_basis.y.y)
			if _a.flippers[0].flap:
				_r.flap = maxf(float(_r.flap), _a.flippers[0].flap.rotation.x)
			if since < 3.0:
				return false
			var up := _b.global_basis.y.y
			print("thrown: lowest up %.2f in the air" % _r.lowest)
			print("thrown: rose %.1f m, now up %.2f; the flap came up %.2f rad, now %.2f" % [_r.peak, up, _r.flap,
				_a.flippers[0].flap.rotation.x if _a.flippers[0].flap else -1.0])
			_expect(float(_r.peak) > 0.8, "thrown up (%.1f m)" % _r.peak)
			_expect(up < 0.3, "over on its back or side (up %.2f)" % up)
			_expect(float(_r.flap) > 1.0 and absf(_a.flippers[0].flap.rotation.x) < 0.05, "the flap came up and went down again")
			_next("air")
		"air":
			if since < MachineFlipper.RECHARGE:
				return false
			_expect(_a.flippers[0].ready(), "the air's back after %.0f s" % MachineFlipper.RECHARGE)
			# 2. on its own back
			_b.queue_free()
			var at := _a.global_position + Vector3.UP * 1.5
			_a.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), at)
			_a.linear_velocity = Vector3.ZERO
			_a.angular_velocity = Vector3.ZERO
			_next("upside")
		"upside":
			if since < 1.5:
				return false
			if not _r.has("righting"):
				_r.righting = true
				print("on its back: up %.2f" % _a.global_basis.y.y)
				_expect(_a.global_basis.y.y < -0.5, "it lies on its back")
				_expect(_a.flip(), "the flipper fires on its back")
				_mark = _frame
				return false
			if since < 3.0:
				return false
			print("after righting: up %.2f" % _a.global_basis.y.y)
			_expect(_a.global_basis.y.y > 0.7, "back on its wheels (up %.2f)" % _a.global_basis.y.y)
			# 3. a Forge flipper rival with its crew
			_a.queue_free()
			var tgt := Vector3(-20, 0, -20)
			tgt.y = _ground(tgt.x, tgt.z) + 1.2
			_b = _g.call("_spawn", Designs.raider(), Transform3D(Basis.IDENTITY, tgt), 0, false)
			_b.invulnerable = true
			var made := Forge.make(5, 1, "flipper")
			var from := Vector3(-20, 0, -2)
			from.y = _ground(from.x, from.z) + 1.5
			_a = _g.call("_spawn", made.data, Transform3D(Basis.IDENTITY, from), 1, true)
			_a.invulnerable = true
			_r.low = 1.0
			_r.fired = false
			_next("crew")
		"crew":
			_b.throttle = 0.0
			_r.low = minf(float(_r.low), _b.global_basis.y.y)
			_r.fired = bool(_r.fired) or (not _a.flippers.is_empty() and _a.flippers[0]._t >= 0.0)
			if since < 25.0 and float(_r.low) > 0.3:
				return false
			print("a forge flipper at a machine standing still: fired %s, its target's up went down to %.2f in %.1f s" % [_r.fired, _r.low, since])
			_expect(bool(_r.fired), "the crew fires its flipper")
			_expect(float(_r.low) < 0.5, "and throws its target over (up %.2f)" % _r.low)
			print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
			return true
	return _frame > 120 * 90
