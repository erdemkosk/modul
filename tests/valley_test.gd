extends SceneTree
## Headless check of the valley's work and its ways (Mode "valley"):
##   godot --headless --path . -s res://tests/valley_test.gd
## 1. The workshop truck stands beside you; building only beside it; V into it and back.
## 2. Parts have a past: a worn one bolted on is as worn as it was, taken off it comes back so, and a
##    saved design keeps its wear; the held parts' wear is kept in the file.
## 3. Mending beside the workshop puts hurt parts right, paid in scrap.
## 4. A worn part driven hard gives in time.
## 5. Expeditions: three jobs offered; one taken, its load waits on its pad, a real crate; a crane
##    on the machine hooks it (Y), lifts it, swings it round and lets it go; a fall hurts it; a winch
##    (N) drags it; steel beams are too heavy for the crane; set down on its pad it's delivered and paid.
## 6. The valley: the mud softer soaked than dry; a ford in flood pushes a machine downstream; today's
##    shut roads are put up near you, broken through they're cleared; a new day comes.
## 7. A giant: out near you, huge (tons), its parts torn off are salvage; brought down, its rare parts
##    and scrap are left, and it's gone for days.

const HZ := 120
var _g: Node
var _frame := 0
var _step := "start"
var _mark := 0
var _fail := PackedStringArray()
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_valley_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	Inventory.path = "user://test_valley_inventory.cfg"
	Inventory.reset()
	for pair: Array in [[Workshop, "user://test_workshop.cfg"], [Expeditions, "user://test_jobs.cfg"], [ValleyLife, "user://test_life.cfg"],
			[Colossus, "user://test_giants.cfg"]]:
		(pair[0] as GDScript).set("path", pair[1])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(pair[1])))
	var ws: GDScript = load("res://scripts/works_sites.gd")
	ws.set("path", "user://test_sites.cfg")
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


func _me() -> Machine:
	return _g.get("machine")


func _put(m: Machine, at: Vector3, yaw := 0.0) -> void:
	var t: Node = _g.get("terrain")
	at.y = float(t.call("height_at", at.x, at.z)) + 1.6
	m.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	m.linear_velocity = Vector3.ZERO
	m.angular_velocity = Vector3.ZERO
	m.brake = 1.0 # (held still: a road's slope would roll it off)
	m.set_down()


