extends SceneTree
## Headless check of ARENA (Mode "waves"):
##   godot --headless --path . -s res://tests/waves_test.gd
## 1. It opens on building: the builder up, the maze laid (every cell reachable, walls and cover up).
## 2. Started: the other side comes in from far cells and drives at once (it's moved within seconds),
##    finding its way round the walls (heading for the next cell's middle when you're far).
## 3. Ammunition's limited: a gun emptied only clicks; a supply crate taken fills it again.
## 4. The last rival down: the round's won, then it's building again, on a new maze.
## 5. Your machine lost: the run's over; a new run starts at round 1.
## 6. The stadium round it full of people, its screens on; the crowd: hits work its mood up, full
##    it sends a crate down near you; sitting it out it boos, then the organisers shell you.

var _g: Node
var _w: Waves
var _frame := 0
var _fail := PackedStringArray()
var _step := "open"
var _mark := 0
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_waves_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	Waves.save_path = "user://test_arena.cfg"
	Mode.current = "waves"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail.append(what)
		print("  FAIL: " + what)


func _next(s: String) -> void:
	_step = s
	_mark = _frame


func _me() -> Machine:
	var m: Variant = _g.get("machine")
	return m if is_instance_valid(m) else null


func _reachable(a: WaveArena) -> int:
	var seen := {WaveArena.START: true}
	var q: Array[Vector2i] = [WaveArena.START]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + d
			if n.x >= 0 and n.y >= 0 and n.x < WaveArena.N and n.y < WaveArena.N and not seen.has(n) and a.is_open(c, n):
				seen[n] = true
				q.append(n)
	return seen.size()


