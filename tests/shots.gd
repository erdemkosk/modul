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
var _forge := false
var _flip := false
var _sites := false
var _mission := ""
var _spin := false
var _robots := false
var _worksite := false
var _st := {}
var _cage := false
var _t := 0.0
var _step := 0
var _mark := 0.0
var _shots: Array[Image] = []
var _expedition := false
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
		if a == "--forge":
			_forge = true
		if a == "--flip":
			_flip = true
		if a == "--sites":
			_sites = true
		if a == "--spin":
			_spin = true
		if a == "--robots":
			_robots = true
		if a == "--worksite":
			_worksite = true
			_valley = true
			(load("res://scripts/works_sites.gd") as GDScript).set("path", "user://shots_sites.cfg")
			Inventory.path = "user://shots_inventory.cfg"
		if a.begins_with("--mission="):
			_mission = a.substr(10)
		if a == "--expedition":
			_expedition = true
			_valley = true
			Inventory.path = "user://shots_inventory.cfg"
			Inventory.reset()
			for pair: Array in [[Workshop, "user://shots_workshop.cfg"], [Expeditions, "user://shots_jobs.cfg"],
					[ValleyLife, "user://shots_life.cfg"], [Colossus, "user://shots_giants.cfg"]]:
				(pair[0] as GDScript).set("path", pair[1])
				DirAccess.remove_absolute(ProjectSettings.globalize_path(str(pair[1])))
	DirAccess.make_dir_recursive_absolute(_out)
	Builder.save_path = "user://shots_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	CageRecord.save_path = "user://shots_cage_record.cfg"
	Mode.current = "valley" if _valley else ("cage" if _cage else "arena")
	if _mission != "":
		Mode.current = "mission"
		Mode.mission = _mission
		Missions.save_path = "user://shots_missions.cfg"
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
	var steps := _robot_steps() if _robots else (_worksite_steps() if _worksite else (_expedition_steps() if _expedition else _all_steps()))
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


func _all_steps() -> Array:
	return _valley_steps() if _valley else (_tracks_steps() if _tracks else (_arena2_steps() if _arena else (_polish_steps() if _polish else (_cage_steps() if _cage else (_forge_steps() if _forge else (_flip_steps() if _flip else (_sites_steps() if _sites else (_mission_steps() if _mission != "" else (_spin_steps() if _spin else _arena_steps())))))))))


## Forge's rivals, one of each style, side by side; the builder's ready designs; the flamethrower.
func _forge_steps() -> Array:
	return [
		[3.0, _noop, func() -> void:
			_g.set("player_input", false)
			_m = _g.get("machine")
			_m.invulnerable = true
			var k := 0
			for st: String in Forge.STYLES:
				var made := Forge.make(31 + k * 5, 3, st)
				var at := _m.global_transform * Vector3(-12.5 + k * 5.0, 1.5, -12.0)
				var e: Machine = _g.call("_spawn", made.data, Transform3D(_m.global_basis.rotated(Vector3.UP, PI * 0.85), at), 1, false)
				e.label = made.name
				k += 1],
		[4.0, func(_s: float) -> void:
			_cam(PI * 0.0, -0.3, 22.0), func() -> void: _shoot("forge_lineup")],
		[2.0, func(_s: float) -> void:
			_cam(PI * 0.12, -0.18, 15.0), func() -> void: _shoot("forge_lineup_low")],
		[1.0, _noop, func() -> void:
			for n in root.get_tree().get_nodes_in_group("machines"):
				if n != _m:
					n.queue_free()
			var b: Builder = _g.get("builder")
			b.set_active(true)
			b.load_preset(5)],
		[3.0, func(_s: float) -> void:
			_cam(PI * 0.75, -0.5, 9.0), func() -> void: _shoot("forge_presets")],
		[1.0, _noop, func() -> void:
			(_g.get("builder") as Builder).set_active(false)
			_g.call("_spawn", Designs.dummy(), Transform3D(_m.global_basis, _m.global_transform * Vector3(0.0, 1.5, -18.0)), 1, false)],
		[3.0, func(_s: float) -> void:
			var e := _enemy()
			if e:
				_m.aim_point = e.com_global()
				_m.throttle = 0.6 if _m.global_position.distance_to(e.global_position) > 9.0 else 0.0
				_m.firing = _m.global_position.distance_to(e.global_position) < 13.0
			_cam(PI * 0.8, -0.2, 9.0), func() -> void: _shoot("forge_flame")],
	]


