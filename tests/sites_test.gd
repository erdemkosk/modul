extends SceneTree
## Headless check of the valley's works sites (works_sites.gd, Mode "valley"):
##   godot --headless --path . -s res://tests/sites_test.gd
## 1. There are four to six (as many as open ground allows), the same each time, on dry, flat ground, far enough from the start and apart.
## 2. Come near one, it's put up: its building and its robots; gone far, it's taken away.
## 3. Its robots killed, they stay dead (put up again, they're not there); the last one clears it and
##    its cache lies out lit to take; cleared and dead are kept (a new valley reads them back).
## 4. A rival from the third round sometimes has its gun on a turret, and it bolts on.

var _g: Node
var _s: Node
var _frame := 0
var _fail := PackedStringArray()
var _step := "start"
var _mark := 0
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_valley_design.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Builder.save_path))
	Inventory.path = "user://test_inventory.cfg"
	Inventory.reset()
	var ws: GDScript = load("res://scripts/works_sites.gd")
	ws.set("path", "user://test_sites.cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_sites.cfg"))
	Mode.current = "valley"
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
	return _g.get("machine")


## The machine set down `off` m from site `i`'s middle.
func _go(i: int, off: float) -> void:
	var at: Vector3 = _s.get("sites")[i].at
	var t: Node = _g.get("terrain")
	var p := at + Vector3(off, 0.0, 0.0)
	p.y = float(t.call("height_at", p.x, p.z)) + 1.5
	var m := _me()
	m.linear_velocity = Vector3.ZERO
	m.global_transform = Transform3D(Basis.IDENTITY, p)


func _robots(i: int) -> Array:
	var out := []
	for n: Variant in _s.get("sites")[i].nodes:
		if is_instance_valid(n) and (n as Node).is_in_group("robots"):
			out.append(n)
	return out


func _physics_process(_d: float) -> bool:
	_frame += 1
	var since := (_frame - _mark) / 120.0
	if _frame > 120 * 120:
		_expect(false, "timed out at " + _step)
		return _done()
	match _step:
		"start":
			if since < 2.0:
				return false
			_g.set("player_input", false)
			_s = _g.get("sites")
			_expect(_s != null, "the valley has its works sites")
			if _s == null:
				return _done()
			var sites: Array = _s.get("sites")
			var t: Node = _g.get("terrain")
			var start: Vector3 = (t.get("spawn") as Transform3D).origin
			var ok := sites.size() >= 4 and sites.size() <= 6
			for a: Dictionary in sites:
				ok = ok and Vector2(a.at.x - start.x, a.at.z - start.z).length() >= 220.0 and not bool(t.call("is_water", a.at.x, a.at.z))
				for b: Dictionary in sites:
					if a != b:
						ok = ok and (a.at as Vector3).distance_to(b.at) >= 300.0
			print("sites: %s" % ", ".join(sites.map(func(a: Dictionary) -> String: return "%s at (%.0f, %.0f) %d robots" % [a.name, a.at.x, a.at.z, a.robots.size()])))
			_expect(ok, "four to six, on dry ground, away from the start and apart")
			_r.first = (sites[0].at as Vector3)
			_me().invulnerable = true
			_go(0, 60.0)
			_next("near")
		"near":
			if since < 0.5:
				return false
			var rs := _robots(0)
			var n: int = _s.get("sites")[0].robots.size()
			print("near: %d nodes, %d robots of %d" % [_s.get("sites")[0].nodes.size(), rs.size(), n])
			_expect(rs.size() == n and _s.get("sites")[0].nodes.size() >= n + 2, "come near, it's put up: its building, its lamp, its yard, its robots")
			# kill one, go away, come back: it stays dead
			rs[0].call("take_hit", 5000.0, (rs[0] as Node3D).global_position, Vector3.FORWARD)
			_go(0, 500.0)
			_next("far")
		"far":
			if since < 0.5:
				return false
			_expect((_s.get("sites")[0].nodes as Array).is_empty(), "gone far, it's taken away")
			_go(0, 40.0)
			_next("back")
		"back":
			if since < 0.5:
				return false
			var rs := _robots(0)
			var n: int = _s.get("sites")[0].robots.size()
			_expect(rs.size() == n - 1, "the one killed stays dead")
			_r.items = Salvage.current.count()
			for r: Variant in rs:
				(r as Node).call("take_hit", 5000.0, (r as Node3D).global_position, Vector3.FORWARD)
			_next("cleared")
		"cleared":
			if since < 1.0:
				return false
			var s: Dictionary = _s.get("sites")[0]
			print("cleared %s; salvage lying %d -> %d (cache %s)" % [s.cleared, _r.items, Salvage.current.count(), s.cache])
			_expect(bool(s.cleared), "the last one clears it")
			_expect(Salvage.current.count() >= int(_r.items) + (s.cache as Array).size(), "its cache lies out to take")
			var cf := ConfigFile.new()
			cf.load("user://test_sites.cfg")
			_expect(bool(cf.get_value("site0", "cleared", false)) and (cf.get_value("site0", "dead", []) as Array).size() == (s.robots as Array).size(),
				"cleared and the dead are kept")
			# 4. a rival on a turret
			var found := false
			for k in 40:
				var made := Forge.make(900 + k, 3, "gunner")
				var has_turret := false
				var on_it := false
				for e: Array in made.data:
					has_turret = has_turret or e[0] == "turret"
					on_it = on_it or (e[0] == "minigun" and int(e[2]) == 4)
				if has_turret and on_it:
					found = true
					break
			_expect(found, "a third-round gunner sometimes has its gun on a turret")
			return _done()
	return false


func _done() -> bool:
	print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
	return true
