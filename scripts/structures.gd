class_name Structures
extends RefCounted
## The industrial sites' structures, built out of StructurePieces (each `make` returns a Structure
## to put where it goes; it works out what rests on what when it enters the tree):
##
##   water_tower   four steel legs braced across, a platform, a tank on it (the tank's what matters)
##   chimney       a brick stack in rings on a concrete foot, a steel band at the top
##   fuel_tank     a long tank on two concrete saddles, a ladder: holed or lit, it goes up
##   warehouse     a steel frame, walls of corrugated sheet, a roof on beams, crates and pallets inside
##   scaffold      wooden poles, ledgers and planks up the side of nothing in particular: it burns
##   transformer   a steel tank of oil (it goes up), its fins, insulators, a fence round it
##   crane         a lattice mast, a jib and its counterweight, on a concrete base
##   silo          a tall steel bin on legs, a conveyor up to it
##   lamp          a yard lamp: a pole, its arm, the lamp lit (it falls with them)

const STEEL := Color(0.36, 0.38, 0.4)
const SAFETY := Color(0.62, 0.42, 0.05)
const RUST := Color(0.42, 0.22, 0.12)
const WHITE := Color(0.72, 0.72, 0.68)
const BLUE := Color(0.18, 0.3, 0.42)
const NAMES := {"water_tower": "Su kulesi", "chimney": "Baca", "fuel_tank": "Yakıt tankı", "warehouse": "Depo",
	"scaffold": "İskele", "transformer": "Trafo", "crane": "Kule vinç", "silo": "Silo", "lamp": "Lamba direği"}


static func make(kind: String, xf: Transform3D, terrain: Node) -> Structure:
	var s := Structure.new()
	s.title = NAMES.get(kind, kind)
	s.name = kind
	s.terrain = terrain
	s.transform = xf
	s.set_meta("kind", kind)
	match kind:
		"water_tower":
			_water_tower(s)
		"chimney":
			_chimney(s)
		"fuel_tank":
			_fuel_tank(s)
		"warehouse":
			_warehouse(s)
		"scaffold":
			_scaffold(s)
		"transformer":
			_transformer(s)
		"crane":
			_crane(s)
		"silo":
			_silo(s)
		"lamp":
			_lamp(s)
	return s


static func _box(s: Structure, size: Vector3, at: Vector3, stuff: String, colour := Color(0, 0, 0, 0), vital := false,
		turn := Basis.IDENTITY) -> StructurePiece:
	return s.add(StructurePiece.make("box", size, stuff, Transform3D(turn, at), colour), vital)


static func _cyl(s: Structure, d: float, h: float, at: Vector3, stuff: String, colour := Color(0, 0, 0, 0), vital := false,
		lying := false, turn := Basis.IDENTITY) -> StructurePiece:
	return s.add(StructurePiece.make("xcyl" if lying else "cyl", Vector3(d, h, d), stuff, Transform3D(turn, at), colour), vital)


static func _water_tower(s: Structure) -> void:
	var h := 9.0
	var w := 1.7
	for x: float in [-w, w]:
		for z: float in [-w, w]:
			_box(s, Vector3(0.3, h, 0.3), Vector3(x, h * 0.5, z), "steel")
	# braces round at two heights (they hang off the legs)
	for y: float in [2.6, 6.0]:
		for z: float in [-w, w]:
			_box(s, Vector3(w * 2.0, 0.16, 0.16), Vector3(0, y, z), "steel")
		for x: float in [-w, w]:
			_box(s, Vector3(0.16, 0.16, w * 2.0), Vector3(x, y, 0), "steel")
	_box(s, Vector3(w * 2.0 + 0.9, 0.25, w * 2.0 + 0.9), Vector3(0, h + 0.125, 0), "steel")
	for z: float in [-w - 0.4, w + 0.4]:
		_box(s, Vector3(w * 2.0 + 0.9, 0.7, 0.06), Vector3(0, h + 0.6, z), "steel") # (railing)
	_cyl(s, 3.8, 3.4, Vector3(0, h + 0.25 + 1.7, 0), "paint", BLUE, true)
	_cyl(s, 4.0, 0.3, Vector3(0, h + 0.25 + 3.55, 0), "paint", WHITE)
	_box(s, Vector3(0.5, h - 0.6, 0.08), Vector3(w + 0.35, (h - 0.6) * 0.5, 0), "steel") # (the ladder, up one side; it holds nothing up)


static func _chimney(s: Structure) -> void:
	_box(s, Vector3(3.6, 1.0, 3.6), Vector3(0, 0.5, 0), "concrete")
	var y := 1.0
	var n := 12
	for k in n:
		var d := lerpf(2.7, 1.8, float(k) / n)
		var col := Color(0.46, 0.22, 0.15).darkened(0.08 * (k % 2))
		if k == n - 2:
			col = Color(0.75, 0.72, 0.68) # (a white band near the top)
		_cyl(s, d, 1.5, Vector3(0, y + 0.75, 0), "brick", col)
		y += 1.5
	_cyl(s, 2.0, 0.35, Vector3(0, y + 0.175, 0), "steel", Color(0.12, 0.12, 0.12))


