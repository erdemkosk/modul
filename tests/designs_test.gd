extends SceneTree
## Headless check of the ready designs and the rivals Forge builds (Mode "arena"):
##   godot --headless --path . -s res://tests/designs_test.gd
## 1. Forge, every style at every round, many seeds: a cab; engines enough for its weight (by the
##    round's mark, less a little); running gear rated for what it weighs; guns (none on a rammer,
##    a spiked nose on a rammer and a brawler); a battery where the guns draw more than an engine
##    charges; nothing that doesn't reach the cab; the same seed the same machine, and seeds giving
##    machines that differ.
## 2. Every preset: the same checks, and loading through the builder.
## 3. Out in the arena: a lot of them set down, each standing on its wheels or tracks after 4 s
##    (not flipped, not flown).

var _g: Node
var _frame := 0
var _fail := PackedStringArray()
var _put: Array[Machine] = []


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
	Mode.current = "arena"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail.append(what)
		print("  FAIL: " + what)


## [mass kg, power kW, rated kg, guns, has battery, spikes, alternator kW, draw kW]
func _sum(data: Array) -> Dictionary:
	var s := {"mass": 0.0, "power": 0.0, "rated": 0.0, "guns": [], "battery": false, "spikes": 0, "alt": 0.0, "draw": 0.0,
		"cab": 0}
	for e: Array in data:
		var id := str(e[0])
		var d := Parts.def(id)
		s.mass += float(d.mass)
		match str(d.kind):
			"engine":
				s.power += float(d.power)
				s.alt += float(d.get("alternator", 0.0))
			"wheel":
				s.rated += float(d.rated)
			"track":
				s.rated += float(d.rated) * float(d.bogies)
			"weapon":
				s.guns.append(str(d.weapon))
				var dk: Array = MachineGun.DRAW[str(d.weapon)]
				s.draw += float(dk[0]) + float(dk[1]) + float(dk[2])
			"battery":
				s.battery = true
			"ram":
				s.spikes += 1
			"cab":
				s.cab += 1
	return s


