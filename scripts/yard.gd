class_name Yard
extends Node3D
## A house's yard, laid out round it when it's finished: a rail fence with a gate in front of the
## door, a kitchen garden in rows behind the house, a hen house, an outhouse in the back corner, a
## woodshed against the side, and the clutter of living there (a cart, a sledge in winter, a hay
## stack, a trough, a bench). Every post stands on the ground where it is, so the fence follows the
## slope. Where the yard would run into another yard or a building, that stretch of fence is left
## out: neighbouring yards share their fences and the lanes stay open between them. The fence is
## shut to walking but at its gate (Nav).
##
## Nothing in it is saved: it's laid out again, the same, from the house (seeded by where it stands).

const BACK := 6.5 ## m of yard behind the house
const SIDE := 2.6 ## m either side of it
const FRONT := 2.4 ## m in front of it, to the gate

var house: Building
var village: Village
var nav: Nav

var rect := Rect2() ## the yard, in the house's own x, z
var _shut: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var sz: Vector2 = house.def.size
	rect = Rect2(-sz.x * 0.5 - SIDE, -sz.y * 0.5 - BACK, sz.x + SIDE * 2.0, sz.y + BACK + FRONT)
	_rng.seed = hash(Vector2i(roundi(house.global_position.x), roundi(house.global_position.z)))
	_fence()
	_garden()
	_outbuildings()
	_clutter()


func _exit_tree() -> void:
	if not _shut.is_empty():
		nav.set_building(_shut, false)


## A point of the yard (house space) in the world, on the ground.
func _at(x: float, z: float) -> Vector3:
	var w := house.global_transform * Vector3(x, 0, z)
	w.y = nav.height(w.x, w.z)
	return w


## Free to be part of this yard: not under a building, not in another yard, not water or cliff.
func _free(x: float, z: float) -> bool:
	var w := house.global_transform * Vector3(x, 0, z)
	if not nav.is_open(w):
		return false
	for y: Yard in village.yards:
		if y == self or not is_instance_valid(y) or not is_instance_valid(y.house):
			continue
		var l := y.house.global_transform.affine_inverse() * Vector3(w.x, y.house.global_position.y, w.z)
		if y.rect.grow(-0.3).has_point(Vector2(l.x, l.z)):
			return false
	for b in village.buildings:
		if b == house or b.state == "gone":
			continue
		var l := b.global_transform.affine_inverse() * Vector3(w.x, b.global_position.y, w.z)
		var bs: Vector2 = b.def.size
		if absf(l.x) < bs.x * 0.5 + 0.8 and absf(l.z) < bs.y * 0.5 + 0.8:
			return false
	return true


func _mesh(mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.global_transform = xf


static func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## The fence: posts every couple of metres, two rails between, the gate open in front of the door.
func _fence() -> void:
	var wood := Building.material("wood")
	var post := _box_mesh(Vector3(0.1, 1.15, 0.1))
	var r := rect
	var corners := [Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.position.y)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var n := maxi(1, int(a.distance_to(b) / 2.2))
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			var mid := (p0 + p1) * 0.5
			if side == 0 and absf(mid.x) < 1.3:
				continue # (the gate, in front of the door)
			if not _free(mid.x, mid.y) or not _free(p0.x, p0.y):
				continue
			var w0 := _at(p0.x, p0.y)
			var w1 := _at(p1.x, p1.y)
			_mesh(post, wood, Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.1, 0.1)), w0 + Vector3.UP * 0.5))
			for h in [0.45, 0.85]:
				var a3: Vector3 = w0 + Vector3.UP * h
				var b3: Vector3 = w1 + Vector3.UP * h
				var rail := _box_mesh(Vector3(0.05, 0.07, a3.distance_to(b3) + 0.1))
				_mesh(rail, wood, Transform3D(Basis.looking_at((b3 - a3).normalized(), Vector3.UP), (a3 + b3) * 0.5))
			var cell := Nav.cell_of(house.global_transform * Vector3(mid.x, 0, mid.y))
			if not cell in _shut:
				_shut.append(cell)
	# the gate posts, taller, and the gate itself standing open
	for s in [-1.0, 1.0]:
		if _free(s * 1.3, r.end.y):
			_mesh(_box_mesh(Vector3(0.14, 1.5, 0.14)), Building.material("dark"), Transform3D(Basis.IDENTITY, _at(s * 1.3, r.end.y) + Vector3.UP * 0.7))
	var gate := _box_mesh(Vector3(1.2, 0.9, 0.05))
	var gp := _at(-0.7, r.end.y + 0.6)
	_mesh(gate, Building.material("plank"), Transform3D(Basis(Vector3.UP, house.global_rotation.y + 1.3), gp + Vector3.UP * 0.55))
	nav.set_building(_shut, true)


