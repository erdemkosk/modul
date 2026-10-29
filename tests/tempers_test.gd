extends SceneTree
## Headless check of KAFES's record and its rivals' tempers (Mode "cage"):
##   godot --headless --path . -s res://tests/tempers_test.gd
## 1. The record: parts not opened yet can't be built with (their tiles locked, a design with them
##    refused); a run's fame is kept (in the file) and opens the parts it reaches.
## 2. A lurker waits at its lair, still, while you're far off; you near, it comes for you.
## 3. A lobber that can't see you (a wall between) lobs rounds over it, a red ring where they land.
## 4. A flanker comes round to the side of you, not straight at you.

const HZ := 120
var _g: Node
var _c: Cage
var _a: CageArena
var _m: Machine
var _e: Machine
var _frame := 0
var _step := "start"
var _mark := 0
var _fail := PackedStringArray()
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	CageRecord.save_path = "user://test_cage_record.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CageRecord.save_path))
	Mode.current = "cage"
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail.append(what)
		print("  FAIL: " + what)


func _next(s: String) -> void:
	_step = s
	_mark = _frame


func _put(m: Machine, at: Vector2, yaw := 0.0) -> void:
	var p := Vector3(at.x, _g.terrain.height_at(at.x, at.y) + 1.0, at.y)
	m.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
	m.linear_velocity = Vector3.ZERO
	m.angular_velocity = Vector3.ZERO
	m.set_down()


## A rival of `temper` at `at`, facing `yaw`, its crew awake.
func _rival(temper: String, at: Vector2, yaw: float) -> AiDriver:
	if is_instance_valid(_e):
		_e.queue_free()
	var p := Vector3(at.x, _g.terrain.height_at(at.x, at.y) + 1.5, at.y)
	_e = _g._spawn(Designs.starter(), Transform3D(Basis(Vector3.UP, yaw), p), 1, true)
	var d: AiDriver = _e.find_children("*", "AiDriver", false, false)[0]
	d.temper = temper
	d._wake = 0.0
	return d


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame > 90 * HZ:
		_expect(false, "timed out at " + _step)
		return _done()
	var since := (_frame - _mark) / float(HZ)
	match _step:
		"start":
			if _frame < HZ:
				return false
			_c = _g.get("cage")
			_a = _c.arena
			var b := _g.get("builder") as Builder
			_m = _g.get("machine")
			_g.set("player_input", false)
			# 1. the record
			print("fresh record: fame %d; rockets %s, frame %s; rockets' tile disabled %s" % [_c.record.fame,
				b.lock_note.call("rockets"), b.lock_note.call("frame"), (b._cards["rockets"] as Button).disabled])
			_expect(b.active and (b._cards["rockets"] as Button).disabled and not (b._cards["frame"] as Button).disabled, "the builder's tiles of parts not open are locked")
			_expect(not _c._may_build("rockets", Vector3i.ZERO, 0) and _c._may_build("frame", Vector3i.ZERO, 0), "and they can't be put on")
			_expect(not bool(b.swap_guard.call([], [["cab", 0, 0, 0, 0], ["rockets", 0, 1, 0, 0]])), "nor a design with them loaded")
			b.set_active(false)
			var got := _c.record.add_run(3, false)
			var again := CageRecord.load_record()
			print("a run of 3 rounds: +%d fame, opened %s; from the file: fame %d, runs %d, best %d" % [got.gained, got.opened, again.fame, again.runs, again.best_round])
			_expect(got.gained == 90 and again.fame == 90 and again.runs == 1 and again.best_round == 3, "a run's fame is kept")
			_expect("track" in got.opened and _c.record.is_open("track") and b.lock_note.call("track") == "", "and opens the parts it reaches")
			# 2. a lurker, far off
			_a.set_round({})
			_m.invulnerable = true
			_put(_m, Vector2(0, -60))
			var d := _rival("pusucu", Vector2(-20, 50), 0.0)
			d.lair = Vector3(0, 0, 40)
			_next("lurk")
		"lurk":
			if since < 8.0:
				return false
			var d: AiDriver = _e.find_children("*", "AiDriver", false, false)[0]
			var off := Vector2(_e.global_position.x, _e.global_position.z).distance_to(Vector2(0, 40))
			print("lurker after 8 s: %.1f m from its lair, speed %.1f, waiting %s" % [off, _e.speed, d.waiting])
			_expect(d.waiting and off < 5.0 and absf(_e.speed) < 0.6, "a lurker waits at its lair, still")
			_put(_m, Vector2(0, 15))
			_r.d0 = _e.global_position.distance_to(_m.global_position)
			_next("roused")
		"roused":
			if since < 4.0:
				return false
			var d: AiDriver = _e.find_children("*", "AiDriver", false, false)[0]
			var dd := _e.global_position.distance_to(_m.global_position)
			print("you near: waiting %s, %.1f m -> %.1f m" % [d.waiting, _r.d0, dd])
			_expect(not d.waiting, "you near, it's roused")
			# 3. a lobber behind a wall
			_a.set_round({"walls": [[Vector2(-16, 0), Vector2(16, 0), "container"]]})
			_put(_m, Vector2(0, -10))
			_m.invulnerable = false
			_r.h0 = _m.health()
			var lb := _rival("topcu", Vector2(0, 26), 0.0)
			lb._lob_t = 0.5
			_r.rings = 0
			_r.near = INF
			_next("lob")
		"lob":
			_g.set("player_input", false)
			for rg in _g.get_tree().get_nodes_in_group("lob_rings"):
				if not _r.has("seen_%d" % rg.get_instance_id()):
					_r["seen_%d" % rg.get_instance_id()] = true
					_r.rings += 1
					_r.near = minf(float(_r.near), (rg as Node3D).global_position.distance_to(_m.global_position))
			if since < 12.0:
				return false
			var d: AiDriver = _e.find_children("*", "AiDriver", false, false)[0]
			print("lobber behind the wall (sees you by the end: %s): %d rings, nearest %.1f m from you; your health %.2f -> %.2f" % [
				d._sees(_m), _r.rings, _r.near, _r.h0, _m.health()])
			_expect(int(_r.rings) >= 1 and float(_r.near) < 10.0, "a lobber lobs over the wall, a ring where it lands") # (it lobs only unseen; by the end it may have come round, or broken through)
			# 4. a flanker
			_a.set_round({})
			_m.invulnerable = true
			_put(_m, Vector2(0, -50))
			_rival("kusatici", Vector2(0, 50), 0.0)
			_r.side = 0.0
			_next("flank")
		"flank":
			var p := _e.global_position
			if p.distance_to(_m.global_position) > 30.0:
				_r.side = maxf(float(_r.side), absf(p.x))
			if since < 9.0:
				return false
			print("flanker: as far as %.1f m to the side on its way in" % _r.side)
			_expect(float(_r.side) > 8.0, "a flanker comes round to the side of you")
			return _done()
	return false


func _done() -> bool:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CageRecord.save_path))
	print("== tempers_test ALL CHECKS PASSED" if _fail.is_empty() else "== tempers_test FAILED: %d" % _fail.size())
	quit(1 if not _fail.is_empty() else 0)
	return true
