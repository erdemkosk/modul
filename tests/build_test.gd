extends SceneTree
## Headless check of the build screen's tools (Mode "arena"):
##   godot --headless --path . -s res://tests/build_test.gd
## 1. Mirror: a part bolted on one side goes on the other too (wheels turned to face out); one on the
##    middle goes on once.
## 2. Designs: saved to a slot and loaded back the same; "clear" (pressed twice) leaves only the cab;
##    the starter comes back.
## 3. The isometric view: orthographic, from a corner at 35°; off again leaving the build screen.
## 4. Taking a part off; F6 clears the other side's machines away.
## 5. Load shedding: low, the lights go out first, and the consumers list says so.
## 6. Turning guns on and off (each its own key, the others as they are; 0 all on): only those on fire. The camera's modes, and the
##    chase camera standing up and looking out past the machine.

var _g: Node
var _b: Builder
var _m: Machine
var _frame := 0
var _fail := PackedStringArray()


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	for k in Builder.SLOTS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.slot_path(k)))
	Mode.current = "arena"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail.append(what)
		print("  FAIL: " + what)


func _count(id: String) -> int:
	var n := 0
	for p: Dictionary in _m.design:
		if p.id == id:
			n += 1
	return n


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame == 120:
		_g.set("player_input", false)
		_m = _g.get("machine")
		_b = _g.get("builder")
		_m.from_data(Designs.starter())
		_b.set_active(true)
		# 1. mirror: armour on the engine (off the middle), and a wheel on the bed's side
		_b.set_mirror(true)
		_b.select("armor")
		var n0 := _m.design.size()
		_b._target = _b.aim_ray(_m.global_transform * (Vector3(0.5, 5.0, 2.5) * Parts.CELL), -_m.global_basis.y)
		print("armour aimed: %s" % _b._target)
		_b.place_target()
		_expect(_m.design.size() == n0 + 2, "mirrored: two armour blocks (%d -> %d)" % [n0, _m.design.size()])
		var xs: Array[int] = []
		for p: Dictionary in _m.design:
			if p.id == "armor":
				xs.append(p.at.x)
		print("armour at x %s (cab middle %d)" % [xs, _m.design[_m.cab_index()].at.x + 1])
		_expect(xs.size() == 2 and xs[0] + xs[1] == 2 * (_m.design[_m.cab_index()].at.x + 1) - 1, "on either side of the cab's middle")
		_b.select("wheel_s")
		var free_side := _m.global_transform * (Vector3(3.5, 0.25, 0.25) * Parts.CELL)
		var t := _b.aim_ray(free_side + _m.global_basis.x * 2.0, -_m.global_basis.x)
		print("wheel aimed at the side: %s" % t)
		var m: Dictionary = t.get("mirror", {})
		_expect(not m.is_empty() and int(m.rot) == (int(t.rot) + 2) % 4, "a mirrored wheel faces the other way")
		# 2. designs
		_b.save_slot(0)
		var saved := _m.to_data()
		_b._on_clear()
		_expect(_m.design.size() > 1, "one press of clear only asks")
		_b._on_clear()
		_expect(_m.design.size() == 1 and _m.design[0].id == "cab", "two presses: only the cab left")
		_b.load_slot(0)
		_expect(_m.to_data() == saved, "the slot loads back the same design")
		_b.undo()
		_expect(_m.design.size() == 1, "undo brings back what was there before (only the cab)")
		_b.redo()
		_expect(_m.to_data() == saved, "and redo the loaded design")
		_b.reset_starter()
		_expect(_m.to_data() == Machine.new().to_data() or _m.design.size() == Designs.starter().size(), "the starter comes back")
		_b._refresh_slots()
		print("slots: %s" % [_b._slot_rows.map(func(l: Label) -> String: return l.text)])
		_expect(_b._slot_rows[0].text.contains("kg"), "slot 1 shows what's in it")
		# 3. iso
		_b.set_iso(true)
	if _frame == 160:
		var c: OrbitCamera = _g.get("cam")
		print("iso: projection %d, yaw %.2f" % [c.projection, c.yaw])
		_expect(c.projection == Camera3D.PROJECTION_ORTHOGONAL, "the isometric view is orthographic")
		_expect(is_equal_approx(fposmod(c.yaw - PI * 0.25, PI * 0.5), 0.0) or is_equal_approx(fposmod(c.yaw - PI * 0.25, PI * 0.5), PI * 0.5), "from a corner")
		# 4. off comes a light
		var li := -1
		for i in _m.design.size():
			if _m.design[i].id == "light":
				li = i
		var n := _m.design.size()
		_b.remove_at(li)
		_expect(_m.design.size() == n - 1, "a right click takes a light off")
		_b.set_active(false)
	if _frame == 200:
		var c: OrbitCamera = _g.get("cam")
		_expect(c.projection == Camera3D.PROJECTION_PERSPECTIVE, "driving again, the view is back in perspective")
		_g.spawn_enemy("raider")
		_g.spawn_enemy("dummy")
		var n: int = _g.clear_enemies()
		_expect(n == 2, "F6 clears the two machines away")
		# 5. shedding: the starter's lights on, the battery at a fifth
		_m.from_data(Designs.starter())
		_m.set_lights(true)
		_m.energy_kj = _m.capacity_kj * 0.2
	if _frame == 230:
		var lamps := false
		for c: Dictionary in _m.consumers:
			if c.name == "Farlar":
				lamps = c.on
				print("lights at 20%%: %s" % c)
		_expect(_m.shed >= 1 and not lamps, "at a fifth of its charge the lights are shed")
		_m.energy_kj = _m.capacity_kj
	if _frame == 260:
		_expect(_m.shed == 0, "charged, everything's back on")
		# 6. picking guns: a minigun and a cannon on the starter; 1 fires only the minigun
		var data := Designs.starter()
		data.append(["minigun", 0, 3, 0, 0])
		data.append(["cannon", 0, 1, -2, 0])
		_m.from_data(data)
		_g.toggle_gun(1) # (the cannon off: the minigun alone)
		_m.aim_point = _m.global_position - _m.global_basis.z * 40.0
		_m.firing = true
	if _frame == 500:
		var mg: MachineGun = _m.guns[0]
		var cn: MachineGun = _m.guns[1]
		print("2 off: minigun on %s spin %.2f, cannon on %s cooling %.2f" % [mg.armed, mg._spin, cn.armed, cn._cool])
		_expect(mg.armed and not cn.armed, "2 turns the cannon off, the minigun stays on")
		_expect(mg._spin > 0.9 and cn._cool <= 0.0, "only the minigun fires")
		_g.toggle_gun(1)
		_expect(mg.armed and cn.armed, "2 again: both on, firing together")
		_g.toggle_gun(0)
		_g.toggle_gun(1)
		_expect(not mg.armed and not cn.armed, "both can be off")
		_g.toggle_gun(-1)
		_expect(mg.armed and cn.armed, "0 turns them all on")
		_m.firing = false
		# the camera's modes
		var cam: OrbitCamera = _g.get("cam")
		var names := [cam.cycle_mode(), cam.cycle_mode(), cam.cycle_mode()]
		print("camera modes: %s" % [names])
		_expect(names == ["Yüksek", "Kule", "Takip"], "C goes round chase, high, turret")
	if _frame == 520:
		var cam: OrbitCamera = _g.get("cam")
		var to := (_m.global_position - cam.global_position)
		var look := -cam.global_basis.z
		print("chase: camera %.1f m up over the machine, looking %.0f deg down; the machine %.0f deg below the middle" % [
			cam.global_position.y - _m.global_position.y, rad_to_deg(asin(-look.y)), rad_to_deg(look.angle_to(to.normalized()))])
		_expect(cam.global_position.y - _m.global_position.y > 2.5, "the chase camera stands well up")
		_expect(rad_to_deg(asin(-look.y)) < rad_to_deg(asin(-to.normalized().y)) - 8.0, "and looks out past the machine, not down at it")
		print("== build_test ALL CHECKS PASSED" if _fail.is_empty() else "== build_test FAILED: %d" % _fail.size())
		quit(1 if not _fail.is_empty() else 0)
		return true
	return false
