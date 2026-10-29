class_name CageArena
extends Node3D
## The cage: a square floor HALF m each way of the middle, walled with concrete to 1.2 m and a steel
## catch fence on posts over it to 5.5 m, a hazard stripe round its edge, a red corner and a blue one
## to start from; all round it the stadium (Stadium: Prototip Deneme Sahası 07), two tiers of its
## crowd that sway, and come up on their feet cheering with `excite`, its LED screens on the roof,
## floodlights along the roof's edge.
##
## Two other corners are the house robots' patrol zones, hatched yellow and black (HOUSE_ZONES).
##
## Each round lays its own floor (set_round): the ground's zones (mud, bog, ice, gravel, snow), the
## pit (a steel lid flush with the floor that, at its time, slides away under flashing lights and a
## siren: what goes over it falls), and its hazards — spike strips that bite the parts that run over them, flame vents that roar up every
## few seconds, chain-link fence islands to fight round, breakable blocks and drums, spinners (a
## toothed drum on the floor spinning flat out: what touches it is torn at and flung off sideways) and
## floor saws (a toothed blade up out of a slot, running to and fro along it, cutting what's over it).
##
## A round's floor is also a maze (plan): N x N cells of CELL m, a walk cut through every one of them
## (so all of it's reachable) and a share of the walls taken out again for loops to flank by, the
## walls containers end to end, double rows of concrete barriers or sandbags and blocks, a block for a
## pillar where walls meet; the round's hazards in cells of their own, cover in the rest. New each
## round and each run (by its seed). The rivals find their way through it by the cells (route).

const HALF := 80.0
const N := 7
const CELL := HALF * 2.0 / N ## m (about 23)
const OPEN := 0.3 ## of the maze's walls taken out again (loops)
const RED := Vector2i(0, 0) ## your corner's cell
const BLUE := Vector2i(N - 1, N - 1) ## the rivals'
const _DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const A := "res://assets/arena/"
const SPIKE_DAMAGE := 22.0 ## hp a bite
const FIRE_DAMAGE := 26.0 ## hp a lick at the middle
const HOUSE_ZONES := [Rect2(-HALF, HALF - 14.0, 14, 14), Rect2(HALF - 14.0, -HALF, 14, 14)] ## (x, z)
const SPINNER_DAMAGE := 34.0 ## hp a tooth's bite (every BLADE_TICK s while it's touching)
const SAW_DAMAGE := 26.0
const BLADE_TICK := 0.15
const SPINNER_FLING := 1800.0 ## N s sideways a bite flings it off

var terrain: TestTerrain
var stadium: Stadium
var _lights: Array[SpotLight3D] = []
var _hazards: Node3D
var _spikes: Array[Area3D] = []
var _vents: Array[Dictionary] = [] ## {area, fire, light, t, period, offset}
var _bite := {} ## Machine -> s till the spikes bite it again
var _t := 0.0
var pit := Rect2() ## (x, z) this round's pit (none: no size)
var pit_open := false
var _pit_node: Node3D
var _pit_lid: Node3D
var _pit_lights: Array[OmniLight3D] = []
var _pit_warn := 0.0
var _zones_now := [] ## (this round's zones, the pit added to them when it opens)
var _spinners: Array[Dictionary] = [] ## {node, area, at, r}
var _saws: Array[Dictionary] = [] ## {node, blade, area, a, b, u, dir}
var _cut := {} ## Machine -> s till a blade bites it again
var layout := {} ## this round's (what set_round was given)
var open := {} ## the maze's: [Vector2i, Vector2i] (the lower first) -> true: no wall between
var walls: Array = [] ## the maze's closed sides: [Vector2 from, Vector2 to]


