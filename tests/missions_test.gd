extends SceneTree
## Headless check of GÖREVLER (Mode "mission"):
##   godot --headless --path . -s res://tests/missions_test.gd
## 1. Every mission lays out: its targets standing, its guards held till the start.
## 2. The first: it waits on its brief (building's allowed); started, the clock runs and building's
##    not; its targets brought down one by one, it's done, with stars by the time; the record's
##    kept and the next mission opens.
## 3. One with guards: they're held before the start and drive after; your machine lost, it's failed.

var _g: Node
var _ms: Missions
var _frame := 0
var _fail := PackedStringArray()
var _step := "lay"
var _mark := 0
var _k := 0


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
	Missions.save_path = "user://test_missions.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Missions.save_path))
	_load(0)


func _load(i: int) -> void:
	if _g:
		_g.queue_free()
	Mode.current = "mission"
	Mode.mission = str(Missions.LIST[i].id)
	_g = load("res://scenes/game.tscn").instantiate()
	root.add_child(_g)
	_mark = _frame


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail.append(what)
		print("  FAIL: " + what)


func _next(s: String) -> void:
	_step = s
	_mark = _frame


func _physics_process(_d: float) -> bool:
	_frame += 1
	var since := (_frame - _mark) / 120.0
	if _frame > 120 * 200:
		_expect(false, "timed out at " + _step)
		return _done()
	match _step:
		"lay":
			if since < 1.0:
				return false
			_ms = _g.get("missions")
			var d: Dictionary = Missions.LIST[_k]
			var held := true
			for e in _ms.guards:
				held = held and not e.is_physics_processing()
			print("  %-14s %d targets (%s), %d guards held %s, state %s" % [d.name, _ms.targets.size(),
				", ".join(_ms.targets.map(func(s: Structure) -> String: return s.title)), _ms.guards.size(), held, _ms.state])
			_expect(_ms.targets.size() == d.targets.size() and _ms.targets_down() == 0, "%s: its targets stand" % d.name)
			_expect(held, "%s: its guards held till the start" % d.name)
			_expect(_ms.state == "prep" and _ms.can_build(), "%s: waits on its brief, building allowed" % d.name)
			_k += 1
			if _k < Missions.LIST.size():
				_load(_k)
				return false
			_load(0)
			_next("first")
		"first":
			if since < 1.0:
				return false
			_ms = _g.get("missions")
			_expect(not Missions.is_open(1), "the second's locked to start with")
			_ms.start()
			_expect(_ms.state == "run" and not _ms.can_build(), "started: running, no building")
			_next("bring_down")
		"bring_down":
			if since < 2.0:
				return false
			_expect(_ms.time > 1.5, "the clock runs (%.1f s)" % _ms.time)
			for s in _ms.targets:
				for p in s.pieces.filter(func(p: StructurePiece) -> bool: return p.grounded):
					p.hit(99999.0, p.global_position, Vector3.UP, true)
			_next("done")
		"done":
			if since < 3.0:
				return false
			print("first mission: state %s, %d/%d down, %.1f s, %d stars" % [_ms.state, _ms.targets_down(), _ms.targets.size(), _ms.time, _ms.stars])
			_expect(_ms.state == "done", "every target down: it's done")
			_expect(_ms.stars == 3, "quick: three stars (%d)" % _ms.stars)
			var rec := Missions.record(str(Missions.LIST[0].id))
			_expect(float(rec[0]) > 0.0 and int(rec[1]) == 3, "the record's kept (%s)" % [rec])
			_expect(Missions.is_open(1), "the next mission's open now")
			_load(3) # (one with guards)
			_next("guards")
		"guards":
			if since < 1.0:
				return false
			_ms = _g.get("missions")
			_ms.start()
			var on := 0
			for e in _ms.guards:
				on += 1 if e.is_physics_processing() else 0
			_expect(on == _ms.guards.size() and on > 0, "the guards drive once it's started (%d)" % on)
			var me: Machine = _g.get("machine")
			me.blast(me.com_global(), 4.0, 99999.0, 0.0, null, "patlama")
			_next("failed")
		"failed":
			if since < 1.0:
				return false
			print("with your machine gone: %s" % _ms.state)
			_expect(_ms.state == "failed", "your machine gone: it's failed")
			return _done()
	return false


func _done() -> bool:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Missions.save_path))
	print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
	return true
