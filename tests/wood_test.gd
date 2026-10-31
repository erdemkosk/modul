extends SceneTree
## Headless check of the valley's wood (Mode "valley"):
##   godot --headless --path . -s res://tests/wood_test.gd
## 1. A new valley starts with little: the first machine is a wooden cart with a saw and a short
##    crane on, two rails spare, a little wood in the store; the builder offers only what can be had.
## 2. R starts the saw; driven into a tree it cuts through it, the tree goes over and lies as
##    billets, and it stays felled (kept).
## 3. The crane hooks a billet (Y), lifts it, swings it over the bed and lets it go: it rides there
##    between the rails. Brought beside the workshop and stopped, what's on the bed goes into the
##    store (and opens parts).
## 4. A wooden part's made out of the store when none's held (and not without the wood); it's heavy,
##    a flame takes it far harder than steel, and it burns on.
## 5. A log lying in the forest is cut into billets too.
## 6. The ages: no metal part's made without its plan; a plan found, the metal age, and it's made of
##    scrap; plans are kept; parts open as wood comes home. The wood age's weapons on a wooden cart: the
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


## A billet lying, not on the cart.
func _billet_off(m: Machine) -> RigidBody3D:
	for n: Node in get_nodes_in_group(Timber.GROUP):
		var b := n as RigidBody3D
		if not b.has_meta("loaded") and not Workshop._riding(b, m):
			return b
	return null


func _on_bed(m: Machine) -> Array:
	var out := []
	for n: Node in get_nodes_in_group(Timber.GROUP):
		if Workshop._riding(n as Node3D, m):
			out.append(n)
	return out


