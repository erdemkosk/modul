extends SceneTree
## Headless check of the valley's wood (Mode "valley"):
##   godot --headless --path . -s res://tests/wood_test.gd
## 1. A new valley starts with little: the first machine has a saw and a bin on, two frames spare,
##    a little wood in the store.
## 2. R starts the saw; driven into a tree it cuts through it, the tree goes over and lies as
##    billets, and it stays felled (kept).
## 3. The bin takes in the billets lying near it; brought beside the workshop it's emptied into the
##    store.
## 4. A wooden part's made out of the store when none's held (and not without the wood); it's heavy,
##    a flame takes it far harder than steel, and it burns on.
## 5. A log lying in the forest is cut into billets too.
## 6. The ages: no metal part's made without its plan; a plan found, the metal age, and it's made of
##    scrap; plans are kept. A rack adds to the bin. The wood age's weapons on a wooden cart: the
##    ballista's bolts hurt it, with pitch beside it they set it alight; the catapult's stones land on
##    it at 55 m; boiling oil burns it.
## 7. A steering joint turns what's on it with the steering, a wheel on it too.
## 8. The wood age's crews are wooden, with its weapons. 9. Wooden parts are mended with wood.

const HZ := 120
var _g: Node
var _frame := 0
var _step := "start"
var _mark := 0
var _fail := PackedStringArray()
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_wood_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	Inventory.path = "user://test_wood_inventory.cfg"
	Inventory.reset()
	for pair: Array in [[Workshop, "user://test_wood_workshop.cfg"], [Expeditions, "user://test_wood_jobs.cfg"],
			[ValleyLife, "user://test_wood_life.cfg"], [Colossus, "user://test_wood_giants.cfg"]]:
		(pair[0] as GDScript).set("path", pair[1])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(pair[1])))
	var ws: GDScript = load("res://scripts/works_sites.gd")
	ws.set("path", "user://test_wood_sites.cfg")
	SaveGame.save_file = "user://test_wood_world.save" # (the felled trees: kept beside it, not in yours)
	RutStore.clear()
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
	m.brake = 1.0
	m.set_down()


