extends SceneTree
## Headless check of the arena and what weapons do to it (Mode "arena"):
##   godot --headless --path . -s res://tests/arena_test.gd
## 1. It's there: the wall all round (a ray out from the middle stops at it, but not through the gate),
##    the cover is Breakable, the floor flat inside.
## 2. A burst on the ground digs a crater (the ground's lower there, its rim higher) and the ground
##    you drive on (the collision) is dug too.
## 3. Bursts break a concrete block into chunks; rounds shred a crate; a drum hit goes up and takes
##    its neighbours with it.
## 4. Your hits are confirmed (for the crosshair) and your gun's shots shake the view; enemies come in
##    at the gate.
## 5. Knocks: a gentle touch on the wall does nothing, a hard one hurts and breaks the nose off (the
##    centre of mass moving back); its engine gone, it's alive but can't move.

var _g: Node
var _m: Machine
var _frame := 0
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


func _nearest(kind: String, to: Vector3) -> Breakable:
	var best: Breakable = null
	var d := INF
	for n in root.get_tree().get_nodes_in_group(Breakable.GROUP):
		var b := n as Breakable
		if b.kind == kind and not b.broken and b.global_position.distance_to(to) < d:
			d = b.global_position.distance_to(to)
			best = b
	return best


func _physics_process(_d: float) -> bool:
	_frame += 1
	var c := Combat.current
	match _frame:
		120:
			_g.set("player_input", false)
			_m = _g.get("machine")
			_m.invulnerable = true
			var space := _m.get_world_3d().direct_space_state
			var walls := 0
			for k in 12:
				var a := TAU * (k + 0.5) / 12
				var q := PhysicsRayQueryParameters3D.create(Vector3(cos(a), 0, sin(a)) * 84.0 + Vector3.UP * 0.5, Vector3(cos(a), 0, sin(a)) * 120.0 + Vector3.UP * 0.5, 1)
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and absf((hit.position as Vector3).length() - Arena.R) < 3.0:
					walls += 1
			var gq := PhysicsRayQueryParameters3D.create(Vector3(-60, 0.5, 0), Vector3(-120, 0.5, 0), 1)
			var through := space.intersect_ray(gq)
			print("rays out (from inside the cover) stopped by the wall: %d of 12; through the gate: %s" % [walls, through])
			_expect(walls >= 10, "a wall all round")
			_expect(through.is_empty() or (through.position as Vector3).x < -96.0, "the gate is open")
			var n := root.get_tree().get_nodes_in_group(Breakable.GROUP).size()
			print("breakables: %d" % n)
			_expect(n > 50, "cover to fight round")
			_expect(absf(_g.terrain.call("height_at", 60.0, 50.0)) < 0.05, "the floor flat inside")
			# 2. a crater
			var p := Vector3(-45.0, 0.0, 60.0)
			p.y = _g.terrain.call("sample_height", p.x, p.z)
			_r.h0 = p.y
			_r.rim0 = _g.terrain.call("sample_height", p.x + 2.6, p.z)
			c.explode(p, MachineGun.CANNON_RADIUS, MachineGun.CANNON_DAMAGE, MachineGun.CANNON_PUSH, null)
			_r.p = p
		125:
			var p: Vector3 = _r.p
			var h1: float = _g.terrain.call("sample_height", p.x, p.z)
			var rim: float = _g.terrain.call("sample_height", p.x + 2.6, p.z)
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5.0, p + Vector3.DOWN * 5.0, 1)
			var hit := _m.get_world_3d().direct_space_state.intersect_ray(q)
			print("crater: ground %.2f -> %.2f, rim %.2f -> %.2f, collision at %.2f" % [_r.h0, h1, _r.rim0, rim, (hit.position as Vector3).y if not hit.is_empty() else 99.0])
			_expect(h1 < float(_r.h0) - 0.3, "a burst digs a crater")
			_expect(rim > float(_r.rim0), "its rim thrown up")
			_expect(not hit.is_empty() and (hit.position as Vector3).y < float(_r.h0) - 0.3, "and you drive in it, not over it")
			# 3. a block broken by bursts
			var b := _nearest("block", Vector3(-10, 0, 60))
			_r.block = b
			_r.debris0 = c._debris.size()
			for k in 4:
				c.explode(b.center() + Vector3(0, 0, -1.4), MachineGun.CANNON_RADIUS, MachineGun.CANNON_DAMAGE, MachineGun.CANNON_PUSH, _m, true)
		130:
			var gone := not is_instance_valid(_r.block)
			print("block after four shells: %s, chunks %d" % ["broken" if gone else "standing (%.0f hp)" % (_r.block as Breakable).hp, c._debris.size() - int(_r.debris0)])
			_expect(gone, "four shells break a concrete block")
			_expect(c._debris.size() - int(_r.debris0) >= 8, "into chunks")
			# a crate under rounds
			var cr := _nearest("crate", Vector3(30, 0, -70))
			_r.crate = cr
			var from := cr.center() + Vector3(-8.0, 0.0, 0.0) # (from the open side of the pile)
			for k in 20:
				c.hitscan(from, (cr.center() - from).normalized(), 50.0, MachineGun.MINIGUN_DAMAGE, MachineGun.MINIGUN_PUSH, _m, false)
			# a drum hit: it goes up, and its neighbours
			_r.drums0 = 0
			var dr := _nearest("drum", Vector3(12, 0, 58))
			for n in root.get_tree().get_nodes_in_group(Breakable.GROUP):
				if (n as Breakable).kind == "drum" and (n as Breakable).global_position.distance_to(dr.global_position) < 2.0:
					_r.drums0 += 1
			_r.drum_at = dr.global_position
			dr.hit(100.0, dr.center(), Vector3.FORWARD)
		140:
			_expect(not is_instance_valid(_r.crate), "twenty rounds shred a crate")
			var left := 0
			for n in root.get_tree().get_nodes_in_group(Breakable.GROUP):
				if (n as Breakable).kind == "drum" and (n as Breakable).global_position.distance_to(_r.drum_at) < 2.0:
					left += 1
			print("drums by the one hit: %d -> %d" % [_r.drums0, left])
			_expect(left == 0, "a drum goes up and takes its neighbours")
			# 4. hits confirmed, the view shaken, enemies at the gate
			_r.conf = 0
			c.hit_confirmed.connect(func(o: Machine, _k: bool) -> void:
				if o == _m:
					_r.conf += 1)
			var p := _m.global_position + Vector3(0, 0, -30)
			p.y = _g.terrain.call("height_at", p.x, p.z) + 2.0
			_r.t = _g._spawn(Designs.dummy(), Transform3D(Basis.IDENTITY, p), 1, false)
		200:
			var t: Machine = _r.t
			var from := t.com_global() + Vector3(0, 0.3, 12.0)
			for k in 5:
				c.hitscan(from, (t.com_global() - from).normalized(), 50.0, 5.0, 1.0, _m, false)
			var cam: OrbitCamera = _g.get("cam")
			cam.trauma = 0.0
			c.shake(_m.global_position, 0.55, _m, 6.0)
			_r.trauma = cam.trauma
			var e: Machine = _g.spawn_enemy("raider")
			_r.e_at = e.global_position
		205:
			print("hits confirmed: %d, trauma after a cannon shot %.2f, enemy in at %s" % [_r.conf, _r.trauma, _r.e_at])
			_expect(int(_r.conf) >= 5, "your hits are confirmed")
			_expect(float(_r.trauma) > 0.5, "your cannon shakes the view")
			_expect((_r.e_at as Vector3).x < -70.0 and absf((_r.e_at as Vector3).z) < 12.0, "the enemy comes in at the gate")
			_g.clear_enemies()
			# 5. knocks: a gentle touch on the wall does nothing
			_m.invulnerable = false
			_m.from_data(Designs.starter())
			var p := Vector3(0.0, 0.0, -Arena.R + 6.0)
			p.y = _g.terrain.call("height_at", p.x, p.z) + 0.8
			_m.global_transform = Transform3D(Basis.IDENTITY, p) # (its nose, -z, toward the wall)
			_m.linear_velocity = Vector3(0, 0, -2.0)
			_m.angular_velocity = Vector3.ZERO
			_r.hp0 = _m.health()
		400:
			print("a 2 m/s touch on the wall: health %.3f -> %.3f" % [_r.hp0, _m.health()])
			_expect(is_equal_approx(_m.health(), float(_r.hp0)), "a gentle touch does no harm")
			# a hard one: 15 m/s into it
			var p := Vector3(0.0, 0.0, -Arena.R + 12.0)
			p.y = _g.terrain.call("height_at", p.x, p.z) + 0.8
			_m.global_transform = Transform3D(Basis.IDENTITY, p)
			_m.linear_velocity = Vector3(0, 0, -15.0)
			_m.angular_velocity = Vector3.ZERO
			_r.hp0 = _m.health()
			_r.parts0 = _m.design.size()
			_r.com0 = _m.com
		520:
			print("15 m/s into the wall: health %.2f -> %.2f, parts %d -> %d, centre of mass %s -> %s" % [
				_r.hp0, _m.health(), _r.parts0, _m.design.size(), _r.com0, _m.com])
			_expect(_m.health() < float(_r.hp0) - 0.05, "a hard knock hurts it")
			_expect(_m.design.size() < int(_r.parts0), "and breaks parts off its nose")
			_expect((_m.com as Vector3).z > (_r.com0 as Vector3).z, "its centre of mass moves back as its nose goes")
			# no engine: it can't move
			var e := -1
			for i in _m.design.size():
				if _m.design[i].id == "engine":
					e = i
			if e >= 0:
				_m.break_off(e)
			_expect(_m.immobile() and _m.alive, "its engine gone, it's alive but can't move")
			print("== arena_test ALL CHECKS PASSED" if _fail.is_empty() else "== arena_test FAILED: %d" % _fail.size())
			quit(1 if not _fail.is_empty() else 0)
			return true
	return false
