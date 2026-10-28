class_name CageArena
extends Node3D
## The cage: a square floor HALF m each way of the middle, walled with concrete to 1.2 m and a steel
## catch fence on posts over it to 5.5 m, a hazard stripe round its edge, a red corner and a blue one
## to start from; outside, a grandstand on each side full of people (a MultiMesh of seated figures
## that sway, and come up on their feet cheering with `excite`), a floodlight mast at each corner.
##
## Each round lays its own floor (set_round): the ground's zones (mud, bog, ice, gravel, snow), and
## its hazards — spike strips that bite the parts that run over them, flame vents that roar up every
## few seconds, chain-link fence islands to fight round, breakable blocks and drums.

const HALF := 24.0
const A := "res://assets/arena/"
const SPIKE_DAMAGE := 22.0 ## hp a bite
const FIRE_DAMAGE := 26.0 ## hp a lick at the middle

var terrain: TestTerrain
var crowd_mat: ShaderMaterial
var _hazards: Node3D
var _spikes: Array[Area3D] = []
var _vents: Array[Dictionary] = [] ## {area, fire, light, t, period, offset}
var _bite := {} ## Machine -> s till the spikes bite it again
var _t := 0.0


func _ready() -> void:
	_floor_marks()
	_walls()
	_stands()
	_masts()
	_hazards = Node3D.new()
	_hazards.name = "Hazards"
	add_child(_hazards)


func _h(x: float, z: float) -> float:
	return float(terrain.height_at(x, z))


func _place(file: String, xf: Transform3D) -> Node3D:
	var n := (load(A + file) as PackedScene).instantiate() as Node3D
	PaintedLook.apply(n)
	n.transform = xf
	add_child(n)
	return n


static func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(size: Vector3, xf: Transform3D, mat: Material, body: StaticBody3D = null) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.transform = xf
	add_child(mi)
	if body:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = xf
		body.add_child(cs)


# --- The build ----------------------------------------------------------------------------------

## The hazard stripe round the floor's edge and the two starting corners, painted on it.
func _floor_marks() -> void:
	var yellow := _mat(Color(0.8, 0.6, 0.08), 0.7)
	var black := _mat(Color(0.05, 0.05, 0.05), 0.7)
	var n := 24
	for side in 4:
		for k in n:
			var along := -HALF + (k + 0.5) * HALF * 2.0 / n
			var p := Vector3(along, 0.0, -HALF + 0.6)
			var b := Basis(Vector3.UP, side * PI * 0.5)
			p = b * p
			p.y = _h(p.x, p.z) + 0.02
			_box(Vector3(HALF * 2.0 / n - 0.05, 0.02, 0.6), Transform3D(b, p), yellow if k % 2 == 0 else black)
	for c: Array in [[Vector2(-1, -1), Color(0.75, 0.12, 0.1)], [Vector2(1, 1), Color(0.12, 0.3, 0.75)]]:
		var at: Vector2 = c[0] * (HALF - 4.5)
		var y := _h(at.x, at.y) + 0.025
		var m := _mat(c[1], 0.6)
		for e: Array in [[Vector3(6, 0.02, 0.4), Vector3(0, 0, -3)], [Vector3(6, 0.02, 0.4), Vector3(0, 0, 3)],
				[Vector3(0.4, 0.02, 6), Vector3(-3, 0, 0)], [Vector3(0.4, 0.02, 6), Vector3(3, 0, 0)]]:
			_box(e[0], Transform3D(Basis.IDENTITY, Vector3(at.x, y, at.y) + (e[1] as Vector3)), m)


