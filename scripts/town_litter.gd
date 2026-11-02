class_name TownLitter
extends Node3D
## The things lying about a settlement's trodden ground, round a building but outside its fence: a
## stack of split wood, a barrel or two, crates, a chopping block with chips round it, a handcart, a
## hay bale, boards stacked on bearers. A few to each building, put where there's room (not in a
## yard, a building or the water), each laid out from the building's place so it's the same on a
## loaded game; baked into a few meshes (MeshBake).

const KINDS := {
	"house": ["wood", "block", "barrel", "boards", "cart"],
	"store": ["crates", "barrel", "barrel", "sacks", "cart", "boards"],
	"square": ["barrel", "crates", "boards"],
	"well": ["barrel", "trough"],
	"work": ["wood", "boards", "block", "cart"],
	"carts": ["cart", "cart", "hay"],
}

var building: Building
var village: Node
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var b := building
	var kinds: Array = KINDS.get(str(b.def.role), [])
	if kinds.is_empty():
		return
	_rng.seed = hash(Vector2i(roundi(b.global_position.x * 2.0), roundi(b.global_position.z * 2.0)))
	var sz: Vector2 = b.def.size
	var n := 2 + _rng.randi() % 3
	var placed: Array[Vector3] = []
	for k in n:
		var kind: String = kinds[_rng.randi() % kinds.size()]
		for attempt in 10:
			var a := _rng.randf() * TAU
			var r := sz.length() * 0.5 + _rng.randf_range(2.5, 6.0)
			if b.def.role == "house":
				r += 3.0 # (beyond its yard)
			var p := b.global_position + Vector3(cos(a), 0, sin(a)) * r
			if not _room(p, placed):
				continue
			p.y = village.nav.height(p.x, p.z)
			_make(kind, p, _rng.randf() * TAU)
			placed.append(p)
			break
	MeshBake.bake(self)


## Free ground for a thing at `p`: open, not in a yard or on a building, not on another thing.
func _room(p: Vector3, placed: Array[Vector3]) -> bool:
	if not village.nav.is_open(p) or village.nav.on_road(p):
		return false
	for q in placed:
		if q.distance_to(p) < 2.2:
			return false
	for o: Building in village.buildings:
		if o.state == "gone":
			continue
		var l := o.global_transform.affine_inverse() * Vector3(p.x, o.global_position.y, p.z)
		var os: Vector2 = o.def.size
		if absf(l.x) < os.x * 0.5 + 1.2 and absf(l.z) < os.y * 0.5 + 1.2:
			return false
	for y: Node in village.yards:
		var yd := y as Yard
		if not is_instance_valid(yd) or not is_instance_valid(yd.house):
			continue
		var l := yd.house.global_transform.affine_inverse() * Vector3(p.x, yd.house.global_position.y, p.z)
		if yd.rect.grow(0.8).has_point(Vector2(l.x, l.z)):
			return false
	return true


func _box(size: Vector3, mat: Material, xf: Transform3D) -> void:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)
	mi.global_transform = xf


func _cyl(r: float, h: float, mat: Material, xf: Transform3D, sides := 10) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = sides
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)
	mi.global_transform = xf


func _make(kind: String, p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var wood := Building.material("wood")
	var plank := Building.material("plank")
	var dark := Building.material("dark")
	var log := Building.material("log")
	match kind:
		"wood": # (split wood stacked between two stakes)
			for row in 4:
				for i in 6:
					var x := (i - 2.5) * 0.17 + (0.08 if row % 2 else 0.0)
					_cyl(0.075, 0.5, wood, Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), p + b * Vector3(x, 0.08 + row * 0.15, 0)), 5)
			for s in [-1.0, 1.0]:
				_box(Vector3(0.06, 0.8, 0.06), dark, Transform3D(b, p + b * Vector3(s * 0.6, 0.4, 0)))
		"block": # (a chopping block, an axe in it, chips about)
			_cyl(0.27, 0.5, log, Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.25), 10)
			var ab := b * Basis(Vector3.RIGHT, 0.5)
			_box(Vector3(0.035, 0.7, 0.035), wood, Transform3D(ab, p + Vector3.UP * 0.5 + ab * Vector3(0, 0.33, 0)))
			for k in 6:
				var c := p + Vector3(_rng.randf_range(-0.8, 0.8), 0.02, _rng.randf_range(-0.8, 0.8))
				_box(Vector3(0.12, 0.03, 0.06), plank, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), c))
		"barrel":
			_cyl(0.3, 0.8, plank, Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.4), 12)
			for hy: float in [0.18, 0.62]:
				_cyl(0.31, 0.04, dark, Transform3D(Basis.IDENTITY, p + Vector3.UP * hy), 12)
		"crates":
			for k in 3:
				var off := Vector3((k % 2) * 0.72 - 0.36, 0.33 + (k / 2) * 0.66, 0)
				_box(Vector3(0.66, 0.66, 0.66), plank, Transform3D(b * Basis(Vector3.UP, _rng.randf_range(-0.15, 0.15)), p + b * off))
		"sacks":
			var sack := StandardMaterial3D.new()
			sack.albedo_color = Color(0.68, 0.6, 0.45)
			for k in 4:
				var sm := SphereMesh.new()
				sm.radius = 0.3
				sm.height = 0.45
				var mi := MeshInstance3D.new()
				mi.mesh = sm
				mi.material_override = sack
				add_child(mi)
				mi.global_position = p + b * Vector3((k % 2) * 0.55 - 0.27, 0.22 + (k / 2) * 0.35, (k / 2) * 0.1)
		"boards": # (boards stacked on two bearers)
			for s in [-0.8, 0.8]:
				_box(Vector3(0.12, 0.12, 1.0), dark, Transform3D(b, p + b * Vector3(s, 0.06, 0)))
			for row in 5:
				_box(Vector3(2.2, 0.05, 0.9), plank, Transform3D(b * Basis(Vector3.UP, _rng.randf_range(-0.04, 0.04)), p + b * Vector3(0, 0.15 + row * 0.055, 0)))
		"cart": # (a handcart left on its legs)
			_box(Vector3(0.9, 0.08, 1.4), plank, Transform3D(b * Basis(Vector3.RIGHT, -0.12), p + b * Vector3(0, 0.55, 0)))
			for s in [-1.0, 1.0]:
				_box(Vector3(0.05, 0.25, 1.4), plank, Transform3D(b * Basis(Vector3.RIGHT, -0.12), p + b * Vector3(s * 0.45, 0.7, 0)))
				_cyl(0.35, 0.06, dark, Transform3D(b * Basis(Vector3.BACK, PI * 0.5), p + b * Vector3(s * 0.55, 0.35, 0.25)), 12)
				_box(Vector3(0.05, 0.05, 1.1), wood, Transform3D(b * Basis(Vector3.RIGHT, 0.25), p + b * Vector3(s * 0.3, 0.45, -1.1)))
		"hay":
			var hay := StandardMaterial3D.new()
			hay.albedo_color = Color(0.72, 0.62, 0.34)
			_box(Vector3(1.1, 0.5, 0.6), hay, Transform3D(b, p + Vector3.UP * 0.25))
			_box(Vector3(1.1, 0.5, 0.6), hay, Transform3D(b * Basis(Vector3.UP, 0.15), p + b * Vector3(0.2, 0.75, 0)))
		"trough":
			_box(Vector3(1.5, 0.4, 0.5), plank, Transform3D(b, p + Vector3.UP * 0.2))
			_box(Vector3(1.4, 0.02, 0.4), Building.material("water"), Transform3D(b, p + Vector3.UP * 0.38))
