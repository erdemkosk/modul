class_name Building
extends Node3D
## A building, put together out of pieces (BuildingDefs.recipe) that stand on one another.
##
## As a ghost it shows where it would go. As a site it's staked out with string between the stakes,
## a scaffold goes up round it in decks, and what's brought for it is stacked at its corner (logs,
## stone). It's built in stages (the footing, the walls, the roof, the fittings), piece by piece:
## a builder takes a piece's share of the stack (`claim`), carries it to its place (up onto the
## scaffold for the high ones) and sets it there (`place`). Nothing goes up that nobody carried. Done, it does its job (Village reads `def.role`).
##
## Every piece knows what it rests on (`supports`, worked out from the pieces under it) and what
## it touches (`near`). One gone (burnt through, knocked down), the rest is worked out again from
## the ground up: a piece with too little left under it lets go and falls as a body of its own. Fire
## is per piece: a burning one chars, loses its hit points and lights what touches it (thatch
## quickest, plaster slowest, stone never); rain puts it out now and then, and villagers with
## buckets from a well (`douse`). Too little left standing and it's a ruin.
##
## What falls stays where it fell, charred, and the ground round a fire is scorched: a raid leaves
## its marks on the village. A damaged building or a ruin can be mended (`start_repair`): the
## missing pieces are put back one by one, bottom first, out of what's brought for them, and the
## rubble they left is cleared as they go. What only charred stays charred: the scars stay.
##
## A store holds its own goods (`goods`); a workplace keeps a pile of what its workers bring back
## when there are carters to fetch it (shown stacked by its door).

signal finished(b: Building)
signal ruined(b: Building)

class Piece:
	var spec: Dictionary
	var xf := Transform3D.IDENTITY ## where it is in the building
	var mesh_local := Transform3D.IDENTITY ## the mesh in the piece (a lying cylinder turned on its side)
	var ext := Vector3.ONE ## its box, in the piece
	var mesh: MeshInstance3D
	var shape: CollisionShape3D
	var aabb := AABB()
	var stuff := "wood"
	var hp := 100.0
	var max_hp := 100.0
	var built := false
	var alive := true
	var grounded := false
	var supports: Array[int] = []
	var near: Array[int] = []
	var burn := 0.0 ## > 0 while it burns: seconds it has
	var wet := 0.0 ## seconds it won't catch (doused)
	var charred := false
	var debris: RigidBody3D ## where it lies, once it's fallen
	var mesh_res: Mesh
	var center := Vector3.ZERO ## its box's middle, in the piece (a model's mesh may sit off it)
	var tag := ""
	var daub := false ## plastered over with mud (a log of a house that's been)
	var painted := false ## a model's: its own colours, in its vertices
	var stage := 0 ## 0 the footing, 1 the walls, 2 the roof, 3 the fittings
	var res := "odun" ## what it's built of, out of the site's stack
	var unit := 0.0 ## how much of it

const MAX_FLAMES := 6
const STAGES := ["Temel atılıyor", "Duvarlar örülüyor", "Çatı kaplanıyor", "Son işler"]
const DECK := 1.8 ## m between the scaffold's decks
const BUILD_SOUNDS := ["clank_01", "clank_02", "clank_03", "bolt_on_01", "bolt_on_02"]

var kind := ""
var def: Dictionary
var state := "ghost" ## ghost, site, done, ruin, gone
var pieces: Array[Piece] = []
var body: StaticBody3D
var cost: Dictionary
var delivered := {}
var incoming := {}
var work := 0.0 ## seconds of building done
var workers: Array = []
var arms := 0 ## (an armoury) rifles on the rack
var ammo := 0 ## (an armoury) cartridges
var bows := 0 ## (an armoury) bows on the rack
var arrows := 0 ## (an armoury) arrows
var training: Array[String] = [] ## (an armoury) the militia to be trained, in turn: "rifle", "bow"
var casting := false ## (an armoury) cartridges cast each morning, from stone and wood
var bowing := false ## (an armoury) a bow or a sheaf of arrows made each morning, of wood
var ox := false ## (a carter's) its carts drawn by oxen
var spur := false ## on a side line: the train loads straight from it
var coal_burn := 0 ## (a house) what's left of the coal on the fire, in firewood's worth
var wanted := 0
var residents: Array = []
var cells: Array[Vector2i] = []
var radius := 4.0
var idle_note := "" ## why its workers stand about (no trees left in reach...)
var nav: Nav ## (for scorching the ground round a fire)
var goods := {} ## a store's goods, a workplace's pile: res -> count
var pile_claim: Node ## the carter on its way for the pile
var repaired := false ## (its last finish was a mending)
var level := 1 ## a house: 2 once its back room's up (BuildingDefs.annex)
var annex := Rect2() ## a house's back room, in its space (the yard keeps off it)
var upgrading := "" ## a house: what's being done to it ("oda", "siva", "soba": BuildingDefs.UPGRADES), as a mending
var upgraded_now := "" ## (what its last finish did to it)
var plastered := false ## a house: its logs plastered with mud
var stove := false ## a house: a brick stove in it
var mode := "" ## a mud pit: "" mud, "kerpic" bricks; a quarry: "" stone, "demir" iron
var work_area := Rect2() ## a workplace: the ground (x, z) its workers keep to, if it's been drawn (ALAN ÇİZ)
var drying: Array[Vector2] = [] ## a mud pit: bricks laid out on the racks: (seconds left, how many)
var _racks: Node3D
var prisoners: Array = [] ## a jail: the outlaws held in it (Villager)
var yard_has: Array[String] = [] ## a house: what its people have brought to its yard (Yard), in order
var crop: Crop ## a field's
var heat_acc := 0.0 ## a house: the firewood burnt toward the next log
var warm := true ## a house: its hearth lit (or no need of it)
var cold_night := false ## a house: went cold in the night
var _chimney: GPUParticles3D
var lit := false ## a lamp or a house: its light on
var _doors: Array = [] ## [door piece, its hinge (in the building), which way it swings in]
var _door_open := 0.0 ## 0 shut .. 1 open
var _door_hold := 0.0 ## seconds it's held open yet
var _glow: OmniLight3D

var _repair_list: Array[int] = [] ## the fallen pieces to put back, bottom first
var _repair_time := 0.0
var _repair_done := 0
var _pile: Node3D
var _pile_shown := -1
var _scorch_t := 0.0

var _shown := 0 ## pieces put up so far
var used := {} ## a site's stack: res -> how much of what's come has been taken for pieces
var claims := {} ## piece index -> the builder carrying it
var _stack: Node3D
var _stakes: Node3D
var _decks: Array[float] = []
var _scaffold: Node3D
var _flames: Array[GPUParticles3D] = []
var _smoke: GPUParticles3D
var _embers: GPUParticles3D
var _light: OmniLight3D
var _sound: AudioStreamPlayer3D
var _sound_t := 0.0
var _fire_t := 0.0
var _ghost_bad := false

static var _mats := {}
static var _streams := {}


func setup(k: String) -> void:
	kind = k
	def = BuildingDefs.def(k)
	cost = (def.cost as Dictionary).duplicate()
	for r: String in cost:
		delivered[r] = 0
		incoming[r] = 0
	var sz: Vector2 = def.size
	radius = sz.length() * 0.5
	wanted = {"work": 1, "tower": 1, "research": 1, "smith": 1, "carts": 1, "farm": 2, "healer": 1}.get(str(def.role), 0)
	body = StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("building", self)
	add_child(body)
	for spec in BuildingDefs.recipe(k):
		_add_piece(spec)
	for p in pieces:
		p.stage = _stage_of(p)
	pieces.sort_custom(func(a: Piece, b: Piece) -> bool: return a.stage * 1000.0 + a.aabb.position.y < b.stage * 1000.0 + b.aabb.position.y)
	_share_cost()
	for p in pieces:
		body.add_child(p.shape)
		add_child(p.mesh)
		if p.tag == "door":
			var left := p.aabb.get_center().x <= 0.01
			var hinge := Vector3(p.aabb.position.x if left else p.aabb.end.x, 0.0, p.aabb.get_center().z)
			_doors.append([p, hinge, 1.0 if left else -1.0])
	_link()
	set_ghost(true)