## The low concrete wall, the posts, the chain-link over it, the top rail.
func _walls() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var concrete := _mat(Color(0.5, 0.48, 0.45), 0.92)
	var steel := _mat(Color(0.55, 0.56, 0.56), 0.45, 0.7)
	var net_mat := ShaderMaterial.new()
	net_mat.shader = preload("res://shaders/chain_link.gdshader")
	net_mat.set_shader_parameter("around", HALF * 8.0)
	net_mat.set_shader_parameter("height", 4.3)
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		var mid := b * Vector3(0.0, 0.0, -HALF - 0.2)
		mid.y = _h(mid.x, mid.z)
		_box(Vector3(HALF * 2.0 + 0.8, 1.2, 0.4), Transform3D(b, mid + Vector3.UP * 0.6), concrete, body)
		# the fence's collision: so nothing leaves over the wall
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(HALF * 2.0 + 0.8, 4.3, 0.1)
		cs.shape = bs
		cs.transform = Transform3D(b, mid + Vector3.UP * 3.35)
		body.add_child(cs)
		for k in 13:
			var p := b * Vector3(-HALF + k * HALF * 2.0 / 12.0, 0.0, -HALF - 0.2)
			p.y = _h(p.x, p.z)
			var post := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.07
			cm.bottom_radius = 0.07
			cm.height = 5.6
			cm.material = steel
			post.mesh = cm
			post.position = p + Vector3.UP * 2.8
			add_child(post)
		_box(Vector3(HALF * 2.0 + 0.4, 0.1, 0.1), Transform3D(b, mid + Vector3.UP * 5.5), steel)
		# the net
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var normals := PackedVector3Array()
		var a0 := b * Vector3(-HALF, 0, -HALF - 0.2)
		var a1 := b * Vector3(HALF, 0, -HALF - 0.2)
		for e: Array in [[a0, 0.0], [a1, 1.0]]:
			var pp: Vector3 = e[0]
			verts.append_array([pp + Vector3.UP * 1.2, pp + Vector3.UP * 5.5])
			uvs.append_array([Vector2((side + float(e[1])) / 4.0, 0.0), Vector2((side + float(e[1])) / 4.0, 1.0)])
			normals.append_array([b * Vector3.BACK, b * Vector3.BACK])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 3, 2])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var net := MeshInstance3D.new()
		net.mesh = mesh
		net.material_override = net_mat
		net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(net)


## Two grandstands a side, facing in, full of people.
func _stands() -> void:
	var seats: Array[Transform3D] = []
	for side in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5) # (side 0: north, the stand's front facing +z, in)
		for k in 2:
			var along := (k - 0.5) * 24.5
			var p := b * Vector3(along, 0.0, -HALF - 5.5)
			p.y = _h(p.x, p.z)
			var face := b * Basis(Vector3.UP, PI) # (the model's front, -z, toward the middle)
			var s := _place("stand.glb", Transform3D(face, p))
			var bd := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(24.0, 4.0, 7.0)
			cs.shape = bs
			cs.position = Vector3(0.0, 2.0, 3.4)
			bd.add_child(cs)
			s.add_child(bd)
			# the seats (as tools/blender/build_arena.py lays them: rows back and up, 16 a row, two aisles)
			for row in 8:
				for i in 16:
					if i in [5, 10] or randf() < 0.12:
						continue
					var x := -12.0 + 0.75 + i * 22.5 / 15.0 + randf_range(-0.08, 0.08)
					var local := Vector3(x, row * 0.45 + 0.68, row * 0.8 - 0.1)
					seats.append(Transform3D(face * Basis(Vector3.UP, randf_range(-0.15, 0.15)), p + face * local))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _figure()
	mm.instance_count = seats.size()
	var shirts := [Color(0.7, 0.15, 0.12), Color(0.15, 0.3, 0.65), Color(0.85, 0.75, 0.2), Color(0.2, 0.45, 0.25),
		Color(0.9, 0.9, 0.88), Color(0.15, 0.15, 0.17), Color(0.85, 0.45, 0.15), Color(0.45, 0.25, 0.5)]
	for i in seats.size():
		mm.set_instance_transform(i, seats[i])
		var c: Color = shirts[randi() % shirts.size()]
		mm.set_instance_color(i, c.lerp(Color(randf(), randf(), randf()), 0.15))
		mm.set_instance_custom_data(i, Color(randf(), randf(), 0, 0))
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = preload("res://shaders/crowd.gdshader")
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = crowd_mat
	add_child(mmi)


