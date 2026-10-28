extends SceneTree
## Headless check of the proving ground's fighting (scenes/game.tscn, Mode "arena"):
##   godot --headless --path . -s res://tests/combat_test.gd
## 1. A minigun bolted on the cab's roof: its turret turns to the aim and its rounds take a target's
##    parts off (a part at 0 hp comes away as debris).
## 2. A cannon: its shells fly and burst on the target and hurt it.
## 3. A raider (AI) set on you drives at you and its minigun hits you.
## 4. A machine whose cab is shot off comes apart: it's gone, its parts lie about.

const HZ := 120
var _g: Node
var _m: Machine
var _t: Machine
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


func _target(ahead: float, side: float) -> Machine:
	var p := _m.global_position - _m.global_basis.z * ahead + _m.global_basis.x * side
	p.y = float(_g.terrain.call("height_at", p.x, p.z)) + 2.0
	return _g._spawn(Designs.dummy(), Transform3D(Basis.IDENTITY, p), 1, false)


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
			_g.set("player_input", false)
			_m = _g.get("machine")
			_m.from_data(Designs.starter())
			_expect(_m.place("minigun", Vector3i(0, 3, 0), 0), "a minigun bolts onto the cab's roof")
			_expect(_m.guns.size() == 1, "and the machine has a gun")
			_t = _target(30.0, 0.0)
			_next("aim")
		"aim":
			if is_instance_valid(_t):
				_m.aim_point = _t.com_global()
			_m.firing = since > 2.0
			if since < 2.0:
				return false
			if not _r.has("parts0"):
				_r.parts0 = _t.design.size()
				print("minigun on target: %s" % _m.guns[0].on_target)
				_expect(_m.guns[0].on_target, "the turret turned onto the target")
			if since < 7.0:
				return false
			_m.firing = false
			var now := _t.design.size() if is_instance_valid(_t) else 0
			print("5 s of minigun: target %d -> %d parts, debris %d" % [_r.parts0, now, Combat.current._debris.size()])
			_expect(now < int(_r.parts0), "the rounds took parts off it")
			_expect(Combat.current._debris.size() > 0, "and they lie about as debris")
			_next("cannon")
		"cannon":
			if since < 0.5:
				return false
			if is_instance_valid(_t):
				_t.queue_free()
			_m.design = _m.design.filter(func(p: Dictionary) -> bool: return p.id != "minigun")
			_m.rebuild()
			_expect(_m.place("cannon", Vector3i(0, 3, 0), 0), "a cannon bolts on instead")
			_t = _target(40.0, 6.0)
			_next("fire_cannon")
		"fire_cannon":
			if is_instance_valid(_t):
				_m.aim_point = _t.com_global()
			if since < 5.0:
				return false
			if not _r.has("hp0"):
				_r.hp0 = _t.health()
			_m.firing = true
			if since < 10.5:
				return false
			_m.firing = false
			var h: float = _t.health() if is_instance_valid(_t) else 0.0
			print("cannon 5.5 s: target health %.2f -> %.2f" % [_r.hp0, h])
			_expect(h < float(_r.hp0) - 0.05, "the shells hurt it")
			_next("ai")
		"ai":
			if is_instance_valid(_t):
				_t.queue_free()
			_m.brake = 1.0 # (parked: the cannon's recoil had it rolling off)
			var e: Machine = _g.spawn_enemy("raider")
			_r.e = e
			_r.d0 = e.global_position.distance_to(_m.global_position)
			_r.hp_me = _m.health()
			_next("ai_run")
		"ai_run":
			if since < 15.0:
				return false
			var e: Machine = _r.e
			var me_alive := is_instance_valid(_m)
			var d := e.global_position.distance_to(_m.global_position) if is_instance_valid(e) and me_alive else 0.0
			var hp: float = _m.health() if me_alive else 0.0
			print("raider 15 s: %.0f m -> %.0f m, your health %.2f -> %.2f" % [float(_r.d0), d, float(_r.hp_me), hp])
			_expect(d < float(_r.d0) - 15.0, "the raider closed in")
			_expect(hp < float(_r.hp_me), "and its minigun hit you")
			_next("kill")
		"kill":
			var e: Machine = _r.e
			if not is_instance_valid(e):
				return _done()
			e.damage_part(e.cab_index(), 99999.0)
			_next("dead")
		"dead":
			if since < 1.0:
				return false
			_expect(not is_instance_valid(_r.e), "its cab shot off, the raider is gone")
			print("debris lying about: %d" % Combat.current._debris.size())
			return _done()
	return false


func _done() -> bool:
	print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
	return true
