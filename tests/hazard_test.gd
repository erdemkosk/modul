extends SceneTree
## Headless check of what hurt parts do and of the cage's dangers (Mode "cage"):
##   godot --headless --path . -s res://tests/hazard_test.gd
## 1. A wheel shot under half: its tyre bursts (it says so, sits lower, grips less); an engine shot:
##    the machine has less power.
## 2. A burst under it throws it no higher than MAX_RISE allows.
## 3. A spinner tears at and flings what touches it; a floor saw cuts what's over it.
## 4. A house robot drives into what comes into its zone.
## 5. The pit: its lights, it opens, what's over it falls.
## 6. The workshop: a new part costs its price, one taken off pays back half; nothing's free.

const HZ := 120
var _g: Node
var _c: Cage
var _a: CageArena
var _m: Machine
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
	if _frame > 90 * HZ:
		_expect(false, "timed out at " + _step)
		return _done()
	var since := (_frame - _mark) / float(HZ)
	match _step:
		"start":
			if _frame < HZ:
				return false
			_c = _g.get("cage")
			_a = _c.arena
			_m = _g.get("machine")
			_g.set("player_input", false)
			_a.set_round({})
			_fresh()
			_put(Vector2(0, -12))
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
			_put(Vector2(0, -12))
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
			# a spinner
			_a.set_round({"spinners": [Vector2(0, 0)]})
			_fresh()
			_put(Vector2(3.6, 0), PI * 0.5)
			_r.h0 = _m.health()
			_m.throttle = 0.0
			_next("spinner")
		"spinner":
			_m.apply_central_force(Vector3(-3000, 0, 0)) # (pushed into it)
			if since < 2.0:
				return false
			print("against a spinner 2 s: health %.2f -> %.2f, speed %.1f m/s" % [_r.h0, _m.health(), _m.linear_velocity.length()])
			_expect(_m.health() < float(_r.h0) - 0.03, "the spinner tears at it")
			_a.set_round({"saws": [[Vector2(-6, 0), Vector2(6, 0)]]})
			_fresh()
			_put(Vector2(0, 0))
			_r.h0 = _m.health()
			_next("saw")
		"saw":
			if since < 4.0:
				return false
			print("over a floor saw 4 s: health %.2f -> %.2f" % [_r.h0, _m.health()])
			_expect(_m.health() < float(_r.h0) - 0.02, "the saw cuts it")
			# the third round has the house robots
			_a.set_round({})
			_fresh()
			_c.state = "won"
			_c.round = 1
			_c.next_round()
			_next("house")
		"house":
			if since < 4.0:
				return false
			if not _r.has("h_at"):
				for e in _c.rivals:
					e.set_physics_process(false)
				_g.set("player_input", false)
				var h: Machine = _c.houses[0]
				_r.h_at = h.global_position
				var z: Rect2 = CageArena.HOUSE_ZONES[0]
				_put(z.get_center() + Vector2(2.5, -2.5))
				_r.hp_h = _m.health()
				_m.invulnerable = true # (watching the robot, not the damage)
				return false
			if since < 8.0:
				return false
			var h: Machine = _c.houses[0]
			print("in its zone 4 s: the house robot moved %.1f m, you're %.1f m off it" % [h.global_position.distance_to(_r.h_at), h.global_position.distance_to(_m.global_position)])
			_expect(h.global_position.distance_to(_r.h_at) > 1.0, "the house robot comes at what's in its zone")
			_expect(h.invulnerable and h.house, "and it can't be hurt")
			_m.invulnerable = false
			# the pit
			_a.set_round({"pit": Rect2(-3, -3, 6, 6)})
			_a.open_pit()
			_next("pit")
		"pit":
			if since < 4.0:
				return false
			print("the pit open: %s" % _a.pit_open)
			_expect(_a.pit_open, "the pit opens after its warning")
			_fresh()
			_put(Vector2(0, 0))
			_next("fall")
		"fall":
			if since < 1.5:
				return false
			print("over the pit: falling %s, down to y %.1f" % [_m.falling, _m.global_position.y])
			_expect(_m.falling and _m.global_position.y < -1.0, "what's over the open pit falls")
			_next("shop")
		"shop":
			# the workshop: a part bought, one sold back
			_c.state = "workshop"
			_c.credits = 500
			var b: Builder = _g.get("builder")
			var ok := bool(b.guard.call("armor", Vector3i.ZERO, 0))
			print("buying armour (%d): ok %s, credits 500 -> %d" % [int(Cage.price("armor")), ok, _c.credits])
			_expect(ok and _c.credits == 500 - int(Cage.price("armor")), "a new part costs its price")
			_c.credits = 10
			_expect(not bool(b.guard.call("cannon", Vector3i.ZERO, 0)) and _c.credits == 10, "nothing bought without the money")
			b.removed.emit("engine", Vector3i.ZERO, 0)
			print("an engine taken off: credits 10 -> %d" % _c.credits)
			_expect(_c.credits == 10 + int(Cage.price("engine") * Cage.REFUND), "one taken off pays back half")
			return _done()
	return false


func _done() -> bool:
	print("== hazard_test ALL CHECKS PASSED" if _fail.is_empty() else "== hazard_test FAILED: %d" % _fail.size())
	quit(1 if not _fail.is_empty() else 0)
	return true
