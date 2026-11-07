class_name TownLitter
extends Node3D
## The things lying about a settlement's trodden ground, round a building but outside its fence: a
## stack of split wood, a barrel or two, crates, a chopping block with chips round it, a handcart, a
## haystack, boards stacked on bearers, the wash hung out by a house, a hand-lettered sign by a
## workplace; and the war's leavings: sandbags piled into a breastwork, ammunition crates, oil drums,
## kerosene tins. A few to each building, put where there's room (not in a yard, a building or the
## water), each laid out from the building's place so it's the same on a
## loaded game; baked into a few meshes (MeshBake). (The models: Props, and Details, made in Blender.)

const KINDS := {
	"house": ["wood", "block", "barrel", "boards", "cart", "logs", "washing", "washing"],
	"store": ["crates", "barrel", "drum", "sacks", "cart", "tins", "drum", "sign"],
	"square": ["barrel", "crates", "boards"],
	"well": ["barrel", "trough"],
	"work": ["wood", "logs", "boards", "block", "cart", "logs", "sign"],
	"carts": ["cart", "cart", "hay", "drum"],
	"barracks": ["sandbags", "sandbags", "ammo", "drum", "ammo"],
	"tower": ["sandbags", "ammo"],
	"smith": ["drum", "tins", "crates", "sign"],
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


## A place in the world, put in this node's terms.
func _at(b: Basis, p: Vector3) -> Transform3D:
	return global_transform.affine_inverse() * Transform3D(b, p)


func _make(kind: String, p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	p.y -= 0.03 # (settled into the ground a little)
	match kind:
		"wood": # (split wood stacked between two stakes)
			Details.place(self, "woodpile", _at(b, p))
		"block": # (a chopping block, an axe in it, chips about)
			Details.place(self, "chopping_block", _at(b, p))
		"logs":
			Props.place(self, "logs", _at(b, p))
		"barrel":
			Props.place(self, "barrel", _at(b, p))
		"crates":
			for k in 3:
				var off := Vector3((k % 2) * 0.72 - 0.36, (k / 2) * 0.68, 0)
				Props.place(self, "crate", _at(b * Basis(Vector3.UP, _rng.randf_range(-0.15, 0.15)), p + b * off))
		"sacks":
			for k in 4:
				var lie := Basis(Vector3.UP, yaw + _rng.randf_range(-0.25, 0.25))
				Props.place(self, "sack", _at(lie, p + b * Vector3((k % 2) * 0.68 - 0.34, (k / 2) * 0.34, (k / 2) * 0.1)))
		"boards": # (boards stacked on two bearers)
			Details.place(self, "boards", _at(b, p))
		"cart": # (a handcart left on its prop)
			Props.place(self, "hand_cart", _at(b, p))
		"hay": # (a stack of hay round its pole)
			Details.place(self, "haystack", _at(b, p))
		"sandbags": # (a breastwork: courses of filled sacks, laid in a shallow arc)
			Details.place(self, "breastwork", _at(b, p))
		"ammo": # (ammunition boxes, olive, stencilled, stacked)
			Details.place(self, "ammo", _at(b, p))
		"drum": # (an oil drum, its paint gone: standing, or now and then on its side)
			var which := "drum_%d" % (_rng.randi() % 3)
			if _rng.randf() < 0.3:
				Details.place(self, which, _at(b * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3.UP * 0.29 + b * Vector3(0, 0, 0.44)))
			else:
				Details.place(self, which, _at(b, p))
		"tins": # (square kerosene tins, a pair and one on its side)
			Details.place(self, "tins", _at(b, p))
		"trough":
			Details.place(self, "trough", _at(b, p))
		"washing": # (the wash hung out on a line between two posts)
			Details.place(self, "washing", _at(b, p + Vector3.UP * 0.03))
		"sign": # (a hand-lettered board on two posts)
			Details.place(self, "signboard", _at(b, p + Vector3.UP * 0.03))
