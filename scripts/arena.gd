class_name Arena
extends Node3D
## The proving ground built as an arena round the test zones: a ring of concrete jersey barriers
## (R m out) with a chain-link catch fence on posts over it and tyre stacks against it, a gate on
## the west where the other side drives in, a grandstand on the north and the south, a floodlight
## mast on each diagonal (lit at night), the ramps of three steepnesses, and cover to fight round:
## a broken fort of concrete blocks, containers, sandbag walls, crates and drums to the north, a
## container yard by the gate, crates and drums by the ramps, a slalom of blocks. All the cover is
## Breakable.

const R := 92.0 ## m: the ring's radius
const GATE_ANGLE := PI ## (the west)
const GATE_GAP := 14.0 ## m of the ring left open for it
const A := "res://assets/arena/"

var terrain: Node
var _lights: Array[SpotLight3D] = []
var _lamp_glows: Array[Node3D] = []


func _ready() -> void:
	_ring()
	_fence()
	_towers()
	_stands()
	_gate()
	_ramps()
	_cover()


func _h(x: float, z: float) -> float:
	return float(terrain.call("height_at", x, z))


## A model's own mesh with its painted materials on it (for MultiMeshes).
func _painted_mesh(file: String) -> Mesh:
	var n := (load(A + file) as PackedScene).instantiate() as Node3D
	PaintedLook.apply(n)
	var mi := n.find_child("Part", true, false) as MeshInstance3D
	var m := mi.mesh.duplicate() as Mesh
	for s in m.get_surface_count():
		var mat := mi.get_surface_override_material(s)
		if mat:
			(m as ArrayMesh).surface_set_material(s, mat)
	n.free()
	return m


func _place(file: String, xf: Transform3D) -> Node3D:
	var n := (load(A + file) as PackedScene).instantiate() as Node3D
	PaintedLook.apply(n)
	n.transform = xf
	add_child(n)
	return n


func _in_gate(ang: float) -> bool:
	return absf(angle_difference(ang, GATE_ANGLE)) < GATE_GAP * 0.5 / R


## The wall: barriers end to end round the ring, each a box to hit; tyre stacks against it.
func _ring() -> void:
	var n := int(ceil(TAU * R / 3.02))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _painted_mesh("barrier.glb")
	var xfs: Array[Transform3D] = []
	var body := StaticBody3D.new()
	add_child(body)
	for i in n:
		var ang := TAU * i / n
		if _in_gate(ang):
			continue
		var p := Vector3(cos(ang) * R, 0.0, sin(ang) * R)
		p.y = _h(p.x, p.z) - 0.03
		# its length along the ring (the model's length is x)
		var xf := Transform3D(Basis(Vector3.UP, -ang - PI * 0.5), p)
		xfs.append(xf)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.0, 0.8, 0.6)
		cs.shape = box
		cs.transform = xf * Transform3D(Basis.IDENTITY, Vector3.UP * 0.4)
		body.add_child(cs)
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# tyre stacks every so often just inside it
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.mesh = _painted_mesh("tyres.glb")
	var tx: Array[Transform3D] = []
	for i in 40:
		var ang := TAU * (i + 0.5) / 40
		if _in_gate(ang) or absf(angle_difference(ang, GATE_ANGLE)) < 0.2:
			continue
		for k in 2:
			var a2 := ang + (k - 0.5) * 0.014
			var p := Vector3(cos(a2) * (R - 0.95), 0.0, sin(a2) * (R - 0.95))
			p.y = _h(p.x, p.z)
			tx.append(Transform3D(Basis(Vector3.UP, randf() * TAU), p))
			var cs := CollisionShape3D.new()
			var cy := CylinderShape3D.new()
			cy.radius = 0.55
			cy.height = 1.3
			cs.shape = cy
			cs.position = p + Vector3.UP * 0.65
			body.add_child(cs)
	tm.instance_count = tx.size()
	for i in tx.size():
		tm.set_instance_transform(i, tx[i])
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tm
	add_child(tmi)


