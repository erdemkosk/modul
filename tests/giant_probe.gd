extends SceneTree
## Probe: a valley giant near you: how it drives (godot --headless --path . -s res://tests/giant_probe.gd)

var _g: Node
var _frame := 0
var _gd: Dictionary


func _initialize() -> void:
	Builder.save_path = "user://test_valley_design.json"
	Inventory.path = "user://test_valley_inventory.cfg"
	for pair: Array in [[Workshop, "user://test_workshop.cfg"], [Expeditions, "user://test_jobs.cfg"], [ValleyLife, "user://test_life.cfg"],
			[Colossus, "user://test_giants.cfg"]]:
		(pair[0] as GDScript).set("path", pair[1])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(pair[1])))
	Mode.current = "valley"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame == 360:
		_g.set("player_input", false)
		_gd = (_g.get("giants") as Colossus).giants[int(OS.get_environment("GIANT")) if OS.get_environment("GIANT") != "" else 0]
		var m: Machine = _g.get("machine")
		var p: Vector3 = Vector3(_gd.at) + Vector3(70, 0, 0)
		p.y = float(_g.terrain.height_at(p.x, p.z)) + 1.6
		m.global_position = p
		m.invulnerable = true
		m.brake = 1.0
	if _frame > 360 and _frame % 120 == 0:
		var gm: Machine = _gd.m if is_instance_valid(_gd.m) else null
		var me: Machine = _g.get("machine")
		if gm:
			var fwd := -gm.global_basis.z
			var want := (me.global_position - gm.global_position) * Vector3(1, 0, 1)
			print("t %d: d %.0f speed %.2f thr %.2f steer %.2f back %.1f up %.2f fwd·want %.2f firing %s ground %s wheels on %d/%d" % [_frame / 120, gm.global_position.distance_to(me.global_position),
				gm.speed, gm.throttle, gm.steer, float(_gd.back), gm.global_basis.y.y, fwd.dot(want.normalized()), gm.firing, gm.ground_label,
				gm.wheels.filter(func(w: MachineWheel) -> bool: return w.load > 0.0).size(), gm.wheels.size()])
	if _frame > 360 + 120 * 25:
		quit()
		return true
	return false