func _ready() -> void:
	add_to_group("cage_arena")
	_floor_marks()
	_walls()
	stadium = Stadium.new()
	stadium.terrain = terrain
	stadium.r0 = HALF + 3.0
	add_child(stadium)
	_floodlights()
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
	var n := 80
	for side in 4:
		for k in n:
			var along := -HALF + (k + 0.5) * HALF * 2.0 / n
			var p := Vector3(along, 0.0, -HALF + 0.6)
			var b := Basis(Vector3.UP, side * PI * 0.5)
			p = b * p
			p.y = _h(p.x, p.z) + 0.02
			_box(Vector3(HALF * 2.0 / n - 0.05, 0.02, 0.6), Transform3D(b, p), yellow if k % 2 == 0 else black)
	# the house robots' patrol zones: hatched
	for z: Rect2 in HOUSE_ZONES:
		var hatch := 8
		for k in hatch:
			var c := z.position + Vector2((k + 0.5) * z.size.x / hatch, z.size.y * 0.5)
			var y := _h(c.x, c.y) + 0.022
			_box(Vector3(z.size.x / hatch * 0.45, 0.02, z.size.y * 1.38), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(c.x, y, c.y)),
				yellow if k % 2 == 0 else black)
		var cy := _h(z.get_center().x, z.get_center().y) + 0.025
		for e: Array in [[Vector3(z.size.x, 0.02, 0.3), Vector3(0, 0, -z.size.y * 0.5)], [Vector3(z.size.x, 0.02, 0.3), Vector3(0, 0, z.size.y * 0.5)],
				[Vector3(0.3, 0.02, z.size.y), Vector3(-z.size.x * 0.5, 0, 0)], [Vector3(0.3, 0.02, z.size.y), Vector3(z.size.x * 0.5, 0, 0)]]:
			_box(e[0], Transform3D(Basis.IDENTITY, Vector3(z.get_center().x, cy, z.get_center().y) + (e[1] as Vector3)), yellow)
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
		for k in 41:
			var p := b * Vector3(-HALF + k * HALF * 2.0 / 40.0, 0.0, -HALF - 0.2)
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


## The floodlights on the stadium's roof edge, at its corners and its sides' middles, on the floor
## (not the stands: they've their own glow).
func _floodlights() -> void:
	for k in 12:
		var a := k * TAU / 12.0 + PI * 0.25
		var p := Vector3(cos(a), 0.0, sin(a))
		p = p / maxf(absf(p.x), absf(p.z)) * (stadium.roof_from - 1.0)
		var l := SpotLight3D.new()
		l.position = p + Vector3.UP * (Stadium.ROOF_H - 1.5)
		add_child(l)
		l.look_at(-p * 0.2, Vector3.UP)
		l.spot_range = 210.0
		l.spot_angle = 42.0
		l.spot_attenuation = 0.45
		l.light_energy = 0.0
		l.light_color = Color(0.94, 0.97, 1.0)
		l.light_cull_mask = 0xFFFFF & ~Stadium.LAYER
		l.shadow_enabled = k == 0 # (one casts: the cars' shadows on the floor; the others fill)
		_lights.append(l)


## Night: the floodlights on, the stadium lit.
func set_night(on: bool) -> void:
	for l in _lights:
		l.light_energy = 8.0 if on else 0.0
	stadium.set_night(on)


## The audience: 0 sitting .. 1 on their feet.
func set_excite(v: float) -> void:
	if stadium and stadium.crowd_mat:
		stadium.set_excite(v)


# --- A round's floor -----------------------------------------------------------------------------

## Lays the floor for a round: {zones: [[Rect2, preset]], spikes: [Rect2], vents: [Vector2],
## fences: [[Vector2 from, Vector2 to]], blocks: [Vector2], drums: [Vector2], spinners: [Vector2],
## saws: [[Vector2, Vector2]], pit: Rect2} and a maze's (plan): open, walls: [[Vector2, Vector2, kind]],
## cover: [[kind, Vector2, yaw]].
func set_round(p_layout: Dictionary) -> void:
	layout = p_layout
	for c in _hazards.get_children():
		c.queue_free()
	_spikes.clear()
	_vents.clear()
	_bite.clear()
	_pit_lights.clear()
	_spinners.clear()
	_saws.clear()
	_cut.clear()
	var zones := []
	for z: Array in layout.get("zones", []):
		zones.append([z[0], Surface.preset(z[1])])
	_zones_now = zones
	terrain.set_zones(zones)
	pit = layout.get("pit", Rect2())
	pit_open = false
	_pit_warn = 0.0
	if pit.size.x > 0.0:
		_build_pit()
	for r: Rect2 in layout.get("spikes", []):
		_spike_strip(r)
	var k := 0
	for v: Vector2 in layout.get("vents", []):
		_vent(v, k)
		k += 1
	for f: Array in layout.get("fences", []):
		_fence(f[0], f[1])
	for sp: Vector2 in layout.get("spinners", []):
		_spinner(sp)
	for sw: Array in layout.get("saws", []):
		_saw(sw[0], sw[1])
	for b: Vector2 in layout.get("blocks", []):
		_hazards.add_child(Breakable.make("block", Transform3D(Basis(Vector3.UP, randf() * 0.4), Vector3(b.x, _h(b.x, b.y), b.y))))
	for d: Vector2 in layout.get("drums", []):
		_hazards.add_child(Breakable.make("drum", Transform3D(Basis(Vector3.UP, randf() * TAU), Vector3(d.x, _h(d.x, d.y), d.y))))
	open = layout.get("open", {})
	walls.clear()
	for w: Array in layout.get("walls", []):
		walls.append([w[0], w[1]])
		_wall(w[0], w[1], str(w[2]))
	for c: Array in layout.get("cover", []):
		var at: Vector2 = c[1]
		_hazards.add_child(Breakable.make(str(c[0]), Transform3D(Basis(Vector3.UP, float(c[2])), Vector3(at.x, _h(at.x, at.y), at.y))))


