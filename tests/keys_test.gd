extends SceneTree
## Headless check of parts lying any way and answering to keys (Mode "arena"):
##   godot --headless --path . -s res://tests/keys_test.gd
## 1. A part tipped over: its footprint and its turn as it lies (the V8 tipped forward stands
##    taller than long); wheels, tracks and the cab only upright; a wedge tipped on the starter's
##    nose bolts on, and its slope's box lies the way it does.
## 2. Saved and loaded: the tilt and the key kept; an old design (five numbers a part) loads.
## 3. Keys: a gun given a key fires on it and not on the mouse; the others on the mouse and not on
##    it; a flipper given a key fires on it and not on F.
## 4. The mirror: a part on its right side mirrors onto its left.

var _g: Node
var _m: Machine
var _frame := 0
var _fail := PackedStringArray()


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
	Mode.current = "arena"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail.append(what)
		print("  FAIL: " + what)


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame == 60:
		_g.set("player_input", false)
		_m = _g.get("machine")
		# 1. lying any way
		var s := Parts.size_of("engine_l", 4)
		print("V8 (2x2x3) tipped forward: %s" % s)
		_expect(s == Vector3i(2, 3, 2), "the V8 tipped forward stands 3 tall, 2 long")
		_expect(Parts.size_of("engine_s", 4) == Vector3i(1, 2, 1), "the small engine (1x1x2) tipped forward stands 2 tall")
		_expect(Parts.size_of("engine_s", 17) == Vector3i(2, 1, 1), "on its side and turned, it lies across")
		var b := Parts.xform_of("wedge", Vector3i.ZERO, 8).basis # (upside down)
		_expect(b.y.y < -0.99, "upside down, its up points down")
		_m.from_data(Designs.starter())
		_expect(not _m.can_place("wheel_s", Vector3i(4, 0, 0), 16), "a wheel won't go on on its side")
		_expect(not _m.can_place("cab", Vector3i(0, 3, 0), 4), "nor the cab")
		var placed := _m.place("wedge", Vector3i(0, 0, -3), 8)
		_expect(placed, "a wedge upside down bolts onto the nose")
		# 2. saved and loaded
		var data := _m.to_data()
		var minigun_row := ["minigun", 0, 3, 0, 0, KEY_G]
		data.append(minigun_row)
		_m.from_data(data)
		var w := -1
		for i in _m.design.size():
			if _m.design[i].id == "wedge" and _m.design[i].at == Vector3i(0, 0, -3):
				w = i
		_expect(w >= 0 and _m.design[w].rot == 8, "the tilt's kept")
		var back := _m.to_data()
		var found := false
		for e: Array in back:
			if e[0] == "minigun" and e.size() == 6 and int(e[5]) == KEY_G:
				found = true
		_expect(found, "the key's kept")
		_m.from_data([["cab", 0, 1, 0, 0], ["frame", 0, 0, 0, 0], ["frame", 1, 0, 0, 0]])
		_expect(_m.design.size() == 3, "an old design (five numbers a part) loads")
		# 3. keys
		var d := Designs.starter()
		d.append(["minigun", 0, 3, 0, 0, KEY_G])
		d.append(["cannon", 0, 1, 2, 0])
		d.append(["flipper", 0, 0, -5, 0, KEY_J])
		_m.from_data(d)
		_m.keyed = true
		_m.invulnerable = true
	if _frame > 60 and _frame < 60 + 240:
		# the key held, the mouse not: the keyed minigun spins up, the cannon doesn't fire
		_m.firing = false
		for g in _m.guns:
			g.key_down = g.key != 0
		_m.aim_point = _m.global_transform * Vector3(0, 1, -40)
	if _frame == 60 + 240:
		var mini: MachineGun = null
		var can: MachineGun = null
		for g in _m.guns:
			if g.kind == "minigun":
				mini = g
			elif g.kind == "cannon":
				can = g
		print("on G alone: minigun spin %.2f, rounds %d; cannon loaded %s" % [mini._spin, mini._round, can._cool <= 0.0])
		_expect(mini.key == KEY_G and mini._spin > 0.9, "the gun with a key fires on it")
		_expect(can._cool <= 0.0, "the gun without one doesn't")
		_expect(not bool(_g.call("_fire_flippers", KEY_F)), "the flipper with a key doesn't answer to F")
		_expect(bool(_g.call("_fire_flippers", KEY_J)) and _m.flippers[0]._t >= 0.0, "it fires on its own key")
	if _frame > 60 + 240 and _frame < 60 + 480:
		# the mouse, no keys: the cannon fires, the keyed minigun winds down
		_m.firing = true
		for g in _m.guns:
			g.key_down = false
	if _frame == 60 + 480:
		var mini: MachineGun = null
		var can: MachineGun = null
		for g in _m.guns:
			if g.kind == "minigun":
				mini = g
			elif g.kind == "cannon":
				can = g
		print("on the mouse alone: minigun spin %.2f; cannon fired %s" % [mini._spin, can._cool > 0.0])
		_expect(mini._spin < 0.2, "the keyed gun doesn't fire on the mouse")
		_expect(can._cool > 0.0, "the others do")
		# 4. the mirror
		var bld: Builder = _g.get("builder")
		_m.from_data(Designs.starter())
		var mr := bld.mirrored("wedge", Vector3i(2, 1, 1), 16 + 1) # (on its right side, turned once)
		print("a wedge on its right side mirrors to rot %d (tilt %d)" % [mr.get("rot", -1), int(mr.get("rot", 0)) / 4])
		_expect(not mr.is_empty() and int(mr.rot) / 4 == 5, "on its right side mirrors onto its left")
		print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
		return true
	return false
