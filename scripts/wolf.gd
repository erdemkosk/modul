class_name Wolf
extends Villager
## A wolf: a villager's walk and bite (Raids gives it its plans) in a grey wolf's body, low and
## long, on four legs, its tail out behind. Quick, and quicker still running someone down.


func _build_look() -> void:
	var fur := StandardMaterial3D.new()
	fur.albedo_color = [Color(0.36, 0.34, 0.31), Color(0.27, 0.25, 0.23), Color(0.45, 0.41, 0.36)][randi() % 3]
	fur.roughness = 1.0
	_tunic = fur
	speed_mul = 1.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.07, 0.07)
	_torso = Node3D.new()
	add_child(_torso)
	_box(_torso, Vector3(0.36, 0.38, 1.05), Vector3(0, 0.72, 0), fur)
	_box(_torso, Vector3(0.4, 0.42, 0.4), Vector3(0, 0.8, -0.42), fur) # (the ruff)
	var head := Node3D.new()
	head.position = Vector3(0, 0.88, -0.7)
	_torso.add_child(head)
	_box(head, Vector3(0.26, 0.24, 0.3), Vector3(0, 0, -0.05), fur)
	_box(head, Vector3(0.14, 0.12, 0.22), Vector3(0, -0.05, -0.28), fur)
	_box(head, Vector3(0.06, 0.05, 0.05), Vector3(0, -0.02, -0.4), dark)
	for s in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var em := CylinderMesh.new()
		em.top_radius = 0.0
		em.bottom_radius = 0.05
		em.height = 0.12
		em.radial_segments = 4
		ear.mesh = em
		ear.material_override = fur
		ear.position = Vector3(s * 0.08, 0.16, 0.02)
		head.add_child(ear)
		for z in [-0.38, 0.38]:
			var hip := Node3D.new()
			hip.position = Vector3(s * 0.12, 0.58, z)
			add_child(hip)
			_box(hip, Vector3(0.08, 0.58, 0.09), Vector3(0, -0.29, 0), fur)
			_legs.append(hip)
	var tail := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.03
	tm.bottom_radius = 0.07
	tm.height = 0.5
	tm.radial_segments = 5
	tail.mesh = tm
	tail.material_override = fur
	tail.transform = Transform3D(Basis(Vector3.RIGHT, 1.1), Vector3(0, 0.75, 0.68))
	_torso.add_child(tail)


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)


func arm_with(_kind: String) -> void:
	pass


func _animate(dt: float, walking: bool) -> void:
	var k := 1.0 - exp(-14.0 * dt)
	for i in _legs.size():
		var swing := sin(_phase * 1.3 + (PI if i % 3 == 0 else 0.0)) * 0.7 if walking else 0.0
		_legs[i].rotation.x = lerpf(_legs[i].rotation.x, swing, k)
	var lunge := 0.0
	if _anim == "strike":
		lunge = sin(Time.get_ticks_msec() * 0.012) * 0.25
	_torso.position.z = lerpf(_torso.position.z, -lunge, k)
	_torso.position.y = absf(sin(_phase * 1.3)) * 0.04 if walking else 0.0
