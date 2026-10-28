extends SceneTree
## Headless check of tracks, rockets and the battery on the proving ground (Mode "arena"):
##   godot --headless --path . -s res://tests/tracks_test.gd
## 1. A tracked machine (Designs.tracked) drives off on grass, steers both ways, turns on the spot
##    with no throttle (one track forward, the other back), and its belt runs.
## 2. In the mud pit a track sinks less than a road wheel carrying the same.
## 3. The rocket pod: a salvo of six goes off, the tubes empty, the rockets burst on a target and
##    hurt it, and the tubes fill again.
## 4. The battery: guns draw on it, a machine with no engine runs it flat and its turret stops; an
##    engine's alternator brings it back. The builder hangs a track off a side, never across.

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


func _place(m: Machine, at: Vector2, yaw := 0.0) -> void:
	var y := float(_g.terrain.call("height_at", at.x, at.y)) + 1.2
	m.linear_velocity = Vector3.ZERO
	m.angular_velocity = Vector3.ZERO
	m.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.y))


func _yaw() -> float:
	return _m.global_basis.get_euler().y


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame > 120 * HZ:
		_expect(false, "timed out at " + _step)
		return _done()
	var since := (_frame - _mark) / float(HZ)
	match _step:
		"start":
			if _frame < HZ:
				return false
			_g.set("player_input", false)
			_m = _g.get("machine")
			_m.from_data(Designs.tracked())
			_m.invulnerable = true
			var rep := _m.report()
			print("tracked: %d kg, %d kW, rated %d kg, %d tracks, %.1f kWh, alternator %.1f kW, peak %.1f kW, warn %s" % [
				int(rep.mass), int(rep.power), int(rep.rated), rep.tracks, rep.kwh, rep.alternator, rep.peak, rep.warn])
			_expect(_m.tracks.size() == 2 and _m.wheels.size() == 10, "two tracks of five road wheels")
			_expect(_m.guns.size() == 1 and _m.guns[0].kind == "rockets", "a rocket pod")
			_place(_m, Vector2(-60, -40), -PI * 0.5) # (facing +x along the asphalt, clear of the arena wall)
			_next("settle")
		"settle":
			if since < 2.0:
				return false
			var on := 0
			for w in _m.wheels:
				if w.contact:
					on += 1
			print("settled: %d of 10 road wheels on the ground, roll %.2f" % [on, _m.global_basis.y.y])
			_expect(on >= 8, "it sits on its tracks")
			_r.z0 = _m.global_position
			_m.throttle = 1.0
			_next("drive")
		"drive":
			if since < 6.0:
				return false
			var kmh := absf(_m.speed) * 3.6
			var gone := _m.global_position.distance_to(_r.z0)
			print("6 s full throttle: %.0f km/h, %.1f m, belt %.1f m/s" % [kmh, gone, _m.tracks[0].speed])
			_expect(kmh > 20.0, "it gets going (over 20 km/h)")
			_expect(_m.tracks[0].speed > 3.0, "its belt runs forward")
			_r.yaw = _yaw()
			_m.steer = 1.0
			_next("steer_right")
		"steer_right":
			if _frame % 30 == 0 and OS.get_environment("TRACE") != "":
				print("   t %.2f pos %s yaw %.2f speed %.1f up %.2f" % [since, _m.global_position, _yaw(), _m.speed, _m.global_basis.y.y])
			if since < 2.0:
				return false
			var turned := angle_difference(_r.yaw, _yaw())
			print("2 s steering right at speed: turned %.0f deg" % rad_to_deg(turned))
			_expect(turned < -0.3, "it turns right (more than 17 deg)")
			_m.throttle = 0.0
			_m.steer = 0.0
			_m.brake = 1.0
			_next("stop")
		"stop":
			if since < 3.0:
				return false
			_m.brake = 0.0
			_r.yaw = _yaw()
			_r.p = _m.global_position
			_m.steer = -1.0
			_next("pivot")
		"pivot":
			_r.turn = float(_r.get("turn", 0.0)) + angle_difference(_r.yaw, _yaw())
			_r.yaw = _yaw()
			if since < 3.0:
				return false
			var turned: float = _r.turn
			var moved := _m.global_position.distance_to(_r.p)
			var l := _m.tracks[0].speed
			var r := _m.tracks[1].speed
			print("3 s pivot left, no throttle: turned %.0f deg, moved %.1f m, belts %.1f / %.1f m/s" % [rad_to_deg(turned), moved, l, r])
			_expect(turned > 0.6, "it turns on the spot (more than 35 deg)")
			_expect(moved < 3.0, "staying about where it was")
			_expect(signf(l) != signf(r), "one track forward, the other back")
			_m.steer = 0.0
			_next("mud")
		"mud":
			# the mud pit: Rect2(-30, 0, 24, 22); the tracked machine and a road-wheeled one, each standing
			_place(_m, Vector2(-24, 11))
			_t = _g._spawn(Designs.starter(), Transform3D.IDENTITY, 0)
			_place(_t, Vector2(-12, 11))
			_next("mud_sink")
		"mud_sink":
			if since < 4.0:
				return false
			var ts := 0.0
			for w in _m.wheels:
				ts = maxf(ts, w.sink)
			var ws := 0.0
			for w in _t.wheels:
				ws = maxf(ws, w.sink)
			var tp := 0.0
			for w in _m.wheels:
				tp += w.load / 9.8
			var wp := 0.0
			for w in _t.wheels:
				wp += w.load / 9.8
			print("in the mud: track sinks %.1f cm under %.0f kg a road wheel, wheel %.1f cm under %.0f kg (%s / %s)" % [
				ts * 100.0, tp / 10.0, ws * 100.0, wp / 4.0, _m.wheels[0].surface_label, _t.wheels[0].surface_label])
			_expect(_m.wheels[0].surface_label == "mud", "the tracks stand in the mud")
			_expect(ts < ws * 0.8, "a track sinks less than a road wheel")
			_t.queue_free()
			_m.throttle = 1.0
			_r.p = _m.global_position
			_next("mud_drive")
		"mud_drive":
			if since < 4.0:
				return false
			var gone := _m.global_position.distance_to(_r.p)
			print("4 s through the mud: %.1f m, mud on the belt %.2f" % [gone, _m.tracks[0].mud])
			_expect(gone > 8.0, "it drives through the mud")
			_expect(_m.tracks[0].mud > 0.05, "and the belt picks the mud up")
			_m.throttle = 0.0
			_place(_m, Vector2(0, -45), PI) # (facing the open meadow, the ramps behind it)
			_next("rockets")
		"rockets":
			if since < 1.5:
				return false
			var p := _m.global_position - _m.global_basis.z * 45.0
			p.y = float(_g.terrain.call("height_at", p.x, p.z)) + 2.0
			_t = _g._spawn(Designs.dummy(), Transform3D(Basis.IDENTITY, p), 1, false)
			_next("rocket_aim")
		"rocket_aim":
			if is_instance_valid(_t):
				_m.aim_point = _t.com_global() # (the pod lays itself over for the drop)
			if since < 3.0:
				return false
			if not _r.has("hp0"):
				_r.hp0 = _t.health()
				_r.e0 = _m.energy_kj
				print("pod on target: %s, %d loaded" % [_m.guns[0].on_target, _m.guns[0].loaded])
			_m.firing = true
			if since < 4.4:
				return false
			_m.firing = false
			var g := _m.guns[0]
			print("salvo: %d left in the pod, %d rockets in the air" % [g.loaded, Combat.current._rockets.size()])
			_expect(g.loaded == 0, "the whole salvo went off")
			_next("rocket_hit")
		"rocket_hit":
			if OS.get_environment("TRACE") != "" and _frame % 6 == 0:
				for r: Dictionary in Combat.current._rockets:
					print("   rocket at %s vel %s (target %s)" % [r.pos, r.vel, _t.com_global() if is_instance_valid(_t) else Vector3.ZERO])
			if is_instance_valid(_t):
				_m.aim_point = _t.com_global()
			if since < 2.0:
				return false
			var h: float = _t.health() if is_instance_valid(_t) else 0.0
			print("rockets: target health %.2f -> %.2f" % [_r.hp0, h])
			_expect(h < float(_r.hp0) - 0.1, "the rockets burst on it and hurt it")
			_next("reload")
		"reload":
			if since < 9.5:
				return false
			print("9.5 s later: %d loaded, battery %.0f%%" % [_m.guns[0].loaded, _m.charge_frac() * 100.0])
			_expect(_m.guns[0].loaded == MachineGun.ROCKETS, "the tubes are full again")
			if is_instance_valid(_t):
				_t.queue_free()
			_next("battery")
		"battery":
			# no engine: a minigun on the cab, spinning, with only the cab's battery
			_m.from_data(Designs.dummy())
			_m.design = _m.design.filter(func(p: Dictionary) -> bool: return p.id == "cab" or p.id == "frame")
			_m.rebuild()
			_expect(_m.place("minigun", Vector3i(0, 3, 0), 0), "a minigun on the dummy's cab")
			_place(_m, Vector2(0, -45))
			_m.energy_kj = _m.capacity_kj * 0.08 # (most of it gone already: a test can't wait minutes)
			_m.aim_point = _m.global_position + Vector3(30, 2, 0)
			_m.firing = true
			_next("drain")
		"drain":
			if since < 1.0:
				return false
			if not _r.has("shed_lo"):
				_r.shed_lo = _m.shed
				print("at 8%%: shed %d, loaders %s, minigun spin %.2f" % [_m.shed, _m.guns[0].can_load, _m.guns[0]._spin])
				_expect(_m.shed == 2 and _m.guns[0]._spin > 0.9, "low, the lights and loaders are shed but the minigun still spins")
			if since < 20.0 and _m.shed < 3:
				return false
			print("minigun on the cab battery: its motor shed at %.0f%% after %.1f s" % [_m.charge_frac() * 100.0, since])
			_expect(_m.shed == 3, "running lower, the minigun's motor is shed too")
			_next("shed_spin")
		"shed_spin":
			if since < 1.5:
				return false
			print("motor shed: spin %.2f, draw %.2f kW, consumers %s" % [_m.guns[0]._spin, _m.draw_kw, _m.consumers])
			_expect(_m.guns[0]._spin < 0.3, "and the barrels wind down")
			# swinging the turret about on what's left, it goes flat
			_m.energy_kj = 2.0
			_next("swing")
		"swing":
			_m.aim_point = _m.global_position + Vector3(30.0 if int(since) % 2 == 0 else -30.0, 2, 0)
			if since < 15.0 and _m.powered:
				return false
			print("swinging the turret: flat after %.1f s" % since)
			_expect(not _m.powered, "the turret's traverse runs it flat")
			_r.yaw = _m.guns[0].yaw
			_m.aim_point = _m.global_position + Vector3(0, 2, 30)
			_next("flat")
		"flat":
			if since < 1.0:
				return false
			var moved := absf(angle_difference(_r.yaw, _m.guns[0].yaw))
			print("flat: turret moved %.3f rad in 1 s" % moved)
			_expect(moved < 0.01, "flat, the turret doesn't turn")
			_expect(_m.place("engine", Vector3i(0, 1, 2), 0), "an engine bolts on behind the cab")
			_m.firing = false
			_next("charge")
		"charge":
			if since < 10.0:
				return false
			print("an engine running 10 s: battery %.0f kJ, charge %.1f kW, powered %s" % [_m.energy_kj, _m.charge_kw, _m.powered])
			_expect(_m.charge_kw > 1.0, "its alternator charges")
			_expect(_m.powered, "and the power's back")
			_next("builder")
		"builder":
			_m.from_data(Designs.starter())
			var b: Builder = _g.builder
			b.select("track")
			_g.builder.set_active(true)
			var side := _m.global_transform * (Vector3(3.5, 0.25, 0.25) * Parts.CELL) # (past the bed's +x side)
			var t := b.aim_ray(side, -_m.global_basis.x)
			print("track aimed at the bed's side: %s" % t)
			_expect(not t.is_empty() and int(t.rot) == 0 and int((t.at as Vector3i).y) == -1, "it goes along the side, hanging down")
			var front := _m.global_transform * (Vector3(0.5, 0.25, -4.0) * Parts.CELL)
			var tf := b.aim_ray(front, _m.global_basis.z)
			_expect(tf.is_empty() or int(tf.rot) % 2 == 0, "never across the machine")
			_g.builder.set_active(false)
			return _done()
	return false


func _done() -> bool:
	if _fail.is_empty():
		print("== tracks_test ALL CHECKS PASSED")
	else:
		print("== tracks_test FAILED: %d" % _fail.size())
	quit(1 if not _fail.is_empty() else 0)
	return true
