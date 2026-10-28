extends SceneTree
## Not a test: a look at a cage fight, second by second (your minigun on the rival, what the rival does).
##   godot --headless --path . -s res://tests/cage_probe.gd

var _g: Node
var _c: Cage
var _m: Machine
var _frame := 0
var _t0 := -1
var _hits := 0


func _initialize() -> void:
	Builder.save_path = "user://probe_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	Mode.current = "cage"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _gun(m: Machine) -> String:
	if m.guns.is_empty():
		return "no gun"
	var g: MachineGun = m.guns[0]
	return "%s spin %.2f can %s on %s rnd %d cool %.2f" % [g.kind, g._spin, g.can_spin, g.on_target, g._round, g._cool]


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame == 120:
		_c = _g.get("cage")
		_m = _g.get("machine")
		var data := Designs.starter()
		data.append(["minigun", 0, 3, 0, 0])
		_m.from_data(data)
		_c.start_run()
	if _frame > 120 and _t0 < 0 and _c.state == "fight":
		_t0 = _frame
		_g.set("player_input", false) # (so the firing below holds)
		Combat.current.hit_confirmed.connect(func(by: Machine, _k: bool) -> void:
			if by == _m:
				_hits += 1)
		print("fight on")
	if _t0 > 0:
		var e: Machine = _c.rivals[0] if not _c.rivals.is_empty() and is_instance_valid(_c.rivals[0]) else null
		if e:
			_m.aim_point = e.com_global()
			_m.firing = OS.get_environment("PROBE_FIRE") == "1"
		if (_frame - _t0) % 60 == 0:
			var s := (_frame - _t0) / 120.0
			print("t %.1f  hits %d ME hp %.2f kj %.0f/%.0f shed %s | %s" % [s, _hits, _m.health(), _m.energy_kj, _m.capacity_kj, _m.get("shed"), _gun(_m)])
			if e:
				var ai: AiDriver = e.get_children().filter(func(n: Node) -> bool: return n is AiDriver).front()
				print("        RIVAL %s hp %.2f kj %.0f/%.0f thr %.1f str %.1f v %.1f fire %s dist %.1f | %s | pw %.0f kW" % [e.label, e.health(),
					e.energy_kj, e.capacity_kj, e.throttle, e.steer, e.speed, e.firing, e.global_position.distance_to(_m.global_position),
					_gun(e), e.power_kw])
		if _frame - _t0 > 120 * 25:
			return true
	return _frame > 120 * 60