static func _fuel_tank(s: Structure) -> void:
	for x: float in [-2.0, 2.0]:
		_box(s, Vector3(0.7, 0.9, 2.6), Vector3(x, 0.45, 0), "concrete")
	_cyl(s, 2.4, 7.0, Vector3(0, 0.9 + 1.2, 0), "fuel", WHITE, true, true)
	_box(s, Vector3(7.0, 0.12, 0.12), Vector3(0, 3.35, 0), "steel") # (the walkway rail along the top)
	_box(s, Vector3(0.08, 3.2, 0.5), Vector3(3.6, 1.6, 0.9), "steel") # (a ladder at the end)


static func _warehouse(s: Structure) -> void:
	var L := 12.0
	var W := 8.0
	var H := 5.0
	# the frame: columns at the corners and the middle of the long sides, beams across their tops
	var cols: Array[Vector3] = []
	for x: float in [-L / 2.0, 0.0, L / 2.0]:
		for z: float in [-W / 2.0, W / 2.0]:
			cols.append(Vector3(x, H / 2.0, z))
	for c in cols:
		_box(s, Vector3(0.3, H, 0.3), c, "paint", SAFETY)
	for x: float in [-L / 2.0, 0.0, L / 2.0]:
		_box(s, Vector3(0.25, 0.35, W + 0.3), Vector3(x, H + 0.175, 0), "steel")
	for z: float in [-W / 2.0, W / 2.0]:
		_box(s, Vector3(L + 0.3, 0.3, 0.25), Vector3(0, H + 0.15, z), "steel")
	# the roof: panels laid on the beams
	for k in 4:
		var x := -L / 2.0 + L / 8.0 + k * L / 4.0
		_box(s, Vector3(L / 4.0, 0.08, W + 0.6), Vector3(x, H + 0.39, 0), "sheet", Color(0.42, 0.44, 0.42))
	# the walls: sheets standing on the ground between the columns (a gap for the doors on one end)
	for k in 4:
		var x := -L / 2.0 + L / 8.0 + k * L / 4.0
		for z: float in [-W / 2.0, W / 2.0]:
			_box(s, Vector3(L / 4.0 - 0.1, H - 0.2, 0.08), Vector3(x, (H - 0.2) / 2.0, z + signf(z) * 0.2), "sheet",
				Color(0.55, 0.57, 0.55) if k % 2 == 0 else Color(0.5, 0.52, 0.5))
	for k in 2:
		var z := -W / 4.0 + k * W / 2.0
		_box(s, Vector3(0.08, H - 0.2, W / 2.0 - 0.1), Vector3(L / 2.0 + 0.2, (H - 0.2) / 2.0, z), "sheet", Color(0.55, 0.57, 0.55))
	# inside: crates on pallets (they burn)
	for x: float in [-4.0, -1.5, 1.5]:
		for z: float in [-2.0, 1.5]:
			_box(s, Vector3(1.2, 0.15, 1.2), Vector3(x, 0.075, z), "wood")
			_box(s, Vector3(1.1, 1.0, 1.1), Vector3(x, 0.65, z), "wood", Color(0.55, 0.42, 0.25))


static func _scaffold(s: Structure) -> void:
	var bays := 3
	var bw := 2.5
	var lifts := 4
	var lh := 2.0
	var x0 := -bays * bw * 0.5
	for i in bays + 1:
		for z: float in [-0.6, 0.6]:
			_box(s, Vector3(0.12, lifts * lh, 0.12), Vector3(x0 + i * bw, lifts * lh * 0.5, z), "wood", Color(0.45, 0.33, 0.2))
	for k in lifts:
		var y := (k + 1) * lh
		for z: float in [-0.6, 0.6]:
			_box(s, Vector3(bays * bw, 0.1, 0.1), Vector3(0, y - 0.15, z), "wood", Color(0.45, 0.33, 0.2)) # (ledgers)
		_box(s, Vector3(bays * bw, 0.06, 1.3), Vector3(0, y - 0.07, 0), "wood") # (the boards)
	for i in bays:
		_box(s, Vector3(bw * 1.15, 0.08, 0.08), Vector3(x0 + (i + 0.5) * bw, lh * 0.5, 0.65), "wood", Color(0.42, 0.3, 0.18),
			false, Basis(Vector3.BACK, 0.7)) # (a brace across each bay)
	_box(s, Vector3(1.2, 1.0, 1.2), Vector3(x0 + bw * 0.5, 0.5, -1.8), "wood", Color(0.55, 0.42, 0.25)) # (a stack of boards)


