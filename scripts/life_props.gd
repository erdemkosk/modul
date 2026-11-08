class_name LifeProps
extends RefCounted
## The things of the daily round, made in code from a few boxes and cylinders (they're seen from
## 40-70 m, and up close only now and then): the yoke and its two pails, the wooden snow shovel,
## the birch besom, the pot on its tripod over a small fire and the ladle, the washing basket, the
## scrubbing board and the wet linen, the garmon (the Russian button accordion) and the
## balalaika, a crate and a sack for the chain at the wagon, a pail for the one at a fire, the
## children's sled and a snowball. Each made once per body that needs it (LifePoses) and kept,
## hidden, when not in use. Every one is built in its own frame as LifePoses holds it.

static var _mats := {}


static func mat(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	match name:
		"wood": m.albedo_color = Color(0.46, 0.33, 0.2)
		"pale": m.albedo_color = Color(0.66, 0.55, 0.38) # (fresh-planed, the shovel's blade)
		"dark": m.albedo_color = Color(0.16, 0.14, 0.12)
		"iron":
			m.albedo_color = Color(0.25, 0.25, 0.26)
			m.metallic = 0.6
			m.roughness = 0.5
		"water":
			m.albedo_color = Color(0.18, 0.26, 0.3)
			m.roughness = 0.1
		"snow": m.albedo_color = Color(0.93, 0.95, 0.98)
		"twig": m.albedo_color = Color(0.4, 0.3, 0.2)
		"wicker": m.albedo_color = Color(0.62, 0.5, 0.32)
		"linen":
			m.albedo_color = Color(0.86, 0.84, 0.78)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"linen_wet":
			m.albedo_color = Color(0.7, 0.69, 0.65)
			m.roughness = 0.6
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"red": m.albedo_color = Color(0.55, 0.14, 0.1)
		"bellows":
			m.albedo_color = Color(0.2, 0.12, 0.1)
		"stone": m.albedo_color = Color(0.5, 0.49, 0.46)
		"ember":
			m.albedo_color = Color(0.2, 0.06, 0.02)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.35, 0.08)
			m.emission_energy_multiplier = 2.0
		"flame":
			m.albedo_color = Color(1.0, 0.6, 0.2)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = Color(1.0, 0.55, 0.15)
			m.emission_energy_multiplier = 3.0
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.85
		"sack": m.albedo_color = Color(0.62, 0.55, 0.42)
		"crate": m.albedo_color = Color(0.52, 0.4, 0.26)
	_mats[name] = m
	return m