func _check(data: Array, what: String, style := "", tier := 0) -> void:
	var s := _sum(data)
	_expect(s.cab == 1, "%s: one cab (%d)" % [what, s.cab])
	var kwt: float = s.power / (s.mass / 1000.0)
	var carts := data.any(func(e: Array) -> bool: return str(e[0]) == "wood_cab") # (the wood age's haulers: slow on purpose)
	_expect(kwt >= (18.0 if carts else 55.0 + 8.0 * tier), "%s: power for its weight %.0f kW/t (%.0f kg, %.0f kW)" % [what, kwt, s.mass, s.power])
	_expect(s.rated >= s.mass * 1.05, "%s: running gear rated %.0f for %.0f kg" % [what, s.rated, s.mass])
	if style == "rammer" or style == "spinner":
		_expect((s.guns as Array).is_empty(), "%s: a rammer or a spinner carries no gun" % what)
	elif style != "":
		_expect(not (s.guns as Array).is_empty(), "%s: armed" % what)
	if style in ["rammer", "brawler"]:
		_expect(s.spikes >= 2, "%s: a spiked nose (%d)" % [what, s.spikes])
	if style == "brawler":
		_expect("flamer" in s.guns, "%s: the flamethrower" % what)
	if style == "spinner":
		var m := Machine.new()
		_g.add_child(m)
		m.from_data(data)
		_expect(m.joints.size() == 1 and not m.joints[0].locked and m.joints[0].members.size() >= 4, "%s: a rotor free to turn its bar (%s)" % [what,
			"none" if m.joints.is_empty() else "%d carried, locked %s" % [m.joints[0].members.size(), m.joints[0].locked]])
		m.queue_free()
	if style == "flipper":
		var has := false
		for e: Array in data:
			has = has or e[0] == "flipper"
		_expect(has, "%s: a flipper" % what)
	if style != "" and s.draw > 2.8:
		_expect(s.battery, "%s: a battery for guns drawing %.1f kW" % [what, s.draw])
	# nothing loose: what reaches the cab is everything
	var rows := Forge._connected(data)
	_expect(rows.size() == data.size(), "%s: all %d parts reach the cab (%d)" % [what, data.size(), rows.size()])
	# nothing overlapping
	var occ := {}
	for e: Array in data:
		for c in Parts.cells_of(str(e[0]), Vector3i(int(e[1]), int(e[2]), int(e[3])), int(e[4])):
			_expect(not occ.has(c), "%s: %s overlaps at %s" % [what, e[0], c])
			occ[c] = true


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame == 60:
		_g.set("player_input", false)
		# 1. Forge
		var n := 0
		for style: String in Forge.STYLES:
			for tier in 6:
				for k in 6:
					var made := Forge.make(1000 + k * 17 + tier, tier, style)
					_check(made.data, "%s t%d #%d" % [style, tier, k], style, tier)
					n += 1
		print("forged %d machines" % n)
		var a := Forge.make(4242, 3)
		var b := Forge.make(4242, 3)
		_expect(str(a.data) == str(b.data) and a.style == b.style, "the same seed: the same machine")
		var seen := {}
		var styles := {}
		for k in 40:
			var m := Forge.make(k * 7919 + 1, k % 6)
			seen[str(m.data)] = true
			styles[m.style] = true
		print("40 seeds: %d different machines, %d styles" % [seen.size(), styles.size()])
		_expect(seen.size() >= 25, "seeds give different machines (%d of 40)" % seen.size())
		_expect(styles.size() == Forge.STYLES.size(), "every style comes up (%d)" % styles.size())
		for st: String in Forge.STYLES:
			var m := Forge.make(99, 2, st)
			var s := _sum(m.data)
			print("  %-10s %-11s %4.0f kg %3.0f kW %s%s" % [st, m.name, s.mass, s.power, s.guns,
				"  (%d rams)" % s.spikes if s.spikes > 0 else ""])
		# 2. presets
		var builder: Builder = _g.get("builder")
		for i in Designs.PRESETS.size():
			var data := Designs.preset(i)
			_check(data, "preset %s" % Designs.PRESETS[i][0])
		builder.set_active(true)
		builder.load_preset(Designs.PRESETS.map(func(p: Array) -> String: return str(p[0])).find("ATEŞBAZ"))
		var me: Machine = _g.get("machine")
		_expect(me.guns.size() >= 1 and me.guns[0].kind == "flamer", "the builder loads ATEŞBAZ (flamer: %s)" % [me.guns.map(func(g: MachineGun) -> String: return g.kind)])
		builder.set_active(false)
		# 3. out in the arena
		var spots := 0
		for st: String in Forge.STYLES:
			for tier: int in [0, 4]:
				var m := Forge.make(555 + tier, tier, st)
				var at := Vector3(-36.0 + spots * 6.5, 0.0, 30.0)
				at.y = float(_g.get("terrain").call("height_at", at.x, at.z)) + 2.0
				var e: Machine = _g.call("_spawn", m.data, Transform3D(Basis.IDENTITY, at), 1, false)
				e.label = "%s %d" % [st, tier]
				_put.append(e)
				spots += 1
	if _frame == 60 + 240:
		for e in _put:
			var up := e.global_basis.y.dot(Vector3.UP)
			var ground := float(_g.get("terrain").call("height_at", e.global_position.x, e.global_position.z))
			var h := e.global_position.y - ground
			print("  %-14s up %.2f  %.1f m over the ground  %.1f m/s" % [e.label, up, h, e.linear_velocity.length()])
			_expect(up > 0.85, "%s stands upright (%.2f)" % [e.label, up])
			_expect(h < 3.0 and e.linear_velocity.length() < 1.5, "%s has settled (%.1f m, %.1f m/s)" % [e.label, h, e.linear_velocity.length()])
		print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
		return true
	return false