func _add_piece(spec: Dictionary) -> void:
	var p := Piece.new()
	p.spec = spec
	p.stuff = spec.mat
	var st: Dictionary = BuildingDefs.STUFF[p.stuff]
	p.max_hp = float(st.hp)
	p.hp = p.max_hp
	var size: Vector3 = spec.size
	var rot: Vector3 = spec.rot
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	p.xf = Transform3D(basis, spec.pos)
	p.tag = str(spec.get("tag", ""))
	var mesh: Mesh
	match str(spec.shape):
		"mesh":
			mesh = spec.mesh
			p.xf = spec.xf
			var bb := mesh.get_aabb()
			p.ext = bb.size.max(Vector3(0.04, 0.04, 0.04))
			p.center = bb.get_center()
			p.painted = true
		"box":
			var m := BoxMesh.new()
			m.size = size
			mesh = m
			p.ext = size
		"prism":
			var m := PrismMesh.new()
			m.size = size
			mesh = m
			p.ext = size
		"cyl":
			var m := CylinderMesh.new()
			m.top_radius = size.x * 0.5
			m.bottom_radius = size.x * 0.5
			m.height = size.y
			m.radial_segments = 12
			m.rings = 1
			mesh = m
			p.ext = Vector3(size.x, size.y, size.x)
		"xcyl":
			var m := CylinderMesh.new()
			m.top_radius = size.y * 0.5
			m.bottom_radius = size.y * 0.5
			m.height = size.x
			m.radial_segments = 10
			m.rings = 1
			mesh = m
			p.mesh_local = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO)
			p.ext = Vector3(size.x, size.y, size.y)
		"cone":
			var m := CylinderMesh.new()
			m.top_radius = 0.02
			m.bottom_radius = size.x * 0.5
			m.height = size.y
			m.radial_segments = 4
			m.rings = 1
			mesh = m
			p.ext = Vector3(size.x * 0.72, size.y, size.x * 0.72)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _look(p)
	mi.transform = p.xf * p.mesh_local
	p.mesh = mi
	p.mesh_res = mesh
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = p.ext
	cs.shape = box
	cs.transform = p.xf * Transform3D(Basis.IDENTITY, p.center)
	p.shape = cs
	p.aabb = p.xf * AABB(p.center - p.ext * 0.5, p.ext)
	pieces.append(p)


## Which stage of the building a piece goes up in.
static func _stage_of(p: Piece) -> int:
	if p.tag in ["plinth", "found", "path", "ground"] or (p.stuff == "plank" and p.tag == "" and p.aabb.end.y < 0.6 and p.aabb.size.x > 2.0):
		return 0
	if p.tag in ["chimney", "chimneytop"] or p.stuff == "log" or (p.stuff == "dark" and p.tag == "") or p.stuff == "stone":
		return 1
	if p.stuff in ["shingle", "thatch"] or p.tag in ["barge", "finial"]:
		return 2
	return 3


## Each piece's share of what the building costs, by what it's made of: stone of the stone if the
## building takes any, the rest of the wood.
func _share_cost() -> void:
	var counts := {}
	for p in pieces:
		p.res = "tas" if p.stuff == "stone" and cost.has("tas") else ("odun" if cost.has("odun") else str(cost.keys()[0]) if not cost.is_empty() else "odun")
		counts[p.res] = int(counts.get(p.res, 0)) + 1
	for p in pieces:
		p.unit = float(cost.get(p.res, 0)) / maxf(float(counts[p.res]), 1.0)


## What rests on what, and what touches what.
func _link() -> void:
	for j in pieces.size():
		var pj := pieces[j]
		var bottom := pj.aabb.position.y
		if bottom < 0.15:
			pj.grounded = true
			continue
		var mid := pj.aabb.get_center().y
		for i in pieces.size():
			if i == j:
				continue
			var a := pieces[i].aabb
			var top := a.end.y
			if top >= bottom - 0.3 and top <= mid and a.position.y < bottom and _overlap_xz(a, pj.aabb):
				pj.supports.append(i)
		if pj.supports.is_empty(): # (a window, a door: held by what it's set in)
			for i in pieces.size():
				if i != j and pieces[i].aabb.grow(0.15).intersects(pj.aabb) and pieces[i].aabb.get_center().y <= mid + 0.5:
					pj.supports.append(i)
		if pj.supports.is_empty():
			pj.grounded = true
	for j in pieces.size():
		var g := pieces[j].aabb.grow(0.25)
		for i in pieces.size():
			if i != j and g.intersects(pieces[i].aabb):
				pieces[j].near.append(i)


static func _overlap_xz(a: AABB, b: AABB) -> bool:
	return a.position.x < b.end.x - 0.02 and b.position.x < a.end.x - 0.02 and a.position.z < b.end.z - 0.02 and b.position.z < a.end.z - 0.02


# --- Looks ------------------------------------------------------------------------------------------

static func material(stuff: String) -> Material:
	if not _mats.has(stuff):
		var m := StandardMaterial3D.new()
		match stuff:
			"ghost_ok", "ghost_bad":
				m.albedo_color = Color(0.45, 1.0, 0.55, 0.38) if stuff == "ghost_ok" else Color(1.0, 0.35, 0.3, 0.42)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.no_depth_test = false
			"plan":
				m.albedo_color = Color(0.8, 0.88, 1.0, 0.055)
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			"char":
				m.albedo_color = Color(0.07, 0.06, 0.05)
				m.roughness = 1.0
				m.emission_enabled = true
				m.emission = Color(0.9, 0.25, 0.05)
				m.emission_energy_multiplier = 0.25
			"window":
				m.albedo_color = BuildingDefs.STUFF.window.color
				m.emission_enabled = true
				m.emission = Color(1.0, 0.6, 0.26)
				m.emission_energy_multiplier = 0.0
				m.roughness = 0.4
				m.rim_enabled = true # (a sheen that catches the eye at a glancing angle, from above)
				m.rim = 0.4
			"water":
				m.albedo_color = BuildingDefs.STUFF.water.color
				m.roughness = 0.05
				m.metallic_specular = 0.9
			_:
				if stuff.ends_with("+"): # (a model's: its colours are in its vertices; snow and wet on it)
					var base := stuff.trim_suffix("+")
					if base == "window" or base == "water":
						return material(base)
					var sm := ShaderMaterial.new()
					sm.shader = preload("res://shaders/building.gdshader")
					sm.set_shader_parameter("roughness_base", 0.92 if base != "stone" else 0.97)
					if base == "daub":
						sm.set_shader_parameter("daub_k", 0.78) # (the logs' shape still shows through)
					_mats[stuff] = sm
					return sm
				elif stuff == "daub":
					m.albedo_color = Color(0.74, 0.65, 0.5)
					m.roughness = 0.95
				else:
					m.albedo_color = BuildingDefs.STUFF[stuff].color
					m.roughness = 0.92 if stuff != "stone" else 0.97
		_mats[stuff] = m
	return _mats[stuff]


## A piece's own look: a model's piece in its own (vertex) colours, a plain one in its stuff's.
static func _look(p: Piece) -> Material:
	if p.daub:
		return material("daub+" if p.painted else "daub")
	return material(p.stuff + ("+" if p.painted else ""))


## Broken rock, as quarried: a few lumpy, faceted shapes made once, and a few tints of stone.
static var _rocks: Array[Mesh] = []
static var _rock_mats: Array[Material] = []


static func rock(i: int) -> Mesh:
	if _rocks.is_empty():
		for k in 5:
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 7
			sphere.rings = 4
			var arr := sphere.get_mesh_arrays()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			# (the same point gets the same knock, so the seams stay shut)
			var squash := Vector3(randf_range(0.85, 1.25), randf_range(0.55, 0.75), randf_range(0.8, 1.1))
			for j in verts.size():
				var v := verts[j]
				var h := absf(sin(v.x * 12.9898 * (k + 1) + v.y * 78.233 + v.z * 37.719) * 43758.5453)
				h = h - floorf(h)
				v *= 1.0 + (h - 0.5) * 0.45
				# a flat broken face or two, where it was split off
				if v.x > 0.32 - k * 0.04:
					v.x = 0.32 - k * 0.04
				if v.y < -0.3:
					v.y = -0.3
				verts[j] = v * squash
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = null
			arr[Mesh.ARRAY_TANGENT] = null
			var st := SurfaceTool.new()
			st.create_from_arrays(arr)
			st.deindex()
			st.generate_normals() # (deindexed: flat facets)
			_rocks.append(st.commit())
		for c in [Color(0.55, 0.53, 0.49), Color(0.6, 0.56, 0.5), Color(0.48, 0.47, 0.45), Color(0.58, 0.55, 0.47)]:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.97
			_rock_mats.append(m)
	return _rocks[i % _rocks.size()]


static func rock_material(i: int) -> Material:
	rock(0)
	return _rock_mats[i % _rock_mats.size()]


## A house's own woodpile against its side wall, as big as what's in it (logs stacked in rows, a
## sack or two of coal beside), and a washing line out the back on a fair day.
var _pile_logs: MultiMeshInstance3D
var _fuel_shown := -1
var _coal_sacks: Array[MeshInstance3D] = []
var _laundry: Node3D


func show_fuel() -> void:
	if state != "done":
		return
	var wood := int(goods.get("odun", 0))
	var coal := int(goods.get("komur", 0))
	var key := wood * 100 + mini(coal, 9)
	if key == _fuel_shown:
		return
	_fuel_shown = key
	var sz: Vector2 = def.size
	var side := Vector3(sz.x * 0.5 + 0.45, 0, -0.3)
	if _pile_logs == null:
		var billet := CylinderMesh.new()
		billet.top_radius = 0.09
		billet.bottom_radius = 0.09
		billet.height = 0.7
		billet.radial_segments = 7
		billet.rings = 1
		billet.material = material("log")
		var stack := MultiMesh.new()
		stack.transform_format = MultiMesh.TRANSFORM_3D
		stack.mesh = billet
		stack.instance_count = 24
		_pile_logs = MultiMeshInstance3D.new()
		_pile_logs.multimesh = stack
		_pile_logs.visibility_range_end = 140.0
		add_child(_pile_logs)
	var mm := _pile_logs.multimesh
	var n := mini(wood * 2, 24)
	mm.visible_instance_count = n
	for i in n:
		var row := i / 6
		var col := i % 6
		var at := side + Vector3(0, 0.1 + row * 0.17, -1.0 + col * 0.19 + (0.09 if row % 2 == 1 else 0.0))
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, sin(i * 3.1) * 0.15), at))
	for s in _coal_sacks:
		s.queue_free()
	_coal_sacks.clear()
	for k in mini(coal, 3):
		var sack := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.25
		sm.height = 0.55
		sm.radial_segments = 8
		sm.rings = 4
		sack.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.19, 0.17)
		m.roughness = 1.0
		sack.material_override = m
		sack.position = side + Vector3(0.1, 0.25, 0.6 + k * 0.45)
		add_child(sack)
		_coal_sacks.append(sack)


