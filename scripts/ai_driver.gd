class_name AiDriver
extends Node
## Drives an enemy Machine (its child) at a target machine, as a crew would.
##
##   its target   the other side's machine it can best go after: near, and the more hurt the better
##   moving       a gunned machine closes in while it's far, then keeps to its fighting range and
##                circles (a moving target is harder to hit); badly hurt itself, it stands further
##                off. One with no guns (a rammer) drives straight at where its target will be.
##   its aim      at the part it can see that matters most (the cab, then the engines, the guns, what
##                it runs on; the more hurt the likelier), a lead for its speed (the guns lay
##                themselves over for their rounds' drop), wandering off the mark as a crew's does
##                (more at range, on the move); it fires when it can see its target (rockets not
##                when it's so close their burst would reach it too), a moment after it first sees it
##   trouble      stuck (pushing and not moving), it backs out and turns; on its side, it rights
##                itself after a few seconds (a crew would winch it back over)

var machine: Machine
var target: Machine
var range_near := 22.0 ## m: closer than this it backs off
var range_far := 45.0 ## m: further than this it closes in
var sight := 160.0 ## m it fires from
var circle := 1.0 ## which way it circles (+1 right)

var _stuck_t := 0.0
var _went_from := Vector3.ZERO ## (where it was _went_t s ago: pinned and jolted, it goes nowhere)
var _went_t := 0.0
var _back_t := 0.0
var _flip_t := 0.0
var _retarget_t := 0.0
var _think := 0.0
var _err := Vector3.ZERO
var _wake := 1.2 ## s before it opens fire (a crew taking it in)
var clumsy := 1.0 ## how far its aim wanders (1 a seasoned crew; more a greener one)
var _err_goal := Vector3.ZERO
var _err_t := 0.0
var _part: Dictionary = {} ## (the part of its target it aims at)
var _reversing := false ## (backing round: until its nose has come round)
var _part_t := 0.0
const AIM_ERR_BASE := 0.6 ## m off its mark however close
const AIM_ERR_PER_M := 0.035 ## and this much more a metre off (about 2 m at 50 m)
## How much each kind of part is worth going for (times how hurt it already is).
const WORTH := {"cab": 5.0, "engine": 4.0, "weapon": 3.0, "wheel": 2.5, "track": 2.5, "battery": 2.0}


func _ready() -> void:
	machine = get_parent() as Machine
	circle = 1.0 if randf() < 0.5 else -1.0


