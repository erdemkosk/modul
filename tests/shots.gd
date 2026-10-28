extends SceneTree
## Pictures of the game (needs a window):
##   godot --path . --resolution 1600x900 -s res://tests/shots.gd -- --out=<folder> [--valley]
## The proving ground: your machine (the starter with a minigun and a cannon) in a fight with a raider
## and a tank, close and from further off; the build screen; the machine in the mud pit, spinning.
## With --valley: the machine out on the valley's road and in its mud. With --tracks: the tracked
## rocket carrier standing, close on its track and its engine, a salvo in the air, the build screen,
## churning through the mud. Writes shot_<name>.png and
## shots_sheet.png; the first fight picture also goes to assets/ui/menu_bg.png (the menu's).

var _g: Node
var _out := "user://shots"
var _valley := false
var _tracks := false
var _arena := false
var _polish := false
var _cage := false
var _t := 0.0
var _step := 0
var _mark := 0.0
var _shots: Array[Image] = []
var _pending := ""
var _wait := 0
var _m: Machine


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a == "--valley":
			_valley = true
		if a == "--tracks":
			_tracks = true
		if a == "--arena":
			_arena = true
		if a == "--polish":
			_polish = true
		if a == "--cage":
			_cage = true
	DirAccess.make_dir_recursive_absolute(_out)
	Builder.save_path = "user://shots_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	Mode.current = "valley" if _valley else ("cage" if _cage else "arena")
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _shoot(name: String) -> void:
	_pending = name
	_wait = 4


func _cam(yaw: float, pitch: float, dist: float) -> void:
	var c: OrbitCamera = _g.get("cam")
	c.yaw = yaw
	c.pitch = pitch
	c.dist = dist


func _process(dt: float) -> bool:
	_t += dt
	if _pending != "":
		_wait -= 1
		if _wait <= 0:
			var img := root.get_texture().get_image()
			img.save_png(_out.path_join("shot_%s.png" % _pending))
			if _pending == "menu_bg":
				img.save_png(ProjectSettings.globalize_path("res://assets/ui/menu_bg.png"))
				for n in _g.find_children("*", "CanvasLayer", true, false):
					(n as CanvasLayer).visible = n != (_g.get("builder") as CanvasLayer) or (_g.get("builder") as Builder).active
					n.process_mode = Node.PROCESS_MODE_INHERIT
				(_g.get("cam") as OrbitCamera).shift = 0.0
			img.resize(533, 300)
			_shots.append(img)
			print("shot ", _pending, " fps ", Engine.get_frames_per_second())
			_pending = ""
		return false
	var since := _t - _mark
	var steps := _valley_steps() if _valley else (_tracks_steps() if _tracks else (_arena2_steps() if _arena else (_polish_steps() if _polish else (_cage_steps() if _cage else _arena_steps()))))
	if _step >= steps.size():
		_sheet()
		return true
	var s: Array = steps[_step]
	if since < float(s[0]):
		(s[1] as Callable).call(since)
		return false
	(s[2] as Callable).call()
	_step += 1
	_mark = _t
	return false


func _noop(_s: float) -> void:
	pass