func show_laundry(on: bool) -> void:
	if state != "done":
		return
	if _laundry == null:
		if hash(get_instance_id()) % 2 == 0:
			return # (not every house has one)
		_laundry = Node3D.new()
		add_child(_laundry)
		var sz: Vector2 = def.size
		var back := -sz.y * 0.5 - 2.2
		var wood := material("wood")
		for x in [-1.8, 1.8]:
			var pole := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.04
			pm.bottom_radius = 0.05
			pm.height = 2.0
			pole.mesh = pm
			pole.material_override = wood
			pole.position = Vector3(x, 1.0, back)
			_laundry.add_child(pole)
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(3.6, 0.01, 0.01)
		line.mesh = lm
		line.material_override = material("dark")
		line.position = Vector3(0, 1.9, back)
		_laundry.add_child(line)
		var cloths := [Color(0.85, 0.83, 0.76), Color(0.62, 0.2, 0.15), Color(0.35, 0.4, 0.5), Color(0.8, 0.78, 0.7), Color(0.5, 0.45, 0.35)]
		var n := 3 + hash(get_instance_id()) % 3
		for k in n:
			var c := MeshInstance3D.new()
			var cm := QuadMesh.new()
			cm.size = Vector2(0.45 + 0.2 * (k % 2), 0.6 + 0.25 * ((k + 1) % 2))
			c.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = cloths[(k + hash(get_instance_id())) % cloths.size()]
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 1.0
			c.material_override = m
			c.position = Vector3(-1.3 + k * (2.6 / maxf(n - 1, 1)), 1.9 - cm.size.y * 0.5, back)
			_laundry.add_child(c)
	_laundry.visible = on


## The years on it: a day older each morning, the wood greying and the moss coming (a mending
## takes most of it off again).
var age := 0.0 ## days standing


func grow_old(days := 1.0) -> void:
	age += days
	_weather_show()


func freshen() -> void:
	age *= 0.35
	_weather_show()


func _weather_show() -> void:
	var w := clampf(age / 36.0, 0.0, 0.85)
	for p in pieces:
		if p.mesh and p.mesh.material_override is ShaderMaterial:
			p.mesh.set_instance_shader_parameter(&"weathering", w)


## Painted shutters on its windows, once the town's doing well (a house's): a pair each, the paint
## each house's own.
var _shutters: Node3D


func set_trim(on: bool) -> void:
	if not on or state != "done" or def.role != "house":
		if _shutters:
			_shutters.visible = false
		return
	if _shutters == null:
		_shutters = Node3D.new()
		add_child(_shutters)
		var paints := [Color(0.18, 0.38, 0.32), Color(0.2, 0.3, 0.5), Color(0.55, 0.16, 0.12), Color(0.85, 0.82, 0.72), Color(0.3, 0.45, 0.2)]
		var m := StandardMaterial3D.new()
		m.albedo_color = paints[hash(get_instance_id()) % paints.size()]
		m.roughness = 0.8
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.9, 0.88, 0.82)
		for p in pieces:
			if p.stuff != "window" or not p.alive:
				continue
			var bb := p.aabb
			var c := bb.get_center()
			var thin_x := bb.size.x < bb.size.z # (which way the wall runs: shutters go along it)
			var w := (bb.size.z if thin_x else bb.size.x) * 0.5
			for s in [-1.0, 1.0]:
				var sh := MeshInstance3D.new()
				var sm := BoxMesh.new()
				sm.size = Vector3(0.06, bb.size.y * 1.05, w) if thin_x else Vector3(w, bb.size.y * 1.05, 0.06)
				sh.mesh = sm
				sh.material_override = m
				var off := Vector3(0, 0, s * (w + 0.05)) if thin_x else Vector3(s * (w + 0.05), 0, 0)
				var out := Vector3(signf(c.x) * 0.06, 0, 0) if thin_x else Vector3(0, 0, signf(c.z) * 0.06)
				sh.position = c + off + out
				_shutters.add_child(sh)
			# a carved board over it
			var top := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(0.08, 0.12, bb.size.z + 0.5) if thin_x else Vector3(bb.size.x + 0.5, 0.12, 0.08)
			top.mesh = tm
			top.material_override = white
			top.position = c + Vector3(0, bb.size.y * 0.5 + 0.12, 0) + (Vector3(signf(c.x) * 0.08, 0, 0) if thin_x else Vector3(0, 0, signf(c.z) * 0.08))
			_shutters.add_child(top)
	_shutters.visible = true


## Icicles hung along the eaves in the winter (a house's): little cones of ice along the roof's low
## front and back edges.
var _icicles: MultiMeshInstance3D
var _coal_smoke := false
var _dust_ms := 0


func set_icicles(on: bool) -> void:
	if not on or state != "done":
		if _icicles:
			_icicles.visible = false
		return
	if _icicles == null:
		var roof := AABB()
		var first := true
		for p in pieces:
			if p.stuff == "shingle" and p.alive:
				roof = p.aabb if first else roof.merge(p.aabb)
				first = false
		if first:
			return
		var cone := CylinderMesh.new()
		cone.top_radius = 0.035
		cone.bottom_radius = 0.0
		cone.height = 0.4
		cone.radial_segments = 5
		cone.rings = 1
		var ice := StandardMaterial3D.new()
		ice.albedo_color = Color(0.82, 0.9, 0.96, 0.85)
		ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ice.roughness = 0.08
		ice.metallic_specular = 0.9
		cone.material = ice
		var spots: Array[Transform3D] = []
		var k := 0
		var x := roof.position.x + 0.2
		while x < roof.end.x - 0.2:
			for z in [roof.position.z + 0.05, roof.end.z - 0.05]:
				var len := 0.5 + 0.9 * absf(sin(k * 2.39 + z))
				spots.append(Transform3D(Basis.from_scale(Vector3(1, len, 1)), Vector3(x, roof.position.y - 0.2 * len, z)))
				k += 1
			x += 0.32 + 0.12 * absf(sin(k * 1.7))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cone
		mm.instance_count = spots.size()
		for i in spots.size():
			mm.set_instance_transform(i, spots[i])
		_icicles = MultiMeshInstance3D.new()
		_icicles.multimesh = mm
		_icicles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_icicles.visibility_range_end = 120.0
		add_child(_icicles)
	_icicles.visible = true


## The windows glow at night (0..1).
static func set_night(n: float) -> void:
	(material("window") as StandardMaterial3D).emission_energy_multiplier = n * 6.0


func set_ghost(on: bool, ok := true) -> void:
	if on:
		state = "ghost"
		_ghost_bad = not ok
		var m := material("ghost_ok" if ok else "ghost_bad")
		for p in pieces:
			p.mesh.visible = p.aabb.end.y > -0.3 # (not the plinth's buried part... it shows the base)
			p.mesh.material_override = m
			p.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.shape.disabled = true


## From ghost to a building site: nothing up yet but the scaffold.
func begin() -> void:
	state = "site"
	for p in pieces:
		p.mesh.visible = false
		p.mesh.material_override = _look(p)
		p.mesh.cast_shadow = _shadow()
	_lay_ground()
	used = {}
	for r: String in cost:
		used[r] = 0.0
	_make_stakes()
	_make_scaffold()
	_update_stack()
	_sound = AudioStreamPlayer3D.new()
	_sound.unit_size = 14.0
	_sound.volume_db = -6.0
	_sound.max_distance = 260.0
	add_child(_sound)


## Straight up, done (the village's first buildings).
## A yard's ground: painted on the land itself (Nav.set_yard: packed earth that frays into the
## grass), so the model's own floor piece isn't drawn.
func _lay_ground() -> void:
	if nav == null or not kind in BuildingDefs.YARDS:
		return
	for p in pieces:
		if p.tag == "ground" and p.mesh:
			p.mesh.mesh = null
	nav.set_yard(global_transform, def.size, true)


func _exit_tree() -> void:
	if nav and kind in BuildingDefs.YARDS:
		nav.set_yard(global_transform, def.size, false)


func complete_now() -> void:
	if state != "site":
		begin()
	for r: String in cost:
		delivered[r] = cost[r]
		used[r] = float(cost[r])
	for p in pieces:
		if not p.built:
			_put_up(p, false)
	_shown = pieces.size()
	_finish()


## A site as it was saved: the stuff that had come, the pieces that were up.
func restore_site(got: Dictionary, built: PackedByteArray) -> void:
	for r: String in got:
		if delivered.has(r):
			delivered[r] = int(got[r])
	for k in mini(pieces.size(), built.size()):
		if built[k] == 1:
			_put_up(pieces[k], false)
			used[pieces[k].res] = float(used.get(pieces[k].res, 0.0)) + pieces[k].unit
			_shown += 1
	_update_stack()
	if _shown >= pieces.size():
		_finish()