## The flipper: a rival across the flap, thrown (in the air, then on its back).
func _flip_steps() -> Array:
	return [
		[3.0, _noop, func() -> void:
			_g.set("player_input", false)
			_m = _g.get("machine")
			var data := Designs.starter()
			data.append(["flipper", 0, 0, -5, 0])
			data.append(["minigun", 0, 3, 0, 0])
			_m.from_data(data)
			_m.invulnerable = true
			var bt := _m.global_transform * Vector3(0.3, 1.2, -3.2)
			var e: Machine = _g.call("_spawn", Designs.raider(), Transform3D(_m.global_basis.rotated(Vector3.UP, PI * 0.5), bt), 1, false)
			e.label = "PASLI"],
		[3.0, func(_s: float) -> void:
			_cam(PI * 0.62, -0.16, 9.5), func() -> void: _shoot("flip_before")],
		[0.3, _noop, func() -> void:
			_m.flip()],
		[0.28, func(_s: float) -> void:
			_cam(PI * 0.62, -0.16, 9.5), func() -> void: _shoot("flip_air")],
		[3.0, func(_s: float) -> void:
			_cam(PI * 0.7, -0.22, 11.0), func() -> void: _shoot("flip_after")],
	]


## The sites' structures: standing in a row, then brought down (legs, the chimney's foot, fire).
func _sites_steps() -> Array:
	return [
		[3.0, _noop, func() -> void:
			_g.set("player_input", false)
			_m = _g.get("machine")
			_m.invulnerable = true
			var t: Node = _g.get("terrain")
			var k := 0
			for kind: String in ["water_tower", "chimney", "fuel_tank", "warehouse", "scaffold", "transformer", "crane", "silo"]:
				var p := _m.global_transform * Vector3(-42.0 + k * 12.0, 0.0, -34.0 - (k % 2) * 6.0)
				p.y = float(t.call("height_at", p.x, p.z))
				var s := Structures.make(kind, Transform3D(Basis.IDENTITY, p), t)
				_g.add_child(s)
				_st[kind] = s
				k += 1],
		[2.0, func(_s: float) -> void:
			_cam(PI * 0.0, -0.12, 30.0), func() -> void: _shoot("sites_standing")],
		[1.0, func(_s: float) -> void:
			_cam(PI * 0.1, -0.2, 16.0), func() -> void: _shoot("sites_close")],
		[0.2, _noop, func() -> void:
			var wt := _st.water_tower as Structure
			# (picked out first: a piece that breaks leaves its structure's list)
			for p in wt.pieces.filter(func(p: StructurePiece) -> bool: return p.grounded and p.size.y > 8.0 and p.global_position.x < wt.global_position.x):
				p.hit(99999.0, p.global_position, Vector3.RIGHT, true)
			var ch := _st.chimney as Structure
			for p in ch.pieces.filter(func(p: StructurePiece) -> bool: return p.stuff == "brick" and p.global_position.y - ch.global_position.y < 2.0):
				p.hit(99999.0, p.global_position, Vector3.RIGHT, true)
			for kind: String in ["scaffold", "warehouse"]:
				for p in (_st[kind] as Structure).pieces:
					if p.stuff == "wood":
						p.ignite()
						break
			for p in (_st.fuel_tank as Structure).pieces:
				if p.stuff == "fuel":
					p.ignite()],
		[1.2, func(_s: float) -> void:
			_cam(PI * 0.0, -0.12, 30.0), func() -> void: _shoot("sites_falling")],
		[6.0, func(_s: float) -> void:
			_cam(PI * 0.0, -0.12, 30.0), func() -> void: _shoot("sites_after")],
	]