func _arena_steps() -> Array:
	return [
		[3.0, _noop, func() -> void:
			_g.set("player_input", false)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui"))
			_m = _g.get("machine")
			var data := Designs.starter()
			data.append(["minigun", 0, 3, 0, 0])
			data.append(["cannon", 0, 1, -2, 0])
			_m.from_data(data)
			_m.invulnerable = true
			_g.spawn_enemy("raider")
			_g.spawn_enemy("tank")],
		[9.0, func(_s: float) -> void:
			_m.throttle = 0.5
			_m.steer = 0.3
			var e := _enemy()
			if e:
				_m.aim_point = e.com_global()
				_m.firing = true
			_cam(PI * 0.8, -0.22, 11.0), func() -> void: _shoot("fight")],
		[1.5, func(_s: float) -> void:
			for n in _g.find_children("*", "CanvasLayer", true, false):
				(n as CanvasLayer).visible = false
				n.process_mode = Node.PROCESS_MODE_DISABLED # (the drive HUD shows itself each frame)
			(_g.get("cam") as OrbitCamera).shift = 4.5
			_cam(PI * 0.72, -0.16, 10.0), func() -> void: _shoot("menu_bg")],
		[3.0, func(_s: float) -> void:
			var e := _enemy()
			if e:
				_m.aim_point = e.com_global()
			_cam(PI * 1.3, -0.45, 26.0), func() -> void: _shoot("fight_wide")],
		[1.0, _noop, func() -> void:
			_m.firing = false
			_m.throttle = 0.0
			for n in root.get_tree().get_nodes_in_group("machines"):
				if n != _m:
					n.queue_free()
			(_g.get("builder") as Builder).set_active(true)
			(_g.get("builder") as Builder).select("cannon")
			_cam(PI * 0.75, -0.5, 9.0)],
		[2.0, func(_s: float) -> void:
			var b: Builder = _g.get("builder")
			var c: Camera3D = _g.get("cam")
			b._aim(c.unproject_position(_m.global_transform * Vector3(-0.5, 0.6, 0.0)))
			, func() -> void: _shoot("build")],
		[1.0, _noop, func() -> void:
			(_g.get("builder") as Builder).set_active(false)
			# into the mud pit
			_m.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-10, float(_g.terrain.call("height_at", -10.0, 11.0)) + 1.5, 11))],
		[5.0, func(_s: float) -> void:
			_m.throttle = 1.0
			_m.steer = 0.4
			_cam(PI * 1.6, -0.25, 9.0), func() -> void: _shoot("mud")],
		[3.0, func(_s: float) -> void:
			_m.throttle = 1.0
			_cam(PI * 0.2, -0.35, 7.0), func() -> void: _shoot("mud_close")],
	]