## Stakes at its corners and a string between them, where its walls will go.
func _make_stakes() -> void:
	_stakes = Node3D.new()
	add_child(_stakes)
	var sz: Vector2 = def.size
	var wood := material("wood")
	var corners := [Vector3(-sz.x, 0, -sz.y) * 0.5, Vector3(sz.x, 0, -sz.y) * 0.5, Vector3(sz.x, 0, sz.y) * 0.5, Vector3(-sz.x, 0, sz.y) * 0.5]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var stake := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.05, 0.7, 0.05)
		stake.mesh = sm
		stake.material_override = wood
		stake.position = a + Vector3(0, 0.15, 0)
		_stakes.add_child(stake)
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.012, 0.012, a.distance_to(b))
		line.mesh = lm
		line.material_override = material("cloth")
		_stakes.add_child(line)
		line.transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) * 0.5 + Vector3(0, 0.38, 0))


## The site's stack, at its front left corner: what's come and not yet built in.
func _stack_spot() -> Vector3:
	var sz: Vector2 = def.size
	return Vector3(-sz.x * 0.5 - 1.4, 0, sz.y * 0.5 + 0.2)


func stack_at() -> Vector3:
	return global_transform * (_stack_spot() + Vector3(0.9, 0, 0.9))


func _update_stack() -> void:
	if _stack:
		_stack.queue_free()
		_stack = null
	if state != "site":
		return
	_stack = Node3D.new()
	_stack.position = _stack_spot()
	add_child(_stack)
	var logs := ceili((float(delivered.get("odun", 0)) - float(used.get("odun", 0.0))) / 1.5)
	var stones := ceili((float(delivered.get("tas", 0)) - float(used.get("tas", 0.0))) / 1.5)
	for k in mini(logs, 16):
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.13
		c.bottom_radius = 0.14
		c.height = 2.2
		c.radial_segments = 8
		mi.mesh = c
		mi.material_override = material("log")
		var row := k / 5
		mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3((k % 5) * 0.28 - 0.56 + row * 0.14, 0.14 + row * 0.25, 0))
		_stack.add_child(mi)
	for k in mini(stones, 12):
		var mi := MeshInstance3D.new()
		mi.mesh = rock(k)
		mi.material_override = rock_material(k * 7)
		mi.scale = Vector3.ONE * randf_range(0.42, 0.55)
		mi.position = Vector3(1.0 + (k % 3) * 0.42, 0.13 + (k / 6) * 0.24, -0.6 + ((k / 3) % 2) * 0.4)
		mi.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2))
		_stack.add_child(mi)


## What's carried here for the site: onto the stack.
func deliver(r: String, n: int) -> void:
	delivered[r] = int(delivered.get(r, 0)) + n
	_update_stack()


## The next piece to go up that the stack can pay for and nobody's carrying yet (-1: none; the
## pieces go in their order, so a piece short of stuff holds up the ones after it).
func next_piece() -> int:
	for i in pieces.size():
		var p := pieces[i]
		if p.built or claims.has(i):
			continue
		if float(delivered.get(p.res, 0)) - float(used.get(p.res, 0.0)) < p.unit - 0.0001:
			return -1
		return i
	return -1


## A builder takes the next piece's share off the stack. Its index, or -1.
func claim(v: Node) -> int:
	var i := next_piece()
	if i < 0:
		return -1
	claims[i] = v
	used[pieces[i].res] = float(used.get(pieces[i].res, 0.0)) + pieces[i].unit
	_update_stack()
	return i


## One piece put back unclaimed (taken, then not carried after all).
func unclaim_one(i: int) -> void:
	if claims.has(i):
		claims.erase(i)
		used[pieces[i].res] = maxf(float(used.get(pieces[i].res, 0.0)) - pieces[i].unit, 0.0)
		_update_stack()


## A builder called off: what it was carrying goes back on the stack.
func unclaim(v: Node) -> void:
	for i: int in claims.keys():
		if claims[i] == v:
			claims.erase(i)
			used[pieces[i].res] = maxf(float(used.get(pieces[i].res, 0.0)) - pieces[i].unit, 0.0)
	_update_stack()


## The stage the site's at.
func stage_name() -> String:
	for p in pieces:
		if not p.built:
			return STAGES[p.stage]
	return STAGES[3]


## Where a builder stands to set piece `i`: outside the walls by its side (on a scaffold deck if
## it's up high), what it faces, and the deck's height (0 on the ground), all in the world.
func work_spot(i: int) -> Dictionary:
	var p := pieces[i]
	var sz: Vector2 = def.size
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var c := p.aabb.get_center()
	var spot: Vector3
	if absf(c.x) > hx + 0.3 or absf(c.z) > hz + 0.3:
		var out := Vector3(c.x, 0, c.z).normalized()
		spot = Vector3(c.x, 0, c.z) + out * 0.8
	elif absf(c.x) / hx > absf(c.z) / hz:
		spot = Vector3(signf(c.x) * (hx + 0.85), 0, clampf(c.z, -hz, hz))
	else:
		spot = Vector3(clampf(c.x, -hx, hx), 0, signf(c.z) * (hz + 0.85))
	var level := 0.0
	for d in _decks:
		if d <= p.aabb.position.y - 0.25:
			level = d
	return {"at": global_transform * spot, "face": global_transform * c, "level": level}


## Piece `i` set in its place by a builder at `from` (in the world): it comes from the builder's
## hands into its place.
func place(i: int, from: Vector3) -> void:
	claims.erase(i)
	var p := pieces[i]
	if p.built or state != "site":
		return
	_put_up(p, true, global_transform.affine_inverse() * from)
	_shown += 1
	if _stakes and p.stage >= 1:
		_stakes.queue_free()
		_stakes = null
	if _shown >= pieces.size():
		_finish()


func _make_scaffold() -> void:
	_scaffold = Node3D.new()
	add_child(_scaffold)
	_decks.clear()
	var sz: Vector2 = def.size
	var top := 0.0
	for p in pieces:
		if p.aabb.get_center().x * p.aabb.get_center().x < sz.x * sz.x and p.tag != "finial":
			top = maxf(top, p.aabb.end.y)
	if top < 2.5:
		return # (nothing so tall it wants one)
	var wood := material("wood")
	var plank := material("plank")
	var ox := sz.x * 0.5 + 0.85
	var oz := sz.y * 0.5 + 0.85
	var h := top - 0.6
	# poles round it, every two metres or so
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.06
	pole.height = h + 0.6
	pole.radial_segments = 6
	for side in 4:
		var along := ox * 2.0 if side < 2 else oz * 2.0
		var n := maxi(1, int(along / 2.0))
		for k in n + 1:
			var t := -along * 0.5 + along * float(k) / n
			var at := Vector3(t, 0, (-oz if side == 0 else oz)) if side < 2 else Vector3((-ox if side == 2 else ox), 0, t)
			for off in [-0.35, 0.35]:
				var mi := MeshInstance3D.new()
				mi.mesh = pole
				mi.material_override = wood
				var o: Vector3 = at + (Vector3(0, 0, off) if side < 2 else Vector3(off, 0, 0))
				mi.position = o + Vector3(0, (h + 0.6) * 0.5 - 0.3, 0)
				_scaffold.add_child(mi)
	# the decks: ledgers and planks all round at each level
	var y := DECK
	while y < h:
		_decks.append(y)
		for side in 4:
			var long := (ox * 2.0 + 0.8) if side < 2 else (oz * 2.0 + 0.8)
			var deck := MeshInstance3D.new()
			var dm := BoxMesh.new()
			dm.size = Vector3(long, 0.05, 0.7) if side < 2 else Vector3(0.7, 0.05, long)
			deck.mesh = dm
			deck.material_override = plank
			deck.position = (Vector3(0, y, -oz if side == 0 else oz)) if side < 2 else Vector3(-ox if side == 2 else ox, y, 0)
			_scaffold.add_child(deck)
			var rail := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(long, 0.05, 0.05) if side < 2 else Vector3(0.05, 0.05, long)
			rail.mesh = rm
			rail.material_override = wood
			var out := 0.35
			rail.position = (Vector3(0, y + 0.9, (-oz - out) if side == 0 else (oz + out))) if side < 2 else Vector3((-ox - out) if side == 2 else (ox + out), y + 0.9, 0)
			_scaffold.add_child(rail)
		y += DECK


# --- Building it ------------------------------------------------------------------------------------

func total_cost() -> int:
	var n := 0
	for r: String in cost:
		n += int(cost[r])
	return n


func total_delivered() -> int:
	var n := 0
	for r: String in delivered:
		n += int(delivered[r])
	return n


## Still to be brought of `r` (not counting what's on its way).
func missing(r: String) -> int:
	return int(cost.get(r, 0)) - int(delivered.get(r, 0)) - int(incoming.get(r, 0))


func materials_share() -> float:
	var t := total_cost()
	return 1.0 if t == 0 else float(total_delivered()) / float(t)


## Being built or mended: wanting stuff and hands.
func under_work() -> bool:
	return state == "site" or state == "repair"


func _time() -> float:
	return _repair_time if state == "repair" else float(def.time)