static func _transformer(s: Structure) -> void:
	_box(s, Vector3(4.2, 0.4, 3.2), Vector3(0, 0.2, 0), "concrete")
	_box(s, Vector3(2.4, 2.2, 1.6), Vector3(0, 0.4 + 1.1, 0), "fuel", Color(0.35, 0.4, 0.38), true) # (the oil tank: it goes up)
	for x: float in [-1.4, 1.4]:
		for k in 4:
			_box(s, Vector3(0.35, 1.6, 0.05), Vector3(x, 0.4 + 1.0, -0.6 + k * 0.4), "steel", Color(0.32, 0.36, 0.34)) # (fins)
	for x: float in [-0.7, 0.0, 0.7]:
		_cyl(s, 0.25, 0.9, Vector3(x, 0.4 + 2.2 + 0.45, 0), "glass", Color(0.5, 0.36, 0.25)) # (insulators)
	# the fence round it, panels on the ground
	for x: float in [-3.0, 3.0]:
		_box(s, Vector3(0.06, 2.0, 5.0), Vector3(x, 1.0, 0), "steel", Color(0.45, 0.46, 0.44))
	for z: float in [-2.5, 2.5]:
		_box(s, Vector3(6.0, 2.0, 0.06), Vector3(0, 1.0, z), "steel", Color(0.45, 0.46, 0.44))


static func _crane(s: Structure) -> void:
	_box(s, Vector3(4.0, 1.0, 4.0), Vector3(0, 0.5, 0), "concrete")
	var seg := 3.0
	var n := 6
	for k in n:
		var y := 1.0 + k * seg
		for x: float in [-0.7, 0.7]:
			for z: float in [-0.7, 0.7]:
				_box(s, Vector3(0.18, seg, 0.18), Vector3(x, y + seg * 0.5, z), "paint", SAFETY)
		_box(s, Vector3(1.6, 0.14, 0.14), Vector3(0, y + seg - 0.07, -0.7), "paint", SAFETY)
		_box(s, Vector3(1.6, 0.14, 0.14), Vector3(0, y + seg - 0.07, 0.7), "paint", SAFETY)
	var top := 1.0 + n * seg
	_box(s, Vector3(2.0, 0.6, 2.0), Vector3(0, top + 0.3, 0), "steel") # (the slewing ring and cab)
	_box(s, Vector3(1.0, 1.0, 1.2), Vector3(0.9, top + 1.1, 0), "paint", WHITE)
	_box(s, Vector3(16.0, 0.8, 0.9), Vector3(5.5, top + 0.9, 0), "paint", SAFETY, true) # (the jib)
	_box(s, Vector3(6.0, 0.6, 0.9), Vector3(-4.0, top + 0.9, 0), "paint", SAFETY) # (the counter-jib)
	_box(s, Vector3(1.6, 1.4, 1.2), Vector3(-6.2, top + 0.3, 0), "concrete") # (the counterweight)
	_box(s, Vector3(0.1, 6.0, 0.1), Vector3(9.0, top - 2.5, 0), "steel") # (the hook's line)
	_box(s, Vector3(0.6, 0.5, 0.4), Vector3(9.0, top - 5.7, 0), "steel", Color(0.12, 0.12, 0.12))


static func _silo(s: Structure) -> void:
	var h := 4.0
	for x: float in [-1.4, 1.4]:
		for z: float in [-1.4, 1.4]:
			_box(s, Vector3(0.3, h, 0.3), Vector3(x, h * 0.5, z), "steel")
	_box(s, Vector3(3.6, 0.3, 3.6), Vector3(0, h + 0.15, 0), "steel")
	for k in 4:
		_cyl(s, 3.4, 2.0, Vector3(0, h + 0.3 + 1.0 + k * 2.0, 0), "steel", Color(0.6, 0.62, 0.6).darkened(0.05 * (k % 2)), k == 0)
	_cyl(s, 3.6, 0.4, Vector3(0, h + 0.3 + 8.2, 0), "steel", Color(0.5, 0.52, 0.5))
	_box(s, Vector3(0.5, 0.5, 9.0), Vector3(3.0, h + 3.0, -2.5), "rust", RUST, false, Basis(Vector3.RIGHT, -0.6)) # (the conveyor)


static func _lamp(s: Structure) -> void:
	_box(s, Vector3(0.6, 0.3, 0.6), Vector3(0, 0.15, 0), "concrete")
	_box(s, Vector3(0.18, 7.0, 0.18), Vector3(0, 0.3 + 3.5, 0), "steel", Color(0.3, 0.32, 0.3))
	_box(s, Vector3(0.12, 0.12, 1.6), Vector3(0, 7.2, -0.7), "steel", Color(0.3, 0.32, 0.3))
	var head := _box(s, Vector3(0.5, 0.18, 0.7), Vector3(0, 7.05, -1.45), "steel", Color(0.15, 0.15, 0.15))
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.85, 0.6)
	var lens := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.4, 0.02, 0.55)
	lm.material = glow
	lens.mesh = lm
	lens.position = Vector3(0, -0.1, 0)
	head.add_child(lens)
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.58)
	l.light_energy = 7.0
	l.spot_range = 24.0
	l.spot_angle = 62.0
	l.rotation.x = -PI * 0.5
	l.position = Vector3(0, -0.12, 0)
	head.add_child(l)