static func _box(parent: Node3D, size: Vector3, at: Vector3, m: String, rot := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if size.length() < 0.25 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.transform = Transform3D(rot, at)
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, at: Vector3, m: String, rot := Basis.IDENTITY, sides := 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat(m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if maxf(r_top, r_bottom) < 0.05 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.transform = Transform3D(rot, at)
	parent.add_child(mi)
	return mi


## A stick from `a` to `b`.
static func _stick(parent: Node3D, a: Vector3, b: Vector3, r: float, m: String) -> MeshInstance3D:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return _cyl(parent, r, r, d.length(), (a + b) * 0.5, m, Basis(x, y, z), 6)


static func make(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = kind
	match kind:
		"yoke": _yoke(n)
		"pail": _pail(n, true)
		"pail_empty": _pail(n, false)
		"shovel": _shovel(n)
		"besom": _besom(n)
		"hearth": _hearth(n)
		"ladle": _stick(n, Vector3(0, 0.08, 0), Vector3(0, -0.62, 0), 0.016, "wood"); _cyl(n, 0.06, 0.04, 0.05, Vector3(0, -0.63, 0), "wood")
		"basket": _basket(n, true)
		"board": _board(n)
		"cloth": _cloth(n, "linen_wet", Vector2(0.5, 0.42))
		"cloth_dry": _cloth(n, "linen", Vector2(0.55, 0.6))
		"garmon_l", "garmon_r": _garmon_end(n, kind == "garmon_r")
		"bellows": _box(n, Vector3(1.0, 0.2, 0.17), Vector3.ZERO, "bellows")
		"balalaika": _balalaika(n)
		"crate":
			_box(n, Vector3(0.42, 0.3, 0.32), Vector3.ZERO, "crate")
			for s: float in [-0.12, 0.12]:
				_box(n, Vector3(0.44, 0.03, 0.34), Vector3(0, s, 0), "dark")
		"sack":
			var s := _cyl(n, 0.13, 0.18, 0.42, Vector3.ZERO, "sack", Basis(Vector3.BACK, PI * 0.5), 8)
			s.scale = Vector3(1, 1, 0.8)
			_cyl(n, 0.05, 0.05, 0.06, Vector3(0.24, 0, 0), "sack", Basis(Vector3.BACK, PI * 0.5), 6)
		"sled": _sled(n)
		"snowball":
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.06
			sm.height = 0.12
			sm.radial_segments = 6
			sm.rings = 3
			mi.mesh = sm
			mi.material_override = mat("snow")
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(mi)
	return n


## The yoke (koromyslo): a bent pole carried over one shoulder, front to back, a hook at each end.
## Built along -z (its front end) to +z, the middle (on the shoulder) at the origin.
static func _yoke(n: Node3D) -> void:
	var pts: Array[Vector3] = []
	for k in 9:
		var f := -1.0 + k * 0.25
		pts.append(Vector3(0, -0.14 * f * f, f * 0.8))
	for k in 8:
		_stick(n, pts[k], pts[k + 1], 0.02 if k in [0, 7] else 0.026, "wood")
	# (the shoulder's worn hollow: a little flat, darker)
	_box(n, Vector3(0.07, 0.02, 0.18), Vector3(0, 0.01, 0), "wood")
	for e: Vector3 in [pts[0], pts[8]]:
		_stick(n, e, e + Vector3(0, -0.12, 0), 0.006, "iron")


## A wooden pail, hooped, its rope handle; full of water (or not). Its rim at the origin's level
## less 0.12 (hung from the hook's end).
static func _pail(n: Node3D, full: bool) -> void:
	var top := -0.42
	_cyl(n, 0.13, 0.11, 0.27, Vector3(0, top - 0.135, 0), "wood")
	for y: float in [top - 0.06, top - 0.22]:
		_cyl(n, 0.134, 0.124, 0.025, Vector3(0, y, 0), "dark")
	if full:
		_cyl(n, 0.122, 0.122, 0.01, Vector3(0, top - 0.02, 0), "water")
	# (the bail: from each side of the rim up to the hook)
	_stick(n, Vector3(-0.13, top, 0), Vector3(0, -0.12, 0), 0.006, "dark")
	_stick(n, Vector3(0.13, top, 0), Vector3(0, -0.12, 0), 0.006, "dark")


## The broad wooden snow shovel: the haft along -y from the top (the hand) to the blade, the
## blade's face toward +z. A heap of snow on it (named "load") when it's carrying.
static func _shovel(n: Node3D) -> void:
	_stick(n, Vector3(0, 0.04, 0), Vector3(0, -1.2, 0), 0.016, "wood")
	_box(n, Vector3(0.12, 0.03, 0.03), Vector3(0, 0.05, 0), "wood") # (the cross-grip)
	_box(n, Vector3(0.42, 0.42, 0.02), Vector3(0, -1.38, -0.01), "pale")
	_box(n, Vector3(0.42, 0.04, 0.05), Vector3(0, -1.18, 0.0), "wood")
	var load := Node3D.new()
	load.name = "load"
	n.add_child(load)
	_box(load, Vector3(0.34, 0.3, 0.06), Vector3(0, -1.4, 0.04), "snow")


## A birch besom: a stick, a bundle of twigs bound at its foot (along -y from the top).
static func _besom(n: Node3D) -> void:
	_stick(n, Vector3.ZERO, Vector3(0, -0.95, 0), 0.016, "wood")
	_cyl(n, 0.04, 0.16, 0.55, Vector3(0, -1.2, 0), "twig", Basis.IDENTITY, 7)
	_cyl(n, 0.04, 0.04, 0.04, Vector3(0, -0.96, 0), "dark", Basis.IDENTITY, 6)


## The cooking fire in the yard: three stakes leant together, the pot hung from them, a few
## sticks burning under it (flames named "flame*" to be flickered). On the ground at the origin.
static func _hearth(n: Node3D) -> void:
	for k in 3:
		var a := k * TAU / 3.0
		_stick(n, Vector3(cos(a) * 0.55, 0, sin(a) * 0.55), Vector3(0, 1.0, 0), 0.02, "wood")
	_stick(n, Vector3(0, 1.0, 0), Vector3(0, 0.62, 0), 0.005, "iron")
	_cyl(n, 0.17, 0.12, 0.2, Vector3(0, 0.5, 0), "iron")
	_cyl(n, 0.15, 0.15, 0.01, Vector3(0, 0.6, 0), "red") # (the soup)
	for k in 4:
		var a := k * TAU / 4.0 + 0.4
		_stick(n, Vector3(cos(a) * 0.28, 0.03, sin(a) * 0.28), Vector3(-cos(a) * 0.05, 0.08, -sin(a) * 0.05), 0.025, "wood")
	_cyl(n, 0.16, 0.2, 0.05, Vector3(0, 0.02, 0), "ember")
	for k in 3:
		# (a tongue of flame: a thin cone, its foot in the embers; flickered by LifePoses)
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.045 - k * 0.008
		c.height = 0.26 - k * 0.05
		c.radial_segments = 5
		c.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = mat("flame")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.name = "flame%d" % k
		holder.position = Vector3(cos(k * 2.1) * 0.06, 0.04, sin(k * 2.1) * 0.06)
		mi.position = Vector3(0, c.height * 0.5, 0)
		holder.add_child(mi)
		n.add_child(holder)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 1.2
	l.omni_range = 3.5
	l.position = Vector3(0, 0.25, 0)
	l.name = "light"
	n.add_child(l)


## A wicker basket of washing, carried on the hip (its middle at the origin).
static func _basket(n: Node3D, full: bool) -> void:
	var b := _cyl(n, 0.24, 0.2, 0.22, Vector3.ZERO, "wicker", Basis.IDENTITY, 12)
	b.scale = Vector3(1.0, 1.0, 0.7)
	if full:
		var c := _cyl(n, 0.21, 0.21, 0.06, Vector3(0, 0.11, 0), "linen", Basis.IDENTITY, 10)
		c.scale = Vector3(1.0, 1.0, 0.7)


## A washboard on a flat stone at the water's edge, the wet linen across it.
static func _board(n: Node3D) -> void:
	var s := _cyl(n, 0.3, 0.34, 0.12, Vector3(0, 0.06, 0), "stone", Basis.IDENTITY, 7)
	s.scale = Vector3(1.0, 1.0, 0.8)
	_box(n, Vector3(0.36, 0.025, 0.5), Vector3(0, 0.14, 0), "pale", Basis(Vector3.RIGHT, -0.25))
	for k in 6:
		_box(n, Vector3(0.34, 0.012, 0.02), Vector3(0, 0.155 + k * 0.01, -0.2 + k * 0.07), "wood", Basis(Vector3.RIGHT, -0.25))


## A cloth held by two corners (the origin between them), hanging down.
static func _cloth(n: Node3D, m: String, size: Vector2) -> void:
	var q := QuadMesh.new()
	q.size = size
	q.center_offset = Vector3(0, -size.y * 0.5, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat(m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)


## One end of the garmon: the keyboard (the right hand's, buttons on it) or the bass end.
static func _garmon_end(n: Node3D, right: bool) -> void:
	_box(n, Vector3(0.05, 0.22, 0.19), Vector3.ZERO, "red" if right else "wood")
	_box(n, Vector3(0.055, 0.2, 0.03), Vector3(0, 0, -0.1), "dark")
	if right:
		for k in 4:
			_box(n, Vector3(0.06, 0.012, 0.012), Vector3(0, -0.07 + k * 0.045, -0.112), "pale")


## The balalaika: its three-cornered body, the neck up from it (along +y), the head.
static func _balalaika(n: Node3D) -> void:
	var p := PrismMesh.new()
	p.size = Vector3(0.36, 0.34, 0.08)
	var mi := MeshInstance3D.new()
	mi.mesh = p
	mi.material_override = mat("pale")
	n.add_child(mi)
	_box(n, Vector3(0.04, 0.5, 0.025), Vector3(0, 0.42, 0), "wood")
	_box(n, Vector3(0.06, 0.1, 0.03), Vector3(0, 0.7, 0), "dark")
	_cyl(n, 0.035, 0.035, 0.01, Vector3(0, 0.02, -0.042), "dark", Basis(Vector3.RIGHT, PI * 0.5), 8)


## The children's sled: two bent runners and slats, a rope at the front (-z).
static func _sled(n: Node3D) -> void:
	for x: float in [-0.17, 0.17]:
		_box(n, Vector3(0.03, 0.03, 0.85), Vector3(x, 0.02, 0.0), "wood")
		_stick(n, Vector3(x, 0.02, -0.42), Vector3(x, 0.14, -0.5), 0.015, "wood")
		for z: float in [-0.25, 0.25]:
			_stick(n, Vector3(x, 0.03, z), Vector3(x, 0.13, z), 0.012, "wood")
	for k in 5:
		_box(n, Vector3(0.4, 0.02, 0.1), Vector3(0, 0.14, -0.3 + k * 0.15), "pale")