## Whether a builder has anything to do here: stuff's come that isn't built into it yet.
func can_work() -> bool:
	if state == "site":
		return next_piece() >= 0
	return state == "repair" and work < _time() * materials_share() - 0.01


## A builder's `dt` of work. False once there's nothing more to do for now.
func add_work(dt: float) -> bool:
	if state != "repair":
		return false
	var cap := _time() * materials_share()
	if work >= cap:
		return false
	work = minf(work + dt, cap)
	_raise()
	if work >= _time() - 0.001 and total_delivered() >= total_cost():
		_finish()
		return false
	return true


func progress() -> float:
	if state == "site":
		return float(_shown) / float(maxi(pieces.size(), 1))
	return work / _time()


func _raise(instant := false) -> void:
	if state == "repair":
		var due := int(floor(progress() * _repair_list.size() + 0.0001))
		if progress() >= 1.0:
			due = _repair_list.size()
		while _repair_done < due:
			_put_back(pieces[_repair_list[_repair_done]])
			_repair_done += 1
		return
	if instant:
		pass


## A lamp's own post and lantern throw no shadow: its light is in among them, and they'd black out
## the ground round it.
func _shadow() -> GeometryInstance3D.ShadowCastingSetting:
	return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if def.role == "light" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## A piece into its place: from the builder's hands (`from`, in the building) or lowered from above,
## turning true as it settles, the dust thrown up where it lands, the knock of it.
func _put_up(p: Piece, animate: bool, from := Vector3.INF) -> void:
	p.built = true
	p.mesh.visible = true
	p.mesh.material_override = _look(p)
	p.mesh.cast_shadow = _shadow()
	p.shape.disabled = false
	var final := p.xf * p.mesh_local
	if animate:
		var lift := Transform3D(Basis(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized(), randf_range(0.08, 0.2)), Vector3.UP * randf_range(1.0, 1.6))
		var start := final.origin + lift.origin
		if from != Vector3.INF:
			start = from + Vector3.UP * 1.3 # (from its hands)
		p.mesh.transform = Transform3D(lift.basis * final.basis, start)
		var tw := p.mesh.create_tween()
		tw.tween_property(p.mesh, "transform", final, 0.4 if from != Vector3.INF else 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT if from != Vector3.INF else Tween.EASE_IN)
		tw.tween_callback(func() -> void: _dust(p.aabb.get_center() - Vector3(0, p.aabb.size.y * 0.5, 0)))
	else:
		p.mesh.transform = final
	if animate and _sound and _sound_t <= 0.0:
		_sound.stream = _stream(BUILD_SOUNDS[randi() % BUILD_SOUNDS.size()])
		_sound.pitch_scale = randf_range(0.8, 1.05)
		_sound.position = p.aabb.get_center()
		_sound.play()
		_sound_t = 0.25


static var _dust_mesh: QuadMesh


func _dust(at: Vector3) -> void:
	if not is_inside_tree():
		return
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, -0.5, 0)
	pm.scale_min = 0.4
	pm.scale_max = 0.9
	pm.color = Color(0.55, 0.47, 0.36, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.6))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var p := GPUParticles3D.new()
	p.amount = 8
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 0.9
	p.process_material = pm
	if _dust_mesh == null:
		_dust_mesh = FireFx._quad(0.8, false)
	p.draw_pass_1 = _dust_mesh
	p.position = at
	add_child(p)
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(1.6)
	tw.tween_callback(p.queue_free)


func _finish() -> void:
	upgraded_now = upgrading
	if upgrading != "":
		upgrading = ""
		_upgraded(upgraded_now)
	repaired = state == "repair" and upgraded_now == ""
	if state == "repair":
		cost = (def.cost as Dictionary).duplicate()
		for r: String in cost:
			delivered[r] = cost[r]
			incoming[r] = 0
		work = float(def.time)
		for p in pieces:
			if p.alive:
				p.hp = p.max_hp
	state = "done"
	if _stack:
		_stack.queue_free()
		_stack = null
	if _stakes:
		_stakes.queue_free()
		_stakes = null
	claims.clear()
	if def.role == "farm" and crop == null and nav:
		crop = Crop.new()
		crop.field = self
		crop.nav = nav
		add_child(crop)
	if _scaffold:
		_scaffold.queue_free()
		_scaffold = null
	if _sound and is_inside_tree():
		_sound.stream = _stream("heavy_01")
		_sound.pitch_scale = 0.9
		_sound.play()
	finished.emit(self)


# --- Mending ----------------------------------------------------------------------------------------

func fallen_count() -> int:
	var n := 0
	for p in pieces:
		if p.built and not p.alive:
			n += 1
	return n


func can_repair() -> bool:
	return (state == "done" or state == "ruin") and not is_burning() and fallen_count() > 0


## What mending it would take: its cost by the share of its pieces that are down.
func repair_cost() -> Dictionary:
	var share := float(fallen_count()) / float(pieces.size())
	var out := {}
	for r: String in def.cost:
		out[r] = maxi(1, ceili(float(def.cost[r]) * share * 1.1))
	return out


func start_repair() -> bool:
	if not can_repair():
		return false
	_mend(repair_cost(), maxf(6.0, float(def.time) * float(fallen_count()) / float(pieces.size()) * 1.2))
	return true


## The pieces that are down put back for `what`, over `secs` of work.
func _mend(what: Dictionary, secs: float) -> void:
	_repair_list.clear()
	for k in pieces.size():
		if pieces[k].built and not pieces[k].alive:
			_repair_list.append(k)
	cost = what
	delivered = {}
	incoming = {}
	for r: String in cost:
		delivered[r] = 0
		incoming[r] = 0
	_repair_time = secs
	_repair_done = 0
	work = 0.0
	state = "repair"
	if upgrading == "": # (what's done to a house is done off the ground)
		_make_scaffold()


# --- Made better ------------------------------------------------------------------------------------

## How many sleep here.
func beds() -> int:
	return BuildingDefs.UPGRADE_BEDS if level >= 2 else int(def.get("beds", 0))


## What it burns of a cold night, of what a plain house does.
func fuel_mul() -> float:
	return (BuildingDefs.SIVA_FUEL if plastered else 1.0) * (BuildingDefs.SOBA_FUEL if stove else 1.0)


## Whether `what` (BuildingDefs.UPGRADES) has been done to it.
func has_upgrade(what: String) -> bool:
	match what:
		"oda": return level >= 2
		"siva": return plastered
		"soba": return stove
	return false


func can_upgrade(what := "oda") -> bool:
	return def.role == "house" and not has_upgrade(what) and upgrading == "" and state == "done" and not is_burning() and fallen_count() == 0


## `what` done to the house as a mending: its stuff carried in and built on (the back room's or the
## stove's pieces, which weren't there before, going up one at a time). `resume`: (a loaded game)
## its pieces are already on.
func start_upgrade(what := "oda", resume := false) -> bool:
	if not resume and not can_upgrade(what):
		return false
	if not resume:
		match what:
			"oda": add_annex(false)
			"soba": add_stove(false)
	upgrading = what
	var up: Dictionary = BuildingDefs.UPGRADES[what]
	_mend((up.cost as Dictionary).duplicate(), float(up.time))
	return true


## Done: what was being done to it taken on.
func _upgraded(what: String) -> void:
	match what:
		"oda": level = 2
		"siva": plaster()
		"soba": stove = true


## Its logs plastered over with mud (a lighter, earthen look; mended ones are plastered too).
func plaster() -> void:
	plastered = true
	for p in pieces:
		if p.stuff == "log":
			p.daub = true
			if p.alive and not p.charred and is_instance_valid(p.mesh):
				p.mesh.material_override = _look(p)


## The back room's pieces on the building: standing (`up`), or not yet built.
func add_annex(up: bool) -> void:
	annex = BuildingDefs.ANNEX
	_add_extra(BuildingDefs.annex(), up)


## The stove's flue on the building: standing (`up`), or not yet built.
func add_stove(up: bool) -> void:
	_add_extra(BuildingDefs.stove(), up)


func _add_extra(specs: Array[Dictionary], up: bool) -> void:
	var first := pieces.size()
	for spec in specs:
		_add_piece(spec)
	for k in range(first, pieces.size()):
		var p := pieces[k]
		p.stage = _stage_of(p)
		p.res = "tas" if p.stuff == "stone" else "odun"
		p.built = true
		body.add_child(p.shape)
		add_child(p.mesh)
		p.mesh.cast_shadow = _shadow()
		if not up:
			p.alive = false
			p.mesh.visible = false
			p.shape.disabled = true
	for p in pieces:
		p.supports.clear()
		p.near.clear()
		p.grounded = false
	_link()


## A fallen piece back in its place, its rubble cleared away.
func _put_back(p: Piece) -> void:
	var res := p.mesh_res
	if is_instance_valid(p.mesh) and p.mesh.get_parent() == self: # (hidden on a loaded game)
		p.mesh.queue_free()
	if is_instance_valid(p.debris):
		p.debris.queue_free()
	p.debris = null
	var mi := MeshInstance3D.new()
	mi.mesh = res
	mi.material_override = _look(p)
	mi.cast_shadow = _shadow()
	mi.transform = p.xf * p.mesh_local
	add_child(mi)
	p.mesh = mi
	p.shape.set_deferred("disabled", false)
	p.alive = true
	p.hp = p.max_hp
	p.burn = 0.0
	p.wet = 0.0
	p.charred = false
	if _sound and _sound_t <= 0.0:
		_sound.stream = _stream(BUILD_SOUNDS[randi() % BUILD_SOUNDS.size()])
		_sound.position = p.aabb.get_center()
		_sound.play()
		_sound_t = 0.25