## A mission: its brief, under way (the targets marked), coming down, done.
func _mission_steps() -> Array:
	return [
		[3.0, func(_s: float) -> void:
			_cam(PI, -0.28, 12.0), func() -> void: _shoot("mission_brief")],
		[0.5, _noop, func() -> void:
			var ms: Missions = _g.get("missions")
			_g.set("player_input", false)
			_m = _g.get("machine")
			_m.invulnerable = true
			ms.start()],
		[2.5, func(_s: float) -> void:
			_m.throttle = 0.4
			_cam(PI, -0.18, 12.0), func() -> void: _shoot("mission_run")],
		[0.2, _noop, func() -> void:
			var ms: Missions = _g.get("missions")
			_m.throttle = 0.0
			for k in ms.targets.size() - 1:
				var st := ms.targets[k]
				for p in st.pieces.filter(func(p: StructurePiece) -> bool: return p.grounded and p.global_position.x < st.global_position.x + 0.5):
					p.hit(99999.0, p.global_position, Vector3.RIGHT, true)],
		[2.0, func(_s: float) -> void:
			_cam(PI, -0.18, 14.0), func() -> void: _shoot("mission_falling")],
		[0.2, _noop, func() -> void:
			var ms: Missions = _g.get("missions")
			var st := ms.targets[ms.targets.size() - 1]
			for p in st.pieces.filter(func(p: StructurePiece) -> bool: return p.grounded):
				p.hit(99999.0, p.global_position, Vector3.RIGHT, true)],
		[3.0, func(_s: float) -> void:
			_cam(PI, -0.18, 14.0), func() -> void: _shoot("mission_done")],
	]


## The joints: a spinner's bar turning, a hinge up; the builder's HAREKET tab.
func _spin_steps() -> Array:
	return [
		[3.0, _noop, func() -> void:
			_g.set("player_input", false)
			_m = _g.get("machine")
			_m.invulnerable = true
			var d := Designs.starter().filter(func(e: Array) -> bool: return e[0] != "light")
			d.append_array([["rotor", -1, 1, -2, 0], ["spike", -3, 2, -2, 0], ["plate", -2, 2, -2, 0], ["plate", -1, 2, -2, 0],
				["plate", 0, 2, -2, 0], ["plate", 1, 2, -2, 0], ["spike", 2, 2, -2, 0], ["hinge", 2, 1, 1, 0], ["plate", 2, 2, 1, 0],
				["minigun", 0, 3, 0, 0]])
			_m.from_data(d)
			_m.joint_key(KEY_E)],
		[2.5, func(_s: float) -> void:
			_m.brake = 1.0
			_cam(PI * 0.8, -0.25, 8.0), func() -> void: _shoot("spin_running")],
		[0.5, _noop, func() -> void:
			var b: Builder = _g.get("builder")
			b.set_active(true)
			b._show_group(4, false)
			b.select("rotor", false)],
		[2.0, func(_s: float) -> void:
			_cam(PI * 0.75, -0.5, 9.0), func() -> void: _shoot("spin_builder")],
	]


var _rb := {}