## `m` and what rides on it, moved to `at` (as driving there would, quicker).
func _carry(m: Machine, at: Vector3) -> void:
	var rides := _on_bed(m)
	var rel := []
	for b: RigidBody3D in rides:
		rel.append(m.global_transform.affine_inverse() * b.global_transform)
	_put(m, at, m.global_basis.get_euler().y)
	for k in rides.size():
		var b: RigidBody3D = rides[k]
		b.global_transform = m.global_transform * (rel[k] as Transform3D)
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO


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
			print("first machine: %d parts, %.0f kg, %.0f kW, saw %s, crane %s; held %s, wood %d" % [ids.size(), m.total_mass, m.power_kw, "saw" in ids,
				"wood_crane" in ids, Inventory.counts, Inventory.wood])
			_expect("saw" in ids and "wood_crane" in ids and "wood_cab" in ids and m.tools.size() == 1 and m.hoists.size() == 1,
				"the first machine is a wooden cart with a saw and a crane")
			_expect(Inventory.counts.size() == 1 and Inventory.count("wood_rail") == 2 and Inventory.wood == Inventory.START_WOOD, "little spare: two rails, a little wood")
			_expect(Inventory.shown("wood_frame") and Inventory.shown("wood_crane") and not Inventory.shown("ballista") and not Inventory.shown("armor")
				and not Inventory.shown("engine") and not Inventory.shown("crane"), "the builder offers only what can be had")
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
			if not props.cut.has(int(_r.tree)): # (the cross a little up the trunk: the saw's arm lifts the blade to it)
				m.keyed = true
				m.aim_point = props.prop_info(int(_r.tree)).origin + Vector3.UP * 0.9
			if props.cut.has(int(_r.tree)):
				print("felled in %.1f s, the arm up %.2f rad" % [since, m.tools[0].lift])
				_expect(m.tools[0].lift > 0.3, "the saw's arm lifts the blade to the cross")
				m.throttle = 0.0
				m.brake = 1.0
				_expect(RutStore.cut.has(int(_r.tree)), "a felled tree's kept")
				_next("fallen")
			elif _frame % 120 == 0:
				var c := m.tools[0].blade()
				var o: Vector3 = props.prop_info(int(_r.tree)).origin
				print("  blade %.2f m up, %.2f m from the trunk's middle, speed %.2f, cutting %d, spin %.2f" % [c.y - o.y, Vector2(c.x - o.x, c.z - o.z).length(), m.speed, m.tools[0].cutting, m.tools[0].spin])
			if not props.cut.has(int(_r.tree)) and since > 20.0:
				var info := props.prop_info(int(_r.tree))
				var c := m.tools[0].blade()
				print("(not cut: blade %s, tree base %s, ground there %.2f, machine %s)" % [c, info.origin, float(_g.get("terrain").call("height_at", c.x, c.z)), m.global_position])
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
			_me().tool_key(KEY_R)
			_r.loaded = 0
			_r.tries = 0
			_next("hook")
		# 3. loading: the cart beside a billet, the crane swung over it, Y; swung over the bed, Y
		"hook":
			var m := _me()
			if since < 0.2:
				var b := _billet_off(m)
				if b == null:
					_expect(false, "a billet to lift")
					return _done()
				_r.b = b
				var at := b.global_position
				var side := m.global_basis.x
				_put(m, at - side * 1.5 + m.global_basis.z * 0.6, m.global_basis.get_euler().y) # (beside it, the seat by it)
				return false
			var b: RigidBody3D = _r.b
			m.aim_point = b.global_position
			var h: MachineHoist = m.hoists[0]
			if not _r.has("picked"): # (2: the crane picked on the bottom panel; the saw's 1, picked from the start)
				_r.picked = true
				_expect(m.tools[0].armed and not h.armed, "the saw's picked to start with, the crane isn't")
				_g.call("toggle_gun", 1)
				_expect(h.armed, "its number picks the crane")
			if since < 2.5:
				return false
			if not _r.has("mouse"): # (the first by the mouse: the left held, the hook goes down and takes what it touches)
				_r.mouse = true
				h.lower_held = true
				_next("mouse_lower")
				return false
			print("Y: '%s'" % m.hoist_key(KEY_Y))
			_expect(m.hoists[0].hooked() is RigidBody3D, "the crane takes hold of a billet")
			if m.hoists[0].hooked():
				_r.b = m.hoists[0].hooked()
			_next("lift")
		"mouse_lower":
			var m := _me()
			var h: MachineHoist = m.hoists[0]
			m.aim_point = (_r.b as RigidBody3D).global_position
			if h.hooked() == null and since < 8.0:
				return false
			h.lower_held = false
			print("left held %.1f s: hooked %s" % [since, MachineHoist.what_is(h.hooked()) if h.hooked() else "nothing"])
			_expect(h.hooked() is RigidBody3D, "held down, the hook goes down and takes what it touches")
			if h.hooked():
				_r.b = h.hooked()
			h.raise_held = true
			_next("mouse_raise")
		"mouse_raise":
			var m := _me()
			var h: MachineHoist = m.hoists[0]
			if since < 2.5:
				return false
			h.raise_held = false
			var b: RigidBody3D = _r.b
			var up := b.global_position.y - float(_g.get("terrain").call("height_at", b.global_position.x, b.global_position.z))
			print("right held 2.5 s: %.2f m off the ground" % up)
			_expect(up > 0.8, "the right held winds it up")
			_next("lift")
		"lift":
			var m := _me()
			var b: RigidBody3D = _r.b
			if since < 2.5:
				m.aim_point = b.global_position + Vector3.UP * 0.5
				return false
			if since < 3.0:
				_r.lifted = b.global_position.y - float(_g.get("terrain").call("height_at", b.global_position.x, b.global_position.z))
			m.aim_point = m.global_transform * Vector3(0.25, 1.0, 0.9) # (over the bed)
			if since < 7.0:
				return false
			if not _r.has("paid"): # (the left held: the rope pays out, the load goes down; let go, it holds)
				_r.paid = true
				var h: MachineHoist = m.hoists[0]
				var l0 := float(m.design[h.index].rope_len)
				h.lower_held = true
				for k in 30:
					h.update(1.0 / 60.0)
				h.lower_held = false
				var l1 := float(m.design[h.index].rope_len)
				h.update(0.5)
				print("held down 0.5 s: rope %.2f -> %.2f, then holds at %.2f" % [l0, l1, float(m.design[h.index].rope_len)])
				_expect(l1 > l0 + 0.1 and absf(float(m.design[h.index].rope_len) - l1) < 0.05, "the left held pays out; let go, it holds")
				m.design[h.index].erase("drum")
			print("lifted %.2f m off the ground; over the bed: %s" % [float(_r.lifted), Workshop._riding(b, m)])
			print("Y: '%s'" % m.hoist_key(KEY_Y))
			_next("set_down")
		"set_down":
			if since < 4.5:
				return false
			_expect(_me().hoists[0].hooked() == null, "set down, it's let go")
			var m := _me()
			var b: RigidBody3D = _r.b
			var on := Workshop._riding(b, m)
			print("let go: on the bed %s (at %s in the cart)" % [on, m.global_transform.affine_inverse() * b.global_position])
			_r.tries = int(_r.tries) + 1
			if on:
				_r.loaded = int(_r.loaded) + 1
				b.set_meta("loaded", true)
			if int(_r.loaded) < 2 and int(_r.tries) < 4:
				_next("hook")
				return false
			_expect(int(_r.loaded) >= 2, "two billets lifted onto the bed")
			# driven home with them: they ride along
			_r.wood0 = Inventory.wood
			_r.on_bed = _on_bed(m)
			_r.worth = 0
			for x: RigidBody3D in _r.on_bed:
				_r.worth = int(_r.worth) + Timber.worth(x)
			_carry(m, shop.truck.global_position + shop.truck.global_basis.x * -16.0)
			_next("unload")
		"unload":
			var m := _me()
			if since < 0.6:
				return false
			if since < 1.0 and not _r.has("said_still"):
				_r.said_still = true
				var still := _on_bed(m).size()
				print("at the workshop, still on the bed: %d of %d" % [still, (_r.on_bed as Array).size()])
				return false
			if since < 4.0:
				return false
			print("beside the workshop: wood %d -> %d (worth %d), all told %d" % [int(_r.wood0), Inventory.wood, int(_r.worth), Inventory.delivered])
			_expect(Inventory.wood > int(_r.wood0) and Inventory.wood <= int(_r.wood0) + int(_r.worth) and _on_bed(m).is_empty(), "what's on the bed goes into the store")
			_expect(Inventory.delivered == Inventory.wood - int(_r.wood0), "and counts toward what opens")
			# 4. wooden parts
			var b: Builder = _g.get("builder")
			var w0 := Inventory.wood
			var made := bool(b.guard.call("wood_frame", Vector3i.ZERO, 0))
			print("a wooden frame made: %s, wood %d -> %d" % [made, w0, Inventory.wood])
			_expect(made and Inventory.wood == w0 - Parts.wood_cost("wood_frame"), "a wooden frame made out of the store")
			Inventory.wood = 0
			_expect(not bool(b.guard.call("wood_plate", Vector3i.ZERO, 0)), "not without the wood")
			_expect(Parts.def("wood_frame").mass > Parts.def("frame").mass * 2.0 and Parts.hp_of("wood_frame") < Parts.hp_of("frame"), "heavier and weaker than steel")
			_put(m, shop.truck.global_position + Vector3(80, 0, 0)) # (away from the workshop: it'd mend them)
			var ok := m.place("wood_frame", Vector3i(0, 1, 1), 0) and m.place("frame", Vector3i(1, 1, 1), 0)
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
			m.from_data(Designs.valley_start()) # (a fresh cart: the fire's had this one)
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
			if _frame % 120 == 0 and not m.tools.is_empty():
				var c := m.tools[0].blade()
				print("  up %s, blade %.2f over the ground, speed %.2f" % [m.global_basis.y, c.y - float(_g.get("terrain").call("height_at", c.x, c.z)), m.speed])
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
				var c := m.tools[0].blade()
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
			Inventory.delivered = 30
			_expect(Inventory.shown("ballista") and not Inventory.shown("catapult"), "parts open as wood comes home")
			var m := _me()
			# a wooden enemy to shoot at, out ahead on the open ground by the workshop
			_r.range_at = shop.truck.global_position + Vector3(45, 0, 0)
			var d := Designs.valley_start()
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
				_expect(ids.count("wood_frame") > 4 and ids.has("wood_cab"), "built of wood, on a wooden seat")
			# 9. mending wood with wood
			var d := Designs.valley_start()
			d.append(["wood_frame", 0, 1, 1, 0])
			m.from_data(d)
			var wi := m.design.size() - 1
			m.design[wi].hp = Parts.hp_of("wood_frame") * 0.3
			_put(m, shop.truck.global_position + Vector3(9, 0, 0))
			Inventory.wood = 10
			pass
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
