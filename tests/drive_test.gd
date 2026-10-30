extends SceneTree
## Headless check of a machine on the valley (scenes/game.tscn):
##   godot --headless --path . -s res://tests/drive_test.gd
## 1. The starter machine: its mass and power from its parts, four wheels, the front two steering.
## 2. It settles on its wheels (all four touching, the springs holding it off the ground).
## 3. W: it drives off; A/D: it turns; Space: it stops.
## 4. Building: a block bolts on where the ray hits, a second cab doesn't, the cab won't come off,
##    a frame a light hangs on alone won't either, a loose one does; the mass follows.

const HZ := 120
var _game: Node
var _m: Machine
var _frame := 0
var _step := "start"
var _mark := 0
var _fail := PackedStringArray()
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	Mode.current = "valley"
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail.append(what)
		print("  FAIL: " + what)


func _next(s: String) -> void:
	_step = s
	_mark = _frame


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame > 60 * HZ:
		_expect(false, "timed out at " + _step)
		return _done()
	var since := (_frame - _mark) / float(HZ)
	match _step:
		"start":
			_m = _game.get("machine")
			_m.from_data(Designs.starter())
			_m.invulnerable = true # (this is about driving and building: knocks off the road don't count here)
			print("starter: %d parts, %.0f kg, %.0f kW, %d wheels, com %s" % [_m.design.size(), _m.total_mass, _m.power_kw, _m.wheels.size(), _m.com])
			var steer := 0
			for w in _m.wheels:
				steer += int(w.steers)
			_expect(_m.wheels.size() == 4 and steer == 2, "four wheels, the front two steer")
			_expect(absf(_m.total_mass - 802.0) < 1.0 and is_equal_approx(_m.power_kw, 90.0), "mass and power from the parts")
			_next("settle")
		"settle":
			if since < 4.0:
				return false
			var touching := 0
			for w in _m.wheels:
				touching += int(w.contact)
			var p := _m.global_position
			var g: float = _game.terrain.height_at(p.x, p.z)
			print("settled: %d wheels touching, frame bottom %.2f m over the ground, speed %.2f, up %.2f" % [touching, p.y - g, _m.linear_velocity.length(), _m.global_basis.y.y])
			_expect(touching == 4, "all four wheels on the ground")
			_expect(p.y - g > 0.15, "the springs hold it off the ground")
			_r.p0 = p
			Input.action_press("throttle")
			_next("drive")
		"drive":
			if since < 6.0:
				return false
			var d: float = (_m.global_position - _r.p0).length()
			print("6 s of W: %.1f m, %.1f km/h on %s" % [d, _m.speed * 3.6, _m.ground_label])
			_expect(d > 20.0, "W drives it off")
			_r.yaw = _m.global_basis.get_euler().y
			Input.action_press("left")
			_next("turn")
		"turn":
			var y := _m.global_basis.get_euler().y # (added up a step at a time: it may go right round)
			_r.turned = float(_r.get("turned", 0.0)) + angle_difference(float(_r.yaw), y)
			_r.yaw = y
			if since < 1.2: # (full lock at 60 km/h: the first moment's what tells; after it, it may spin)
				return false
			Input.action_release("left")
			Input.action_release("throttle")
			var turned := rad_to_deg(float(_r.turned))
			print("A 1.2 s: turned %.0f deg" % turned)
			_expect(turned > 15.0, "A turns it left")
			Input.action_press("brake")
			_next("stop")
		"stop":
			if since < 4.0:
				return false
			Input.action_release("brake")
			print("Space 4 s: %.1f km/h" % (_m.speed * 3.6))
			_expect(absf(_m.speed) < 1.0, "the brake stops it")
			_next("build")
		"build":
			if since < 1.0:
				return false
			var b: Builder = _game.get("builder")
			b.set_active(true)
			var under_light := _m.part_at(Vector3i(-1, 0, -2))
			_expect(not _m.can_remove(under_light), "the frame a light hangs on alone doesn't come off")
			var m0 := _m.total_mass
			b.select("armor")
			# straight down onto the bed ahead of the cab
			var top := _m.global_transform * (Vector3(0.25, 3.0, -0.75))
			var aim := b.aim_ray(top, -_m.global_basis.y)
			print("aim at the bed: ", aim)
			_expect(not aim.is_empty() and aim.ok, "the ray finds the bed, an armour block fits on it")
			if not aim.is_empty():
				_expect(_m.place("armor", aim.at, aim.rot), "it bolts on")
			_expect(absf(_m.total_mass - m0 - 55.0) < 0.5, "and the machine is 55 kg heavier")
			_expect(not _m.can_place("cab", Vector3i(0, 1, 2), 0), "no second cab")
			_expect(not _m.can_remove(_m.cab_index()), "the cab doesn't come off")
			var armor := _m.design.size() - 1
			_expect(_m.remove(armor), "the loose armour block comes off")
			b.set_active(false)
			return _done()
	return false


func _done() -> bool:
	Input.action_release("throttle")
	Input.action_release("reverse")
	Input.action_release("left")
	print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
	return true