## The pit: a deep square shaft under the floor, walled and striped round its lip, a steel lid over
## it flush with the floor, a lamp at each corner.
func _build_pit() -> void:
	_pit_node = Node3D.new()
	_hazards.add_child(_pit_node)
	var c := pit.get_center()
	var y := _h(c.x, c.y)
	var dark := _mat(Color(0.03, 0.03, 0.035), 0.9)
	var depth := 6.0
	for e: Array in [[Vector3(pit.size.x, depth, 0.2), Vector3(0, -depth * 0.5, -pit.size.y * 0.5)],
			[Vector3(pit.size.x, depth, 0.2), Vector3(0, -depth * 0.5, pit.size.y * 0.5)],
			[Vector3(0.2, depth, pit.size.y), Vector3(-pit.size.x * 0.5, -depth * 0.5, 0)],
			[Vector3(0.2, depth, pit.size.y), Vector3(pit.size.x * 0.5, -depth * 0.5, 0)],
			[Vector3(pit.size.x, 0.2, pit.size.y), Vector3(0, -depth, 0)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[0]
		bm.material = dark
		mi.mesh = bm
		mi.position = Vector3(c.x, y, c.y) + (e[1] as Vector3)
		_pit_node.add_child(mi)
	# its lip: yellow and black
	var yellow := _mat(Color(0.8, 0.6, 0.08), 0.7)
	var black := _mat(Color(0.05, 0.05, 0.05), 0.7)
	var n := 10
	for side in 4:
		for k in n:
			var horiz := side < 2
			var len := pit.size.x if horiz else pit.size.y
			var along := -len * 0.5 + (k + 0.5) * len / n
			var off := Vector3(along, 0.0, (-0.5 if side == 0 else 0.5) * pit.size.y + (-0.25 if side == 0 else 0.25)) if horiz \
				else Vector3((-0.5 if side == 2 else 0.5) * pit.size.x + (-0.25 if side == 2 else 0.25), 0.0, along)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(len / n - 0.04, 0.025, 0.5) if horiz else Vector3(0.5, 0.025, len / n - 0.04)
			bm.material = yellow if k % 2 == 0 else black
			mi.mesh = bm
			mi.position = Vector3(c.x, y + 0.02, c.y) + off
			_pit_node.add_child(mi)
	_pit_lid = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(pit.size.x, 0.08, pit.size.y)
	lm.material = _mat(Color(0.32, 0.33, 0.34), 0.45, 0.8)
	(_pit_lid as MeshInstance3D).mesh = lm
	_pit_lid.position = Vector3(c.x, y + 0.03, c.y)
	_pit_node.add_child(_pit_lid)
	for k in 4:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.1)
		l.omni_range = 5.0
		l.light_energy = 0.0
		l.position = Vector3(c.x + (pit.size.x * 0.5 + 0.5) * (1 if k % 2 == 0 else -1), y + 0.6, c.y + (pit.size.y * 0.5 + 0.5) * (1 if k < 2 else -1))
		_pit_node.add_child(l)
		_pit_lights.append(l)


## The pit's lights flash for a few seconds, then its lid slides off and the floor's open there.
func open_pit() -> void:
	if pit.size.x <= 0.0 or pit_open or _pit_warn > 0.0:
		return
	_pit_warn = 3.0
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/heavy_01.wav", Vector3(pit.get_center().x, 1.0, pit.get_center().y), 4.0, 0.6)


func _pit_opens() -> void:
	pit_open = true
	var zones := _zones_now.duplicate()
	var hole := Surface.new() # (no ground there at all: the floor's mesh opens over it)
	hole.label = "pit"
	hole.color = Color(0.03, 0.03, 0.03)
	zones.append([pit, hole])
	terrain.set_zones(zones)
	if _pit_lid:
		var tw := _pit_lid.create_tween()
		tw.tween_property(_pit_lid, "position:x", _pit_lid.position.x + pit.size.x + 0.4, 1.2).set_trans(Tween.TRANS_QUAD)
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/bolt_off_01.wav", Vector3(pit.get_center().x, 1.0, pit.get_center().y), 6.0, 0.5)


## Where it's dangerous to drive, for the AI: [{c: Vector2 (the nearest point to `p` on it), r: m to
## keep off it, hole: true for the pit}] — the spinners, the saws' slots, the vents, the spikes, the pit
## (open or about to be), and, for any but a house robot, the house robots' zones.
func dangers(p: Vector2, house := false) -> Array:
	var out := []
	for sp: Dictionary in _spinners:
		var c := Vector2((sp.at as Vector3).x, (sp.at as Vector3).z)
		out.append({"c": c, "r": float(sp.r) + 1.6})
	for sw: Dictionary in _saws:
		var a := Vector2((sw.a as Vector3).x, (sw.a as Vector3).z)
		var b := Vector2((sw.b as Vector3).x, (sw.b as Vector3).z)
		out.append({"c": Geometry2D.get_closest_point_to_segment(p, a, b), "r": 1.8})
	for v: Dictionary in _vents:
		out.append({"c": Vector2((v.at as Vector3).x, (v.at as Vector3).z), "r": 2.4})
	for a in _spikes:
		if is_instance_valid(a):
			var cs := a.get_child(0) as CollisionShape3D
			var size := (cs.shape as BoxShape3D).size
			var r := Rect2(Vector2(cs.position.x, cs.position.z) - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
			out.append({"c": p.clamp(r.position, r.end), "r": 1.4})
	if pit.size.x > 0.0 and (pit_open or _pit_warn > 0.0):
		out.append({"c": p.clamp(pit.position, pit.end), "r": 2.0, "hole": true, "mid": pit.get_center()})
	if not house:
		for z: Rect2 in HOUSE_ZONES:
			out.append({"c": p.clamp(z.position, z.end), "r": 1.5})
	# the walls: kept off, slid along (the maze's too, those near)
	for w: Vector2 in [Vector2(p.x, -HALF), Vector2(p.x, HALF), Vector2(-HALF, p.y), Vector2(HALF, p.y)]:
		out.append({"c": w.clamp(Vector2(-HALF, -HALF), Vector2(HALF, HALF)), "r": 2.0})
	for w: Array in walls:
		var c := Geometry2D.get_closest_point_to_segment(p, w[0], w[1])
		if c.distance_squared_to(p) < 100.0:
			out.append({"c": c, "r": 2.2})
	return out


## Where a machine could be shoved to come to harm, for the AI: [{c: Vector2, r: m round it}] — the
## open pit first, the spinners, the spikes.
func shove_spots() -> Array:
	var out := []
	if pit_open:
		out.append({"c": pit.get_center(), "r": pit.size.x * 0.5})
	for sp: Dictionary in _spinners:
		out.append({"c": Vector2((sp.at as Vector3).x, (sp.at as Vector3).z), "r": float(sp.r)})
	for a in _spikes:
		if is_instance_valid(a):
			var cs := a.get_child(0) as CollisionShape3D
			out.append({"c": Vector2(cs.position.x, cs.position.z), "r": 1.5})
	return out


## Over the open pit (its middle, a little in from the lip).
func over_pit(p: Vector3) -> bool:
	return pit_open and pit.grow(-0.6).has_point(Vector2(p.x, p.z))


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


## A spinner: a steel drum on a low base, teeth round its rim, spinning flat out; solid to drive
## into, and it bites and flings what touches it.
func _spinner(at: Vector2) -> void:
	var r := 1.5
	var root := Node3D.new()
	_hazards.add_child(root)
	var y := _h(at.x, at.y)
	root.position = Vector3(at.x, y, at.y)
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = r + 0.4
	bm.bottom_radius = r + 0.6
	bm.height = 0.12
	bm.material = _mat(Color(0.8, 0.6, 0.08), 0.6)
	base.mesh = bm
	base.position.y = 0.06
	root.add_child(base)
	var drum := Node3D.new()
	drum.name = "Drum"
	drum.position.y = 0.42
	root.add_child(drum)
	var dm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.5
	cm.radial_segments = 24
	cm.material = _mat(Color(0.22, 0.22, 0.24), 0.35, 0.85)
	dm.mesh = cm
	drum.add_child(dm)
	var steel := _mat(Color(0.7, 0.71, 0.72), 0.25, 0.95)
	for k in 6: # the teeth
		var a := k * TAU / 6.0
		var t := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.5, 0.36, 0.18)
		tm.material = steel
		t.mesh = tm
		t.position = Vector3(cos(a), 0.0, sin(a)) * (r + 0.12)
		t.rotation.y = -a
		drum.add_child(t)
	var cap := MeshInstance3D.new()
	var capm := CylinderMesh.new()
	capm.top_radius = 0.4
	capm.bottom_radius = 0.4
	capm.height = 0.1
	capm.material = _mat(Color(0.8, 0.6, 0.08), 0.6)
	cap.mesh = capm
	cap.position.y = 0.28
	drum.add_child(cap)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = 0.6
	cs.shape = cyl
	cs.position.y = 0.3
	body.add_child(cs)
	root.add_child(body)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var acs := CollisionShape3D.new()
	var acyl := CylinderShape3D.new()
	acyl.radius = r + 0.45
	acyl.height = 1.2
	acs.shape = acyl
	acs.position.y = 0.5
	area.add_child(acs)
	root.add_child(area)
	var hum := AudioStreamPlayer3D.new()
	var s := (load("res://assets/audio/weapons/minigun_motor_loop.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = 44100
	hum.stream = s
	hum.pitch_scale = 0.45
	hum.volume_db = -8.0
	hum.unit_size = 6.0
	hum.autoplay = true
	root.add_child(hum)
	_spinners.append({"node": drum, "area": area, "at": root.position, "r": r})


## A floor saw: a slot in the floor from `a` to `b`, a toothed blade standing up out of it and
## running to and fro along it.
func _saw(a: Vector2, b: Vector2) -> void:
	var root := Node3D.new()
	_hazards.add_child(root)
	var len := a.distance_to(b)
	var mid := (a + b) * 0.5
	var y := _h(mid.x, mid.y)
	var basis := Basis(Vector3.UP, -atan2(b.y - a.y, b.x - a.x))
	var slot := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(len + 1.4, 0.03, 0.35)
	sm.material = _mat(Color(0.03, 0.03, 0.03), 0.9)
	slot.mesh = sm
	slot.transform = Transform3D(basis, Vector3(mid.x, y + 0.015, mid.y))
	root.add_child(slot)
	for side: float in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(len + 1.4, 0.035, 0.12)
		rm.material = _mat(Color(0.8, 0.6, 0.08), 0.6)
		rail.mesh = rm
		rail.transform = Transform3D(basis, Vector3(mid.x, y + 0.02, mid.y) + basis * Vector3(0, 0, side * 0.25))
		root.add_child(rail)
	var blade := Node3D.new()
	root.add_child(blade)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.75
	dm.bottom_radius = 0.75
	dm.height = 0.04
	dm.radial_segments = 28
	dm.material = _mat(Color(0.75, 0.76, 0.78), 0.2, 0.95)
	disc.mesh = dm
	disc.rotation.x = PI * 0.5 # (standing up, its face across the slot)
	var spin := Node3D.new()
	spin.name = "Spin"
	blade.add_child(spin)
	spin.add_child(disc)
	var steel := _mat(Color(0.6, 0.61, 0.62), 0.3, 0.9)
	for k in 16:
		var ang := k * TAU / 16.0
		var t := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.12, 0.12, 0.05)
		tm.material = steel
		t.mesh = tm
		t.position = Vector3(cos(ang), sin(ang), 0.0) * 0.78
		t.rotation.z = ang + PI * 0.25
		spin.add_child(t)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var acs := CollisionShape3D.new()
	var ab := BoxShape3D.new()
	ab.size = Vector3(1.6, 1.4, 0.8)
	acs.shape = ab
	acs.position.y = 0.4
	area.add_child(acs)
	blade.add_child(area)
	_saws.append({"node": blade, "spin": spin, "area": area, "a": Vector3(a.x, y, a.y), "b": Vector3(b.x, y, b.y),
		"u": randf(), "dir": 1.0, "basis": basis, "len": len})


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
	# the pit: its warning lights, then open; what's over it then falls
	if _pit_warn > 0.0:
		_pit_warn -= dt
		for l in _pit_lights:
			l.light_energy = 5.0 if fmod(_t, 0.4) < 0.2 else 0.0
		if _pit_warn <= 0.0:
			_pit_opens()
	elif pit_open:
		for l in _pit_lights:
			l.light_energy = 3.0 if fmod(_t, 1.0) < 0.5 else 1.0
		for n in get_tree().get_nodes_in_group("machines"):
			var m := n as Machine
			if m.alive and not m.falling and over_pit(m.com_global()):
				m.fall()
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
	# the blades: spin, run, bite
	for c in _cut.keys():
		_cut[c] = float(_cut[c]) - dt
	for sp: Dictionary in _spinners:
		(sp.node as Node3D).rotate_y(dt * 14.0)
		for b in (sp.area as Area3D).get_overlapping_bodies():
			var m := b as Machine
			if m and m.alive and float(_cut.get(m, 0.0)) <= 0.0:
				_cut[m] = BLADE_TICK
				var c: Vector3 = sp.at
				var to := m.com_global() - c
				to.y = 0.0
				var touch := c + to.normalized() * float(sp.r) + Vector3.UP * 0.45
				m.hit(touch, -to.normalized(), SPINNER_DAMAGE, 0.0)
				m.last_hit_kind = "çark"
				# flung off along the rim's way (it spins about up) and out
				var tangent := Vector3.UP.cross(to.normalized())
				m.apply_central_impulse((tangent * 0.8 + to.normalized() * 0.6).normalized() * SPINNER_FLING * BLADE_TICK * 4.0)
				if Combat.current:
					Combat.current.muzzle_flash(touch, -to.normalized(), 0.9)
					Combat.current.sound("res://assets/audio/impact/metal_0%d.wav" % randi_range(1, 3), touch, 0.0, randf_range(0.7, 0.9))
	for sw: Dictionary in _saws:
		sw.u = float(sw.u) + float(sw.dir) * dt * 3.5 / maxf(float(sw.len), 1.0)
		if float(sw.u) > 1.0 or float(sw.u) < 0.0:
			sw.dir = -float(sw.dir)
			sw.u = clampf(float(sw.u), 0.0, 1.0)
		var blade := sw.node as Node3D
		blade.transform = Transform3D(sw.basis, (sw.a as Vector3).lerp(sw.b, float(sw.u)) + Vector3.UP * 0.15)
		(sw.spin as Node3D).rotate_z(-dt * 30.0)
		for b in (sw.area as Area3D).get_overlapping_bodies():
			var m := b as Machine
			if m and m.alive and float(_cut.get(m, 0.0)) <= 0.0:
				_cut[m] = BLADE_TICK
				var at := blade.global_position + Vector3.UP * 0.7
				m.hit(at, Vector3.UP, SAW_DAMAGE, 120.0)
				m.last_hit_kind = "testere"
				if Combat.current:
					Combat.current.muzzle_flash(at, Vector3.UP, 0.7)
					Combat.current.sound("res://assets/audio/impact/metal_0%d.wav" % randi_range(1, 3), at, -2.0, randf_range(1.2, 1.5))
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
				m.blast(v.at + Vector3.UP * 0.8, 2.6, FIRE_DAMAGE, 120.0, null, "ateş") # (it burns; it hardly shoves)


# --- The maze --------------------------------------------------------------------------------------

## A round's floor by its theme and `seed_`: the maze, the theme's hazards in cells of their own, cover
## in the rest. A theme: {ground: preset, middle: preset for the middle cell, patches: [[preset, n]],
## pit: bool, vents, spinners, saws, spikes, fences, drums: how many of each}.
static func plan(theme: Dictionary, seed_: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var opened := {}
	# the maze: a walk that cuts through to every cell
	var start := Vector2i(rng.randi() % N, rng.randi() % N)
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var next: Array[Vector2i] = []
		for d: Vector2i in _DIRS:
			if _inside(c + d) and not seen.has(c + d):
				next.append(c + d)
		if next.is_empty():
			stack.pop_back()
			continue
		var pick := next[rng.randi() % next.size()]
		opened[_edge(c, pick)] = true
		seen[pick] = true
		stack.append(pick)
	# loops: some of the walls taken out again; the corners always open both ways (no dead end to start in)
	var corners := [RED, BLUE, Vector2i(0, N - 1), Vector2i(N - 1, 0)]
	for x in N:
		for y in N:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(x, y)
				if _inside(a + d) and (rng.randf() < OPEN or a in corners or (a + d) in corners):
					opened[_edge(a, a + d)] = true
	var out := {"open": opened, "walls": [], "cover": [], "zones": [], "spikes": [], "vents": [], "spinners": [],
		"saws": [], "fences": [], "drums": []}
	out.zones.append([Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0), str(theme.get("ground", "asphalt"))])
	# the walls, stubs at the ends of some open sides, a pillar where walls meet
	var posts := {}
	for x in N:
		for y in N:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(x, y)
				var b := a + d
				if not _inside(b):
					continue
				var s := _side(a, b)
				if not opened.has(_edge(a, b)):
					var r := rng.randf()
					out.walls.append([s[0], s[1], "container" if r < 0.55 else ("barrier" if r < 0.85 else "sandbags")])
					posts[s[0]] = true
					posts[s[1]] = true
				elif rng.randf() < 0.3 and not a in corners and not b in corners:
					var kind := "container" if rng.randf() < 0.5 else "block"
					var along := ((s[1] as Vector2) - (s[0] as Vector2)).normalized()
					var off := 4.3 if kind == "container" else 2.3
					var yaw := -along.angle()
					out.cover.append([kind, (s[0] as Vector2) + along * off, yaw])
					out.cover.append([kind, (s[1] as Vector2) - along * off, yaw])
	for p: Vector2 in posts:
		if absf(p.x) < HALF - 1.0 and absf(p.y) < HALF - 1.0:
			out.cover.append(["block", p, 0.0])
	# the hazards, each in a cell of its own (never a corner's, nor the middle's for anything but the pit)
	var free: Array[Vector2i] = []
	for x in N:
		for y in N:
			var c := Vector2i(x, y)
			if not c in corners and c != Vector2i(N / 2, N / 2):
				free.append(c)
	_shuffle(free, rng)
	var mid := Vector2i(N / 2, N / 2)
	if theme.get("middle", "") != "":
		out.zones.append([_cell_rect(mid), str(theme.middle)])
	for pr: Array in theme.get("patches", []):
		for k in int(pr[1]):
			var c := Vector2i(rng.randi() % N, rng.randi() % N)
			if c in corners:
				continue
			var r := _cell_rect(c)
			if rng.randf() < 0.5: # (two cells long now and then)
				r = r.merge(_cell_rect(c + (Vector2i(1, 0) if c.x < N - 1 else Vector2i(-1, 0))))
			out.zones.append([r.grow(-1.0), str(pr[0])])
	var used := {}
	var take := func() -> Vector2i:
		var c: Vector2i = free.pop_back() if not free.is_empty() else mid
		used[c] = true
		return c
	if theme.get("pit", false):
		var c: Vector2i = take.call() if rng.randf() < 0.6 else mid
		used[c] = true
		out.pit = Rect2(_cell_mid(c) - Vector2(4, 4), Vector2(8, 8))
	for k in int(theme.get("vents", 0)):
		out.vents.append(_cell_mid(take.call()) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
	for k in int(theme.get("spinners", 0)):
		out.spinners.append(_cell_mid(take.call()))
	for k in int(theme.get("saws", 0)):
		var m := _cell_mid(take.call())
		var ax := Vector2(6, 0) if rng.randf() < 0.5 else Vector2(0, 6)
		out.saws.append([m - ax, m + ax])
	for k in int(theme.get("spikes", 0)):
		var m := _cell_mid(take.call())
		out.spikes.append(Rect2(m - Vector2(6, 1.5), Vector2(12, 3)) if rng.randf() < 0.5 else Rect2(m - Vector2(1.5, 6), Vector2(3, 12)))
	for k in int(theme.get("fences", 0)):
		var m := _cell_mid(take.call())
		var a := rng.randf() * PI
		var ax := Vector2(cos(a), sin(a)) * 5.0
		out.fences.append([m - ax, m + ax])
	for k in int(theme.get("drums", 0)):
		var m := _cell_mid(take.call())
		for j in 3:
			out.drums.append(m + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)))
	# cover in the cells left: nothing, a pair of blocks, a crate stack, a sandbag nest, drums, barriers
	for x in N:
		for y in N:
			var c := Vector2i(x, y)
			if c in corners or used.has(c) or c == mid:
				continue
			var at := _cell_mid(c)
			var a := rng.randf() * TAU
			var o := Vector2(cos(a), sin(a)) * rng.randf_range(4.0, 6.5)
			match rng.randi() % 6:
				1:
					out.cover.append(["block", at + o, a])
					out.cover.append(["block", at + o + Vector2(cos(a + 1.57), sin(a + 1.57)) * 2.2, a])
				2:
					for k in 3:
						out.cover.append(["crate", at + o + Vector2(k * 1.3, 0.0), 0.0])
				3:
					for k in 3:
						out.cover.append(["sandbags", at + o + Vector2(cos(a + k * 0.8), sin(a + k * 0.8)) * 2.4, -(a + k * 0.8)])
				4:
					for k in 4:
						out.drums.append(at + o + Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8)))
				5:
					out.cover.append(["barrier", at + o, -a + PI * 0.5])
					out.cover.append(["barrier", at - o, -a + PI * 0.5])
	return out


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