## The new blocks (a minigun on a turret turned aside; one fed and long-barrelled) and the works
## robots: a sentry and a warden by day, fighting, the warden a wreck, the sentry's lamp at night.
func _robot_steps() -> Array:
	return [
		[3.0, _noop, func() -> void:
			_g.set("player_input", false)
			_m = _g.get("machine")
			_m.invulnerable = true
			var d := Designs.starter()
			d.append_array([["turret", 0, 3, 0, 0], ["minigun", 0, 4, 0, 0], ["ammo", 0, 3, 2, 0], ["barrel", 1, 3, 2, 0]])
			_m.from_data(d)],
		[2.0, func(_s: float) -> void:
			_m.brake = 1.0
			_m.aim_point = _m.global_transform * Vector3(-20.0, 2.0, -8.0)
			_cam(PI * 0.78, -0.35, 7.0), func() -> void: _shoot("blocks_turret")],
		[0.3, _noop, func() -> void:
			var d := Designs.starter()
			d.append_array([["minigun", 0, 3, 0, 0], ["ammo", 0, 3, 2, 0], ["barrel", 1, 3, 2, 0]])
			_m.from_data(d)],
		[1.5, func(_s: float) -> void:
			_m.aim_point = _m.global_transform * Vector3(0.0, 1.5, -30.0)
			_cam(PI * 0.6, -0.4, 6.0), func() -> void: _shoot("blocks_kit")],
		[0.3, _noop, func() -> void:
			var t: Node = _g.get("terrain")
			for e: Array in [["sentry", Vector3(-4.0, 0.0, -11.0)], ["warden", Vector3(3.5, 0.0, -9.0)]]:
				var at: Vector3 = _m.global_transform * (e[1] as Vector3)
				at.y = float(t.call("height_at", at.x, at.z))
				var r: CharacterBody3D = (load("res://scripts/robot.gd") as GDScript).call("make", e[0], Transform3D(Basis.IDENTITY, at), _g, t)
				_g.add_child(r)
				r.set_physics_process(false)
				_rb[e[0]] = r],
		[1.5, func(_s: float) -> void:
			_cam(0.25, -0.22, 9.0), func() -> void: _shoot("robots_day")],
		[0.2, _noop, func() -> void:
			for r: Node in _rb.values():
				r.set_physics_process(true)],
		[2.6, func(_s: float) -> void:
			_cam(0.5, -0.25, 10.0), func() -> void: _shoot("robots_fight")],
		[0.2, _noop, func() -> void:
			var w: Node3D = _rb["warden"]
			w.call("take_hit", 9999.0, w.global_position + Vector3.UP, Vector3.LEFT)],
		[2.0, func(_s: float) -> void:
			_cam(0.5, -0.3, 9.0), func() -> void: _shoot("robots_wreck")],
		[0.2, _noop, func() -> void:
			# close: a fresh pair just behind the machine, between it and the camera
			var t: Node = _g.get("terrain")
			for e: Array in [["sentry", Vector3(-2.5, 0.0, 5.5)], ["warden", Vector3(2.5, 0.0, 6.0)]]:
				var at: Vector3 = _m.global_transform * (e[1] as Vector3)
				at.y = float(t.call("height_at", at.x, at.z))
				var r: CharacterBody3D = (load("res://scripts/robot.gd") as GDScript).call("make", e[0], Transform3D(Basis(Vector3.UP, PI * 0.8), at), _g, t)
				_g.add_child(r)
				r.set_physics_process(false)
				_rb["close_" + str(e[0])] = r],
		[1.5, func(_s: float) -> void:
			_cam(0.0, -0.18, 13.0), func() -> void: _shoot("robots_close")],
		[0.2, _noop, func() -> void:
			(_g.get("weather") as Weather).hour = 22.5
			for k: String in ["close_sentry", "close_warden"]:
				(_rb[k] as Node).set_physics_process(true)],
		[2.5, func(_s: float) -> void:
			_cam(0.1, -0.15, 9.0), func() -> void: _shoot("robots_night")],
	]


## The valley: a works site, its building and its robots, from where you'd come on it.
func _worksite_steps() -> Array:
	return [
		[8.0, func(_s: float) -> void: _g.set("player_input", false), func() -> void:
			_m = _g.get("machine")
			_m.invulnerable = true
			var ws: Node = _g.get("sites")
			var at: Vector3 = ws.get("sites")[2].at
			var t: Node = _g.get("terrain")
			var p := at + Vector3(0.0, 0.0, 30.0)
			p.y = float(t.call("height_at", p.x, p.z)) + 1.5
			_m.linear_velocity = Vector3.ZERO
			_m.global_transform = Transform3D(Basis.IDENTITY, p)],
		[3.0, func(_s: float) -> void:
			_m.brake = 1.0
			_cam(0.0, -0.2, 11.0), func() -> void: _shoot("worksite_near")],
		[4.0, func(_s: float) -> void:
			_cam(0.0, -0.2, 11.0), func() -> void: _shoot("worksite_fight")],
	]


