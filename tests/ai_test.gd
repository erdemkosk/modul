extends SceneTree
## Headless check of the rivals' AI in the cage (Mode "cage"):
##   godot --headless --path . -s res://tests/ai_test.gd
## 1. Driving at you across the cage with a spinner between, it goes round the spinner.
## 2. It aims at a part that matters and that it can see (not just your middle).
## 3. You near the open pit, a rammer goes round behind you and shoves you toward it.

const HZ := 120
var _g: Node
var _c: Cage
var _a: CageArena
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
	Mode.current = "cage"
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
	if _frame > 80 * HZ:
		_expect(false, "timed out at " + _step)
		return _done()
	var since := (_frame - _mark) / float(HZ)
	match _step:
		"start":
			if _frame < HZ:
				return false
			_c = _g.get("cage")
			_a = _c.arena
			(_g.get("builder") as Builder).set_active(false) # (the cage opens on the builder)
			_m = _g.get("machine")
			_g.set("player_input", false)
			_m.invulnerable = true
			# 1. a spinner between: the rammer must go round it to reach you
			_a.set_round({"spinners": [Vector2(0, 0)]})
			_put(_m, Vector2(16, 0), PI * 0.5)
			_rival(Designs.rammer(), Vector2(-16, 0), -PI * 0.5) # (its nose toward you, +x)
			_r.closest = INF
			_next("round_spinner")
		"round_spinner":
			var p := _e.global_position
			_r.closest = minf(float(_r.closest), Vector2(p.x, p.z).length())
			if OS.get_environment("TRACE") != "" and _frame % 60 == 0:
				var ai0: AiDriver = _e.find_children("*", "AiDriver", false, false)[0]
				print("   s %.1f rammer %s throttle %.1f steer %.1f rev %s speed %.1f stuck %.2f back %.2f" % [since, p, _e.throttle, _e.steer, ai0._reversing, _e.speed, ai0._stuck_t, ai0._back_t])
			if since < 13.0 and _e.global_position.distance_to(_m.global_position) > 6.0: # (time to back off a spinner it caught and go round)
				return false
			print("rammer at you past a spinner: came within %.1f m of its middle, %.1f m from you after %.1f s" % [
				_r.closest, _e.global_position.distance_to(_m.global_position), since])
			_expect(float(_r.closest) > 1.5 + 0.8, "it goes round the spinner, not into it")
			_expect(_e.global_position.distance_to(_m.global_position) < 12.0, "and still gets to you")
			# 2. a gunned rival: what it aims at
			_a.set_round({})
			_put(_m, Vector2(0, 14), 0.0)
			_rival(Designs.raider(), Vector2(0, -16), PI)
			_next("aim")
		"aim":
			if since < 3.0:
				return false
			var ai: AiDriver = _e.find_children("*", "AiDriver", false, false)[0]
			var part: Dictionary = ai.get("_part")
			print("the raider aims at: %s" % (part.id if not part.is_empty() else "your middle"))
			_expect(not part.is_empty() and str(Parts.def(part.id).kind) in ["cab", "engine", "weapon", "wheel"], "it aims at a part that matters")
			# 3. the pit open just behind you; a rammer comes
			_a.set_round({"pit": Rect2(-3, -3, 6, 6)})
			_a.open_pit()
			_put(_m, Vector2(6.5, 0), PI * 0.5)
			_rival(Designs.rammer(), Vector2(20, 6), PI * 0.5)
			_r.d0 = INF
			_next("shove")
		"shove":
			if since < 4.0:
				_r.d0 = Vector2(_m.global_position.x, _m.global_position.z).length()
				return false
			var ai: AiDriver = _e.find_children("*", "AiDriver", false, false)[0] if is_instance_valid(_e) else null
			if ai and ai.shoving:
				_r.shoved = true
			var d := Vector2(_m.global_position.x, _m.global_position.z).length()
			if OS.get_environment("TRACE") != "" and _frame % 60 == 0 and is_instance_valid(_e):
				print("   t %.1f you %s  rammer %s  shoving %s  throttle %.1f" % [since, _m.global_position, _e.global_position, ai.shoving if ai else false, _e.throttle])
			if since < 16.0 and not _m.falling:
				return false
			print("by the open pit: the rammer went to shove %s; you %s (%.1f m -> %.1f m off its middle)" % [
				_r.get("shoved", false), "fell in" if _m.falling else "held on", _r.d0, d])
			_expect(bool(_r.get("shoved", false)), "the rammer sets out to shove you in")
			_expect(_m.falling or d < float(_r.d0) - 1.0, "and shoves you toward it")
			return _done()
	return false


func _done() -> bool:
	print("== ai_test ALL CHECKS PASSED" if _fail.is_empty() else "== ai_test FAILED: %d" % _fail.size())
	quit(1 if not _fail.is_empty() else 0)
	return true