static func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < N and c.y < N


static func _edge(a: Vector2i, b: Vector2i) -> Array:
	return [a, b] if (a.x < b.x or (a.x == b.x and a.y < b.y)) else [b, a]


## A cell's middle (x, z).
static func _cell_mid(c: Vector2i) -> Vector2:
	return Vector2(-HALF + (c.x + 0.5) * CELL, -HALF + (c.y + 0.5) * CELL)


static func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(-HALF + c.x * CELL, -HALF + c.y * CELL, CELL, CELL)


## The side between cells `a` and `b` (b to the right of or below a), end to end.
static func _side(a: Vector2i, b: Vector2i) -> Array:
	if b.x != a.x:
		var x := -HALF + b.x * CELL
		return [Vector2(x, -HALF + a.y * CELL), Vector2(x, -HALF + (a.y + 1) * CELL)]
	var z := -HALF + b.y * CELL
	return [Vector2(-HALF + a.x * CELL, z), Vector2(-HALF + (a.x + 1) * CELL, z)]


## A wall from `a` to `b`: containers end to end, a double row of concrete barriers, or sandbags
## and blocks.
func _wall(a: Vector2, b: Vector2, kind: String) -> void:
	var along := (b - a).normalized()
	var mid := (a + b) * 0.5
	var yaw := -along.angle() # (a box's length is its x)
	var put := func(k: String, at: Vector2) -> void:
		_hazards.add_child(Breakable.make(k, Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, _h(at.x, at.y), at.y))))
	match kind:
		"container":
			for k in 3:
				put.call("container", mid + along * (k - 1) * 6.4)
		"barrier":
			var side := Vector2(-along.y, along.x)
			for k in 7:
				for row: float in [-0.35, 0.35]:
					put.call("barrier", mid + along * (k - 3) * 3.05 + side * row)
		_:
			for k in 6:
				put.call("sandbags" if k % 2 == 0 else "block", mid + along * (k - 2.5) * 3.5)


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((p.x + HALF) / CELL), 0, N - 1), clampi(floori((p.z + HALF) / CELL), 0, N - 1))


