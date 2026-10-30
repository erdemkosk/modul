extends SceneTree
## Headless check of the other side's AI on the proving ground (Mode "arena"):
##   godot --headless --path . -s res://tests/ai_test.gd
## 1. A rammer across the asphalt comes and gets to you.
## 2. It aims at a part that matters and that it can see (not just your middle).

const HZ := 120
var _g: Node
var _m: Machine
var _e: Machine
var _frame := 0
var _step := "start"
var _mark := 0
var _fail := PackedStringArray()
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	seed(int(OS.get_environment("AI_SEED")) if OS.get_environment("AI_SEED") != "" else 4) # (the crews' dice fixed: the same fight each time)
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


func _put(m: Machine, at: Vector2, yaw := 0.0) -> void:
	var p := Vector3(at.x, _g.terrain.height_at(at.x, at.y) + 1.0, at.y)
	m.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
	m.linear_velocity = Vector3.ZERO
	m.angular_velocity = Vector3.ZERO
	m.set_down()


func _rival(data: Array, at: Vector2, yaw: float) -> Machine:
	if is_instance_valid(_e):
		_e.queue_free()
	var p := Vector3(at.x, _g.terrain.height_at(at.x, at.y) + 1.5, at.y)
	_e = _g._spawn(data, Transform3D(Basis(Vector3.UP, yaw), p), 1, true)
	return _e


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame > 60 * HZ:
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
			_m.invulnerable = true
			# 1. a rammer at the far end of the asphalt: it must come and get to you
			_put(_m, Vector2(0, -28), 0.0)
			_rival(Designs.rammer(), Vector2(0, -56), PI) # (its nose toward you, +z)
			_next("ram")
		"ram":
			if OS.get_environment("TRACE") != "" and _frame % 60 == 0:
				var ai0: AiDriver = _e.find_children("*", "AiDriver", false, false)[0]
				print("   s %.1f rammer %s throttle %.1f steer %.1f rev %s speed %.1f stuck %.2f back %.2f" % [since, _e.global_position, _e.throttle, _e.steer, ai0._reversing, _e.speed, ai0._stuck_t, ai0._back_t])
			if since < 13.0 and _e.global_position.distance_to(_m.global_position) > 6.0:
				return false
			print("rammer across the asphalt: %.1f m from you after %.1f s" % [_e.global_position.distance_to(_m.global_position), since])
			_expect(_e.global_position.distance_to(_m.global_position) < 8.0, "the rammer gets to you")
			# 2. a gunned rival: what it aims at
			_put(_m, Vector2(0, -26), 0.0)
			_rival(Designs.raider(), Vector2(0, -56), PI)
			_next("aim")
		"aim":
			if since < 3.0:
				return false
			var ai: AiDriver = _e.find_children("*", "AiDriver", false, false)[0]
			var part: Dictionary = ai.get("_part")
			print("the raider aims at: %s" % (part.id if not part.is_empty() else "your middle"))
			_expect(not part.is_empty() and str(Parts.def(part.id).kind) in ["cab", "engine", "weapon", "wheel"], "it aims at a part that matters")
			return _done()
	return false


func _done() -> bool:
	print("== ai_test ALL CHECKS PASSED" if _fail.is_empty() else "== ai_test FAILED: %d" % _fail.size())
	quit(1 if not _fail.is_empty() else 0)
	return true
