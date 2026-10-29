extends SceneTree
## Headless check of KAFES (Mode "cage"):
##   godot --headless --path . -s res://tests/cage_test.gd
## 1. The cage is built: walls all round, a crowd in the stands, the first round's maze (mud in the
##    middle, a way through from your corner to theirs, another maze for another seed); the builder's
##    open, and it waits for you to build and start.
## 2. A round: the countdown holds everyone, then the rival drives; its cab gone, the round's yours and
##    it pays; the workshop comes up.
## 3. The workshop: the next round's maze laid (another one), you in the red corner with the builder
##    open; what's broken and missing, costed; repairing puts parts back and takes credits.
## 4. The next round lays another floor (ice in the middle) with spikes that bite what's on them; the
##    third's fire vents burn what's over them.
## 5. Your cab gone, you're out.
## The crowd (in round 1): the stadium full and its screens on; hits raise COŞKU, full it sends a
## crate down near you; sitting it out has them booing, then the organisers shell you.

const HZ := 120
var _g: Node
var _c: Cage
var _m: Machine
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
			_c = _g.get("cage")
			_m = _g.get("machine")
			var mm: MultiMeshInstance3D = _g.find_children("*", "MultiMeshInstance3D", true, false)[0]
			print("crowd: %d people; state %s; floor in the middle: %s" % [mm.multimesh.instance_count, _c.state,
				_g.terrain.surface_at(Vector3.ZERO).label])
			_expect(mm.multimesh.instance_count > 400, "a crowd in the stands")
			_expect(_c.state == "prep" and _c.can_build(), "it waits for you to build and start")
			_expect(_g.terrain.surface_at(Vector3.ZERO).label == "mud", "the first round's mud pit")
			var space := _m.get_world_3d().direct_space_state
			var walled := 0
			for k in 8:
				var a := TAU * k / 8.0
				var q := PhysicsRayQueryParameters3D.create(Vector3(0, 1.0, 0), Vector3(cos(a), 0, sin(a)) * (CageArena.HALF + 10.0) + Vector3.UP, 1)
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and (hit.position as Vector3).length() < CageArena.HALF * 1.5:
					walled += 1
			_expect(walled == 8, "walled all round (%d/8)" % walled)
			var st := _c.arena.stadium
			print("stadium: %d people, screen: %s" % [st.people, st.line(0)])
			_expect(st.people > 12000, "a stadium full of people round the cage")
			_expect(st.line(0).begins_with("PROTOTİP"), "its screens on")
			var ar := _c.arena
			var way := ar.path(ar.center(CageArena.RED), ar.center(CageArena.BLUE))
			var other := CageArena.plan(Cage.ROUNDS[0].theme, 12345)
			var again := CageArena.plan(Cage.ROUNDS[0].theme, 12345)
			print("maze: %d walls, %d pieces of cover, %d cells from your corner to theirs; another seed: %d walls" % [ar.walls.size(),
				ar.layout.cover.size(), way.size(), other.walls.size()])
			_expect(ar.walls.size() > 10 and way.size() >= CageArena.N * 2 - 2, "a maze, with a way through from your corner to theirs")
			_expect(str(other.walls) == str(again.walls) and str(other.walls) != str(ar.layout.walls), "the same seed the same maze, another seed another")
			_expect((_g.get("builder") as Builder).active, "the builder's open on it")
			_r.walls1 = str(ar.layout.walls)
			_c.start_run()
			_next("countdown")
		"countdown":
			if since < 1.0:
				return false
			var e: Machine = _c.rivals[0]
			if not _r.has("e0"):
				_r.e0 = e.global_position
				print("counting down: state %s, rival %s at %s" % [_c.state, e.label, e.global_position])
				_expect(_c.state == "countdown" and not _g.get("player_input"), "the countdown holds you")
				_expect(" · " in e.label, "the rival's temper in its name (%s)" % e.label)
				var dv: AiDriver = e.find_children("*", "AiDriver", false, false)[0]
				var to := dv.route.call(e, _m, _m.global_position) as Vector3
				print("its way to you: next %s (cell %s), %d cells" % [to, _c.arena.cell_of(to), _c.arena.path(e.global_position, _m.global_position).size()])
				_expect(_c.arena.cell_of(to) == _c.arena.path(e.global_position, _m.global_position)[0], "it finds its way through the maze")
			if since < 5.0:
				return false
			print("after the countdown: state %s, rival moved %.1f m" % [_c.state, e.global_position.distance_to(_r.e0)])
			_expect(_c.state == "fight", "then it's on")
			_expect(e.global_position.distance_to(_r.e0) > 1.0, "and the rival drives")
			_hold()
			var m0 := _c.mood
			_c.you_hit(120.0)
			print("crowd: mood %.2f -> %.2f after a hit" % [m0, _c.mood])
			_expect(_c.mood > m0, "a hit raises the mood")
			_c.mood_up(1.0)
			var drops := _g.get_tree().get_nodes_in_group("supply")
			var near := drops.size() == 1 and Vector2((drops[0] as Node3D).global_position.x - _m.global_position.x,
				(drops[0] as Node3D).global_position.z - _m.global_position.z).length() < 25.0
			print("full: %d present(s), %d crate(s) near: %s, mood now %.2f" % [_c.presents, drops.size(), near, _c.mood])
			_expect(_c.presents == 1 and near and _c.mood < 0.5, "full, the crowd sends a crate down near you")
			_c.camp_t = Cage.CAMP_BOO
			_r.hh = _m.health()
			_next("boo")
		"boo":
			if since < 0.2:
				return false
			if not _r.has("booed"):
				_r.booed = true
				_expect(_c.booing, "sitting it out, they boo")
				_c.camp_t = Cage.CAMP_SHELL
			if since < 7.0:
				return false
			print("shelled %d, health %.2f -> %.2f" % [_c.shelled, _r.hh, _m.health()])
			_expect(_c.shelled == 1 and _m.health() < float(_r.hh), "then the organisers shell you")
			_m.from_data(_c.full) # (made whole again: what the shells did isn't the workshop's to check)
			var e: Machine = _c.rivals[0]
			_r.cr0 = _c.credits
			# your machine hurt a little meanwhile (for the workshop): a light off, a frame hit
			for i in range(_m.design.size() - 1, -1, -1):
				if _m.design[i].id == "light":
					_m.break_off(i)
					break
			_m.damage_part(0, 30.0)
			e.damage_part(e.cab_index(), 99999.0)
			_next("won")
		"won":
			if since < 0.5:
				return false
			if not _r.has("paid"):
				_r.paid = true
				print("rival's cab gone: state %s, credits %d -> %d" % [_c.state, _r.cr0, _c.credits])
				_expect(_c.state == "won" and _c.credits > int(_r.cr0), "the round's yours, and it pays")
			if since < 4.0:
				return false
			_expect(_c.state == "workshop", "the workshop comes up")
			var b := _g.get("builder") as Builder
			var corner := Vector2(_m.global_position.x, _m.global_position.z).distance_to(Vector2(-1, -1) * (CageArena.HALF - 4.5))
			print("workshop: builder open %s, %.1f m from the red corner, a new maze %s" % [b.active, corner, str(_c.arena.layout.walls) != _r.walls1])
			_expect(b.active and corner < 3.0 and str(_c.arena.layout.walls) != _r.walls1, "the next maze laid, you in your corner, building")
			b.set_active(false)
			var d := _c.damage_list()
			print("workshop: %s" % [d.map(func(e: Dictionary) -> String: return "%s %s %d" % [e.id, "yok" if e.missing else "%.2f" % e.frac, e.cost])])
			_expect(d.size() >= 2 and d.any(func(e: Dictionary) -> bool: return e.missing), "what's broken and missing, costed")
			var cr := _c.credits
			var n0 := _m.design.size()
			var spent := _c.repair(false)
			print("repaired for %d: credits %d -> %d, parts %d -> %d, left to do %d" % [spent, cr, _c.credits, n0, _m.design.size(), _c.damage_list().size()])
			_expect(spent > 0 and _c.credits == cr - spent, "repairs take credits")
			_expect(_m.design.size() == n0 + 1 and _c.damage_list().is_empty(), "and put it all back")
			_c.next_round()
			_next("round2")
		"round2":
			if since < 4.5:
				return false
			print("round 2: floor in the middle %s, state %s" % [_g.terrain.surface_at(Vector3.ZERO).label, _c.state])
			_expect(_g.terrain.surface_at(Vector3.ZERO).label == "ice", "the next round's floor: ice")
			# onto the spikes, everyone held
			_hold()
			_put((_c.arena.layout.spikes[0] as Rect2).get_center())
			_r.h0 = _m.health()
			_next("spikes")
		"spikes":
			if since < 2.5:
				return false
			print("2.5 s on the spikes: health %.3f -> %.3f" % [_r.h0, _m.health()])
			_expect(_m.health() < float(_r.h0) - 0.01, "the spikes bite")
			# the third round's vents
			_c.state = "won"
			_c.round = 1
			_c.next_round()
			_next("round3")
		"round3":
			if since < 4.5:
				return false
			_hold()
			_put(_c.arena.layout.vents[0])
			_r.h1 = _m.health()
			_next("vent")
		"vent":
			if since < 9.0:
				return false
			print("9 s over a fire vent: health %.3f -> %.3f" % [_r.h1, _m.health()])
			_expect(_m.health() < float(_r.h1) - 0.02, "the vent burns what's over it")
			_m.damage_part(_m.cab_index(), 99999.0)
			_next("lost")
		"lost":
			if since < 3.0:
				return false
			print("cab gone: state %s; the record: %d run(s), fame %d (+%d)" % [_c.state, _c.record.runs, _c.record.fame, int(_c.last_run.get("gained", -1))])
			_expect(_c.state == "lost", "your cab gone, you're out")
			_expect(_c.record.runs == 1 and _c.record.fame == CageRecord.fame_for(_c.round, false) and CageRecord.load_record().runs == 1,
				"the run goes into the record, its fame kept")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CageRecord.save_path))
			return _done()
	return false


## Everyone stood still: the rivals not driving, you not either.
func _hold() -> void:
	for e in _c.rivals:
		if is_instance_valid(e):
			e.set_physics_process(false)
	_g.set("player_input", false)
	_m.throttle = 0.0


## Your machine put down at (x, z) on the floor.
func _put(at: Vector2) -> void:
	var p := Vector3(at.x, _g.terrain.height_at(at.x, at.y) + 1.0, at.y)
	_m.global_transform = Transform3D(Basis.IDENTITY, p)
	_m.linear_velocity = Vector3.ZERO
	_m.angular_velocity = Vector3.ZERO
	_m.set_down()


func _done() -> bool:
	print("== cage_test ALL CHECKS PASSED" if _fail.is_empty() else "== cage_test FAILED: %d" % _fail.size())
	quit(1 if not _fail.is_empty() else 0)
	return true