## A seated figure (its feet at the origin, facing -z): body, legs forward, head, arms hanging; the
## part each vertex belongs to in UV.x for crowd.gdshader, which side an arm's on in UV.y.
static func _figure() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [
		[_capsule(0.16, 0.5), Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0.02)), 0.0, 0.0],
		[_box_m(Vector3(0.3, 0.13, 0.42)), Transform3D(Basis.IDENTITY, Vector3(0, 0.08, -0.17)), 0.25, 0.0],
		[_box_m(Vector3(0.28, 0.42, 0.12)), Transform3D(Basis.IDENTITY, Vector3(0, -0.15, -0.36)), 0.25, 0.0],
		[_sphere(0.11), Transform3D(Basis.IDENTITY, Vector3(0, 0.66, 0.0)), 0.5, 0.0],
		[_capsule(0.05, 0.42), Transform3D(Basis.IDENTITY, Vector3(-0.21, 0.26, 0.0)), 1.0, 0.0],
		[_capsule(0.05, 0.42), Transform3D(Basis.IDENTITY, Vector3(0.21, 0.26, 0.0)), 1.0, 1.0],
	]
	for e: Array in parts:
		var arr: Array = (e[0] as Mesh).surface_get_arrays(0)
		var xf: Transform3D = e[1]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for k in idx.size():
			var j := idx[k]
			st.set_normal(xf.basis * ns[j])
			st.set_uv(Vector2(float(e[2]), float(e[3])))
			st.set_color(Color.WHITE)
			st.add_vertex(xf * vs[j])
	return st.commit()


static func _capsule(r: float, h: float) -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 2
	return m


