extends SceneTree
## Headless check of the turret, the ammo box and the barrel kit (Mode "arena"):
##   godot --headless --path . -s res://tests/blocks_test.gd
## 1. A turret on the cab's roof with a minigun on it: it carries the gun, follows the aim round to
##    the right on its own, E doesn't touch it; given a key, that key brings it to the front.
## 2. A minigun with an ammo box and a barrel kit beside it: twice the rounds, long-barrelled (truer,
##    the barrel's end further out), and a cannon's shell gets there sooner with a kit.
## 3. The ammo box shot through: it goes up and hurts what's beside it.

var _g: Node
var _m: Machine
var _frame := 0
var _fail := PackedStringArray()
var _step := ""
var _mark := 0
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
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


func _idx(id: String) -> int:
	for i in _m.design.size():
		if _m.design[i].id == id:
			return i
	return -1


func _with(extra: Array) -> Array:
	var d := Designs.starter()
	d.append_array(extra)
	return d


func _physics_process(_d: float) -> bool:
	_frame += 1
	var since := (_frame - _mark) / 120.0
	if _frame == 60:
		_g.set("player_input", false)
		_m = _g.get("machine")
		_m.invulnerable = true
		_m.from_data(_with([["turret", 0, 3, 0, 0], ["minigun", 0, 4, 0, 0]]))
		var jt := _m.joints[0]
		print("turret: carries %s (the gun is %d), on %s, %.0f kg on it" % [jt.members, _idx("minigun"), jt.on, jt.carried_kg])
		_expect(jt.kind == "turret" and jt.members == [_idx("minigun")], "the turret carries the gun")
		_expect(jt.on, "a turret's on by itself")
		_expect(not _m.joint_key(KEY_E), "E leaves a keyless turret alone")
		_next("follow")
	match _step:
		"follow":
			_m.aim_point = _m.global_transform * Vector3(20.0, 1.5, 0.5) # (off to its right)
			if since < 2.5:
				return false
			var jt := _m.joints[0]
			var gun_fwd := -_m.part_nodes[_idx("minigun")].global_basis.z
			print("turned %.0f°, off by %.2f rad; the gun's mount faces %s" % [rad_to_deg(jt.angle), jt.aim_err, gun_fwd])
			_expect(absf(jt.angle + PI * 0.5) < 0.1 and jt.aim_err < 0.06, "it follows the aim round to the right")
			_expect(gun_fwd.dot(_m.global_basis.x) > 0.95, "and the gun with it")
			# given a key: that key holds it at the front
			var d := _m.to_data()
			for row: Array in d:
				if row[0] == "turret":
					if row.size() < 6:
						row.append(KEY_V)
					else:
						row[5] = KEY_V
			_m.from_data(d)
			_expect(_m.joint_key(KEY_V), "its key answers")
			_next("front")
		"front":
			_m.aim_point = _m.global_transform * Vector3(20.0, 1.5, 0.5)
			if since < 2.0:
				return false
			print("keyed off: %.0f°" % rad_to_deg(_m.joints[0].angle))
			_expect(absf(_m.joints[0].angle) < 0.02 and not _m.joints[0].on, "its key brings it round to the front")
			# 2. fed and long-barrelled
			_m.from_data(_with([["minigun", 0, 3, 0, 0], ["ammo", 0, 3, 2, 0], ["barrel", 1, 3, 2, 0]]))
			var g := _m.guns[0]
			print("minigun: feed %d, kit %d, carries %.0f, spread x%.2f, barrel end %s" % [g.feed, g.kit, g.ammo_max, g.spread_k(),
				g._kit_muzzle.position if g._kit_muzzle else Vector3.ZERO])
			_expect(g.feed == 1 and g.kit == 1, "the box and the kit beside it count")
			_expect(is_equal_approx(g.ammo_max, 2.0 * float(MachineGun.AMMO.minigun)) and g.spread_k() < 0.7, "a box carries as much again, a kit makes it truer")
			_expect(g._kit_muzzle != null and g._kit_muzzle.position.z < -0.2, "the long barrel's end is further out")
			_expect(MachineGun.flight_time("cannon", 200.0, 1.3) < MachineGun.flight_time("cannon", 200.0) * 0.8,
				"a kitted shell gets there sooner")
			_expect(MachineGun.flight_time("rockets", 150.0, 1.3) < MachineGun.flight_time("rockets", 150.0), "a kitted rocket too")
			# 3. the box shot through
			_m.invulnerable = false
			_r.gun_hp = float(_m.design[_idx("minigun")].hp)
			_r.parts = _m.design.size()
			_m.damage_part(_idx("ammo"), 1000.0)
			_next("boom")
		"boom":
			if since < 0.5:
				return false
			var gi := _idx("minigun")
			var left := float(_m.design[gi].hp) if gi >= 0 else 0.0
			print("ammo gone: %s; the gun %.0f -> %.0f hp, parts %d -> %d" % [_idx("ammo") < 0, _r.gun_hp, left, _r.parts, _m.design.size()])
			_expect(_idx("ammo") < 0, "the box is gone")
			_expect(left < float(_r.gun_hp) - 30.0, "it went up and hurt the gun beside it")
			print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
			return true
	return _frame > 120 * 40