## Posts round the ring outside the wall, the chain-link over them, rails top and bottom.
func _fence() -> void:
	var r := R + 0.55
	var post := CylinderMesh.new()
	post.top_radius = 0.045
	post.bottom_radius = 0.045
	post.height = 4.2
	post.radial_segments = 8
	var galv := StandardMaterial3D.new()
	galv.albedo_color = Color(0.55, 0.56, 0.56)
	galv.metallic = 0.7
	galv.roughness = 0.45
	post.material = galv
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post
	var xfs: Array[Transform3D] = []
	var n := int(TAU * r / 4.0)
	for i in n:
		var ang := TAU * i / n
		if _in_gate(ang):
			continue
		var p := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		xfs.append(Transform3D(Basis.IDENTITY, p + Vector3.UP * (_h(p.x, p.z) + 2.1)))
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# the net: an open band round the ring (the gate's gap left out of it)
	var gap := GATE_GAP / r
	var seg := 180
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var a0 := GATE_ANGLE + gap * 0.5
	var span := TAU - gap
	for i in seg + 1:
		var ang := a0 + span * i / seg
		var p := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var g := _h(p.x, p.z)
		verts.append_array([p + Vector3.UP * (g + 0.85), p + Vector3.UP * (g + 4.1)])
		uvs.append_array([Vector2(float(i) / seg, 0.0), Vector2(float(i) / seg, 1.0)])
		normals.append_array([-p.normalized(), -p.normalized()])
		if i < seg:
			var k := i * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/chain_link.gdshader")
	mat.set_shader_parameter("around", span * r)
	mat.set_shader_parameter("height", 3.25)
	var net := MeshInstance3D.new()
	net.mesh = mesh
	net.material_override = mat
	net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(net)


## A floodlight mast on each diagonal, its lamps aimed at the middle.
func _towers() -> void:
	for k in 4:
		var ang := PI * 0.25 + k * PI * 0.5
		var p := Vector3(cos(ang) * (R + 7.0), 0.0, sin(ang) * (R + 7.0))
		p.y = _h(p.x, p.z)
		# the lamp bank faces the model's +Y (Godot -Z): turn that toward the middle
		var face := Basis.looking_at(Vector3(-p.x, 0.0, -p.z).normalized(), Vector3.UP)
		var t := _place("tower.glb", Transform3D(face, p))
		var glow := t.find_child("Lamps", true, false) as Node3D
		if glow:
			_lamp_glows.append(glow)
		var l := SpotLight3D.new()
		l.light_color = Color(1.0, 0.95, 0.86)
		l.light_energy = 22.0
		l.spot_range = 180.0
		l.spot_angle = 58.0
		l.spot_attenuation = 0.6
		l.spot_angle_attenuation = 0.8
		l.shadow_enabled = false
		add_child(l)
		l.global_position = p + Vector3.UP * 21.5 + face * Vector3(0, 0, -1.2)
		l.look_at(Vector3(p.x, 0.0, p.z) * 0.35, Vector3.UP) # (a third of the way across: each lights its own quarter and the middle)
		_lights.append(l)
	set_night(false)


## The floodlights on (night) or off.
func set_night(on: bool) -> void:
	for l in _lights:
		l.visible = on
	for g in _lamp_glows:
		g.visible = on


## A grandstand north and south, outside the ring, facing in.
func _stands() -> void:
	for ang: float in [PI * 0.5, -PI * 0.5]:
		var p := Vector3(cos(ang) * (R + 4.0), 0.0, sin(ang) * (R + 4.0))
		p.y = _h(p.x, p.z)
		var face := Basis.looking_at(Vector3(-p.x, 0.0, -p.z).normalized(), Vector3.UP)
		var s := _place("stand.glb", Transform3D(face, p))
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(24.0, 4.0, 7.0)
		cs.shape = box
		cs.position = Vector3(0.0, 2.0, 3.4)
		body.add_child(cs)
		s.add_child(body)


## The gate on the west: a pillar either side of the gap, their leaves swung open.
func _gate() -> void:
	var c := Vector3(cos(GATE_ANGLE) * R, 0.0, sin(GATE_ANGLE) * R)
	var along := Vector3(-sin(GATE_ANGLE), 0.0, cos(GATE_ANGLE)) # (round the ring)
	var out := c.normalized()
	for s: float in [-1.0, 1.0]:
		var p := c + along * s * (GATE_GAP * 0.5 + 0.4)
		p.y = _h(p.x, p.z)
		# the leaf hangs off the pillar's +x, away from the gap, swung open (one out, one in)
		var b := Basis(along * s, Vector3.UP, -out * s)
		var g := _place("gate.glb", Transform3D(b, p))
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.4, 8.0, 1.4)
		cs.shape = box
		cs.position = Vector3.UP * 4.0
		body.add_child(cs)
		g.add_child(body)