## As it was saved: what had fallen (gone, its rubble cleared) and what had charred.
func apply_damage(alive: PackedByteArray, charred: PackedByteArray) -> void:
	for k in mini(pieces.size(), alive.size()):
		var p := pieces[k]
		if alive[k] == 0 and p.built:
			p.alive = false
			p.mesh.visible = false
			p.shape.disabled = true
		elif k < charred.size() and charred[k] == 1:
			p.charred = true
			p.mesh.material_override = material("char")


## A house's hearth: smoke from the chimney while it burns (if the chimney's still standing).
func set_hearth(on: bool) -> void:
	var stack_up := false
	var smoke_at := Vector3(1.9, 5.8, -1.7)
	for p in pieces:
		if p.tag == "chimneytop" and p.alive:
			stack_up = true
			smoke_at = Vector3(p.aabb.get_center().x, p.aabb.end.y + 0.1, p.aabb.get_center().z)
		elif p.tag == "" and p.stuff == "stone" and p.ext.x < 1.0 and p.ext.y > 4.0 and p.alive:
			stack_up = true
	on = on and stack_up
	if on and _chimney == null:
		_chimney = FireFx.smoke(false)
		_chimney.amount = 22
		_chimney.lifetime = 9.0
		(_chimney.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.15, 0.1, 0.15)
		(_chimney.process_material as ParticleProcessMaterial).initial_velocity_min = 0.6
		(_chimney.process_material as ParticleProcessMaterial).initial_velocity_max = 1.2
		# wood smoke: a bluish grey thinning to nothing
		(_chimney.process_material as ParticleProcessMaterial).color_ramp = FireFx._ramp([Color(0.32, 0.33, 0.36, 0.0),
			Color(0.42, 0.43, 0.46, 0.28), Color(0.55, 0.56, 0.58, 0.1), Color(0.6, 0.6, 0.62, 0.0)], [0.0, 0.12, 0.5, 1.0])
		# (a thin wisp, not a cloud: smaller, fainter, fewer)
		(_chimney.process_material as ParticleProcessMaterial).scale_min = 0.55
		(_chimney.process_material as ParticleProcessMaterial).scale_max = 1.0
		_chimney.amount = 16
		(_chimney.draw_pass_1 as QuadMesh).size = Vector2(1.0, 1.0)
		_chimney.position = smoke_at
		add_child(_chimney)
	if _chimney:
		_chimney.emitting = on
		# Laid over by the wind: straight up on a still morning, streaming off in a breeze.
		var w := Weather.wind_now
		(_chimney.process_material as ParticleProcessMaterial).gravity = Vector3(w.x * 0.55, 0.45 / (1.0 + w.length() * 0.25), w.z * 0.55)
		# coal on the fire: a thicker, darker smoke
		var coal := coal_burn > 0
		if coal != _coal_smoke:
			_coal_smoke = coal
			(_chimney.process_material as ParticleProcessMaterial).color_ramp = FireFx._ramp([Color(0.12, 0.12, 0.12, 0.0),
				Color(0.18, 0.18, 0.19, 0.42), Color(0.32, 0.32, 0.33, 0.18), Color(0.45, 0.45, 0.46, 0.0)], [0.0, 0.12, 0.5, 1.0]) if coal else FireFx._ramp([Color(0.32, 0.33, 0.36, 0.0),
				Color(0.42, 0.43, 0.46, 0.28), Color(0.55, 0.56, 0.58, 0.1), Color(0.6, 0.6, 0.62, 0.0)], [0.0, 0.12, 0.5, 1.0])


## Its chimney smoking.
func smoking() -> bool:
	return _chimney != null and _chimney.emitting


## Its night light: a lamp's flame, a house's windows. (A lamp whose post is down gives none.)
func set_lit(on: bool) -> void:
	if def.role == "light":
		for p in pieces:
			if p.stuff == "window" and not p.alive:
				on = false
	lit = on
	if on and _glow == null:
		_glow = OmniLight3D.new()
		if def.role == "light":
			_glow.position = Vector3(0.7, 3.0, 0)
			for p in pieces:
				if p.stuff == "window":
					_glow.position = p.aabb.get_center() + Vector3.DOWN * 0.1
			_glow.omni_range = float(def.light) + 4.0
			_glow.light_energy = 5.0
			_glow.omni_attenuation = 0.9
			_glow.light_volumetric_fog_energy = 0.6
			_glow.shadow_enabled = true
			_glow.distance_fade_enabled = true
			_glow.distance_fade_begin = 220.0
			_glow.distance_fade_length = 60.0
		else:
			_glow.position = Vector3(0, 1.6, (def.size as Vector2).y * 0.5 + 0.8)
			_glow.omni_range = 8.0
			_glow.light_energy = 0.9
			_glow.light_volumetric_fog_energy = 0.4
		_glow.light_color = Color(1.0, 0.68, 0.36)
		if def.role != "light":
			_glow.shadow_enabled = false
		add_child(_glow)
	if _glow:
		_glow.visible = on


## The watch's lantern: hung up under a lookout tower's roof while someone's up there, or by a
## guardhouse's door all night.
var _watch: Node3D


func set_watch_light(on: bool) -> void:
	if on and _watch == null:
		_watch = Node3D.new()
		var tower: bool = def.role == "tower"
		_watch.position = Vector3(0, 10.9, 0) if tower else Vector3(1.1, 2.3, (def.size as Vector2).y * 0.5 + 0.15)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.32, 0.22)
		box.mesh = bm
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.75, 0.4)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.62, 0.25)
		glow.emission_energy_multiplier = 4.0
		box.material_override = glow
		_watch.add_child(box)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.66, 0.32)
		l.omni_range = 20.0 if tower else 12.0
		l.light_energy = 2.6 if tower else 1.8
		l.light_volumetric_fog_energy = 0.4
		l.position = Vector3.DOWN * 0.25
		l.shadow_enabled = false
		_watch.add_child(l)
		add_child(_watch)
	if _watch:
		_watch.visible = on
	if def.role == "tower":
		lit = on


## The square's evening fire: flames in the pit, its light, a little smoke.
var _fire: Array[Node3D] = []


func set_fire(on: bool) -> void:
	if on and _fire.is_empty():
		var at := Vector3(0, 0.6, 0)
		for p in pieces:
			if p.tag == "fire":
				at = p.aabb.get_center()
		var f := FireFx.flames()
		f.amount = 24
		f.position = at
		(f.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.3, 0.2, 0.3)
		add_child(f)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.28)
		l.light_energy = 3.5
		l.omni_range = 14.0
		l.light_volumetric_fog_energy = 0.2
		l.position = at + Vector3.UP * 0.6
		add_child(l)
		var s := FireFx.smoke()
		s.amount = 12
		s.position = at + Vector3.UP * 0.8
		(s.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.3, 0.2, 0.3)
		add_child(s)
		_fire = [f, l, s]
	for n in _fire:
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = on
		else:
			n.visible = on
	lit = on


## The bell swung and sounded (`times` strokes, `gap` s apart).
func ring(times := 3, gap := 1.6) -> void:
	for p in pieces:
		if p.tag != "bell" or not p.alive:
			continue
		var base := p.xf * p.mesh_local
		var pivot := p.aabb.end + Vector3(0, 0.05, 0)
		pivot.x = p.aabb.get_center().x
		pivot.z = p.aabb.get_center().z
		var tw := p.mesh.create_tween()
		for k in times:
			for ang in [0.45, -0.45]:
				tw.tween_method(func(a: float) -> void:
					p.mesh.transform = Transform3D(Basis(Vector3.RIGHT, a), pivot) * Transform3D(Basis.IDENTITY, -pivot) * base, 0.0, ang, gap * 0.25)
				tw.tween_method(func(a: float) -> void:
					p.mesh.transform = Transform3D(Basis(Vector3.RIGHT, a), pivot) * Transform3D(Basis.IDENTITY, -pivot) * base, ang, 0.0, gap * 0.25)
			tw.tween_callback(Ambience.bell.bind(p.aabb.get_center() + global_position))
		tw.tween_callback(func() -> void: p.mesh.transform = base)


## How far its light reaches when lit (0: none).
func light_reach() -> float:
	if not lit:
		return 0.0
	if def.role == "square":
		return 14.0
	if def.role == "tower":
		return 20.0
	return float(def.light) if def.role == "light" else 8.0


# --- Goods ----------------------------------------------------------------------------------------

const PILE_MAX := 24 ## what a workplace's yard holds piled, unless its kind says ("holds")
const SIDING_MAX := 120 ## a workplace on a side line: piled by the rails for the train


## How much it holds: a store all told, a workplace in its pile (more by a side line).
func holds() -> int:
	if spur and def.role == "work":
		return SIDING_MAX
	return int(def.get("holds", PILE_MAX))


## Room left in it.
func room() -> int:
	return holds() - goods_total()


