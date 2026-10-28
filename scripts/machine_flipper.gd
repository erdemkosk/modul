class_name MachineFlipper
extends RefCounted
## A flipper on a Machine (the part "flipper"): a plate hinged at its back, flung up by a pneumatic
## ram. Fired (F; the crews when their target's on it), the flap snaps up in a tenth of a second and
## whatever's standing on it is thrown: lifted at that end and rolled over, the harder the lighter it
## is (and the machine firing it pushed down into the ground). On its back or its side, a machine
## fires it into the ground and rights itself with it, the only way back up in the cage. The ram runs
## on air its compressor makes from the battery: a flip takes FLIP_KJ, then RECHARGE s to fill again.

const ANGLE := 1.2 ## rad the flap comes up to
const UP_T := 0.09 ## s it takes to come up
const HOLD_T := 0.25
const DOWN_T := 0.6
const RECHARGE := 3.0 ## s for the air to come back
const FLIP_KJ := 6.0 ## the compressor's draw for a flip
const THROW_DV := 6.5 ## m/s up it gives what it throws (at the flap)
const MAX_THROW := 4200.0 ## kg: past this it only lifts it a little
const RIGHT_DV := 5.5 ## m/s it gives itself, righting
const ROLL := 5.0 ## rad/s it turns itself righting
const THROW_ROLL := 2.4 ## rad/s it rolls what it throws (about half a turn in the air: onto its back)

var machine: Machine
var node: Node3D
var flap: Node3D
var air := 1.0 ## 0..1: full, it can fire
var condition := 1.0
var key := 0 ## the key it fires on (0: F)
var _rest: Transform3D
var _t := -1.0 ## s since it fired (-1: down)


static func make(m: Machine, part: Node3D) -> MachineFlipper:
	var f := MachineFlipper.new()
	f.machine = m
	f.node = part
	f.flap = part.find_child("Flap", true, false) as Node3D
	if f.flap:
		f._rest = f.flap.transform
	return f


func ready() -> bool:
	return air >= 1.0 and _t < 0.0 and condition > 0.25


## Where it throws from: the middle of the plate, a little above it (world).
func throw_point() -> Vector3:
	return node.global_transform * Vector3(0.0, 0.3, -0.15)


## What would be thrown if it fired now: the other machines over the plate.
func over_it() -> Array[Machine]:
	var out: Array[Machine] = []
	if not is_instance_valid(node):
		return out
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 0.9, 1.7)
	q.shape = box
	q.transform = Transform3D(node.global_basis, node.global_transform * Vector3(0.0, 0.55, -0.2))
	q.collision_mask = 2
	q.exclude = [machine.get_rid()]
	for hit: Dictionary in machine.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var b := hit.collider as Machine
		if b and b.alive and not b in out:
			out.append(b)
	return out


## Fires it (if it's ready): throws what's on it, or, on its back, rights its own machine. True if
## it fired.
func fire() -> bool:
	if not ready() or not machine.powered or machine.energy_kj < FLIP_KJ:
		return false
	machine.energy_kj -= FLIP_KJ
	air = 0.0
	_t = 0.0
	var at := throw_point()
	var up_world := node.global_basis.y
	if machine.global_basis.y.y < 0.3:
		# on its back or side: the flap drives into the ground and rolls it back over
		machine.apply_impulse(Vector3.UP * machine.total_mass * RIGHT_DV * condition, at - machine.global_position)
		# and turned back toward its wheels (about the line that takes its top toward the sky)
		var axis := machine.global_basis.y.cross(Vector3.UP)
		if axis.length() < 0.2:
			axis = machine.global_basis.x # (flat on its back: over its side, end over end)
		machine.angular_velocity += axis.normalized() * ROLL * condition
		machine.set_down()
	else:
		var dir := (up_world * 0.85 - node.global_basis.z * 0.35).normalized() # (up, and on away from it)
		for m in over_it():
			var k := clampf(MAX_THROW / maxf(m.total_mass, 1.0), 0.2, 1.0) * condition
			var j := m.total_mass * THROW_DV * k
			m.apply_impulse(dir * j, at - m.global_position)
			# rolled over, away from the flap: its near side goes up, its far side down
			var away := m.global_position - at
			away.y = 0.0
			if away.length() < 0.1:
				away = -node.global_basis.z
			m.angular_velocity += Vector3.UP.cross(away.normalized()) * THROW_ROLL * k
			m.last_hit_by = machine
			m.last_hit_kind = "çevirici"
			# (and down into the ground, its own end)
			machine.apply_impulse(-dir * j * 0.3, at - machine.global_position)
	if Combat.current:
		Combat.current.sound("res://assets/audio/weapons/flip_air.wav", at, 4.0, randf_range(0.95, 1.05))
		Combat.current.sound("res://assets/audio/build/heavy_01.wav", at, 2.0, 1.3)
		Combat.current.shake(at, 0.25, machine, 2.0)
	return true


func update(dt: float, powered: bool) -> void:
	if _t >= 0.0:
		_t += dt
		if _t > UP_T + HOLD_T + DOWN_T:
			_t = -1.0
	elif air < 1.0 and powered:
		air = minf(air + dt / RECHARGE, 1.0)
	if flap == null:
		return
	var a := 0.0
	if _t >= 0.0:
		if _t < UP_T:
			a = ANGLE * _t / UP_T
		elif _t < UP_T + HOLD_T:
			a = ANGLE
		else:
			a = ANGLE * (1.0 - smoothstep(0.0, 1.0, (_t - UP_T - HOLD_T) / DOWN_T))
	flap.transform = Transform3D(_rest.basis * Basis(Vector3.RIGHT, a), _rest.origin)


## kW its compressor draws now (filling).
func draw_kw() -> float:
	return FLIP_KJ / RECHARGE if air < 1.0 else 0.0
