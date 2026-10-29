extends SceneTree
## Headless check of how blows feel (HitFeel; Mode "arena"):
##   godot --headless --path . -s res://tests/hitfeel_test.gd
## 1. You ram a machine hard: the knock is reported (what it struck, how hard), the view shakes, and
##    the game would stop for a moment (a hit-stop: counted, not done headless).
## 2. A part torn off one you hit: another hit-stop and a shake.
## 3. One you put down: another.
## 4. A soft touch (a nudge) does none of it.
## 5. Cover driven into is battered: a concrete barrier rammed hard breaks, a container's dented.

const HZ := 120
var _g: Node
var _m: Machine
var _e: Machine
var _hf: HitFeel
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


func _put(m: Machine, at: Vector3, yaw: float) -> void:
	at.y = _g.terrain.height_at(at.x, at.z) + 1.0
	m.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	m.linear_velocity = Vector3.ZERO
	m.angular_velocity = Vector3.ZERO
	m.set_down()


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame > 40 * HZ:
		_expect(false, "timed out at " + _step)
		return _done()
	var since := (_frame - _mark) / float(HZ)
	match _step:
		"start":
			if _frame < HZ:
				return false
			_m = _g.get("machine")
			_hf = _g.get("hit_feel")
			_g.set("player_input", false)
			_e = _g._spawn(Designs.starter(), Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), 1, false)
			_put(_e, Vector3(0, 0, -30), 0.0)
			_put(_m, Vector3(0, 0, -16), 0.0)
			_r.hits = []
			_m.struck.connect(func(_at: Vector3, dv: float, other: Object) -> void:
				if other == _e:
					(_r.hits as Array).append(dv))
			_next("nudge")
		"nudge":
			if since < 1.0:
				return false
			if not _r.has("pushed"):
				_r.pushed = true
				_r.s0 = _hf.stops
				_m.linear_velocity = Vector3(0, 0, -2.5) # (a nudge)
				return false
			if since < 3.0:
				return false
			print("a nudge: %d knock(s) reported, hit-stops %d -> %d" % [(_r.hits as Array).size(), _r.s0, _hf.stops])
			_expect(_hf.stops == int(_r.s0), "a nudge stops nothing")
			_put(_m, Vector3(0, 0, -12), 0.0)
			_put(_e, Vector3(0, 0, -30), 0.0)
			(_g.get("cam") as OrbitCamera).trauma = 0.0
			_r.hits = []
			_next("ram")
		"ram":
			if since < 0.5:
				return false
			if not _r.has("rammed"):
				_r.rammed = true
				_r.s1 = _hf.stops
				_r.shook = 0.0
				_m.linear_velocity = Vector3(0, 0, -16.0) # (flat out into it)
			_r.shook = maxf(float(_r.shook), (_g.get("cam") as OrbitCamera).trauma)
			if since < 2.5:
				return false
			var hits: Array = _r.hits
			print("a ram at 16 m/s: knocks %s, the view shook to %.2f, hit-stops %d -> %d" % [hits.map(func(v: float) -> String: return "%.1f" % v),
				_r.shook, _r.s1, _hf.stops])
			_expect(not hits.is_empty() and float(hits.max()) > HitFeel.SPARK_FROM, "the knock's reported, what it struck and how hard")
			_expect(float(_r.shook) > 0.2, "the view shakes")
			_expect(_hf.stops > int(_r.s1), "and the game stops for a moment")
			_r.s2 = _hf.stops
			_e.last_hit_by = _m
			for i in _e.design.size():
				if _e.design[i].id == "light":
					_e.break_off(i)
					break
			_next("torn")
		"torn":
			if since < 0.5:
				return false
			print("a part off theirs: hit-stops %d -> %d" % [_r.s2, _hf.stops])
			_expect(_hf.stops > int(_r.s2), "a part torn off one you hit stops it too")
			_r.s3 = _hf.stops
			_e.last_hit_by = _m
			_e.damage_part(_e.cab_index(), 99999.0, Vector3.INF, _m)
			_next("kill")
		"kill":
			if since < 0.5:
				return false
			print("one put down: hit-stops %d -> %d, time scale %.2f" % [_r.s3, _hf.stops, Engine.time_scale])
			_expect(_hf.stops > int(_r.s3), "and one put down")
			_expect(is_equal_approx(Engine.time_scale, 1.0), "the game's at its own speed (headless: never stopped)")
			# 5. into cover
			_r.bar = Breakable.make("barrier", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-20, _g.terrain.height_at(-20, -40), -40)))
			_g.add_child(_r.bar)
			_r.box = Breakable.make("container", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(20, _g.terrain.height_at(20, -40), -40)))
			_g.add_child(_r.box)
			_put(_m, Vector3(-20, 0, -26), 0.0)
			_next("ram_bar")
		"ram_bar":
			if since < 2.0: # (just set down, knocks don't count for a moment)
				return false
			if not _r.has("go_bar"):
				_r.go_bar = true
				_m.linear_velocity = Vector3(0, 0, -15.0)
			if since < 4.5:
				return false
			var bar: Variant = _r.bar
			var gone := not is_instance_valid(bar) or (bar as Breakable).broken
			print("rammed a barrier at 15 m/s: broken %s" % gone)
			_expect(gone, "a barrier rammed hard breaks")
			_put(_m, Vector3(20, 0, -26), 0.0)
			_next("ram_box")
		"ram_box":
			if since < 2.0: # (just set down, knocks don't count for a moment)
				return false
			if not _r.has("go_box"):
				_r.go_box = true
				_m.linear_velocity = Vector3(0, 0, -15.0)
			if since < 4.5:
				return false
			var box: Variant = _r.box
			var hp := (box as Breakable).hp if is_instance_valid(box) and not (box as Breakable).broken else 0.0
			print("rammed a container at 15 m/s: hp %.0f of %.0f" % [hp, Breakable.KINDS.container.hp])
			_expect(hp < float(Breakable.KINDS.container.hp) - 100.0, "a container rammed is battered")
			return _done()
	return false


func _done() -> bool:
	print("== hitfeel_test ALL CHECKS PASSED" if _fail.is_empty() else "== hitfeel_test FAILED: %d" % _fail.size())
	quit(1 if not _fail.is_empty() else 0)
	return true