func goods_total() -> int:
	var n := 0
	for r: String in goods:
		n += int(goods[r])
	return n


func add_goods(r: String, n: int) -> void:
	goods[r] = int(goods.get(r, 0)) + n
	if def.role in ["work", "farm"]:
		_show_pile()


## Takes up to `n` of `r`; what it could.
func take_goods(r: String, n: int) -> int:
	var k := mini(n, int(goods.get(r, 0)))
	goods[r] = int(goods.get(r, 0)) - k
	if def.role in ["work", "farm"]:
		_show_pile()
	return k


## A workplace's pile by its door: a log, a stone or a basket for every few it holds.
func _show_pile() -> void:
	var n := mini(ceili(goods_total() / 3.0), 12)
	if n == _pile_shown:
		return
	_pile_shown = n
	if _pile:
		_pile.queue_free()
		_pile = null
	if n == 0:
		return
	_pile = Node3D.new()
	var sz: Vector2 = def.size
	_pile.position = def.get("pile", Vector3(sz.x * 0.5 + 1.0, 0.0, sz.y * 0.5 - 0.6)) + Vector3(0, 0.4, 0)
	add_child(_pile)
	var res := biggest_good()
	for k in n:
		var mi := MeshInstance3D.new()
		match res:
			"odun":
				var c := CylinderMesh.new()
				c.top_radius = 0.16
				c.bottom_radius = 0.17
				c.height = 1.6
				c.radial_segments = 8
				mi.mesh = c
				mi.material_override = material("wood")
				mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3((k % 4) * 0.34 - 0.5 + (k / 4) * 0.17, 0.17 + (k / 4) * 0.3, 0))
			"tas":
				# a heap of broken rock, the bigger lumps at the bottom
				mi.mesh = rock(k)
				mi.material_override = rock_material(k * 3 + 1)
				mi.scale = Vector3.ONE * randf_range(0.48, 0.62) * (1.0 - (k / 4) * 0.12)
				mi.position = Vector3((k % 4) * 0.42 - 0.63 + (k / 4) * 0.2, 0.14 + (k / 4) * 0.24, randf_range(-0.15, 0.15))
				mi.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
			"camur": # (a wet heap: lumps slopped one on another, slumping)
				mi.mesh = rock(k)
				mi.material_override = mud_material()
				var s := (0.62 - (k / 4) * 0.1) * randf_range(0.85, 1.1)
				mi.scale = Vector3(s, s * 0.45, s * 1.1)
				mi.position = Vector3((k % 4) * 0.36 - 0.54 + (k / 4) * 0.18, 0.02 + (k / 4) * 0.11, randf_range(-0.2, 0.2))
				mi.rotation.y = randf() * TAU
			"kerpic": # (stacked in courses, crosswise each course)
				mi.mesh = _brick_mesh()
				mi.material_override = clay_material(k)
				var course := k / 4
				mi.position = Vector3((k % 4) * 0.3 - 0.45, -0.32 + course * 0.13, 0) if course % 2 == 0 else Vector3(0, -0.32 + course * 0.13, (k % 4) * 0.3 - 0.45)
				mi.rotation.y = 0.0 if course % 2 == 0 else PI * 0.5
			_:
				var c := CylinderMesh.new()
				c.top_radius = 0.22
				c.bottom_radius = 0.17
				c.height = 0.3
				c.radial_segments = 10
				mi.mesh = c
				mi.material_override = material("thatch")
				mi.position = Vector3((k % 4) * 0.48 - 0.7, 0.15 + (k / 4) * 0.31, 0)
		_pile.add_child(mi)


## What there's most of in its pile (its own work's goods if none).
func biggest_good() -> String:
	var res := str(def.get("res", "odun"))
	var top := 0
	for k: String in goods:
		if int(goods[k]) > top:
			top = int(goods[k])
			res = k
	return res


static var _mud_mat: StandardMaterial3D
static var _brick: BoxMesh


static func mud_material() -> StandardMaterial3D:
	if _mud_mat == null:
		_mud_mat = StandardMaterial3D.new()
		_mud_mat.albedo_color = Color(0.24, 0.17, 0.11)
		_mud_mat.roughness = 0.35 # (wet)
	return _mud_mat


static var _clays: Array[StandardMaterial3D] = []


## A dry mud brick's colour: a few earths, a brick to brick difference.
static func clay_material(i: int) -> StandardMaterial3D:
	if _clays.is_empty():
		for c in [Color(0.68, 0.56, 0.4), Color(0.62, 0.5, 0.35), Color(0.72, 0.61, 0.45), Color(0.58, 0.47, 0.34)]:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.97
			_clays.append(m)
	return _clays[i % _clays.size()]


static func _brick_mesh() -> BoxMesh:
	if _brick == null:
		_brick = BoxMesh.new()
		_brick.size = Vector3(0.28, 0.12, 0.16)
	return _brick


# --- A mud pit's bricks ---------------------------------------------------------------------------

const DRY_TIME := 90.0 ## s a brick takes to dry in the sun

## `n` bricks pressed into moulds and laid out on the racks to dry.
func lay_to_dry(n: int) -> void:
	drying.append(Vector2(DRY_TIME, n))
	_show_racks()


## `t` s of drying at `rate` (1 in the sun, less in the rain, none under snow): those dry go on the pile.
func dry(t: float, rate: float) -> int:
	var done := 0
	for i in range(drying.size() - 1, -1, -1):
		drying[i].x -= t * rate
		if drying[i].x <= 0.0:
			done += int(drying[i].y)
			drying.remove_at(i)
	if done > 0:
		add_goods("kerpic", done)
		_show_racks()
	return done


func drying_count() -> int:
	var n := 0
	for d in drying:
		n += int(d.y)
	return n


## The bricks drying, in rows on the straw under the drying shelter at the back left (the model's;
## the weather still has its say: Village._dry_bricks), pale once they're nearly dry.
func _show_racks() -> void:
	if _racks:
		_racks.queue_free()
		_racks = null
	if drying.is_empty():
		return
	_racks = Node3D.new()
	add_child(_racks)
	var wet := mud_material()
	var k := 0
	for d in drying:
		for j in int(d.y):
			if k >= 24:
				break
			var mi := MeshInstance3D.new()
			mi.mesh = _brick_mesh()
			mi.material_override = clay_material(k) if d.x < DRY_TIME * 0.4 else wet
			var lx := -2.4 + (k % 6) * 0.4
			var lz := -0.85 - (k / 6) * 0.3
			var ground := global_transform * Vector3(lx, 0, lz)
			# (on the straw, or on the ground where the land stands higher than it)
			var y := maxf(0.55, (nav.height(ground.x, ground.z) - global_position.y + 0.06) if nav else 0.0)
			mi.position = Vector3(lx, y, lz)
			mi.rotation.y = (k * 0.37 - floorf(k * 0.37)) * 0.12 - 0.06 # (laid by hand, not quite square)
			_racks.add_child(mi)
			k += 1


static func _stream(id: String) -> AudioStream:
	if not _streams.has(id):
		_streams[id] = load("res://assets/audio/build/%s.wav" % id)
	return _streams[id]


## Where a villager stands to go in or work at it: in front of its door.
func door() -> Vector3:
	var sz: Vector2 = def.size
	return global_transform * Vector3(0, 0, sz.y * 0.5 + 1.3)


## Where someone stands once in through the door, on the floor.
func inside() -> Vector3:
	var sz: Vector2 = def.size
	return global_transform * Vector3(0, 0.47, sz.y * 0.5 - 1.1)


func has_door() -> bool:
	for d in _doors:
		if (d[0] as Piece).alive and (d[0] as Piece).built:
			return true
	return false


## Where a worker stands to do the yard's work (in the world), and what it faces.
func station() -> Vector3:
	return global_transform * (def.get("station", Vector3(0, 0, (def.size as Vector2).y * 0.5 - 0.6)) + Vector3(0, 0.4, 0))


func station_face() -> Vector3:
	return global_transform * def.get("face", Vector3.ZERO)


## Someone's at the door: it swings in and stays open a moment.
func open_door(hold := 2.2) -> void:
	_door_hold = maxf(_door_hold, hold)


func _swing_doors(dt: float) -> void:
	_door_hold -= dt
	var want := 1.0 if _door_hold > 0.0 else 0.0
	if is_equal_approx(_door_open, want):
		return
	_door_open = move_toward(_door_open, want, dt * 2.2)
	var k := smoothstep(0.0, 1.0, _door_open)
	for d in _doors:
		var p: Piece = d[0]
		if not p.alive or not p.built or p.mesh.get_parent() != self:
			continue
		var h: Vector3 = d[1]
		p.mesh.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(100.0) * float(d[2]) * k), h) * Transform3D(Basis.IDENTITY, -h) * p.xf * p.mesh_local


func center() -> Vector3:
	return global_position + Vector3.UP * 1.5


func display_name() -> String:
	var what := BuildingDefs.workshop_of(self)
	if what != "":
		return "Atölye (%s)" % BuildingDefs.WORKSHOP[what].word
	return str(def.name)


# --- Fire and falling ----------------------------------------------------------------------------

func is_burning() -> bool:
	if crop and crop.burning > 0.0:
		return true
	for p in pieces:
		if p.burn > 0.0:
			return true
	return false


