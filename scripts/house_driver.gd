class_name HouseDriver
extends Node
## Drives a cage's house robot (its child Machine): it waits in its patrol zone, its nose to the
## middle; whatever comes into the zone (you or a rival, anyone but its own kind) it drives into,
## hard, and once that's out of the zone again it goes back to its spot.

var machine: Machine
var zone := Rect2() ## (x, z) its patrol zone on the floor
var home := Vector3.ZERO
var _back_t := 0.0
var _stuck_t := 0.0


func _ready() -> void:
	machine = get_parent() as Machine


func _intruder() -> Machine:
	var best: Machine = null
	var best_d := INF
	var reach := zone.grow(1.5)
	for n: Node in machine.get_tree().get_nodes_in_group("machines"):
		var m := n as Machine
		if m == machine or not is_instance_valid(m) or not m.alive or m.house or m.falling:
			continue
		var p := m.global_position
		if not reach.has_point(Vector2(p.x, p.z)):
			continue
		var d := p.distance_to(machine.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


func _physics_process(dt: float) -> void:
	if machine == null or not machine.alive or machine.building:
		return
	var me := machine.global_position
	var fwd := -machine.global_basis.z
	var t := _intruder()
	var goal := home
	var throttle := 0.0
	if t:
		goal = t.global_position + t.linear_velocity * 0.4
		throttle = 1.0
	elif me.distance_to(home) > 1.5:
		throttle = 0.7
	var want := goal - me
	want.y = 0.0
	if throttle == 0.0:
		want = -home * Vector3(1, 0, 1) # (at home: its nose to the middle)
	var ang := fwd.signed_angle_to(want.normalized(), Vector3.UP)
	var steer := clampf(-ang * 1.6, -1.0, 1.0)
	if absf(ang) > 2.0 and throttle > 0.0:
		throttle = 0.5
	# stuck against something: back off and come again
	if _back_t > 0.0:
		_back_t -= dt
		throttle = -0.8
		steer = -steer
	elif throttle > 0.4 and absf(machine.speed) < 0.4:
		_stuck_t += dt
		if _stuck_t > 2.0:
			_stuck_t = 0.0
			_back_t = 1.2
	else:
		_stuck_t = 0.0
	machine.throttle = throttle
	machine.steer = steer if throttle != 0.0 or absf(ang) > 0.15 else 0.0
	machine.brake = 1.0 if throttle == 0.0 and absf(ang) < 0.15 else 0.0