func _physics_process(_d: float) -> bool:
	_frame += 1
	var since := (_frame - _mark) / 120.0
	if _frame > 120 * 150:
		_expect(false, "timed out at " + _step)
		return _done()
	match _step:
		"open":
			if since < 1.5:
				return false
			_w = _g.get("waves")
			var a: WaveArena = _g.get("wave_arena")
			var b: Builder = _g.get("builder")
			var cover := get_nodes_in_group(Breakable.GROUP).size()
			print("open: state %s, builder %s, %d cells reachable, %d open sides, %d pieces of cover" % [_w.state, b.active, _reachable(a), a.open.size(), cover])
			_expect(_w.state == "build" and b.active, "it opens on building")
			_expect(_reachable(a) == WaveArena.N * WaveArena.N, "every cell's reachable")
			_expect(a.open.size() < 2 * WaveArena.N * (WaveArena.N - 1) and cover > 40, "there are walls and cover")
			_r.open = a.open.duplicate()
			_me().from_data(Designs.raider()) # (a minigun on it)
			b.save()
			_w.start()
			_expect(_w.state == "fight" and not b.active, "Enter starts the round")
			_next("come")
		"come":
			if since < 2.0:
				return false
			if not _r.has("first"):
				_expect(not _w.rivals.is_empty(), "the other side comes in")
				if _w.rivals.is_empty():
					return _done()
				_r.first = _w.rivals[0]
				_r.from = _w.rivals[0].global_position
				var a: WaveArena = _g.get("wave_arena")
				_r.cell = a.cell_of(_r.from)
				return false
			if since < 8.0:
				return false
			var e: Machine = _r.first
			var moved := e.global_position.distance_to(_r.from) if is_instance_valid(e) else 99.0
			print("a rival came in at %s and moved %.1f m in 6 s" % [_r.cell, moved])
			_expect(moved > 4.0, "it drives at once")
			# its way: the next cell's middle while you're far
			var a: WaveArena = _g.get("wave_arena")
			if is_instance_valid(e):
				var p := a.path(e.global_position, _me().global_position)
				var g: Vector3 = a.route(e, _me(), _me().global_position)
				_expect(p.size() <= 1 or g.distance_to(a.center(p[0])) < 0.1, "it heads for the next cell on the way")
			# 3. ammunition
			var gun := _me().guns[0]
			_expect(gun.limited, "ammunition's limited here")
			gun.ammo = 0.0
			_expect(not gun.has_ammo(), "emptied, it can't fire")
			var s := _w.drop("ammo")
			s.global_position = _me().global_position + Vector3.UP * 3.0
			s.set("_ground", _me().global_position.y - 0.8)
			_me().invulnerable = true
			_next("crate")
		"crate":
			if since < 2.0:
				return false
			var gun := _me().guns[0]
			print("after the crate: %.0f / %.0f rounds" % [gun.ammo, gun.ammo_max])
			_expect(gun.ammo > gun.ammo_max * 0.5, "a supply crate taken fills it again")
			# 6. the stadium and its crowd
			var st: Stadium = (_g.get("wave_arena") as WaveArena).stadium
			print("stadium: %d people, its screen: %s / %s" % [st.people, st.line(0), st.line(1)])
			_expect(st.people > 20000, "the stadium's full of people")
			_expect(st.line(0).begins_with("DENEME 01"), "its screens show the trial")
			var before := _w.mood
			_w.you_hit(100.0)
			_expect(_w.mood > before, "a hit works the crowd up")
			var crates := get_nodes_in_group("supply").size()
			_w.mood_up(1.0)
			var near := false
			for d in get_nodes_in_group("supply"):
				var sd := d as Node3D
				if Vector2(sd.global_position.x - _me().global_position.x, sd.global_position.z - _me().global_position.z).length() < 26.0:
					near = true
			print("mood full: %d presents, crates %d -> %d, mood now %.2f" % [_w.presents, crates, get_nodes_in_group("supply").size(), _w.mood])
			_expect(_w.presents == 1 and near and _w.mood < 0.5, "full, the crowd sends a crate down near you")
			if _w.rivals.is_empty():
				_w._send_one()
			_r.hp = _me().health()
			_me().invulnerable = false
			_w.camp_t = Waves.CAMP_BOO + 0.1
			_next("boo")
		"boo":
			if since < 0.2:
				return false
			if not _r.has("booed"):
				_r.booed = true
				_expect(_w.booing, "sitting it out, the crowd boos")
				_w.camp_t = Waves.CAMP_SHELL
				return false
			if since < 6.5:
				return false
			print("shelled %d, health %.2f -> %.2f" % [_w.shelled, _r.hp, _me().health()])
			_expect(_w.shelled == 1 and _me().health() < _r.hp, "then the organisers shell you")
			_me().invulnerable = true
			# 4. the round won
			_w.to_come = 0
			for e in _w.rivals:
				if is_instance_valid(e):
					e.break_off(e.cab_index())
			_next("won")
		"won":
			if since < 0.5:
				return false
			if not _r.has("won_seen"):
				_r.won_seen = true
				_expect(_w.state == "cleared", "the last rival down wins the round")
				return false
			if since < 5.0:
				return false
			var a: WaveArena = _g.get("wave_arena")
			print("round %d, state %s, a new maze: %s" % [_w.round, _w.state, a.open != _r.open])
			_expect(_w.round == 2 and _w.state == "build", "then it's building again, the next round")
			_expect(a.open != _r.open, "on a new maze")
			_w.start()
			_me().invulnerable = false
			_me().break_off(_me().cab_index())
			_next("lost")
		"lost":
			if since < 0.5:
				return false
			_expect(_w.state == "lost", "your machine lost, the run's over")
			var ev := InputEventKey.new()
			ev.keycode = KEY_ENTER
			ev.pressed = true
			_w._unhandled_key_input(ev)
			_next("again")
		"again":
			if since < 1.0:
				return false
			print("again: round %d, state %s, machine alive %s" % [_w.round, _w.state, _me() != null and _me().alive])
			_expect(_w.round == 1 and _w.state == "build" and _me() != null and _me().alive, "a new run starts at round 1")
			return _done()
	return false


func _done() -> bool:
	print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
	return true