## Facing `d` (flat).
static func _yaw(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame > 150 * HZ:
		_expect(false, "timed out at " + _step)
		return _done()
	var since := (_frame - _mark) / float(HZ)
	var shop: Workshop = _g.get("workshop")
	var props := Timber.props_of(_g)
	match _step:
		"start":
			if since < 3.0:
				return false
			_g.set("player_input", false)
			var m := _me()
			var ids := m.design.map(func(p: Dictionary) -> String: return str(p.id))
			print("first machine: %d parts, saw %s, bin %s; held %s, wood %d" % [ids.size(), "saw" in ids, "collector" in ids, Inventory.counts, Inventory.wood])
			_expect("saw" in ids and "collector" in ids and m.tools.size() == 2, "the first machine has a saw and a bin")
			_expect(Inventory.counts.size() == 1 and Inventory.count("frame") == 2 and Inventory.wood == Inventory.START_WOOD, "little spare: two frames, a little wood")
			# a tree to fell, not far
			var at := m.global_position
			var i := props.prop_near(Vector2(at.x, at.z), 300.0, ["tree"])
			_expect(i >= 0, "a tree nearby")
			if i < 0:
				return _done()
			var info := props.prop_info(i)
			var base: Vector3 = info.origin
			var d := Vector3(base.x - at.x, 0.0, base.z - at.z).normalized()
			_put(m, base - d * 4.6, _yaw(d))
			_r.tree = i
			_r.d = d
			print("tree %d: trunk r %.2f m, %.1f m tall" % [i, float(info.radius), float(info.height)])
			_next("saw")
		"saw":
			var m := _me()
			if since < 1.0:
				return false
			if not _r.has("on"):
				_r.on = true
				print("R: '%s'" % m.tool_key(KEY_R))
				m.brake = 0.0
			m.throttle = 0.25
			var d: Vector3 = _r.d
			m.steer = clampf(-(m.global_basis * Vector3.FORWARD).cross(d).y * 2.0, -1.0, 1.0)
			if props.cut.has(int(_r.tree)):
				print("felled in %.1f s" % since)
				m.throttle = 0.0
				m.brake = 1.0
				_expect(RutStore.cut.has(int(_r.tree)), "a felled tree's kept")
				_next("fallen")
			elif since > 20.0:
				_expect(false, "the saw cuts through the trunk")
				return _done()
		"fallen":
			if since < 7.0:
				return false
			var n := Timber.lying()
			print("billets lying: %d" % n)
			_expect(n >= 2, "the tree lies as billets")
			_expect(props.prop_near(Vector2((_r.d as Vector3).x, 0) * 0.0 + Vector2(props.prop_info(int(_r.tree)).origin.x, props.prop_info(int(_r.tree)).origin.z), 0.5, ["tree"]) != int(_r.tree),
				"and it's gone from where it stood")
			_r.lying = n
			# the bin over them
			var mid := Vector3.ZERO
			var k := 0
			for b: Node in get_nodes_in_group(Timber.GROUP):
				mid += (b as Node3D).global_position
				k += 1
			mid /= maxi(k, 1)
			var m := _me()
			m.tool_key(KEY_R)
			_put(m, mid - m.global_basis.z * 2.3, m.global_basis.get_euler().y) # (its back, the bin, over them)
			_next("gather")
		"gather":
			# along the trunk: the bin brought by each billet still lying, in turn
			if since < 8.0:
				if int(since * 120) % 96 == 0:
					var m := _me()
					for b: Node in get_nodes_in_group(Timber.GROUP):
						var at := (b as Node3D).global_position
						_put(m, at - m.global_basis.z * 2.3, m.global_basis.get_euler().y)
						break
				return false
			print("in the bin: %d of %d lying" % [Inventory.bin, int(_r.lying)])
			_expect(Inventory.bin >= mini(int(_r.lying), 8) - 1 and Inventory.bin >= 2, "the bin takes them in")
			_r.wood0 = Inventory.wood
			_r.bin0 = Inventory.bin
			_put(_me(), shop.truck.global_position + Vector3(9, 0, 0))
			_next("unload")
		"unload":
			if since < 1.5:
				return false
			print("beside the workshop: wood %d -> %d, bin %d" % [int(_r.wood0), Inventory.wood, Inventory.bin])
			_expect(Inventory.bin == 0 and Inventory.wood == int(_r.wood0) + int(_r.bin0), "emptied into the store beside the workshop")
			# 4. wooden parts
			var b: Builder = _g.get("builder")
			var w0 := Inventory.wood
			var made := bool(b.guard.call("wood_frame", Vector3i.ZERO, 0))
			print("a wooden frame made: %s, wood %d -> %d" % [made, w0, Inventory.wood])
			_expect(made and Inventory.wood == w0 - Parts.wood_cost("wood_frame"), "a wooden frame made out of the store")
			Inventory.wood = 0
			_expect(not bool(b.guard.call("wood_plate", Vector3i.ZERO, 0)), "not without the wood")
			_expect(Parts.def("wood_frame").mass > Parts.def("frame").mass * 2.0 and Parts.hp_of("wood_frame") < Parts.hp_of("frame"), "heavier and weaker than steel")
			var m := _me()
			_put(m, shop.truck.global_position + Vector3(80, 0, 0)) # (away from the workshop: it'd mend them)
			var ok := m.place("wood_frame", Vector3i(-1, 1, 0), 0) and m.place("frame", Vector3i(2, 1, 0), 0)
			_expect(ok, "a wooden and a steel frame bolted on")
			var wi := m.design.size() - 2
			var si := m.design.size() - 1
			_r.w_row = m.design[wi]
			_r.s_row = m.design[si]
			var w_hp := float(m.design[wi].hp)
			var s_hp := float(m.design[si].hp)
			m.blast(m.global_transform * m.part_xform(wi).origin, 0.6, 10.0, 0.0, null, "alev")
			m.blast(m.global_transform * m.part_xform(si).origin, 0.6, 10.0, 0.0, null, "alev")
			_r.w_lost = w_hp - float(_r.w_row.hp)
			_r.s_lost = s_hp - float(_r.s_row.hp)
			print("a flame: wood lost %.1f, steel %.1f; wood alight %s" % [float(_r.w_lost), float(_r.s_lost), m.burning(m.design.find(_r.w_row))])
			_expect(float(_r.w_lost) > float(_r.s_lost) * 2.5 and m.burning(m.design.find(_r.w_row)), "a flame takes wood far harder, and it catches")
			_r.w_after = float(_r.w_row.hp)
			_next("burn")
		"burn":
			if since < 3.0:
				return false
			var m := _me()
			var left := float(_r.w_row.hp) if m.design.has(_r.w_row) else 0.0
			print("burning on: %.1f -> %.1f" % [float(_r.w_after), left])
			_expect(left < float(_r.w_after) - 10.0, "it burns on")
			# 5. a log lying in the forest
			var at := m.global_position
			var i := props.prop_near(Vector2(at.x, at.z), 400.0, ["log"])
			if i < 0:
				print("(no log lying near: skipped)")
				_next("ages")
				return false
			var info := props.prop_info(i)
			var o: Vector3 = info.origin
			var ax: Vector3 = info.axis
			var side := Vector3.UP.cross(ax).normalized()
			# the blade 2.4 m ahead of the middle: the machine square on to the log, its blade just short
			_put(m, o - side * 3.2, _yaw(side))
			_r.log = i
			_r.side = side
			_r.n0 = Timber.lying()
			_next("log")
		"log":
			var m := _me()
			if since < 1.0:
				return false
			if not _r.has("log_on"):
				_r.log_on = true
				m.tool_key(KEY_R)
				m.brake = 0.0
			m.throttle = 0.5
			if props.cut.has(int(_r.log)):
				m.throttle = 0.0
				m.brake = 1.0
				if not _r.has("log_t"):
					_r.log_t = since
				if since > float(_r.log_t) + 0.5:
					print("a log cut in %.1f s: billets %d -> %d" % [float(_r.log_t), int(_r.n0), Timber.lying()])
					_expect(Timber.lying() > int(_r.n0), "a log lying is cut into billets")
					_next("ages")
			elif since > 20.0:
				var info := props.prop_info(int(_r.log))
				var c := m.tools[0].node.global_transform * MachineTool.BLADE
				print("(the log wasn't reached: machine %s, blade %s; log %s r %.2f len %.1f ground %.2f)" % [m.global_position, c, info.origin,
					float(info.radius), float(info.length), float(_g.get("terrain").call("height_at", c.x, c.z))])
				_expect(false, "the saw cuts a log lying")
				_next("ages")
		# 6. the ages: metal wants its plan
		"ages":
			var b: Builder = _g.get("builder")
			_expect(Inventory.age() == 1, "the valley starts in the wood age")
			Inventory.scrap = 100
			_expect(not bool(b.guard.call("armor", Vector3i.ZERO, 0)), "no armour without its plan")
			var s0 := Inventory.scrap
			_expect(Inventory.learn("celik") and Inventory.age() == 2, "a plan found: the metal age")
			var made := bool(b.guard.call("armor", Vector3i.ZERO, 0))
			print("armour with the plan: %s, scrap %d -> %d (costs %d)" % [made, s0, Inventory.scrap, Parts.metal_cost("armor")])
			_expect(made and Inventory.scrap == s0 - Parts.metal_cost("armor"), "with its plan, armour's made of scrap")
			_expect(not bool(b.guard.call("minigun", Vector3i.ZERO, 0)), "but not a minigun (another plan)")
			Inventory.load_all()
			_expect(Inventory.knows("celik"), "the plans are kept")
			# the bins: a rack adds to the bin
			var m := _me()
			var d := Designs.valley_start()
			d.append(["wood_rack", 0, 2, 4, 0])
			m.from_data(d)
			print("a bin and a rack hold %d" % m.bin_holds())
			_expect(m.bin_holds() == 14, "a rack adds six to the bin")
			# a wooden enemy to shoot at, out ahead on the open ground by the workshop
			_r.range_at = shop.truck.global_position + Vector3(45, 0, 0)
			d = Designs.valley_start()
			d.append(["ballista", 0, 3, 0, 0])
			m.from_data(d)
			_put(m, Vector3(_r.range_at), _yaw(Vector3.RIGHT))
			_r.target = _target(Vector3(_r.range_at) + Vector3.RIGHT * 30.0)
			_r.h0 = (_r.target as Machine).health()
			_next("ballista")
		"ballista":
			var m := _me()
			var t: Machine = _r.target
			m.aim_point = t.com_global()
			m.firing = since > 1.0
			if since < 9.0:
				return false
			m.firing = false
			print("the ballista: the target %.2f -> %.2f, bolts loosed %d" % [float(_r.h0), t.health(), 16 - int(m.guns[0].ammo)])
			_expect(t.health() < float(_r.h0) - 0.03, "the ballista's bolts hurt it")
			# fire arrows: pitch beside it
			var d := Designs.valley_start()
			d.append_array([["ballista", 0, 3, 0, 0], ["pitch", 2, 3, 0, 0]])
			m.from_data(d)
			_expect(m.guns[0].fiery, "a cask of pitch beside it: its bolts burn")
			_r.burnt = false
			_next("fire_arrows")
		"fire_arrows":
			var m := _me()
			var t: Machine = _r.target
			if not t.alive:
				_next("catapult_setup")
				return false
			m.aim_point = t.com_global()
			m.firing = since > 1.0
			for i in t.design.size():
				if t.burning(i):
					_r.burnt = true
			if since < 8.0:
				return false
			m.firing = false
			print("fire arrows: the target alight %s" % _r.burnt)
			_expect(bool(_r.burnt), "a burning bolt sets wood alight")
			_next("catapult_setup")
		"catapult_setup":
			var m := _me()
			if is_instance_valid(_r.target):
				(_r.target as Machine).queue_free()
			var d := Designs.valley_start()
			d.append(["catapult", 0, 3, 0, 0])
			m.from_data(d)
			_put(m, Vector3(_r.range_at), _yaw(Vector3.RIGHT))
			_r.target = _target(Vector3(_r.range_at) + Vector3.RIGHT * 55.0)
			_r.h0 = (_r.target as Machine).health()
			_next("catapult")
		"catapult":
			var m := _me()
			var t: Machine = _r.target
			if t.alive:
				m.aim_point = t.com_global()
			m.firing = since > 2.0
			if since < 18.0:
				return false
			m.firing = false
			var left := t.health() if t.alive else 0.0
			print("the catapult at 55 m: the target %.2f -> %.2f, stones %d" % [float(_r.h0), left, 10 - int(m.guns[0].ammo)])
			_expect(left < float(_r.h0) - 0.05, "the catapult's stones land on it")
			if is_instance_valid(t):
				t.queue_free()
			var d := Designs.valley_start()
			d.append(["oilpot", 0, 3, 0, 0])
			m.from_data(d)
			_put(m, Vector3(_r.range_at), _yaw(Vector3.RIGHT))
			_r.target = _target(Vector3(_r.range_at) + Vector3.RIGHT * 7.5)
			_r.h0 = (_r.target as Machine).health()
			_next("oil")
		"oil":
			var m := _me()
			var t: Machine = _r.target
			if t.alive:
				m.aim_point = t.global_position
			m.firing = since > 1.0 and since < 2.0
			if since < 6.0:
				return false
			var left := t.health() if t.alive else 0.0
			print("boiling oil at 7 m: the target %.2f -> %.2f, fires %d" % [float(_r.h0), left, Combat.current._fires.size()])
			_expect(left < float(_r.h0) - 0.05, "burning oil burns what's in it")
			if is_instance_valid(t):
				t.queue_free()
			# 7. the steering joint: what's on it turns with the steering, its wheel with it
			var d := Designs.starter()
			d.append_array([["steer", 0, -1, -5, 0], ["frame", 0, 0, -5, 0], ["wheel_s", 1, -1, -6, 0]])
			m.from_data(d)
			_put(m, m.global_position, m.global_basis.get_euler().y)
			m.brake = 0.0
			_next("steer")
		"steer":
			var m := _me()
			m.steer = 1.0
			m.throttle = 0.3
			if since < 1.5:
				return false
			var jt: MachineJoint = m.joints[0]
			var w: MachineWheel = null
			for x in m.wheels:
				if x.part == m.design.size() - 1:
					w = x
			print("steering right: the joint %.2f rad, its wheel rolls %s, members %s" % [jt.angle, w.roll_dir if w else "?", jt.members])
			_expect(jt.angle < -0.3 and w != null and absf(w.roll_dir.x) > 0.2, "the steering joint turns what's on it, and its wheel")
			m.steer = 0.0
			m.throttle = 0.0
			m.brake = 1.0
			# 8. the wood age's crews: wooden machines with its weapons
			for style: String in WoodForge.STYLES:
				var made := WoodForge.make(7, 2, style)
				var ids: Array = (made.data as Array).map(func(e: Array) -> String: return str(e[0]))
				var weapons := ids.filter(func(id: String) -> bool: return str(Parts.def(id).kind) == "weapon")
				print("a wood age crew (%s): %s, %d parts, weapons %s" % [style, made.name, ids.size(), weapons])
				_expect((not weapons.is_empty() or style == "kocbasi") and weapons.all(func(id: String) -> bool: return Parts.burns(id)), "its weapons are the wood age's")
				_expect(ids.count("wood_frame") > 4 and ids.has("cab"), "built of wood, on a cab")
			# 9. mending wood with wood
			var d := Designs.valley_start()
			d.append(["wood_frame", -1, 1, 0, 0])
			m.from_data(d)
			var wi := m.design.size() - 1
			m.design[wi].hp = Parts.hp_of("wood_frame") * 0.3
			_put(m, shop.truck.global_position + Vector3(9, 0, 0))
			Inventory.wood = 10
			Inventory.bin = 0
			_r.wood0 = 10
			_r.w_row = m.design[wi]
			_next("mend_wood")
		"mend_wood":
			if since < 3.0:
				return false
			var m := _me()
			var row: Dictionary = m.design[m.design.size() - 1]
			print("mending wood beside the workshop: %.0f / %.0f hp, wood %d -> %d" % [float(row.hp), Parts.hp_of("wood_frame"), int(_r.wood0), Inventory.wood])
			_expect(float(row.hp) > Parts.hp_of("wood_frame") * 0.5 and Inventory.wood <= int(_r.wood0), "a wooden part's mended with wood")
			return _done()
	return false


## A wooden cart of the other side's at `at` (no crew), facing back toward where you are.
func _target(at: Vector3) -> Machine:
	var d := []
	for x in range(-1, 3):
		for z in range(-2, 4):
			d.append(["wood_frame", x, 0, z, 0])
	d.append_array([["cab", 0, 1, 0, 0], ["engine", 0, 1, 2, 0], ["wood_plate", -1, 1, 0, 1], ["wood_plate", 2, 1, 0, 3],
		["wheel_s", 3, -1, -2, 0], ["wheel_s", 3, -1, 2, 0], ["wheel_s", -2, -1, -2, 2], ["wheel_s", -2, -1, 2, 2]])
	var t: Node = _g.get("terrain")
	at.y = float(t.call("height_at", at.x, at.z)) + 1.6
	var e: Machine = _g.call("_spawn", d, Transform3D(Basis.IDENTITY, at), 1, false)
	e.brake = 1.0
	return e


func _done() -> bool:
	print("WOOD: %s" % ("OK" if _fail.is_empty() else "FAILED: " + ", ".join(_fail)))
	quit(0 if _fail.is_empty() else 1)
	return true