func _build_key() -> void:
	var ev := InputEventAction.new()
	ev.action = "build"
	ev.pressed = true
	_g.call("_unhandled_input", ev)


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame > 240 * HZ:
		_expect(false, "timed out at " + _step)
		return _done()
	var since := (_frame - _mark) / float(HZ)
	var shop: Workshop = _g.get("workshop")
	var ex: Expeditions = _g.get("expeditions")
	var life: ValleyLife = _g.get("life")
	var gi: Colossus = _g.get("giants")
	var b: Builder = _g.get("builder")
	match _step:
		"start":
			if since < 3.0:
				return false
			_g.set("player_input", false)
			var m := _me()
			print("workshop truck %.1f m from you, %.0f kg, carries %.0f kg; depots %d, offers %d" % [shop.dist(m), shop.truck.total_mass,
				shop.truck.rated_kg, ex.depots.size(), ex.offers.size()])
			_expect(shop.dist(m) < 15.0 and shop.truck.total_mass > 2000.0, "the workshop truck stands beside you")
			_expect(ex.depots.size() >= 10 and ex.offers.size() == 3, "the valley's places and three jobs offered")
			# 1. building only beside it
			_put(m, shop.truck.global_position + Vector3(70, 0, 0))
			_build_key()
			var far_ok := b.active
			_put(m, shop.truck.global_position + Vector3(9, 0, 0))
			_build_key()
			print("build far from the workshop: %s; beside it: %s" % [far_ok, b.active])
			_expect(not far_ok and b.active, "building only beside the workshop")
			b.set_active(false)
			_next("swap")
		"swap":
			if since < 1.0:
				return false
			var own := _me()
			_expect(shop.swap() and _me() == shop.truck, "V: into the truck")
			_build_key()
			_expect(not b.active, "no building from the truck")
			_expect(shop.swap() and _me() == own, "and back")
			# 2. worn parts
			Inventory.add("armor", 1, 0.4)
			Inventory.add("armor", 1, 0.7)
			var m := _me()
			var ok := bool(b.guard.call("armor", Vector3i(-1, 1, 0), 0)) and m.place("armor", Vector3i(-1, 1, 0), 0)
			b.placed.emit(m.design.size() - 1)
			var i := m.design.size() - 1
			var frac := float(m.design[i].hp) / Parts.hp_of("armor")
			print("armour held 0.4 and 0.7: the one bolted on has %.2f; held left %s" % [frac, Inventory.cond.get("armor")])
			_expect(ok and absf(frac - 0.7) < 0.01, "a worn part bolted on is as worn as the best held")
			b.save()
			var rows := Builder.load_saved()
			var worn_row: Array = rows[rows.size() - 1]
			_expect(worn_row.size() >= 7 and absf(float(worn_row[6]) - 0.7) < 0.01, "a saved design keeps its wear")
			var probe := Machine.new()
			_g.add_child(probe)
			probe.position = Vector3(0, -500, 0)
			probe.from_data(rows)
			_expect(absf(float(probe.design[probe.design.size() - 1].hp) / Parts.hp_of("armor") - 0.7) < 0.01, "and comes back worn")
			probe.queue_free()
			b.remove_at(i)
			print("taken off: armour held %s" % [Inventory.cond.get("armor")])
			_expect(Inventory.count("armor") == 2 and absf(Inventory.best("armor") - 0.7) < 0.01, "taken off, it's held as worn as it was")
			Inventory.load_all()
			_expect(Inventory.count("armor") == 2 and absf(Inventory.best("armor") - 0.7) < 0.01, "the held parts' wear is kept in the file")
			# 3. mending
			for p: Dictionary in m.design:
				if Parts.def(p.id).kind == "wheel" or p.id == "engine":
					p.hp = Parts.hp_of(p.id) * 0.3
			m.rebuild()
			_r.hp0 = m.health()
			Inventory.scrap = 30
			_r.s0 = Inventory.scrap
			_put(m, shop.truck.global_position + Vector3(9, 0, 0))
			_next("mend")
		"mend":
			if since < 5.0:
				return false
			var m := _me()
			print("mending beside the workshop: health %.2f -> %.2f, scrap %d -> %d" % [_r.hp0, m.health(), _r.s0, Inventory.scrap])
			_expect(m.health() > float(_r.hp0) + 0.05 and Inventory.scrap < int(_r.s0), "mended beside the workshop, paid in scrap")
			# 4. a worn part driven hard
			for p: Dictionary in m.design:
				if p.id == "light":
					p.hp = Parts.hp_of(p.id) * 0.05
			var n0 := m.design.size()
			m.speed = 9.0
			for k in 200:
				m.speed = 9.0
				life._wear_t = 99.0
				life._fatigue(0.0, m)
				if m.design.size() < n0:
					break
			print("a light at 5%% driven hard: parts %d -> %d" % [n0, m.design.size()])
			_expect(m.design.size() < n0, "a worn part driven hard gives")
			# 5. an expedition: a crane on the cab's roof, a winch at the back
			_expect(ex.accept(0) and str(ex.job.state) == "waiting", "a job taken: its load waits")
			ex.job.goods = "medicine"
			var d := Designs.starter()
			d.append(["crane", 0, 3, 0, 0])
			d.append(["winch", -1, 1, 2, 0])
			m.from_data(d)
			_expect(m.hoists.size() == 2, "a crane and a winch bolted on")
			_put(m, Vector3(ex.job.at) + Vector3(0, 0, 2.7))
			_next("crane_in")
		"crane_in":
			var m := _me()
			if since < 1.0:
				return false
			if not is_instance_valid(ex.crate):
				if since > 4.0:
					_expect(false, "the load's out on its pad")
					return _done()
				return false
			m.keyed = true
			m.aim_point = ex.crate.global_position
			if since < 2.5:
				return false
			var t := m.hoists[0].tip()
			print("crane over the load: tip %.1f m from it" % t.distance_to(ex.crate.global_position))
			print("Y: '%s'" % m.hoist_key(KEY_Y))
			_expect(m.hoists[0].hooked() == ex.crate, "Y with the hook over the load: hooked")
			_r.y0 = ex.crate.global_position.y
			_r.ground = float(_g.terrain.height_at(ex.crate.global_position.x, ex.crate.global_position.z))
			_next("lift")
		"lift":
			var m := _me()
			m.aim_point = ex.crate.global_position if is_instance_valid(ex.crate) else m.aim_point
			if since < 4.0:
				return false
			var up := ex.crate.global_position.y - float(_r.ground)
			print("lifted: the load's bottom %.2f m off the ground" % (up - 0.35))
			_expect(up > 1.0, "the crane lifts it")
			_r.p0 = ex.crate.global_position
			m.aim_point = m.global_position + m.global_basis.x * 8.0 + Vector3.UP # (swung round to the right)
			_next("swing")
		"swing":
			var m := _me()
			m.aim_point = m.global_position + m.global_basis.x * 8.0 + Vector3.UP
			if since < 4.0:
				return false
			var moved := Vector2(ex.crate.global_position.x - _r.p0.x, ex.crate.global_position.z - _r.p0.z).length()
			print("swung round: the load carried %.1f m, the job %s" % [moved, ex.job.state])
			_expect(moved > 2.0 and str(ex.job.state) == "moved", "slewed round, the load goes with it")
			print("Y: '%s'" % m.hoist_key(KEY_Y))
			_expect(m.hoists[0].hooked() == null, "Y again lets it go")
			_next("set_down")
		"set_down":
			if since < 2.0:
				return false
			var c0 := float(ex.job.cond)
			ex.crate.linear_velocity = Vector3(0, -8, 0) # (a hard fall, as if dropped from high)
			_r.c0 = c0
			_next("knock")
		"knock":
			if since < 0.2:
				return false
			print("a fall: the load %.2f -> %.2f" % [_r.c0, float(ex.job.cond)])
			_expect(float(ex.job.cond) < float(_r.c0) - 0.05, "a fall hurts the load")
			# the winch: the machine ahead of the load, its back to it
			var m := _me()
			var c: Vector3 = ex.crate.global_position
			_put(m, c + Vector3(0, 0, -7.0))
			_next("winch")
		"winch":
			var m := _me()
			if since < 1.5:
				return false
			if not _r.has("towing"):
				_r.towing = true
				print("N: '%s'" % m.hoist_key(KEY_N))
				_expect(m.hoists[1].hooked() == ex.crate, "N: the winch's rope on the load")
				_r.p1 = ex.crate.global_position
				m.brake = 0.0
			m.throttle = 0.6
			if since < 7.0:
				return false
			m.throttle = 0.0
			m.brake = 1.0
			var moved := ex.crate.global_position.distance_to(_r.p1)
			print("towed: the load dragged %.1f m" % moved)
			_expect(moved > 3.0, "the winch drags the load")
			m.hoist_key(KEY_N)
			# too heavy for the crane: steel beams
			ex.job.goods = "beams"
			var bat: Vector3 = shop.truck.global_position + Vector3(25, 0, -12.0) # (flat ground by the workshop, clear of the machine)
			ex._lay(bat)
			_put(m, bat + Vector3(0, 0, 4.0))
			_next("heavy")
		"heavy":
			var m := _me()
			if not is_instance_valid(ex.crate):
				return false
			m.aim_point = ex.crate.global_position
			if since < 2.5:
				return false
			if not _r.has("heavy_hooked"):
				_r.heavy_hooked = true
				print("before hooking the beams: upright %.2f" % m.global_basis.y.y)
				m.hoist_key(KEY_Y)
				_r.hground = float(_g.terrain.height_at(ex.crate.global_position.x, ex.crate.global_position.z))
			if since < 6.0:
				return false
			var up := ex.crate.global_position.y - float(_r.hground)
			print("steel beams (1600 kg) on the 1.5 t crane: %.2f m up (resting: 0.30)" % up)
			_expect(up < 0.7, "too heavy for the crane: it stays down")
			_expect(m.global_basis.y.y > 0.9, "and the machine stays on its wheels (the limiter)")
			m.hoist_key(KEY_Y)
			ex.job.goods = "medicine"
			ex.job.cond = 0.9
			_r.scrap = Inventory.scrap
			_r.wood = Inventory.wood
			_r.held = 0
			for k: String in Inventory.counts:
				_r.held = int(_r.held) + int(Inventory.counts[k])
			var to: Vector3 = ex.depot(ex.job.to).at
			_put(m, to + Vector3(14, 0, 14))
			ex._lay(to + Vector3(3, 0, 0)) # (set down on its pad)
			_next("deliver")
		"deliver":
			if since < 4.0:
				return false
			var held := 0
			for k: String in Inventory.counts:
				held += int(Inventory.counts[k])
			print("on the pad: job %s, delivered %d, wood %d -> %d (age %d), parts held %d -> %d, scrap %d -> %d" % ["done" if ex.job.is_empty() else ex.job.state, ex.done, int(_r.wood), Inventory.wood, Inventory.age(),
				_r.held, held, _r.scrap, Inventory.scrap])
			_expect(ex.job.is_empty() and ex.done == 1 and (Inventory.wood > int(_r.wood) or held > int(_r.held)) and Inventory.scrap > int(_r.scrap),
				"set down on its pad: delivered and paid (in wood in the wood age, parts after)")
			_expect(not is_instance_valid(ex.crate), "and it's taken")
			# 6. the valley soaked
			var mud := Surface.preset("mud")
			var w: Weather = _g.get("weather")
			w.wetness = 0.0
			life._apply_soak()
			_r.dry = mud.static_sink
			w.wetness = 1.0
			life._apply_soak()
			print("mud's sinking dry %.3f, soaked %.3f" % [_r.dry, mud.static_sink])
			_expect(mud.static_sink > float(_r.dry) * 1.8, "the mud's softer soaked than dry")
			var f: Dictionary = life.floods[0]
			_r.ford = f
			_put(_me(), Vector3(f.at.x, 0, f.at.y))
			_me().brake = 0.0 # (not holding against it)
			_r.p0 = _me().global_position
			_next("flood")
		"flood":
			if since < 3.0:
				return false
			var f: Dictionary = _r.ford
			var moved := _me().global_position - Vector3(_r.p0)
			var along := Vector2(moved.x, moved.z).dot(f.down)
			print("in the ford in flood (%.1f m deep): carried %.1f m downstream" % [float(f.depth), along])
			_expect(float(f.depth) > 1.0 and along > 1.0, "a ford in flood carries a machine downstream")
			(_g.get("weather") as Weather).wetness = 0.2
			_expect(not life.blocks.is_empty(), "today's shut roads")
			var bl: Dictionary = life.blocks[0]
			print("today's shut road: %s on %s, cleared already %s, %d pieces up" % [bl.kind, bl.road, bl.cleared, (bl.nodes as Array).size()])
			bl.cleared = false # (the teleports before may have run through it: as it was this morning)
			life._lower(bl)
			_r.block = bl
			_put(_me(), Vector3(bl.at.x, 0, bl.at.y) + Vector3(bl.across.y, 0, -bl.across.x) * 40.0)
			_next("block")
		"block":
			if since < 1.0:
				return false
			var bl: Dictionary = _r.block
			print("near the %s on %s: %d pieces up" % [bl.kind, bl.road, (bl.nodes as Array).size()])
			_expect(not (bl.nodes as Array).is_empty(), "a shut road's put up near you")
			for n: Variant in bl.nodes:
				if is_instance_valid(n):
					(n as Breakable).hit(99999.0, (n as Node3D).global_position, Vector3.FORWARD)
			_next("cleared")
		"cleared":
			if since < 1.0:
				return false
			var bl: Dictionary = _r.block
			_expect(bool(bl.cleared), "broken through, it's cleared")
			var d0 := ValleyLife.day
			life.new_day()
			_expect(ValleyLife.day == d0 + 1, "a new day")
			# 7. a giant
			var g: Dictionary = gi.giants[0]
			_r.giant = g
			_put(_me(), Vector3(g.at) + Vector3(70, 0, 0))
			_me().invulnerable = true
			_r.fired = false
			_next("giant")
		"giant":
			var g: Dictionary = _r.giant
			var gm: Machine = g.m if is_instance_valid(g.m) else null
			if gm and not _r.has("g0"):
				_r.g0 = gm.global_position.distance_to(_me().global_position)
			if gm and gm.firing:
				_r.fired = true
			if since < 16.0:
				return false
			_expect(gm != null, "a giant's out near you")
			if gm == null:
				return _done()
			var dd := gm.global_position.distance_to(_me().global_position)
			var facing := (-gm.global_basis.z).dot(((_me().global_position - gm.global_position) * Vector3(1, 0, 1)).normalized())
			print("%s: %.0f kg, %d parts, %.0f kW, alive %s; upright %.2f, %.0f m -> %.0f m from you, facing you %.2f, fired %s" % [g.name, gm.total_mass,
				gm.design.size(), gm.power_kw, gm.alive, gm.global_basis.y.y, _r.g0, dd, facing, _r.fired])
			_expect(gm.total_mass > 6000.0 and gm.alive, "huge")
			_expect(gm.global_basis.y.y > 0.8 and (dd < float(_r.g0) - 3.0 or facing > 0.7 or bool(_r.fired)), "it turns on you, upright") # (its guns fire when the ground between's clear: not always)
			_r.sal = Salvage.current.count()
			for i in gm.design.size():
				if Parts.def(gm.design[i].id).kind == "weapon":
					gm.break_off(i)
					break
			_next("torn")
		"torn":
			if since < 1.0:
				return false
			var g: Dictionary = _r.giant
			var gm: Machine = g.m
			print("a gun torn off it: salvage lying %d -> %d" % [_r.sal, Salvage.current.count()])
			_expect(Salvage.current.count() > int(_r.sal), "its parts torn off are salvage")
			_r.sal = Salvage.current.count()
			_r.scrap = Inventory.scrap
			gm.damage_part(gm.cab_index(), 999999.0, Vector3.INF, _me())
			_next("fell")
		"fell":
			if since < 1.5:
				return false
			var g: Dictionary = _r.giant
			print("brought down: fell on day %d, salvage %d -> %d, scrap %d -> %d" % [int(g.fell), _r.sal, Salvage.current.count(), _r.scrap, Inventory.scrap])
			_expect(int(g.fell) == ValleyLife.day and Salvage.current.count() >= int(_r.sal) + 5 and Inventory.scrap >= int(_r.scrap) + 40,
				"brought down: its rare parts and scrap left, and it's gone")
			return _done()
	return false


func _done() -> bool:
	print("== valley_test ALL CHECKS PASSED" if _fail.is_empty() else "== valley_test FAILED: %d" % _fail.size())
	quit(1 if not _fail.is_empty() else 0)
	return true
