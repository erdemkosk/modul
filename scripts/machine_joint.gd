class_name MachineJoint
extends RefCounted
## A joint on a Machine: a hinge, a rotor or a piston (parts of kind "joint"), and what it carries:
## everything bolted to its top (its output face) that doesn't reach the cab another way. On its key
## (E for one with no key of its own) a hinge swings what it carries up 90° about its back top edge
## (again: back down), a rotor spins it up to SPIN rad/s (again: lets it run down), a piston pushes it
## out a cell along it (again: draws it back), fast enough to throw what's on it. A joint inside what
## another carries moves with it. What it carries keeps its parts' boxes and hit points; where a
## moving part strikes something, the blow is by how fast that point's going (Machine works it out).

const SWING := 1.5708 ## rad a hinge comes up
const SWING_RATE := 3.2 ## rad/s
const SPIN := 16.0 ## rad/s a rotor runs at
const SPIN_UP := 1.4 ## s to get there
const STROKE := 0.5 ## m a piston pushes out
const PUSH_RATE := 5.0 ## m/s out
const DRAW_RATE := 1.6 ## m/s back
const DRAW := {"hinge": 1.5, "rotor": 4.0, "piston": 2.5} ## kW while it moves

var machine: Machine
var kind := "hinge"
var index := -1 ## its part
var node: Node3D
var top: Node3D
var key := 0
var members: Array[int] = [] ## the parts it carries (its own not among them)
var depth := 0 ## (how many joints it's carried by)
var locked := false ## (what it carries also reaches the cab another way: it can't move)
var pivot := Vector3.ZERO ## (machine space, at rest)
var axis := Vector3.UP
var on := false ## where it's been told to be: up, spinning, out
var angle := 0.0 ## rad (hinge, rotor) or m (piston)
var rate := 0.0 ## rad/s or m/s it's moving at now
var _top_rest: Transform3D
var _node_rest: Transform3D


static func make(m: Machine, part: Node3D, i: int, id: String, xf: Transform3D) -> MachineJoint:
	var j := MachineJoint.new()
	j.machine = m
	j.kind = str(Parts.def(id).joint)
	j.index = i
	j.node = part
	j._node_rest = xf
	j.top = part.find_child("Top", true, false) as Node3D
	if j.top:
		j._top_rest = j.top.transform
	var h := Parts.CELL * 0.5
	match j.kind:
		"hinge":
			j.pivot = xf * Vector3(0.0, h - 0.06, h - 0.06) # (its back top edge)
			j.axis = (xf.basis * Vector3.RIGHT).normalized()
		_:
			j.pivot = xf.origin
			j.axis = (xf.basis * Vector3.UP).normalized()
	return j


## Its output face's way out, in the machine's cells (what's bolted there is carried).
func out_normal() -> Vector3i:
	var n := Parts.basis_of(machine.design[index].rot) * Vector3.UP
	return Vector3i(roundi(n.x), roundi(n.y), roundi(n.z))


func toggle() -> void:
	if locked:
		return
	on = not on


## Its own motion (machine space, at rest): what it does to what it carries.
func motion() -> Transform3D:
	if kind == "piston":
		return Transform3D(Basis.IDENTITY, axis * angle)
	var b := Basis(axis, angle)
	return Transform3D(b, pivot - b * pivot)


func update(dt: float, powered: bool) -> void:
	if locked:
		rate = 0.0
		return
	var was := angle
	match kind:
		"hinge":
			var want := SWING if on else 0.0
			angle = move_toward(angle, want, SWING_RATE * dt) if powered else angle
		"rotor":
			var r := rate
			r = move_toward(r, SPIN if on and powered else 0.0, SPIN / SPIN_UP * dt * (1.0 if on else 0.5))
			angle = fmod(angle + r * dt, TAU)
			rate = r
			_show_top()
			return
		"piston":
			var want := STROKE if on else 0.0
			angle = move_toward(angle, want, (PUSH_RATE if on else DRAW_RATE) * dt) if powered else angle
	rate = (angle - was) / maxf(dt, 1e-4)
	_show_top()


## How fast a point (machine space, where it is at rest) on what it carries is going, from this joint.
func velocity_at(p: Vector3) -> Vector3:
	if kind == "piston":
		return axis * rate
	return (axis * rate).cross(p - pivot)


func draw_kw() -> float:
	return float(DRAW[kind]) if absf(rate) > 0.01 else 0.0


## Its own top moving with it (the part's node stays; the top's in its space).
func _show_top() -> void:
	if top == null:
		return
	top.transform = _node_rest.affine_inverse() * motion() * _node_rest * _top_rest


func reset() -> void:
	on = false
	angle = 0.0
	rate = 0.0
	_show_top()
