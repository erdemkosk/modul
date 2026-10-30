extends SceneTree
## Headless check of the valley's salvage (Mode "valley"):
##   godot --headless --path . -s res://tests/salvage_test.gd
## 1. A new start: the starter on, a few spare parts held.
## 2. Building takes from what's held (none left: refused), taking off gives back.
## 3. A ready design you can't cover is refused (the machine as it was); with the parts held, it's
##    built and they're spent.
## 4. A wanderer comes in on dry ground 170-260 m off; one of the other side's machines torn apart
##    leaves its whole parts lying lit; driving up to one takes it.

var _g: Node
var _frame := 0
var _fail := PackedStringArray()
var _step := "start"
var _mark := 0
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_valley_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	Inventory.path = "user://test_inventory.cfg"
	Inventory.reset()
	Mode.current = "valley"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail.append(what)
		print("  FAIL: " + what)


func _next(s: String) -> void:
	_step = s
	_mark = _frame


func _physics_process(_d: float) -> bool:
	_frame += 1
	var since := (_frame - _mark) / 120.0
	if _frame > 120 * 120:
		_expect(false, "timed out at " + _step)
		return _done()
	match _step:
		"start":
			if since < 2.0:
				return false
			_g.set("player_input", false)
			var b: Builder = _g.get("builder")
			var m: Machine = _g.get("machine")
			Inventory.count("frame")
			print("held: %s; on the machine %d parts" % [Inventory.counts, m.design.size()])
			_expect(Inventory.count("frame") == 2 and Inventory.count("plate") == 0, "a new start holds little spare")
			_expect(m.design.size() == Designs.valley_start().size(), "the first machine's on (the starter, a saw, a bin)")
			# 2. building takes and gives back
			_expect(bool(b.guard.call("frame", Vector3i.ZERO, 0)) and Inventory.count("frame") == 1, "a frame bolted on comes out of what's held")
			_expect(not bool(b.guard.call("cannon", Vector3i.ZERO, 0)), "a cannon you don't hold is refused")
			b.removed.emit("frame", Vector3i.ZERO, 0)
			_expect(Inventory.count("frame") == 2, "taken off, it's held again")
			# 3. a ready design
			b.set_active(true)
			var before := m.design.size()
			b.load_preset(2) # (TOPÇU: a cannon, armour, off-road wheels)
			_expect(m.design.size() == before, "a design you can't cover is refused")
			for e: Array in Designs.tank():
				Inventory.add(str(e[0]))
			var held := Inventory.count("frame")
			b.load_preset(2)
			var tank := Designs.tank().size()
			print("with the parts held: %d parts on (TOPÇU has %d); frames held %d -> %d" % [m.design.size(), tank, held, Inventory.count("frame")])
			_expect(m.design.size() == tank, "with the parts held, it's built")
			_expect(Inventory.count("cannon") == 0 and Inventory.count("engine") >= 1, "the parts it took are spent (and the starter's back in hand)")
			b.set_active(false)
			_next("wander")
		"wander":
			if since < 1.0:
				return false
			var w: Wanderers = _g.get("wanderers")
			var m: Machine = _g.get("machine")
			var e := w.spawn_near(m.global_position)
			var d := e.global_position.distance_to(m.global_position) if e else -1.0
			var t: Node = _g.get("terrain")
			print("a wanderer: %s at %.0f m, on water %s" % [e.label if e else "none", d, bool(t.call("is_water", e.global_position.x, e.global_position.z)) if e else false])
			_expect(e != null and d > 160.0 and d < 270.0, "a wanderer comes in 170-260 m off")
			_expect(e != null and not bool(t.call("is_water", e.global_position.x, e.global_position.z)), "on dry ground")
			# 4. one torn apart beside you
			var at := m.global_transform * Vector3(0, 1.5, -14)
			var r: Machine = _g.call("_spawn", Designs.raider(), Transform3D(m.global_basis, at), 1, false)
			_r.raider = r
			_next("tear")
		"tear":
			if since < 1.5:
				return false
			var r: Machine = _r.raider
			var cab := r.cab_index()
			r.damage_part(cab, 99999.0, r.com_global(), null)
			_next("lying")
		"lying":
			if since < 2.0:
				return false
			var s: Salvage = _g.get("salvage")
			print("torn apart: %d whole parts lying" % s.count())
			_expect(s.count() >= 4, "its whole parts lie there to take (%d)" % s.count())
			var item: RigidBody3D = null
			for n in _g.get_tree().get_nodes_in_group("salvage"):
				item = n
				break
			_r.id = str(item.get_meta("salvage")) if item else ""
			_r.before = Inventory.count(str(_r.id))
			var m: Machine = _g.get("machine")
			if item:
				item.global_position = m.global_position + m.global_basis.x * 2.5 + Vector3.UP * 0.5 # (as if you'd driven up to it)
			_next("taken")
		"taken":
			if since < 0.5:
				return false
			print("took a %s: held %d -> %d" % [_r.id, _r.before, Inventory.count(str(_r.id))])
			_expect(Inventory.count(str(_r.id)) == int(_r.before) + 1, "driving up to it takes it")
			return _done()
	return false


func _done() -> bool:
	Inventory.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
	return true