func _physics_process(dt: float) -> void:
	if machine == null or not machine.alive or machine.building:
		return
	if not machine.is_physics_processing():
		# held: nothing counts as stuck, and it's not backing round yet
		_stuck_t = 0.0
		_back_t = 0.0
		_reversing = false
		return
	_retarget_t -= dt
	if not is_instance_valid(target) or not target.alive or _retarget_t <= 0.0:
		_retarget_t = 2.0
		var t := _pick_target()
		if t != target:
			_part = {}
		target = t
	if target == null:
		machine.throttle = 0.0
		machine.firing = false
		return
	var me := machine.global_position
	var to := target.com_global() - me
	var dist := to.length()
	var rams := machine.guns.is_empty() or not machine.armed_any() or not machine.flippers.is_empty() # (a flipper has to get under you; out of rounds, it rams)
	var hurt := machine.health() < 0.35 and not rams
	var near := range_near * (1.6 if hurt else 1.0)
	var far := range_far * (1.4 if hurt else 1.0)
	if _only("flamer") or _only("oil"): # (a flamethrower's or an oil cask's got to be close: it fights at 5-11 m)
		near = 4.0 if _only("oil") else 5.0
		far = 8.0 if _only("oil") else 11.0
	elif _only("catapult"): # (a catapult throws from well off)
		near = 40.0
		far = 80.0
	# where to drive this moment
	var goal := target.global_position
	if rams:
		goal = target.global_position + target.linear_velocity * clampf(dist / 15.0, 0.0, 1.5) # (where it'll be)
	elif dist < far:
		# round it: a point off to the side at the middle of its range
		var side := to.cross(Vector3.UP).normalized() * circle
		goal = target.global_position - to.normalized() * ((near + far) * 0.5) + side * 12.0
	var fwd := -machine.global_basis.z
	var flat := Vector3(goal.x - me.x, 0.0, goal.z - me.z).normalized()
	var want := flat if flat != Vector3.ZERO else fwd
	var ang := fwd.signed_angle_to(want, Vector3.UP) # (+: to the left)
	var steer := clampf(-ang * 1.5, -1.0, 1.0)
	var throttle := 1.0 if dist > near or rams else -0.6
	var moving_on := dist > near or rams
	if _reversing and (absf(ang) < 1.0 or _blocked_behind()):
		_reversing = false
	elif not _reversing and absf(ang) > 2.3 and moving_on and machine.tracks.is_empty() and absf(machine.speed) < 3.0 \
			and not _blocked_behind():
		_reversing = true
	if _reversing:
		# its way's behind it: back round with the wheels the other way (a three-point turn: far
		# tighter than going round forward)
		throttle = -0.8
		steer = -steer
	elif absf(ang) > 2.2 and moving_on:
		throttle = 0.5 # (tracks: it turns round where it is)
	# spiked: struck home, it backs off for a run-up and comes again (a ram bites by its speed)
	if rams and _spiked() and dist < 3.2 and _back_t <= 0.0 and absf(machine.speed) < 4.0:
		_back_t = 1.1
	# stuck: backs out, turned the other way
	if _back_t > 0.0:
		_back_t -= dt
		throttle = -0.8
		steer = -steer
	elif absf(throttle) > 0.4 and absf(machine.speed) < 0.4 and dist > 6.0: # (not up against its target: pushing it)
		_stuck_t += dt
		if _stuck_t > 2.5:
			_stuck_t = 0.0
			_back_t = 1.8
			circle = -circle
	else:
		_stuck_t = maxf(_stuck_t - dt, 0.0) # (a jolt, a spinner's fling, doesn't free it)
	_went_t += dt
	if _went_t > 3.0:
		if _back_t <= 0.0 and absf(throttle) > 0.4 and machine.global_position.distance_to(_went_from) < 1.5 \
				and dist > 6.0: # (pushing its target along isn't being stuck)
			_back_t = 1.8 # (pushing three seconds and still where it was)
			circle = -circle
		_went_t = 0.0
		_went_from = machine.global_position
	machine.throttle = throttle
	machine.steer = steer
	machine.brake = 0.0
	_aim(dt, dist)
	# a flipper and its target over it: throw it
	if is_instance_valid(target) and machine.can_flip(target):
		machine.flip()
	# joints: a rotor spun up when it's near (a spinner), a hinge or a piston worked when it's close
	for jt in machine.joints:
		if jt.kind == "turret":
			if not jt.on:
				jt.toggle() # (a crew keeps its turret on the mark)
		elif jt.kind == "rotor":
			if jt.on != (dist < 16.0):
				jt.toggle()
		elif dist < 4.0 and not jt.on:
			jt.toggle()
		elif jt.on and (dist > 6.0 or absf(jt.angle) >= (MachineJoint.SWING if jt.kind == "hinge" else MachineJoint.STROKE) - 0.01):
			jt.toggle()
	# on its side or its roof: a few seconds, then back on its wheels (its own flipper first)
	if machine.global_basis.y.y < 0.3:
		_flip_t += dt
		if _flip_t > 1.0 and not machine.flippers.is_empty():
			if machine.flip():
				_flip_t = 0.0
		elif _flip_t > 4.0:
			_flip_t = 0.0
			var yaw := machine.global_basis.get_euler().y
			machine.linear_velocity = Vector3.ZERO
			machine.angular_velocity = Vector3.ZERO
			machine.global_transform = Transform3D(Basis(Vector3.UP, yaw), me + Vector3.UP * 2.0)
			machine.set_down()
	else:
		_flip_t = 0.0


## Something solid close behind it (a wall, cover): it can't back round there.
func _blocked_behind() -> bool:
	var back := machine.global_basis.z
	var from := machine.com_global()
	var q := PhysicsRayQueryParameters3D.create(from, from + back * 5.0, 1 | 2)
	q.exclude = [machine.get_rid()]
	return not machine.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- Aiming -------------------------------------------------------------------------------------