func burning_count() -> int:
	var n := 0
	for p in pieces:
		if p.burn > 0.0:
			n += 1
	return n


## Sets a piece alight (one at random that can burn, if -1). False if nothing would catch.
func ignite(i := -1) -> bool:
	if crop and crop.ignite():
		return true
	var can: Array[int] = []
	for k in pieces.size():
		var p := pieces[k]
		if p.alive and p.built and p.burn <= 0.0 and BuildingDefs.STUFF[p.stuff].burns:
			can.append(k)
	if can.is_empty():
		return false
	var k := i if i >= 0 and i in can else can[randi() % can.size()]
	pieces[k].burn = 0.01
	pieces[k].wet = 0.0
	return true


## A bucket of water thrown on it: puts out a piece or two and soaks what's round them.
func douse() -> void:
	if crop and crop.burning > 0.0 and randf() < 0.35:
		crop.burning = 0.0
		for f in crop._flames:
			f.emitting = false
	var lit: Array[Piece] = []
	for p in pieces:
		if p.burn > 0.0:
			lit.append(p)
	lit.shuffle()
	for k in mini(3, lit.size()):
		if randf() < 0.75:
			lit[k].burn = 0.0
			lit[k].wet = 30.0
			for n in lit[k].near:
				pieces[n].wet = maxf(pieces[n].wet, 12.0)


func standing_share() -> float:
	var all := 0.0
	var up := 0.0
	for p in pieces:
		if p.built:
			var v := p.ext.x * p.ext.y * p.ext.z
			all += v
			if p.alive:
				up += v
	return 1.0 if all <= 0.0 else up / all


func _process(dt: float) -> void:
	_sound_t -= dt
	if state == "ghost" or state == "gone":
		return
	if not _doors.is_empty():
		_swing_doors(dt)

	_fire_t += dt
	if _fire_t < 0.25:
		_flicker()
		return
	var t := _fire_t
	_fire_t = 0.0
	var any := false
	var rain := Weather.rain_now
	for p in pieces:
		if p.wet > 0.0:
			p.wet -= t
		if p.burn <= 0.0 or not p.alive:
			continue
		any = true
		var st: Dictionary = BuildingDefs.STUFF[p.stuff]
		p.burn += t
		p.hp -= p.max_hp * t / float(st.burn)
		if rain > 0.25 and randf() < rain * 0.025 * t * 4.0:
			p.burn = 0.0
			p.wet = 20.0
			continue
		if not p.charred and p.burn > float(st.burn) * 0.35:
			p.charred = true
			p.mesh.material_override = material("char")
		for n in p.near:
			var q := pieces[n]
			if q.alive and q.built and q.burn <= 0.0 and q.wet <= 0.0 and BuildingDefs.STUFF[q.stuff].burns:
				if randf() < float(BuildingDefs.STUFF[q.stuff].catch) * t * 2.5 * (1.0 - rain * 0.6):
					q.burn = 0.01
		if p.hp <= 0.0:
			_break(p)
	if any:
		_fire_fx()
		_scorch_t += t
		if _scorch_t >= 1.0 and nav:
			nav.scorch(global_position, radius + 2.5, 0.05 * _scorch_t)
			_scorch_t = 0.0
		if state in ["done", "site", "repair"] and standing_share() < 0.45:
			_to_ruin()
	elif _light:
		_fire_fx()


func _break(p: Piece) -> void:
	if not p.alive:
		return
	_drop(p, Vector3.ZERO)
	_restand()


## What's left worked out again from the ground up: a piece with less than a third of what it
## rested on still standing lets go.
func _restand() -> void:
	var changed := true
	while changed:
		changed = false
		for p in pieces:
			if not p.alive or not p.built or p.grounded:
				continue
			var up := 0
			var had := 0
			for i in p.supports:
				if pieces[i].built:
					had += 1
					if pieces[i].alive:
						up += 1
			if had > 0 and up * 3 < had:
				_drop(p, Vector3.ZERO)
				changed = true


## The piece comes away: a body of its own, falling as physics has it, gone a while later.
func _drop(p: Piece, push: Vector3) -> void:
	p.alive = false
	var was_burning := p.burn > 0.0
	p.burn = 0.0
	p.shape.set_deferred("disabled", true)
	if not p.built or not is_inside_tree():
		p.mesh.visible = false
		return
	var rb := RigidBody3D.new()
	rb.collision_layer = 4
	rb.collision_mask = 1 | 2 | 4
	var st: Dictionary = BuildingDefs.STUFF[p.stuff]
	rb.mass = clampf(p.ext.x * p.ext.y * p.ext.z * float(st.density), 5.0, 4000.0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = p.ext
	cs.shape = box
	cs.position = p.center
	rb.add_child(cs)
	var world_xf := global_transform * p.xf
	remove_child(p.mesh)
	rb.add_child(p.mesh)
	p.mesh.transform = p.mesh_local
	if was_burning:
		p.mesh.material_override = material("char")
	get_parent().add_child(rb)
	rb.global_transform = world_xf
	rb.linear_velocity = push + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	rb.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.8
	p.debris = rb
	# something big coming down: dust where it lands (once a second at most, per building)
	var now := Time.get_ticks_msec()
	if p.ext.length() > 1.6 and now - _dust_ms > 900:
		_dust_ms = now
		var heavy := clampf(p.ext.length() / 4.0, 0.6, 1.6)
		get_tree().create_timer(0.8, false).timeout.connect(func() -> void:
			if is_instance_valid(rb):
				FireFx.dust(rb.get_parent(), rb.global_position, heavy))
	var tw := rb.create_tween() # (its own: gone with it if it's cleared first)
	tw.tween_interval(12.0)
	tw.tween_callback(rb.set.bind("freeze", true))


## Rubble sinks away a while after: what's left once a building's gone for good.
static func _sink_later(rb: RigidBody3D, after: float) -> void:
	var tw := rb.create_tween()
	tw.tween_interval(after)
	tw.tween_callback(rb.set.bind("freeze", true))
	tw.tween_property(rb, "position:y", rb.position.y - 1.5, 6.0)
	tw.tween_callback(rb.queue_free)


func _to_ruin() -> void:
	state = "ruin"
	ruined.emit(self)


## Pulled down: everything still up comes away, thrown out a little from the middle.
func demolish() -> void:
	for p in pieces:
		if p.alive and p.built:
			var out := (p.aabb.get_center() * Vector3(1, 0, 1)).normalized()
			_drop(p, global_transform.basis * out * randf_range(0.5, 2.0))
	state = "gone"
	_stop_fx()
	for p in pieces:
		if is_instance_valid(p.debris):
			_sink_later(p.debris, randf_range(70.0, 110.0))
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(queue_free)


# --- Fire's look ------------------------------------------------------------------------------------

func _fire_fx() -> void:
	var lit: Array[Piece] = []
	for p in pieces:
		if p.burn > 0.0 and p.alive:
			lit.append(p)
	if lit.is_empty():
		_stop_fx()
		return
	if _smoke == null:
		_smoke = FireFx.smoke()
		add_child(_smoke)
		_embers = FireFx.embers()
		add_child(_embers)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.55, 0.22)
		_light.omni_range = 18.0
		_light.shadow_enabled = false
		_light.light_volumetric_fog_energy = 0.15 # (more and the fog round it lights up in hard squares)
		add_child(_light)
	var sz: Vector2 = def.size
	var top := 0.0
	var mid := Vector3.ZERO
	for p in lit:
		top = maxf(top, p.aabb.end.y)
		mid += p.aabb.get_center()
	mid /= lit.size()
	_smoke.position = Vector3(0, top, 0)
	(_smoke.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(sz.x * 0.4, 0.5, sz.y * 0.4)
	_smoke.amount_ratio = clampf(0.3 + lit.size() * 0.12, 0.3, 1.0)
	_smoke.emitting = true
	_embers.position = Vector3(0, top * 0.8, 0)
	(_embers.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(sz.x * 0.35, 0.5, sz.y * 0.35)
	_embers.amount_ratio = clampf(0.2 + lit.size() * 0.1, 0.2, 1.0)
	_embers.emitting = true
	_light.position = mid + Vector3.UP * 0.8
	_light.set_meta("energy", clampf(1.5 + lit.size() * 0.5, 1.5, 6.0))
	for k in MAX_FLAMES:
		if k >= _flames.size():
			if k >= lit.size():
				break
			var f := FireFx.flames()
			add_child(f)
			_flames.append(f)
		var fl := _flames[k]
		if k < lit.size():
			var p := lit[k]
			fl.position = p.aabb.get_center()
			(fl.process_material as ParticleProcessMaterial).emission_box_extents = (p.aabb.size * 0.45).clamp(Vector3(0.1, 0.1, 0.1), Vector3(3, 2, 3))
			fl.emitting = true
		else:
			fl.emitting = false


func _flicker() -> void:
	if _light and _light.has_meta("energy"):
		_light.light_energy = float(_light.get_meta("energy")) * randf_range(0.7, 1.15)


func _stop_fx() -> void:
	for f in _flames:
		f.emitting = false
	if _smoke:
		_smoke.emitting = false
	if _embers:
		_embers.emitting = false
	if _light:
		_light.light_energy = 0.0
		_light.remove_meta("energy")