## The arena: from above, a fight that breaks the fort's blocks, the drive HUD, building (grid, iso,
## mirror), the floodlights at night.
func _arena2_steps() -> Array:
	return [
		[3.0, _noop, func() -> void:
			_g.set("player_input", false)
			_m = _g.get("machine")
			var data := Designs.starter()
			data.append(["minigun", 0, 3, 0, 0])
			data.append(["cannon", 0, 1, -2, 0])
			_m.from_data(data)
			_m.invulnerable = true
			_m.set_lights(true)
			_m.global_transform = Transform3D(Basis.IDENTITY, Vector3(-5, float(_g.terrain.call("height_at", -5.0, 82.0)) + 1.2, 82))
			_m.global_transform = Transform3D(Basis(Vector3.UP, PI), _m.global_position) # (facing south: the fort)
			],
		[2.0, func(_s: float) -> void: _cam(PI * 0.2, -0.75, 40.0), func() -> void:
			var c: OrbitCamera = _g.get("cam")
			c.target = _m
			_shoot("arena_high")],
		[1.0, func(_s: float) -> void:
			_m.global_transform = Transform3D(Basis.IDENTITY, Vector3(-5, float(_g.terrain.call("height_at", -5.0, 35.0)) + 1.2, 35))
			_cam(PI * 0.1, -0.35, 16.0), func() -> void: pass],
		[5.5, func(_s: float) -> void:
			_m.aim_point = Vector3(-8.0, 1.0, 60.0) if _s < 2.5 else Vector3(-12.0, 0.8, 60.0)
			_m.global_transform = Transform3D(Basis(Vector3.UP, PI), _m.global_position)
			_m.firing = _s > 0.5
			_cam(PI * 0.9, -0.12, 9.0), func() -> void: _shoot("destruction")],
		[1.2, func(_s: float) -> void:
			_m.firing = true
			_cam(PI * 0.75, -0.2, 22.0), func() -> void: _shoot("destruction_wide")],
		[1.0, func(_s: float) -> void:
			_m.firing = false
			_cam(PI * 1.1, -0.3, 10.0), func() -> void: _shoot("hud")],
		[2.5, func(_s: float) -> void:
			# the chase camera looking where it shoots: at the fort, the minigun alone (1)
			if _once("chase"):
				_g.toggle_gun(1) # (the cannon off: the minigun alone)
			_m.aim_point = _g.aim_point()
			_m.firing = _s > 1.0
			_cam(PI, -0.12, 11.0), func() -> void: _shoot("chase_fire")],
		[2.0, func(_s: float) -> void:
			if _once("high"):
				(_g.get("cam") as OrbitCamera).mode = OrbitCamera.HIGH
				_g.toggle_gun(-1)
			_m.aim_point = _g.aim_point()
			_m.firing = _s > 0.6
			_cam(PI, -0.25, 11.0), func() -> void: _shoot("high_fire")],
		[1.5, func(_s: float) -> void:
			if _once("turret"):
				(_g.get("cam") as OrbitCamera).mode = OrbitCamera.TURRET
			_m.aim_point = _g.aim_point()
			_m.firing = false
			_cam(PI, -0.05, 11.0), func() -> void:
				_shoot("turret")
				(_g.get("cam") as OrbitCamera).mode = OrbitCamera.CHASE],
		[1.0, _noop, func() -> void:
			var b: Builder = _g.get("builder")
			b.set_active(true)
			b.select("armor", false)
			b.set_mirror(true)
			_cam(PI * 0.78, -0.45, 9.0)],
		[2.0, func(_s: float) -> void:
			var b: Builder = _g.get("builder")
			var c: Camera3D = _g.get("cam")
			b._aim(c.unproject_position(_m.global_transform * Vector3(0.25, 1.8, 1.25))), func() -> void: _shoot("build_grid")],
		[1.5, func(_s: float) -> void:
			var b: Builder = _g.get("builder")
			if not (_g.get("cam") as OrbitCamera).iso:
				b.set_iso(true)
			var c: Camera3D = _g.get("cam")
			b._aim(c.unproject_position(_m.global_transform * Vector3(0.25, 1.8, 1.25))), func() -> void: _shoot("build_iso")],
		[1.0, _noop, func() -> void:
			(_g.get("builder") as Builder).set_active(false)
			(_g.get("weather") as Weather).hour = 22.5
			(_g.get("arena_node") as Arena).set_night(true)],
		[4.0, func(_s: float) -> void: _cam(PI * 0.15, -0.4, 34.0), func() -> void: _shoot("arena_night")],
	]