static func _sphere(r: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m


static func _box_m(s: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = s
	return m


## A floodlight mast at each corner, lit, aimed in.
func _masts() -> void:
	for k in 4:
		var ang := PI * 0.25 + k * PI * 0.5
		var p := Vector3(cos(ang), 0.0, sin(ang)) * (HALF * 1.41 + 9.0)
		p.y = _h(p.x, p.z)
		var face := Basis.looking_at(Vector3(-p.x, 0.0, -p.z).normalized(), Vector3.UP)
		_place("tower.glb", Transform3D(face, p))
		var l := SpotLight3D.new()
		l.light_color = Color(1.0, 0.96, 0.88)
		l.light_energy = 26.0
		l.spot_range = 90.0
		l.spot_angle = 34.0
		l.spot_attenuation = 0.5
		l.shadow_enabled = k == 0 # (one casts: the cars' shadows on the floor; the others fill)
		add_child(l)
		l.global_position = p + Vector3.UP * 21.5
		l.look_at(Vector3(p.x, 0.0, p.z) * 0.1, Vector3.UP)


## The audience: 0 sitting .. 1 on their feet.
func set_excite(v: float) -> void:
	if crowd_mat:
		crowd_mat.set_shader_parameter("excite", clampf(v, 0.0, 1.0))


# --- A round's floor -----------------------------------------------------------------------------

## Lays the floor for a round: {zones: [[Rect2, preset]], spikes: [Rect2], vents: [Vector2],
## fences: [[Vector2 from, Vector2 to]], blocks: [Vector2], drums: [Vector2]}.
func set_round(layout: Dictionary) -> void:
	for c in _hazards.get_children():
		c.queue_free()
	_spikes.clear()
	_vents.clear()
	_bite.clear()
	var zones := []
	for z: Array in layout.get("zones", []):
		zones.append([z[0], Surface.preset(z[1])])
	terrain.set_zones(zones)
	for r: Rect2 in layout.get("spikes", []):
		_spike_strip(r)
	var k := 0
	for v: Vector2 in layout.get("vents", []):
		_vent(v, k)
		k += 1
	for f: Array in layout.get("fences", []):
		_fence(f[0], f[1])
	for b: Vector2 in layout.get("blocks", []):
		_hazards.add_child(Breakable.make("block", Transform3D(Basis(Vector3.UP, randf() * 0.4), Vector3(b.x, _h(b.x, b.y), b.y))))
	for d: Vector2 in layout.get("drums", []):
		_hazards.add_child(Breakable.make("drum", Transform3D(Basis(Vector3.UP, randf() * TAU), Vector3(d.x, _h(d.x, d.y), d.y))))


## A strip of steel spikes: low enough to drive over, and they bite what does.
func _spike_strip(r: Rect2) -> void:
	var root := Node3D.new()
	_hazards.add_child(root)
	var y := _h(r.get_center().x, r.get_center().y)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(r.size.x, 0.06, r.size.y)
	bm.material = _mat(Color(0.12, 0.12, 0.13), 0.5, 0.6)
	base.mesh = bm
	base.position = Vector3(r.get_center().x, y + 0.03, r.get_center().y)
	root.add_child(base)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.07
	cone.height = 0.28
	cone.radial_segments = 6
	cone.material = _mat(Color(0.62, 0.63, 0.64), 0.3, 0.9)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	var xs := int(r.size.x / 0.35)
	var zs := int(r.size.y / 0.35)
	mm.instance_count = xs * zs
	for i in xs:
		for j in zs:
			var p := Vector3(r.position.x + (i + 0.5) * r.size.x / xs, y + 0.2, r.position.y + (j + 0.5) * r.size.y / zs)
			mm.set_instance_transform(i * zs + j, Transform3D(Basis.IDENTITY, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(r.size.x, 1.2, r.size.y)
	cs.shape = bs
	cs.position = Vector3(r.get_center().x, y + 0.6, r.get_center().y)
	area.add_child(cs)
	root.add_child(area)
	_spikes.append(area)


## A flame vent: a grate in the floor that roars up in a column of fire every few seconds (a hiss
## and a flicker a second before).
func _vent(at: Vector2, k: int) -> void:
	var root := Node3D.new()
	_hazards.add_child(root)
	var y := _h(at.x, at.y)
	var grate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.05, 2.4)
	bm.material = _mat(Color(0.06, 0.05, 0.05), 0.6, 0.5)
	grate.mesh = bm
	grate.position = Vector3(at.x, y + 0.03, at.y)
	root.add_child(grate)
	for i in 6:
		var bar := MeshInstance3D.new()
		var b2 := BoxMesh.new()
		b2.size = Vector3(2.3, 0.04, 0.06)
		b2.material = _mat(Color(0.3, 0.28, 0.26), 0.5, 0.8)
		bar.mesh = b2
		bar.position = Vector3(at.x, y + 0.07, at.y - 1.0 + i * 0.4)
		root.add_child(bar)
	var fire := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3(0, 2.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.05, 0.9)
	pm.scale_min = 1.2
	pm.scale_max = 2.4
	var fade := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	g.add_point(0.4, Color(1.0, 0.45, 0.1, 0.8))
	g.set_color(g.get_point_count() - 1, Color(0.2, 0.15, 0.12, 0.0))
	fade.gradient = g
	pm.color_ramp = fade
	fire.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = WheelSpray._puff()
	q.material = fm
	fire.draw_pass_1 = q
	fire.amount = 120
	fire.lifetime = 0.7
	fire.emitting = false
	fire.position = Vector3(at.x, y + 0.1, at.y)
	fire.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 12, 8))
	root.add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 9.0
	light.light_energy = 0.0
	light.position = Vector3(at.x, y + 2.0, at.y)
	root.add_child(light)
	var hiss := AudioStreamPlayer3D.new()
	hiss.stream = load("res://assets/audio/rocket/launch.wav")
	hiss.unit_size = 10.0
	hiss.position = light.position
	root.add_child(hiss)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 4.0, 2.6)
	cs.shape = bs
	cs.position = Vector3(at.x, y + 2.0, at.y)
	area.add_child(cs)
	root.add_child(area)
	_vents.append({"area": area, "fire": fire, "light": light, "hiss": hiss, "at": Vector3(at.x, y, at.y),
		"period": 7.0, "offset": k * 2.3, "tick": 0.0, "on": false})


