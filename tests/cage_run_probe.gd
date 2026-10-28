extends SceneTree
## Not a test: a whole KAFES run on autopilot (a beginner's machine: the starter with a minigun on the
## cab, driving at the nearest rival and firing), the workshop repairing all it can between rounds;
## each round's time, what it took, the pay, the credits and the bill.
##   godot --headless --path . -s res://tests/cage_run_probe.gd [-- --design=tank|starter|heavy] [-- --seed=N]

var _g: Node
var _c: Cage
var _frame := 0
var _round_t := 0.0
var _last := ""
var _design := "starter"
var _seed := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--design="):
			_design = a.substr(9)
		if a.begins_with("--seed="):
			_seed = int(a.substr(7))
	Builder.save_path = "user://probe_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	Mode.current = "cage"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _physics_process(dt: float) -> bool:
	_frame += 1
	if _frame == 120:
		_c = _g.get("cage")
		var m: Machine = _g.get("machine")
		var data: Array = Designs.starter()
		if _design == "starter":
			data.append(["minigun", 0, 3, 0, 0])
		else:
			data = Callable(Designs, _design).call()
		m.from_data(data)
		if _seed != 0:
			_c.run_seed = _seed
		_c.start_run()
		_g.set("player_input", false)
		print("run: %s, %d credits to start" % [_design, _c.credits])
	if _frame < 120:
		return false
	var st := _c.state
	if st != _last:
		_on_state(st)
		_last = st
	if st == "fight":
		_g.set("player_input", false) # (the cage hands you the controls at the bell: the autopilot keeps them)
		_round_t += dt
		_drive()
		if int(_round_t * 120.0) % 1200 == 0:
			var me: Variant = _g.get("machine")
			var hp := (me as Machine).health() if is_instance_valid(me) else 0.0
			var rs := []
			for e in _c.rivals:
				if is_instance_valid(e):
					rs.append("%s %d%% %.0fm" % [e.label, int(e.health() * 100.0), e.global_position.distance_to((me as Machine).global_position) if is_instance_valid(me) else 0.0])
			var gs := ""
			if is_instance_valid(me):
				for g in (me as Machine).guns:
					gs += "%s rnd %d spin %.1f on %s armed %s " % [g.kind, g._round, g._spin, g.on_target, g.armed]
				gs += "fire %s kj %.0f" % [(me as Machine).firing, (me as Machine).energy_kj]
			print("    %.0fs you %d%%  %s  | %s" % [_round_t, int(hp * 100.0), ", ".join(rs), gs])
	if st in ["lost", "champion"] or _frame > 120 * 60 * 25:
		print("END: %s after round %d, %d credits" % [st, _c.round + 1, _c.credits])
		return true
	return false


func _on_state(st: String) -> void:
	var mv: Variant = _g.get("machine")
	var m: Machine = mv if is_instance_valid(mv) else null
	match st:
		"fight":
			_round_t = 0.0
			var names := []
			for e in _c.rivals:
				names.append("%s %.0f kg" % [e.label, e.total_mass])
			print("round %d %s: %s" % [_c.round + 1, Cage.ROUNDS[_c.round].name, ", ".join(names)])
		"won", "lost":
			print("  %s in %.0f s, you at %d%%, credits %d" % [st, _round_t, int(m.health() * 100.0) if m else 0, _c.credits])
		"workshop":
			var before := _c.credits
			var spent := _c.repair(false)
			var mm: Machine = _g.get("machine")
			print("  workshop: repaired for %d (had %d), now %d%% with %d left" % [spent, before, int(mm.health() * 100.0), _c.credits])
			_c.next_round()


## At the nearest rival: closes to 12 m, circling a little, firing whenever it's ahead.
func _drive() -> void:
	var m: Machine = _g.get("machine")
	if not is_instance_valid(m) or not m.alive:
		return
	var best: Machine = null
	for e in _c.rivals:
		if is_instance_valid(e) and e.alive and (best == null or e.global_position.distance_to(m.global_position) < best.global_position.distance_to(m.global_position)):
			best = e
	if best == null:
		m.throttle = 0.0
		m.firing = false
		return
	var to := best.global_position - m.global_position
	var dist := to.length()
	var ang := (-m.global_basis.z).signed_angle_to(to, Vector3.UP)
	m.steer = clampf(-ang * 1.5, -1.0, 1.0)
	m.throttle = 1.0 if dist > 12.0 else (0.35 if absf(ang) > 0.6 else 0.0)
	m.aim_point = best.com_global()
	m.firing = dist < 60.0
