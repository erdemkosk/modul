extends SceneTree
## Headless check of what hurt parts do (Mode "arena"):
##   godot --headless --path . -s res://tests/hazard_test.gd
## 1. A wheel shot under half: its tyre bursts (it says so, sits lower, grips less); an engine shot:
##    the machine has less power.
## 2. A burst under it throws it no higher than MAX_RISE allows.

const HZ := 120
var _g: Node
var _m: Machine
var _frame := 0
var _step := "start"
var _mark := 0
var _fail := PackedStringArray()
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
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


func _put(at: Vector2, yaw := 0.0) -> void:
	var p := Vector3(at.x, _g.terrain.height_at(at.x, at.y) + 1.0, at.y)
	_m.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
	_m.linear_velocity = Vector3.ZERO
	_m.angular_velocity = Vector3.ZERO
	_m.set_down()


func _fresh() -> void:
	_m.from_data(Designs.starter())
	_m.invulnerable = false


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame > 30 * HZ:
		_expect(false, "timed out at " + _step)
		return _done()
	var since := (_frame - _mark) / float(HZ)
	match _step:
		"start":
			if _frame < HZ:
				return false
			(_g.get("builder") as Builder).set_active(false)
			_m = _g.get("machine")
			_g.set("player_input", false)
			_fresh()
			_put(Vector2(0, -40))
			_next("systems")
		"systems":
			if since < 1.0:
				return false
			var said := []
			_m.system_hit.connect(func(t: String, _at: Vector3) -> void: said.append(t))
			var wi := -1
			var ei := -1
			for i in _m.design.size():
				if _m.design[i].id == "wheel_s" and wi < 0:
					wi = i
				if _m.design[i].id == "engine":
					ei = i
			var p0 := _m.power_kw
			_m.damage_part(wi, Parts.hp_of("wheel_s") * 0.5)
			_m.damage_part(ei, Parts.hp_of("engine") * 0.6)
			var flats := _m.wheels.filter(func(w: MachineWheel) -> bool: return w.flat).size()
			print("a wheel at half, the engine at 40%%: flat tyres %d, power %.0f -> %.0f kW, said %s" % [flats, p0, _m.power_kw, said])
			_expect(flats == 1, "the wheel's tyre bursts")
			_expect(_m.power_kw < p0 * 0.75, "the hurt engine gives less power")
			_expect(said.has("LASTİK PATLADI") and said.any(func(t: String) -> bool: return t.begins_with("MOTOR")), "and it says so")
			# a burst right under it
			_fresh()
			_put(Vector2(0, -40))
			_next("blast")
		"blast":
			if since < 1.0:
				return false
			Combat.current.explode(_m.global_position + Vector3.DOWN * 0.3, 3.0, 0.0, 30000.0, null, false)
			_r.vy = 0.0
			_next("blast_watch")
		"blast_watch":
			_r.vy = maxf(float(_r.vy), _m.linear_velocity.y)
			if since < 0.5:
				return false
			print("a huge burst under it: up at most %.1f m/s" % _r.vy)
			_expect(float(_r.vy) <= Machine.MAX_RISE + 0.01, "it isn't thrown into the air")
			return _done()
	return false


func _done() -> bool:
	print("== hazard_test ALL CHECKS PASSED" if _fail.is_empty() else "== hazard_test FAILED: %d" % _fail.size())
	quit(1 if not _fail.is_empty() else 0)
	return true
