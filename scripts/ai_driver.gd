class_name AiDriver
extends Node
## Drives an enemy Machine (its child) at a target machine, as a crew would: closes in while it's far,
## then keeps to its fighting range and circles (a moving target is harder to hit), turrets on the
## target with a lead for its speed (the guns lay themselves over for their rounds' drop), its aim
## wandering off the mark as a crew's does (more at range, on the move), firing when the
## target is in sight (rockets not when it's so close their burst would reach it too). Stuck (pushing and not moving), it backs out and turns; on its side, it rights itself
## after a few seconds (a crew would winch it back over).

var machine: Machine
var target: Machine
var range_near := 22.0 ## m: closer than this it backs off
var range_far := 45.0 ## m: further than this it closes in
var sight := 160.0 ## m it fires from
var circle := 1.0 ## which way it circles (+1 right)

var _stuck_t := 0.0
var _back_t := 0.0
var _flip_t := 0.0
var _retarget_t := 0.0
var _think := 0.0
var _err := Vector3.ZERO
var _wake := 1.2 ## s before it opens fire (a crew taking it in)
var _err_goal := Vector3.ZERO
var _err_t := 0.0
const AIM_ERR_BASE := 0.6 ## m off its mark however close
const AIM_ERR_PER_M := 0.035 ## and this much more a metre off (about 2 m at 50 m)


func _ready() -> void:
	machine = get_parent() as Machine
	circle = 1.0 if randf() < 0.5 else -1.0


func _physics_process(dt: float) -> void:
	if machine == null or not machine.alive or machine.building:
		return
	_retarget_t -= dt
	if not is_instance_valid(target) or not target.alive or _retarget_t <= 0.0:
		_retarget_t = 2.0
		target = _nearest_enemy()
	if target == null:
		machine.throttle = 0.0
		machine.firing = false
		return
	var me := machine.global_position
	var to := target.com_global() - me
	var dist := to.length()
	# steer: where to drive this moment (one with no guns drives straight at it: a rammer)
	var goal := target.global_position
	var rams := machine.guns.is_empty()
	if rams:
		goal = target.global_position + target.linear_velocity * clampf(dist / 15.0, 0.0, 1.5) # (where it'll be)
	elif dist < range_far:
		# round it: a point off to the side at the middle of its range
		var side := to.cross(Vector3.UP).normalized() * circle
		goal = target.global_position - to.normalized() * ((range_near + range_far) * 0.5) + side * 12.0
	var fwd := -machine.global_basis.z
	var want := (goal - me)
	want.y = 0.0
	var ang := fwd.signed_angle_to(want.normalized(), Vector3.UP) # (+: to the left)
	var steer := clampf(-ang * 1.5, -1.0, 1.0)
	var throttle := 1.0 if dist > range_near or rams else -0.6
	if absf(ang) > 2.2 and (dist > range_near or rams):
		throttle = 0.5 # (turning round)
	# stuck: backs out, turned the other way
	if _back_t > 0.0:
		_back_t -= dt
		throttle = -0.8
		steer = -steer
	elif absf(throttle) > 0.4 and absf(machine.speed) < 0.4:
		_stuck_t += dt
		if _stuck_t > 2.5:
			_stuck_t = 0.0
			_back_t = 1.8
			circle = -circle
	else:
		_stuck_t = 0.0
	machine.throttle = throttle
	machine.steer = steer
	machine.brake = 0.0
	# guns: on it, a lead for its speed
	var kind := "minigun"
	if _has("cannon"):
		kind = "cannon"
	elif _has("rockets"):
		kind = "rockets"
	var aim := target.com_global() + target.linear_velocity * MachineGun.flight_time(kind, dist)
	# a crew's aim isn't a computer's: it wanders off the mark, more the further off it is and the
	# faster either is moving, settling as they keep at it
	_err_t -= dt
	if _err_t <= 0.0:
		_err_t = randf_range(0.6, 1.3)
		var spread := AIM_ERR_BASE + dist * AIM_ERR_PER_M + (target.linear_velocity.length() + absf(machine.speed)) * 0.08
		_err_goal = Vector3(randf_range(-1, 1), randf_range(-0.4, 0.6), randf_range(-1, 1)).normalized() * spread * randf_range(0.3, 1.0)
	_err = _err.lerp(_err_goal, 1.0 - exp(-2.5 * dt))
	machine.aim_point = aim + _err
	_think -= dt
	_wake = maxf(_wake - dt, 0.0)
	if _think <= 0.0:
		_think = 0.25
		machine.firing = dist < sight and _sees(target) and _wake <= 0.0 and not (_has("rockets") and dist < 12.0 and machine.guns.size() == 1)
	# on its side or its roof: a few seconds, then back on its wheels
	if machine.global_basis.y.y < 0.3:
		_flip_t += dt
		if _flip_t > 4.0:
			_flip_t = 0.0
			var yaw := machine.global_basis.get_euler().y
			machine.linear_velocity = Vector3.ZERO
			machine.angular_velocity = Vector3.ZERO
			machine.global_transform = Transform3D(Basis(Vector3.UP, yaw), me + Vector3.UP * 2.0)
			machine.set_down()
	else:
		_flip_t = 0.0


func _has(kind: String) -> bool:
	for g in machine.guns:
		if g.kind == kind:
			return true
	return false


func _sees(t: Machine) -> bool:
	var from := machine.com_global() + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, t.com_global(), 1)
	return machine.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _nearest_enemy() -> Machine:
	var best: Machine = null
	var best_d := INF
	for n: Node in machine.get_tree().get_nodes_in_group("machines"):
		var m := n as Machine
		if m == machine or not is_instance_valid(m) or not m.alive or m.team == machine.team or m.house or m.falling:
			continue
		var d := m.global_position.distance_to(machine.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best