## Where the other side comes in: just inside the gate.
func gate_point(k: int) -> Transform3D:
	var c := Vector3(cos(GATE_ANGLE) * (R - 10.0 - (k / 3) * 9.0), 0.0, sin(GATE_ANGLE) * (R - 10.0))
	c += Vector3(-sin(GATE_ANGLE), 0.0, cos(GATE_ANGLE)) * ((k % 3) - 1) * 5.0
	c.y = _h(c.x, c.z) + 2.5
	return Transform3D(Basis.looking_at(-c.normalized() * Vector3(1, 0, 1), Vector3.UP), c)


## The ramps of three steepnesses, as they were.
func _ramps() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.48, 0.46, 0.42)
	mat.roughness = 0.9
	for it: Array in [[Vector3(-12, 0, -75), Vector3(8, 0.3, 14), 12.0], [Vector3(0, 0, -75), Vector3(8, 0.3, 12), 20.0],
			[Vector3(12, 0, -75), Vector3(8, 0.3, 10), 28.0]]:
		var c: Vector3 = it[0]
		c.y = _h(c.x, c.z)
		var size: Vector3 = it[1]
		var tilt := deg_to_rad(float(it[2]))
		var xf := Transform3D(Basis(Vector3.RIGHT, tilt), c + Vector3.UP * (size.z * 0.5 * sin(tilt) - 0.15))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = xf
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		mi.transform = xf
		body.add_child(mi)


func _breakable(kind: String, x: float, z: float, yaw := 0.0, stack := 0.0) -> Breakable:
	var b := Breakable.make(kind, Transform3D(Basis(Vector3.UP, yaw), Vector3(x, _h(x, z) + stack, z)))
	add_child(b)
	return b


## Things to fight round, all of them breakable.
func _cover() -> void:
	# the fort to the north: two broken walls of blocks, a container on its side, sandbags, crates, drums
	for i in 6:
		if i == 2:
			continue # (the breach)
		_breakable("block", -14.0 + i * 2.05, 60.0)
		if i % 2 == 0:
			_breakable("block", -14.0 + i * 2.05, 60.0, 0.0, 1.2)
	for i in 4:
		_breakable("block", 4.0, 62.5 + i * 2.05, PI * 0.5)
	_breakable("container", -4.0, 72.0, 0.2)
	_breakable("container", -4.0, 72.0, 0.2, 2.59)
	_breakable("container", 10.0, 70.0, 1.4)
	for i in 3:
		_breakable("sandbags", -22.0 + i * 3.1, 55.0, 0.0)
		_breakable("sandbags", 18.0, 52.0 + i * 3.1, PI * 0.5)
	for i in 5:
		_breakable("crate", -18.0 + (i % 3) * 1.25, 66.0 + (i / 3) * 1.3, randf() * 0.2, 0.0)
	_breakable("crate", -17.4, 66.0, 0.1, 1.2)
	for i in 4:
		_breakable("drum", 12.0 + (i % 2) * 0.7, 58.0 + (i / 2) * 0.7, randf() * TAU)
	# the container yard either side of the lane in from the gate (the lane itself, z -9..9, clear)
	for z: float in [-36.0, -22.0, 22.0, 36.0]:
		_breakable("container", -70.0, z, PI * 0.5 + randf_range(-0.1, 0.1))
	_breakable("container", -60.0, -15.0, 0.0)
	_breakable("container", -60.0, 15.0, 0.0)
	_breakable("container", -60.0, 15.0, 0.05, 2.59)
	for i in 6:
		_breakable("drum", -66.0 + (i % 3) * 0.7, 12.0 + (i / 3) * 0.7, randf() * TAU)
	for i in 5:
		_breakable("barrier", -78.0, -40.0 + i * 3.1, PI * 0.5)
	# crates and drums by the ramps
	for i in 8:
		_breakable("crate", 30.0 + (i % 4) * 1.25, -70.0 + (i / 4) * 1.25)
	for i in 3:
		_breakable("crate", 30.6 + i * 1.25, -70.0, 0.0, 1.2)
	for i in 5:
		_breakable("drum", 38.0 + (i % 3) * 0.75, -64.0 + (i / 3) * 0.75, randf() * TAU)
	# a slalom of blocks on the north-east (where the old row stood)
	for k in 6:
		_breakable("block", 30.0 + k * 9.0, 40.0 + (k % 2) * 6.0, k * 0.4)
	# jersey barriers as a chicane south of the asphalt
	for k in 4:
		_breakable("barrier", -40.0 + k * 6.0, -64.0 + (k % 2) * 4.0, 0.3 * (k % 2))