## The polish: a hurt machine smoking and sooted, enemies marked, a hit from the side, the pause
## menu, the death card.
## KAFES: the start panel, the cage from above with its crowd, the countdown, the fight, the crowd up
## close on its feet, the workshop.
func _cage_steps() -> Array:
	return [
		[3.0, _noop, func() -> void:
			_m = _g.get("machine")
			var data := Designs.starter()
			data.append(["minigun", 0, 3, 0, 0])
			data.append(["cannon", 0, 1, -2, 0])
			_m.from_data(data)
			_cam(PI * 1.25, -0.3, 12.0)
			_shoot("cage_prep")],
		[1.0, _noop, func() -> void:
			(_g.get("cage") as Cage).start_run()],
		[1.6, func(_s: float) -> void: _cam(PI * 1.25, -0.25, 12.0), func() -> void: _shoot("cage_countdown")],
		[6.0, func(_s: float) -> void:
			_g.set("player_input", false)
			var c: Cage = _g.get("cage")
			if not c.rivals.is_empty() and is_instance_valid(c.rivals[0]):
				_m.aim_point = c.rivals[0].com_global()
				_m.firing = _s > 2.0
			(_g.get("cam") as OrbitCamera).mode = OrbitCamera.HIGH
			_cam(PI * 1.25, -0.35, 14.0), func() -> void: _shoot("cage_fight")],
		[2.0, func(_s: float) -> void:
			(_g.get("cage") as Cage).excite = 1.0
			(_g.get("cam") as OrbitCamera).mode = OrbitCamera.CHASE
			_cam(PI * 0.25, 0.25, 6.0), func() -> void: _shoot("cage_crowd")],
		[0.5, _noop, func() -> void:
			_m.firing = false
			var c: Cage = _g.get("cage")
			for e in c.rivals:
				if is_instance_valid(e):
					e.damage_part(e.cab_index(), 99999.0)],
		[5.0, func(_s: float) -> void: _cam(PI * 1.25, -0.3, 12.0), func() -> void: _shoot("cage_workshop")],
		[0.5, _noop, func() -> void:
			var c: Cage = _g.get("cage")
			(c.get("_ui") as CageUi).close()
			c.call("_begin_round", 5)],
		[5.5, func(_s: float) -> void:
			var c: Cage = _g.get("cage")
			_g.set("player_input", false)
			for e in c.rivals:
				if is_instance_valid(e):
					_m.aim_point = e.com_global()
					break
			_m.firing = _s > 4.0
			(_g.get("cam") as OrbitCamera).mode = OrbitCamera.CHASE
			_cam(PI * 1.25, -0.2, 11.0), func() -> void: _shoot("final_hits")],
		[0.5, _noop, func() -> void:
			_m.firing = false
			(_g.get("cage") as Cage).arena.open_pit()],
		[4.0, func(_s: float) -> void:
			(_g.get("cam") as OrbitCamera).mode = OrbitCamera.HIGH
			_cam(PI * 1.25, -0.6, 22.0), func() -> void: _shoot("final_overview")],
	]


func _polish_steps() -> Array:
	return [
		[3.0, _noop, func() -> void:
			_g.set("player_input", false)
			_m = _g.get("machine")
			var data := Designs.starter()
			data.append(["minigun", 0, 3, 0, 0])
			_m.from_data(data)
			var e1: Machine = _g.spawn_enemy("tank")
			var e2: Machine = _g.spawn_enemy("raider")
			for e: Machine in [e1, e2]:
				e.set_physics_process(false)
				for c in e.get_children():
					if c is AiDriver:
						c.queue_free()
			e1.global_position = _m.global_position + Vector3(-12, 1, -34)
			e2.global_position = _m.global_position + Vector3(40, 1, -10)
			e1.damage_part(e1.cab_index(), 300.0)
			# hurt: the engine burning, the bed and a wheel shot about
			for i in _m.design.size():
				var id: String = _m.design[i].id
				var frac := {"engine": 0.15, "light": 0.5, "frame": 0.45, "wheel_s": 0.6}.get(id, 1.0) as float
				if id == "frame" and i % 3 != 0:
					frac = 1.0
				_m.design[i].hp = Parts.hp_of(id) * frac
			_m.damage_part(_m.cab_index(), 420.0)],
		[2.5, func(_s: float) -> void:
			_cam(PI * 1.15, -0.25, 9.0)
			if _s > 2.3 and _once("hit"):
				_m.damaged.emit(60.0, _m.global_position + Vector3(30, 0, 0), "top")
			, func() -> void: _shoot("hurt")],
		[1.0, func(_s: float) -> void:
			_cam(PI, -0.05, 11.0)
			if _s > 0.8 and _once("hit2"):
				_m.damaged.emit(80.0, _m.global_position + Vector3(-20, 0, 25), "roket")
			, func() -> void: _shoot("markers")],
		[0.5, _noop, func() -> void: (_g.get("pause") as PauseMenu).open()],
		[0.6, _noop, func() -> void: _shoot("pause")],
		[0.5, _noop, func() -> void:
			(_g.get("pause") as PauseMenu)._show_settings(true)],
		[0.6, _noop, func() -> void: _shoot("settings")],
		[0.5, _noop, func() -> void:
			(_g.get("pause") as PauseMenu).close()
			(_g.get("_death") as DeathCard).show_card("TANK", "top", 154.0, 2)],
		[1.6, _noop, func() -> void: _shoot("death")],
	]


