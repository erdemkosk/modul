extends SceneTree
## Headless check of the works robots (robot.gd), out in the arena:
##   godot --headless --path . -s res://tests/robots_test.gd
## 1. A sentry 30 m off your front: it turns to you and its bursts hurt your machine.
## 2. A warden 20 m off: it drives to you and its disc cuts.
## 3. Shot (Combat's hitscan) a robot loses hit points; a burst finishes it: it's a wreck, no target.
## 4. Driven into hard, a warden's flattened.
## 5. Held (no physics), a robot does nothing.

const ROBOT := preload("res://scripts/robot.gd")

var _g: Node
var _m: Machine
var _frame := 0
var _fail := PackedStringArray()
var _step := ""
var _mark := 0
var _r := {}


func _initialize() -> void:
	Builder.save_path = "user://test_design.json"
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


func _put(kind: String, local: Vector3) -> CharacterBody3D:
	var at := _m.global_transform * local
	var t: Node = _g.get("terrain")
	at.y = float(t.call("height_at", at.x, at.z))
	var r := ROBOT.make(kind, Transform3D(Basis.IDENTITY, at), _g, t)
	_g.add_child(r)
	return r


func _hold(on: bool) -> void:
	_m.throttle = 0.0
	_m.brake = 1.0 if on else 0.0


func _physics_process(_d: float) -> bool:
	_frame += 1
	var since := (_frame - _mark) / 120.0
	if _frame == 60:
		_g.set("player_input", false)
		_m = _g.get("machine")
		_m.from_data(Designs.starter())
		_r.held = _put("sentry", Vector3(-6, 0, -25))
		_r.held.set_physics_process(false)
		_r.sentry = _put("sentry", Vector3(0, 0, -30))
		_r.hp0 = _m.health()
		_next("sentry")
	match _step:
		"sentry":
			_hold(true)
			if since < 6.0:
				return false
			var s: Node = _r.sentry
			print("sentry: health %.3f -> %.3f" % [_r.hp0, _m.health()])
			_expect(_m.health() < float(_r.hp0) - 0.01, "the sentry's bursts hurt your machine")
			var h: Node = _r.held
			_expect(absf(float(h.get("_yaw"))) < 1e-4, "a held robot does nothing")
			# 3. shot, then burst
			var hp := float(s.get("hp"))
			var c := Combat.current
			var to := (s as Node3D).global_position + Vector3.UP * 1.0
			var from := to + Vector3(0, 2, 8)
			c.hitscan(from, (to - from).normalized(), 30.0, 25.0, 10.0, _m, false)
			print("shot: %.0f -> %.0f hp" % [hp, float(s.get("hp"))])
			_expect(float(s.get("hp")) < hp - 20.0, "a round takes its hit points")
			c.explode(to, 3.0, 400.0, 2000.0, _m, false)
			_expect(not bool(s.get("alive")), "a burst finishes it")
			_expect((s as CollisionObject3D).collision_layer == 1, "the wreck's no target")
			_m.invulnerable = true
			_r.warden = _put("warden", Vector3(4, 0, -20))
			_r.hp1 = _m.health()
			_m.invulnerable = false
			_next("warden")
		"warden":
			_hold(true)
			var w: Node3D = _r.warden
			if since < 9.0:
				return false
			var d := w.global_position.distance_to(_m.global_position)
			print("warden: %.1f m off, health %.3f -> %.3f" % [d, _r.hp1, _m.health()])
			_expect(d < 5.0, "the warden drives to you")
			_expect(_m.health() < float(_r.hp1) - 0.005, "and cuts")
			w.set("hp", 1000.0)
			w.global_position = _m.global_transform * Vector3(0, 0, -16)
			w.global_position.y = float((_g.get("terrain") as Node).call("height_at", w.global_position.x, w.global_position.z))
			_m.invulnerable = true
			_next("ram")
		"ram":
			_m.brake = 0.0
			_m.throttle = 1.0
			_m.steer = 0.0
			var w: Node3D = _r.warden
			if since < 4.0 and float(w.get("hp")) > 999.0:
				return false
			print("rammed at %.1f m/s: warden %.0f hp" % [_m.speed, float(w.get("hp"))])
			_expect(float(w.get("hp")) < 990.0, "driven into hard, it's hurt")
			print("ALL CHECKS PASSED" if _fail.is_empty() else "FAILED:\n  " + "\n  ".join(_fail))
			return true
	return _frame > 120 * 60