## The kitchen garden behind the house: dug rows, cabbages and the green of potatoes in them (bare in
## winter: Seasons).
func _garden() -> void:
	var sz: Vector2 = house.def.size
	var z0 := -sz.y * 0.5 - 1.4
	var z1 := rect.position.y + 1.0
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color(0.2, 0.14, 0.09)
	earth.roughness = 1.0
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.24, 0.42, 0.18)
	var row := _box_mesh(Vector3(sz.x - 0.6, 0.12, 0.45))
	var cab := SphereMesh.new()
	cab.radius = 0.16
	cab.height = 0.24
	cab.radial_segments = 8
	cab.rings = 4
	var z := z0
	while z > z1:
		if _free(0, z):
			var w := _at(0, z)
			_mesh(row, earth, Transform3D(Basis(Vector3.UP, house.global_rotation.y), w + Vector3.UP * 0.03))
			var x := -sz.x * 0.5 + 0.6
			while x < sz.x * 0.5 - 0.4:
				if _rng.randf() < 0.85:
					var pw := _at(x, z)
					var s := _rng.randf_range(0.7, 1.2)
					_mesh(cab, leaf, Transform3D(Basis().scaled(Vector3(s, s * 0.8, s)), pw + Vector3.UP * 0.14))
				x += 0.42
		z -= 0.75


## The hen house, the outhouse in the back corner, the woodshed against the side.
func _outbuildings() -> void:
	var r := rect
	var plank := Building.material("plank")
	var dark := Building.material("dark")
	var shingle := Building.material("shingle")
	var yaw := house.global_rotation.y
	# the outhouse
	var ox := r.end.x - 0.9
	var oz := r.position.y + 0.9
	if _free(ox, oz):
		var w := _at(ox, oz)
		var b := Basis(Vector3.UP, yaw)
		_mesh(_box_mesh(Vector3(1.0, 2.0, 1.0)), plank, Transform3D(b, w + Vector3.UP * 1.0))
		_mesh(_box_mesh(Vector3(1.2, 0.06, 1.25)), shingle, Transform3D(b * Basis(Vector3.RIGHT, 0.2), w + Vector3.UP * 2.08))
		_mesh(_box_mesh(Vector3(0.6, 1.7, 0.04)), dark, Transform3D(b, w + b * Vector3(0, 0.88, 0.52)))
		_mesh(_box_mesh(Vector3(0.08, 0.12, 0.02)), Building.material("window"), Transform3D(b, w + b * Vector3(0, 1.55, 0.55))) # (the little window cut in the door)
	# the hen house
	var hx := r.position.x + 1.1
	var hz := r.position.y + 1.2
	if _free(hx, hz):
		var w := _at(hx, hz)
		var b := Basis(Vector3.UP, yaw)
		_mesh(_box_mesh(Vector3(1.4, 0.9, 1.0)), plank, Transform3D(b, w + Vector3.UP * 0.75))
		for s in [-1.0, 1.0]:
			for t in [-1.0, 1.0]:
				_mesh(_box_mesh(Vector3(0.08, 0.35, 0.08)), dark, Transform3D(b, w + b * Vector3(s * 0.6, 0.17, t * 0.42)))
		_mesh(_box_mesh(Vector3(1.6, 0.05, 1.25)), shingle, Transform3D(b * Basis(Vector3.RIGHT, -0.25), w + Vector3.UP * 1.3))
		_mesh(_box_mesh(Vector3(0.3, 0.05, 0.8)), dark, Transform3D(b * Basis(Vector3.RIGHT, 0.5), w + b * Vector3(0.3, 0.2, 0.75))) # (the ramp)
	# the woodshed against the house's side: split wood stacked under a lean-to
	var sz: Vector2 = house.def.size
	var wx := sz.x * 0.5 + 1.0
	if _free(wx, -sz.y * 0.5 + 0.8):
		var w := _at(wx, -0.2)
		var b := Basis(Vector3.UP, yaw)
		var split := CylinderMesh.new()
		split.top_radius = 0.08
		split.bottom_radius = 0.08
		split.height = 0.5
		split.radial_segments = 5
		var wood := Building.material("wood")
		for k in 30:
			var lx := (k % 5) * 0.18 - 0.36
			var ly := (k / 10) * 0.16 + 0.1
			var lz := ((k / 5) % 2) * 0.5 - 1.0 + _rng.randf_range(-0.03, 0.03)
			_mesh(split, wood, Transform3D(b * Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, _rng.randf()), w + b * Vector3(lx, ly, lz * 2.0)))
		_mesh(_box_mesh(Vector3(1.2, 0.05, 2.6)), shingle, Transform3D(b * Basis(Vector3.FORWARD, -0.3), w + b * Vector3(0, 1.0, -0.4)))
		for t in [-1.0, 1.0]:
			_mesh(_box_mesh(Vector3(0.08, 1.0, 0.08)), Building.material("dark"), Transform3D(b, w + b * Vector3(0.5, 0.5, -0.4 + t * 1.2)))