## The valley's work: the workshop truck beside you, a load lashed on, the radio, a giant, a shut
## road, a ford in flood.
func _expedition_steps() -> Array:
	return [
		[8.0, func(_s: float) -> void: _g.set("player_input", false), func() -> void:
			_m = _g.get("machine")
			_m.invulnerable = true
			_m.brake = 1.0],
		[2.0, func(_s: float) -> void: _cam(PI * 0.3, -0.28, 22.0), func() -> void: _shoot("workshop")],
		[0.5, _noop, func() -> void:
			var ex: Expeditions = _g.get("expeditions")
			ex.accept(0)
			ex.job.goods = "generator"
			_put_at(Vector3(ex.job.at) + Vector3(4, 0, 0))],
		[5.0, func(_s: float) -> void: _cam(PI * 0.75, -0.25, 10.0), func() -> void: _shoot("loaded")],
		[1.0, func(_s: float) -> void: pass, func() -> void:
			(_g.get("valley_hud") as ValleyHud).toggle_board()
			_shoot("radio")],
		[1.0, _noop, func() -> void:
			(_g.get("valley_hud") as ValleyHud).toggle_board()
			var gi: Colossus = _g.get("giants")
			var g: Dictionary = gi.giants[0]
			_put_at(Vector3(g.at) + Vector3(45, 0, 0))],
		[3.0, _noop, func() -> void: # (in front of it, on its way)
			var gm: Variant = (_g.get("giants") as Colossus).giants[0].m
			if is_instance_valid(gm):
				var gb := (gm as Machine).global_transform
				_put_at(gb.origin - gb.basis.z * 38.0 + gb.basis.x * 10.0)],
		[5.0, func(_s: float) -> void:
			var gm: Variant = (_g.get("giants") as Colossus).giants[0].m
			if is_instance_valid(gm):
				_look_at((gm as Machine).global_position, -0.1, 12.0), func() -> void: _shoot("giant")],
		[0.5, _noop, func() -> void:
			var life: ValleyLife = _g.get("life")
			var bl: Dictionary = life.blocks[0]
			_put_at(Vector3(bl.at.x, 0, bl.at.y) + Vector3(bl.across.y, 0, -bl.across.x) * 14.0)],
		[4.0, func(_s: float) -> void:
			var life: ValleyLife = _g.get("life")
			var bl: Dictionary = life.blocks[0]
			_look_at(Vector3(bl.at.x, 0, bl.at.y), -0.25, 12.0), func() -> void: _shoot("shut_road")],
		[0.5, _noop, func() -> void:
			(_g.get("weather") as Weather).wetness = 1.0
			var life: ValleyLife = _g.get("life")
			var f: Dictionary = life.floods[0]
			_put_at(Vector3(f.at.x, 0, f.at.y) + Vector3(f.down.y, 0, -f.down.x) * 26.0)],
		[4.0, func(_s: float) -> void:
			var f: Dictionary = (_g.get("life") as ValleyLife).floods[0]
			_look_at(Vector3(f.at.x, 0, f.at.y), -0.3, 14.0), func() -> void: _shoot("flood")],
	]


## The camera behind you, looking toward `at`.
func _look_at(at: Vector3, pitch: float, dist: float) -> void:
	var to := at - _m.global_position
	_cam(atan2(-to.x, -to.z), pitch, dist)


func _put_at(at: Vector3) -> void:
	var t: Node = _g.get("terrain")
	at.y = float(t.call("height_at", at.x, at.z)) + 1.6
	_m.global_transform = Transform3D(Basis.IDENTITY, at)
	_m.linear_velocity = Vector3.ZERO
	_m.angular_velocity = Vector3.ZERO
	_m.brake = 1.0
	_m.set_down()


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
## KAFES: the start panel, the round's maze from above and from in it, the cage with its crowd, the countdown, the fight, the crowd up
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
		[1.0, func(_s: float) -> void:
			(_g.get("cam") as OrbitCamera).mode = OrbitCamera.HIGH
			_cam(PI * 1.25, -1.1, 125.0), func() -> void: _shoot("cage_maze")],
		[1.0, func(_s: float) -> void: _cam(PI * 1.1, -0.35, 30.0), func() -> void: _shoot("cage_maze_low")],
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
		[2.0, func(_s: float) -> void:
			(_g.get("cam") as OrbitCamera).mode = OrbitCamera.HIGH
			_cam(PI * 1.25, -0.42, 110.0), func() -> void: _shoot("cage_stadium")],
		[2.0, func(_s: float) -> void:
			if _once("shell"):
				(_g.get("cage") as Cage).camp_t = Cage.CAMP_SHELL
			_cam(PI * 1.1, -0.2, 16.0), func() -> void: _shoot("cage_shelled")],
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