func _tracks_steps() -> Array:
	return [
		[3.0, _noop, func() -> void:
			_g.set("player_input", false)
			_m = _g.get("machine")
			_m.from_data(Designs.tracked())
			_m.invulnerable = true
			_m.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-20, float(_g.terrain.call("height_at", -20.0, -40.0)) + 1.2, -40))],
		[3.0, func(_s: float) -> void: _cam(-PI * 0.25, -0.22, 8.5), func() -> void: _shoot("tracked")],
		[1.5, func(_s: float) -> void: _cam(-PI * 0.42, -0.12, 3.6), func() -> void: _shoot("track_close")],
		[1.5, func(_s: float) -> void:
			var c: OrbitCamera = _g.get("cam")
			c.target = _m
			_cam(PI * 0.62, -0.5, 3.4), func() -> void: _shoot("engine_close")],
		[1.0, _noop, func() -> void:
			var p := _m.global_position - _m.global_basis.z * 60.0
			p.y = float(_g.terrain.call("height_at", p.x, p.z)) + 2.0
			_g._spawn(Designs.dummy(), Transform3D(Basis.IDENTITY, p), 1, false)],
		[3.0, func(_s: float) -> void:
			var e := _enemy()
			if e:
				_m.aim_point = e.com_global() + Vector3.UP * 0.8
			_m.firing = _s > 2.4
			_cam(-PI * 0.12, -0.12, 9.0), func() -> void: _shoot("salvo")],
		[0.6, _noop, func() -> void: _shoot("salvo_late")],
		[2.0, func(_s: float) -> void:
			_m.firing = false
			_cam(PI * 0.15, -0.2, 26.0), func() -> void: _shoot("salvo_hit")],
		[1.0, _noop, func() -> void:
			for n in root.get_tree().get_nodes_in_group("machines"):
				if n != _m:
					n.queue_free()
			(_g.get("builder") as Builder).set_active(true)
			(_g.get("builder") as Builder).select("track")
			_cam(PI * 0.7, -0.45, 11.0)],
		[2.0, func(_s: float) -> void:
			var b: Builder = _g.get("builder")
			var c: Camera3D = _g.get("cam")
			b._aim(c.unproject_position(_m.global_transform * Vector3(0.5, 0.6, -1.0)))
			, func() -> void: _shoot("build")],
		[1.0, _noop, func() -> void:
			(_g.get("builder") as Builder).set_active(false)
			_m.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-8, float(_g.terrain.call("height_at", -8.0, 11.0)) + 1.5, 11))],
		[4.0, func(_s: float) -> void:
			_m.throttle = 0.8
			_m.steer = 0.3
			_cam(PI * 1.7, -0.22, 8.0), func() -> void: _shoot("tracks_mud")],
	]


func _valley_steps() -> Array:
	return [
		[8.0, func(_s: float) -> void: _g.set("player_input", false), func() -> void:
			_m = _g.get("machine")],
		[8.0, func(_s: float) -> void:
			_m.throttle = 0.7
			_cam(PI * 0.85, -0.2, 10.0), func() -> void: _shoot("valley_road")],
	]


var _onces := {}


## True the first time it's asked with `key` (a step's per-frame call doing something once).
func _once(key: String) -> bool:
	if _onces.has(key):
		return false
	_onces[key] = true
	return true


func _enemy() -> Machine:
	for n in root.get_tree().get_nodes_in_group("machines"):
		if n != _m and is_instance_valid(n) and (n as Machine).alive:
			return n
	return null


func _sheet() -> void:
	var cols := 2
	var rows := int(ceil(_shots.size() / float(cols)))
	var sheet := Image.create(533 * cols, 300 * rows, false, Image.FORMAT_RGBA8)
	for k in _shots.size():
		var s := _shots[k]
		s.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(s, Rect2i(0, 0, 533, 300), Vector2i((k % cols) * 533, (k / cols) * 300))
	sheet.save_png(_out.path_join("shots_sheet.png"))
	print("sheet written")