## What's left about a yard where people live: a cart, a hay stack, a trough, a bench by the fence,
## a sledge leant against it.
func _clutter() -> void:
	var r := rect
	var plank := Building.material("plank")
	var dark := Building.material("dark")
	var yaw := house.global_rotation.y
	var spots := [Vector2(r.position.x + 1.0, r.end.y - 1.0), Vector2(r.end.x - 1.0, r.end.y - 1.2), Vector2(r.end.x - 1.0, r.position.y + 3.0),
		Vector2(r.position.x + 1.0, r.position.y + 3.2)]
	var kinds := ["cart", "hay", "trough", "bench", "sledge"]
	for spot: Vector2 in spots:
		if _rng.randf() < 0.3 or not _free(spot.x, spot.y):
			continue
		var w := _at(spot.x, spot.y)
		var b := Basis(Vector3.UP, yaw + _rng.randf_range(-0.6, 0.6))
		match kinds[_rng.randi() % kinds.size()]:
			"cart":
				_mesh(_box_mesh(Vector3(1.0, 0.1, 1.6)), plank, Transform3D(b, w + Vector3.UP * 0.55))
				for s in [-1.0, 1.0]:
					_mesh(_box_mesh(Vector3(0.05, 0.3, 1.6)), plank, Transform3D(b, w + b * Vector3(s * 0.5, 0.75, 0)))
					var wheel := CylinderMesh.new()
					wheel.top_radius = 0.4
					wheel.bottom_radius = 0.4
					wheel.height = 0.06
					wheel.radial_segments = 12
					_mesh(wheel, dark, Transform3D(b * Basis(Vector3.BACK, PI * 0.5), w + b * Vector3(s * 0.6, 0.4, 0.1)))
				_mesh(_box_mesh(Vector3(0.06, 0.06, 1.2)), dark, Transform3D(b * Basis(Vector3.RIGHT, 0.3), w + b * Vector3(0, 0.35, -1.3)))
			"hay":
				var hay := CylinderMesh.new()
				hay.top_radius = 0.15
				hay.bottom_radius = 0.9
				hay.height = 1.6
				hay.radial_segments = 10
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.68, 0.58, 0.3)
				m.roughness = 1.0
				_mesh(hay, m, Transform3D(Basis.IDENTITY, w + Vector3.UP * 0.75))
				_mesh(_box_mesh(Vector3(0.06, 2.2, 0.06)), dark, Transform3D(Basis.IDENTITY, w + Vector3.UP * 1.0))
			"trough":
				_mesh(_box_mesh(Vector3(1.4, 0.35, 0.45)), plank, Transform3D(b, w + Vector3.UP * 0.25))
				_mesh(_box_mesh(Vector3(1.3, 0.02, 0.35)), Building.material("water"), Transform3D(b, w + Vector3.UP * 0.4))
			"bench":
				_mesh(_box_mesh(Vector3(1.5, 0.06, 0.35)), plank, Transform3D(b, w + Vector3.UP * 0.45))
				for s in [-1.0, 1.0]:
					_mesh(_box_mesh(Vector3(0.08, 0.45, 0.3)), dark, Transform3D(b, w + b * Vector3(s * 0.6, 0.22, 0)))
			"sledge":
				_mesh(_box_mesh(Vector3(0.6, 0.06, 1.8)), plank, Transform3D(b * Basis(Vector3.RIGHT, 1.1), w + Vector3.UP * 0.8))
				for s in [-1.0, 1.0]:
					_mesh(_box_mesh(Vector3(0.05, 0.08, 1.9)), dark, Transform3D(b * Basis(Vector3.RIGHT, 1.1), w + b * Vector3(s * 0.28, 0.75, 0.08)))