## Its guns: on the part it's chosen of its target, a lead for its speed, a crew's wander.
func _aim(dt: float, dist: float) -> void:
	if machine.guns.is_empty():
		machine.firing = false
		return
	var kind := "minigun"
	if _has("cannon"):
		kind = "cannon"
	elif _has("rockets"):
		kind = "rockets"
	_part_t -= dt
	if _part_t <= 0.0 or (not _part.is_empty() and not target.design.has(_part)):
		_part_t = 0.8
		_part = _pick_part()
	var mark := target.com_global()
	if not _part.is_empty() and target.design.has(_part):
		mark = target.global_transform * Parts.xform_of(_part.id, _part.at, _part.rot).origin
	var aim := mark + target.linear_velocity * MachineGun.flight_time(kind, dist)
	# a crew's aim isn't a computer's: it wanders off the mark, more the further off it is and the
	# faster either is moving, settling as they keep at it
	_err_t -= dt
	if _err_t <= 0.0:
		_err_t = randf_range(0.6, 1.3)
		var spread := (AIM_ERR_BASE + dist * AIM_ERR_PER_M + (target.linear_velocity.length() + absf(machine.speed)) * 0.08) * clumsy
		_err_goal = Vector3(randf_range(-1, 1), randf_range(-0.4, 0.6), randf_range(-1, 1)).normalized() * spread * randf_range(0.3, 1.0)
	_err = _err.lerp(_err_goal, 1.0 - exp(-2.5 * dt))
	machine.aim_point = aim + _err
	_think -= dt
	_wake = maxf(_wake - dt, 0.0)
	if _think <= 0.0:
		_think = 0.25
		machine.firing = dist < sight and _sees(target) and _wake <= 0.0 and not (_has("rockets") and dist < 12.0 and machine.guns.size() == 1)


## The part of its target worth most that it can see from where its guns are: its worth by kind,
## times how hurt it is already; seen if a line from the guns meets that part first. {} if none.
func _pick_part() -> Dictionary:
	var from := machine.com_global() + Vector3.UP * (machine.top_y * 0.6 + 0.4)
	var cands: Array = []
	for p: Dictionary in target.design:
		var w: float = WORTH.get(str(Parts.def(p.id).kind), 1.0)
		var frac := clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0)
		cands.append([w * (1.4 - frac * 0.6), p])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var space := machine.get_world_3d().direct_space_state
	for k in mini(cands.size(), 8):
		var p: Dictionary = cands[k][1]
		var at := target.global_transform * Parts.xform_of(p.id, p.at, p.rot).origin
		var q := PhysicsRayQueryParameters3D.create(from, at + (at - from).normalized() * 0.3, 1 | 2)
		q.exclude = [machine.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.collider != target:
			continue
		var i: int = target.call("_part_near", (hit.position as Vector3) + (at - from).normalized() * 0.06)
		if i >= 0 and target.design[i] == p:
			return p
	return {}


# --- What to go after ---------------------------------------------------------------------------

## Rams on its nose (two or more spikes).
func _spiked() -> bool:
	var n := 0
	for p: Dictionary in machine.design:
		if p.id == "spike":
			n += 1
	return n >= 2


## Every gun it has is of `kind`.
func _only(kind: String) -> bool:
	if machine.guns.is_empty():
		return false
	for g in machine.guns:
		if g.kind != kind:
			return false
	return true


func _has(kind: String) -> bool:
	for g in machine.guns:
		if g.kind == kind:
			return true
	return false


func _sees(t: Machine) -> bool:
	var from := machine.com_global() + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, t.com_global(), 1)
	return machine.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The other side's machine it can best go after: near, and the more hurt the better (a hurt one is
## worth 20 m of distance).
func _pick_target() -> Machine:
	var best: Machine = null
	var best_s := INF
	for n: Node in machine.get_tree().get_nodes_in_group("machines"):
		var m := n as Machine
		if m == machine or not is_instance_valid(m) or not m.alive or m.team == machine.team:
			continue
		var s := m.global_position.distance_to(machine.global_position) - (1.0 - m.health()) * 20.0
		if s < best_s:
			best_s = s
			best = m
	return best
