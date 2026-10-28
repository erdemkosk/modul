extends SceneTree
## Headless check of the sites' structures (Mode "arena"):
##   godot --headless --path . -s res://tests/structures_test.gd
## 1. Every kind builds and stands: pieces held, some on the ground, what rests on what worked out.
## 2. A water tower: two legs on one side shelled away, the platform and tank come down (it's down);
##    one leg alone leaves it standing.
## 3. A chimney: its lowest ring broken, the stack above falls over.
## 4. A fuel tank: flame on it lights it, and in a moment it goes up (its pieces gone, it's down).
## 5. A scaffold: lit at one pole, the fire spreads along the wood; in the rain much less.
## 6. A machine driven hard into a warehouse column breaks it.

var _g: Node
var _frame := 0
var _fail := PackedStringArray()
var _s := {}
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


func _place(kind: String, x: float, z: float) -> Structure:
	var t: Node = _g.get("terrain")
	var at := Vector3(x, float(t.call("height_at", x, z)), z)
	var s := Structures.make(kind, Transform3D(Basis.IDENTITY, at), t)
	_g.add_child(s)
	return s


func _next(s: String) -> void:
	_step = s
	_mark = _frame


func _physics_process(_d: float) -> bool:
	_frame += 1
	var since := (_frame - _mark) / 120.0
	if _frame == 60:
		_g.set("player_input", false)
		(_g.get("machine") as Machine).global_position = Vector3(0, 30, -60)
		var x := -45.0
		for k: String in ["water_tower", "chimney", "fuel_tank", "warehouse", "scaffold", "transformer", "crane", "silo"]:
			_s[k] = _place(k, x, 35.0)
			x += 13.0
		_s.tower2 = _place("water_tower", -45.0, 15.0)
		_s.scaffold_wet = _place("scaffold", 40.0, 10.0)
		_s.wh2 = _place("warehouse", 25.0, -25.0)
		_next("stand")
	match _step:
		"stand":
			if since < 1.0:
				return false
			for k: String in _s:
				var s: Structure = _s[k]
				var ground := 0
				var rests := 0
				for p in s.pieces:
					ground += 1 if p.grounded else 0
					rests += 1 if not p.below.is_empty() else 0
				print("  %-12s %3d pieces, %2d on the ground, %2d resting on others, standing %.2f" % [k, s.pieces.size(), ground, rests, s.standing_share()])
				_expect(s.pieces.size() >= 4 and ground >= 1 and s.standing_share() > 0.99 and not s.down, "%s builds and stands" % k)
			# 2. one leg off the second tower, two on one side off the first
			_leg_off(_s.tower2, 1)
			_leg_off(_s.water_tower, 2)
			# 3. the chimney's lowest ring
			for p in (_s.chimney as Structure).pieces:
				if p.stuff == "brick" and p.global_position.y - (_s.chimney as Structure).global_position.y < 2.0:
					p.hit(99999.0, p.global_position, Vector3.RIGHT, true)
			# 4. flame on the fuel tank
			var tank: Structure = _s.fuel_tank
			for p in tank.pieces:
				if p.stuff == "fuel":
					p.ignite()
			# 5. a pole of each scaffold lit; rain on the second
			_light_one(_s.scaffold)
			_r.rain = true
			_next("burn")
		"burn":
			Weather.rain_now = 0.0
			if since < 0.2 and is_instance_valid(_s.scaffold_wet):
				pass
			if since < 6.0:
				return false
			var t1: Structure = _s.water_tower
			var t2: Structure = _s.tower2
			print("water towers: two legs off -> down %s (standing %.2f); one leg off -> down %s (standing %.2f)" % [t1.down, t1.standing_share(), t2.down, t2.standing_share()])
			_expect(t1.down, "two legs on one side gone: the tank comes down")
			_expect(not t2.down, "one leg gone: it still stands")
			var ch: Structure = _s.chimney
			print("chimney: down %s, standing %.2f" % [ch.down, ch.standing_share()])
			_expect(ch.down, "the chimney falls with its foot ring gone")
			var ft: Structure = _s.fuel_tank
			print("fuel tank: down %s" % ft.down)
			_expect(ft.down, "the lit fuel tank goes up")
			var sc: Structure = _s.scaffold
			var lit := 0
			for p in sc.pieces:
				lit += 1 if p.burning or p.hp <= 0.0 else 0
			print("scaffold: %d pieces burning or burnt of %d" % [lit, sc.pieces.size()])
			_expect(lit >= 4, "the fire spread along the scaffold (%d)" % lit)
			_r.dry = lit
			# 5b. the wet one: rain on, lit
			Weather.rain_now = 1.0
			_light_one(_s.scaffold_wet)
			# 6. a machine into a column
			var wh: Structure = _s.wh2
			_r.wh_hp = _hp_of(wh)
			var at := Vector3(25.0, 0.0, -52.0)
			at.y = float(_g.get("terrain").call("height_at", at.x, at.z)) + 1.2
			var m: Machine = _g.call("_spawn", Designs.rammer(), Transform3D(Basis(Vector3.UP, PI), at), 1, false) # (its nose to it)
			m.invulnerable = true
			_r.ram = m
			_next("wet")
		"wet":
			Weather.rain_now = 1.0
			if since >= 6.0 and not _r.has("wet_lit"):
				var n := 0
				for p in (_s.scaffold_wet as Structure).pieces:
					n += 1 if p.burning or p.hp <= 0.0 else 0
				_r.wet_lit = n
			var m: Machine = _r.ram
			if is_instance_valid(m):
				m.throttle = 1.0
				var to := Vector3(25.0, m.global_position.y, -25.0) - m.global_position
				m.steer = clampf(-(-m.global_basis.z).signed_angle_to(to * Vector3(1, 0, 1), Vector3.UP) * 1.5, -1.0, 1.0)
			if since < 8.0:
				return false
			var lit := int(_r.wet_lit) # (after the same 6 s the dry one had)
			print("scaffold in the rain: %d burning or burnt" % lit)
			_expect(lit * 2 < int(_r.dry), "in the rain the fire spreads less than half as far (%d to %d)" % [lit, _r.dry])
			var after := _hp_of(_s.wh2)
			print("rammed warehouse: its pieces' hit points %.0f -> %.0f" % [_r.wh_hp, after])
			_expect(after < float(_r.wh_hp) - 50.0, "ramming the warehouse hurts it")
			Weather.rain_now = 0.0
			print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
			return true
	return _frame > 120 * 60


## Breaks `n` legs on the tower's -x side.
func _leg_off(s: Structure, n: int) -> void:
	var legs: Array[StructurePiece] = []
	for p in s.pieces:
		if p.grounded and p.size.y > 8.0 and p.global_position.x < s.global_position.x:
			legs.append(p)
	for k in mini(n, legs.size()):
		legs[k].hit(99999.0, legs[k].global_position, Vector3.RIGHT, true)


func _hp_of(s: Structure) -> float:
	var t := 0.0
	for p in s.pieces:
		if is_instance_valid(p):
			t += maxf(p.hp, 0.0)
	return t


func _light_one(s: Structure) -> void:
	for p in s.pieces:
		if p.stuff == "wood" and p.grounded:
			p.ignite()
			return
