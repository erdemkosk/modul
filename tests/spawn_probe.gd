extends SceneTree
## Probe: the cage's rivals from their spawn through the countdown and the first seconds: are they
## upright? (godot --headless --path . -s res://tests/spawn_probe.gd)

const HZ := 120
var _g: Node
var _c: Cage
var _frame := 0
var _run := 0
var _t0 := 0


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
	CageRecord.save_path = "user://test_cage_record.cfg"
	Mode.current = "cage"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame == HZ:
		_c = _g.get("cage")
		(_g.get("builder") as Builder).set_active(false)
		_g.set("player_input", false)
		_c.start_run()
		_t0 = _frame
	if _c == null or _frame <= HZ:
		return false
	var t := (_frame - _t0) / float(HZ)
	if (_frame - _t0) % 30 == 0:
		var line := "t %.2f %s:" % [t, _c.state]
		for e in _c.rivals:
			if is_instance_valid(e):
				var d: AiDriver = e.find_children("*", "AiDriver", false, false)[0]
				line += "  [%s up %.2f y %.2f v %.1f av %.1f thr %.1f rev %s back %.1f]" % [e.label, e.global_basis.y.y, e.global_position.y,
					e.linear_velocity.length(), e.angular_velocity.length(), e.throttle, d._reversing, d._back_t]
		print(line)
	if t > 9.0:
		_run += 1
		if _run >= 4:
			quit()
			return true
		# another round (another rival, another maze)
		_c.state = "won"
		_c.next_round()
		_t0 = _frame
	return false