## A cell's middle on the ground.
func center(c: Vector2i) -> Vector3:
	var m := _cell_mid(c)
	return Vector3(m.x, _h(m.x, m.y), m.y)


## Is there a maze wall within `r` of `p` (x, z)?
func near_wall(p: Vector2, r: float) -> bool:
	for w: Array in walls:
		if Geometry2D.get_closest_point_to_segment(p, w[0], w[1]).distance_to(p) < r:
			return true
	return false


## The cells' way from where `from` is to where `to` is, through the open sides (the cells in order,
## the first the next one to go to); empty if they're in the same cell (or there's no maze).
func path(from: Vector3, to: Vector3) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a := cell_of(from)
	var b := cell_of(to)
	if a == b or open.is_empty():
		return out
	var came := {a: a}
	var q: Array[Vector2i] = [a]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == b:
			break
		for d: Vector2i in _DIRS:
			var n2 := c + d
			if _inside(n2) and not came.has(n2) and open.has(_edge(c, n2)):
				came[n2] = c
				q.append(n2)
	if not came.has(b):
		return out
	var c2 := b
	while c2 != a:
		out.push_front(c2)
		c2 = came[c2]
	return out


## Where a machine at `m` making for `goal` should head this moment (AiDriver's route): straight for
## it in the same or the next open cell, else the middle of the next cell on the way.
func route(m: Machine, _target: Machine, goal: Vector3) -> Vector3:
	var p := path(m.global_position, goal)
	if p.size() <= 1:
		return goal
	return center(p[0])