## A chain-link fence between two points on the floor: posts, the net, a rail; it stops things.
func _fence(a: Vector2, b: Vector2) -> void:
	var body := StaticBody3D.new()
	_hazards.add_child(body)
	var steel := _mat(Color(0.55, 0.56, 0.56), 0.45, 0.7)
	var len := a.distance_to(b)
	var mid := (a + b) * 0.5
	var y := _h(mid.x, mid.y)
	var basis := Basis(Vector3.UP, -atan2(b.y - a.y, b.x - a.x))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(len, 2.2, 0.12)
	cs.shape = bs
	cs.transform = Transform3D(basis, Vector3(mid.x, y + 1.1, mid.y))
	body.add_child(cs)
	var n := maxi(int(len / 2.5), 1)
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 2.3
		cm.material = steel
		post.mesh = cm
		post.position = Vector3(p.x, _h(p.x, p.y) + 1.15, p.y)
		body.add_child(post)
	var rail := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(len, 0.06, 0.06)
	rm.material = steel
	rail.mesh = rm
	rail.transform = Transform3D(basis, Vector3(mid.x, y + 2.25, mid.y))
	body.add_child(rail)
	var net := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(len, 2.1)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/chain_link.gdshader")
	mat.set_shader_parameter("around", len)
	mat.set_shader_parameter("height", 2.1)
	qm.material = mat
	net.mesh = qm
	net.transform = Transform3D(basis, Vector3(mid.x, y + 1.1, mid.y))
	net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(net)


# --- The hazards at work --------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_t += dt
	# the spikes: what runs over them is bitten, a part at its bottom, every so often while it's on them
	for a in _spikes:
		if not is_instance_valid(a):
			continue
		for b in a.get_overlapping_bodies():
			var m := b as Machine
			if m == null or not m.alive:
				continue
			var left: float = _bite.get(m, 0.0) - dt
			if left <= 0.0:
				left = 0.35 if m.linear_velocity.length() > 0.5 else 0.8
				var under := m.com_global() + Vector3.DOWN * 0.6
				m.hit(under, Vector3.UP, SPIKE_DAMAGE, 250.0)
				m.last_hit_kind = "diken"
				if Combat.current:
					Combat.current.sound("res://assets/audio/impact/metal_0%d.wav" % randi_range(1, 3), under, -2.0, randf_range(0.8, 1.0))
			_bite[m] = left
	# the vents: a cycle each, fire for 2 s of it, a warning second before
	for v: Dictionary in _vents:
		var ph := fmod(_t + float(v.offset), float(v.period))
		var on := ph > float(v.period) - 2.0
		var warn := ph > float(v.period) - 3.0 and not on
		var fire := v.fire as GPUParticles3D
		var light := v.light as OmniLight3D
		if on and not bool(v.on):
			(v.hiss as AudioStreamPlayer3D).play()
		v.on = on
		fire.emitting = on or (warn and fmod(_t, 0.3) < 0.1)
		(fire.process_material as ParticleProcessMaterial).initial_velocity_max = 10.0 if on else 2.0
		light.light_energy = (6.0 + randf() * 2.0) if on else (0.8 if warn else 0.0)
		if not on:
			continue
		v.tick = float(v.tick) - dt
		if float(v.tick) > 0.0:
			continue
		v.tick = 0.25
		for b in (v.area as Area3D).get_overlapping_bodies():
			var m := b as Machine
			if m and m.alive:
				m.blast(v.at + Vector3.UP * 0.8, 2.6, FIRE_DAMAGE, 900.0, null, "ateş")
