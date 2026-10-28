class_name MachineTrack
extends RefCounted
## A track unit on a Machine: its five road wheels are MachineWheels (the Machine's physics runs
## them like any wheel, pressing through the belt), and this turns its sprocket and idler and runs
## the belt round as fast as its tread goes over the ground, the links scrolling on its shader, and
## cakes it with the mud it runs through.

const PITCH := 0.15 ## m a link (build_parts.py: the belt is a whole number of them)
const BELT_SHADER := preload("res://shaders/track_belt.gdshader")

var machine: Machine
var node: Node3D
var bogies: Array[MachineWheel] = []
var sprocket: Node3D
var idler: Node3D
var belt: GeometryInstance3D
var speed := 0.0 ## m/s the belt runs (+: driving forward)
var mud := 0.0
var _dist := 0.0
var _sprocket_rest := Transform3D.IDENTITY
var _idler_rest := Transform3D.IDENTITY
var _sprocket_r := 0.22
var _idler_r := 0.19

static var _belt_mat: ShaderMaterial


static func make(m: Machine, part: Node3D, id: String, xf: Transform3D) -> MachineTrack:
	var t := MachineTrack.new()
	t.machine = m
	t.node = part
	var n := int(Parts.def(id).get("bogies", 5))
	for k in n:
		# (the end ones throw the clods and the dust: five sprays a side would cost and add nothing)
		t.bogies.append(MachineWheel.make(m, part, id, xf, "Road%d" % k, k == 0 or k == n - 1))
	t.sprocket = part.find_child("Sprocket", true, false) as Node3D
	t.idler = part.find_child("Idler", true, false) as Node3D
	if t.sprocket:
		t._sprocket_rest = t.sprocket.transform
	if t.idler:
		t._idler_rest = t.idler.transform
	var b := part.find_child("Belt", true, false)
	if b is GeometryInstance3D:
		t.belt = b
		if _belt_mat == null:
			_belt_mat = ShaderMaterial.new()
			_belt_mat.shader = BELT_SHADER
		t.belt.material_override = _belt_mat
	return t


## After the physics: how fast its belt runs (its road wheels' treads on the ground; off it, the
## belt keeps turning as the engine drives it and runs down), the mud it picks up.
func step(dt: float, drive: float) -> void:
	var sum := 0.0
	var weight := 0.0
	var soft := 0.0
	for w in bogies:
		if w.contact:
			sum += w.tread_speed * w.load
			weight += w.load
			soft = maxf(soft, w.sink / 0.05)
	if weight > 0.0:
		speed = sum / weight
	else:
		speed = move_toward(speed, drive * 12.0, dt * 6.0)
	if soft > 0.05:
		mud = minf(mud + dt * 0.08 * clampf(soft, 0.0, 2.0) * clampf(absf(speed) / 3.0, 0.2, 1.0), 1.0)
	else:
		mud = maxf(mud - dt * 0.004 * absf(speed), 0.15 * mud) # (it sheds some on hard ground, never all)


func animate(dt: float) -> void:
	_dist += speed * dt
	var spin_axis := (node.transform.basis.inverse() * Vector3.UP.cross(bogies[0].roll_dir)).normalized() if not bogies.is_empty() else Vector3.RIGHT
	if sprocket:
		sprocket.transform = Transform3D(Basis(spin_axis, _dist / _sprocket_r) * _sprocket_rest.basis, _sprocket_rest.origin)
	if idler:
		idler.transform = Transform3D(Basis(spin_axis, _dist / _idler_r) * _idler_rest.basis, _idler_rest.origin)
	if belt:
		belt.set_instance_shader_parameter("scroll", fmod(_dist / PITCH, 1000.0))
		belt.set_instance_shader_parameter("mud", mud)
