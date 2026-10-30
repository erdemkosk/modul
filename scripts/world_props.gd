class_name WorldProps
extends Node3D
## Every tree, bush, fern, rock, cliff, stump and log of the open world (assets/world/props.f32.gz,
## placed by tools/world/build_world.py; models from assets/nature/, made by
## tools/blender/build_nature.py).
##
## Drawing: each model has a detailed LOD0 and a cheap LOD1. LOD1 copies sit in MultiMeshes per
## 128 m chunk and kind, drawn out to the kind's far range. Every quarter second the props within
## the kind's near range of the camera move to one LOD0 MultiMesh per kind (their LOD1 copy is
## collapsed to nothing), so the swap is per prop rather than per chunk.
## Collision: trunks, rocks and logs are shapes on one StaticBody3D per chunk, added straight to
## the physics server (no node per tree). Trees are winch anchors: a Node3D each in the
## "winch_anchor" group, and anchors_near() finds them by grid instead of scanning the group.

const NATURE_DIR := "res://assets/nature/"
## The trees' bark, and the wood under it: one brown for standing trunks, felled ones, stumps and
## billets alike (Timber), a weathered pine's rather than the models' bright orange.
const BARK := Color(0.4, 0.27, 0.17)
const CUT_WOOD := Color(0.78, 0.63, 0.42)
const CHUNK := 128.0
const CELL := 32.0
const UPDATE_PERIOD := 0.25
const HYSTERESIS := 12.0 ## Extra metres before a LOD0 prop drops back to LOD1.
const REBUILD_MOVE := 3.0 ## The near set is rebuilt once the camera has moved this far from where it was built.
const PAD := 8.0 ## The near set reaches this far past the near range, so it still covers the crossfade after the camera has moved REBUILD_MOVE.
const FOLIAGE := ["Needles", "Leaves", "LeavesAutumn", "FernLeaf"]
## The LOD1 copies of the kinds seen from far off go in bigger chunks: each chunk is a draw call
## in every pass, and 128 m ones made thousands of them for trees seen across the whole basin.
const FAR_CHUNK := {"tree": 384.0, "cliff": 512.0, "rock": 256.0}

## Per model kind: near (LOD0) range, far (LOD1) range (0 = no LOD1 at all), shadows of LOD1.
const RANGES := {
	"tree": [130.0, 2000.0, true],
	"rock": [110.0, 900.0, true],
	"cliff": [260.0, 2500.0, true],
	"bush": [85.0, 380.0, false],
	"fern": [70.0, 0.0, false],
	"log": [90.0, 420.0, false],
	"stump": [80.0, 380.0, false],
}

var terrain: WorldTerrain

var _models: Array[Dictionary] = [] ## Per kind index: {id, kind, info, lod0, lod1, near, far}
var _xf: Array[Transform3D] = []
var _kind := PackedInt32Array()
var _tint := PackedFloat32Array()
var _far_mm: Array[MultiMesh] = [] ## Per prop: its LOD1 MultiMesh (or null).
var _far_idx := PackedInt32Array()
var _grid := {} ## Vector2i cell -> Array of prop indices
var _anchor_grid := {} ## Vector2i cell -> Array[Node3D]
var _near := {} ## prop index -> true while drawn at LOD0
var _near_mmi: Array[MultiMeshInstance3D] = []
var _max_near := 0.0
var _since_update := 100.0
var _lod_center := Vector3(INF, INF, INF) ## Where the near set was last built.
var _shapes := {} ## cache key -> Shape3D (kept alive for the server)
var _shape_of := {} ## prop index -> [body RID, shape index]: its collision, to switch off when felled
var _anchor_of := {} ## prop index -> its winch anchor node (trees)
var cut := {} ## prop index -> true: felled (RutStore.cut keeps them between runs)
var _bodies := {} ## Vector2i chunk -> StaticBody3D


func _ready() -> void:
	add_to_group("anchor_index")
	# Nothing here moves on its own. With physics interpolation on, a near-set slot handed to a
	# different tree was drawn gliding from the old tree's spot to the new one: trees flying
	# across the view and vanishing as you drove.
	physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF
	var info: Dictionary = {}
	if FileAccess.file_exists(NATURE_DIR + "nature.json"):
		info = JSON.parse_string(FileAccess.get_file_as_string(NATURE_DIR + "nature.json"))
	for id: String in terrain.meta.props:
		_models.append(_load_model(id, info.get(id, {})))
	_load_props()
	_build_far()
	_build_near_nodes()
	_build_collision_and_anchors()


func _process(delta: float) -> void:
	_since_update += delta
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		# The crossfade follows the live camera every frame, so it glides instead of stepping each
		# time the set is rebuilt. A global rather than the camera in the shader: in the shadow
		# pass that would be the light, and the shadows would dissolve on their own pattern.
		RenderingServer.global_shader_parameter_set(&"props_lod_center", cam.global_position)
	var moved := cam != null and cam.global_position.distance_to(_lod_center) > REBUILD_MOVE
	if _since_update >= UPDATE_PERIOD or moved:
		_since_update = 0.0
		_update_near()


## Winch anchors (trees) within `radius` of a ground point.
func anchors_near(p: Vector2, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var c0 := Vector2i(floori((p.x - radius) / CELL), floori((p.y - radius) / CELL))
	var c1 := Vector2i(floori((p.x + radius) / CELL), floori((p.y + radius) / CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var list: Array = _anchor_grid.get(Vector2i(cx, cz), [])
			for a: Node3D in list:
				if Vector2(a.position.x, a.position.z).distance_to(p) <= radius:
					out.append(a)
	return out


# --- Models -----------------------------------------------------------------------------------------

func _load_model(id: String, info: Dictionary) -> Dictionary:
	var kind := str(info.get("kind", _guess_kind(id)))
	var lod0: Mesh = null
	var lod1: Mesh = null
	var path := NATURE_DIR + id + ".glb"
	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate()
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			if mi.name.begins_with("LOD0"):
				lod0 = mi.mesh
			elif mi.name.begins_with("LOD1"):
				lod1 = mi.mesh
		scene.free()
	if lod0 == null:
		lod0 = _fallback_mesh(id, kind)
	if lod1 == null:
		lod1 = lod0
	var height := float(info.get("height", 16.0 if kind == "tree" else 2.0))
	var r: Array = RANGES.get(kind, [80.0, 300.0, false])
	return {
		"id": id, "kind": kind, "info": info, "height": height,
		# The two crossfade over the last 28 m of the near range (nature.gdshader): with no
		# LOD1 at all (ferns), LOD0 just dissolves away there instead of vanishing.
		"lod0": _with_nature_materials(lod0, kind, height, 0.0, r[0]),
		"lod1": _with_nature_materials(lod1, kind, height, 1.0, r[0]),
		"near": r[0], "far": r[1], "far_shadow": r[2],
	}


static func _guess_kind(id: String) -> String:
	for k in ["cliff", "rock", "bush", "fern", "stump", "log"]:
		if id.begins_with(k):
			return k
	return "tree"


## A copy of the mesh whose surfaces use the nature shader (wind, wet, snow), coloured like the
## model's own materials.
func _with_nature_materials(mesh: Mesh, kind: String, height: float, lod_role := 0.0, lod_near := 0.0) -> Mesh:
	var out := mesh.duplicate() as Mesh
	for s in out.get_surface_count():
		var src := out.surface_get_material(s)
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/nature.gdshader")
		var col := Color(0.5, 0.5, 0.5)
		var rough := 0.85
		var mat_name := ""
		if src is BaseMaterial3D:
			col = (src as BaseMaterial3D).albedo_color
			rough = (src as BaseMaterial3D).roughness
			mat_name = src.resource_name
		elif src:
			mat_name = src.resource_name
		var foliage := mat_name in FOLIAGE
		if mat_name == "Bark":
			col = BARK
		elif mat_name == "Wood":
			col = CUT_WOOD
		mat.set_shader_parameter("albedo", col)
		mat.set_shader_parameter("roughness", rough)
		mat.set_shader_parameter("leaf", 1.0 if foliage else 0.0)
		mat.set_shader_parameter("broadleaf", 1.0 if mat_name in ["Leaves", "LeavesAutumn"] or (foliage and kind == "bush") else 0.0)
		mat.set_shader_parameter("model_height", maxf(height, 0.5))
		mat.set_shader_parameter("lod_role", lod_role)
		mat.set_shader_parameter("lod_near", lod_near)
		mat.set_shader_parameter("stone", 1.0 if kind in ["rock", "cliff"] and not foliage else 0.0)
		var sway := 0.0
		match kind:
			"tree": sway = 1.0
			"bush", "fern": sway = 0.6
		mat.set_shader_parameter("sway", sway)
		if out is ArrayMesh:
			(out as ArrayMesh).surface_set_material(s, mat)
	return out


## Stand-in shapes for when assets/nature/ hasn't been built.
func _fallback_mesh(id: String, kind: String) -> Mesh:
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.3, 0.22, 0.15)
	bark.resource_name = "Bark"
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.13, 0.22, 0.12) if not id.begins_with("birch") else Color(0.35, 0.45, 0.18)
	green.resource_name = "Needles"
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.42, 0.41, 0.39)
	rock.resource_name = "Rock"
	var mesh := ArrayMesh.new()
	match kind:
		"tree":
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.12
			trunk.bottom_radius = 0.3
			trunk.height = 16.0
			_append(mesh, trunk, Transform3D(Basis.IDENTITY, Vector3(0, 8, 0)), bark)
			for i in 4:
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 3.2 - i * 0.65
				cone.height = 4.5
				cone.radial_segments = 10
				_append(mesh, cone, Transform3D(Basis.IDENTITY, Vector3(0, 5.5 + i * 2.6, 0)), green)
		"bush", "fern":
			var s := SphereMesh.new()
			s.radius = 0.8
			s.height = 1.1
			_append(mesh, s, Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), green)
		"log", "stump":
			var c := CylinderMesh.new()
			c.top_radius = 0.22
			c.bottom_radius = 0.25
			c.height = 6.0 if kind == "log" else 0.6
			var xf := Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, 0.22, 0)) if kind == "log" else Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0))
			_append(mesh, c, xf, bark)
		_:
			var s := SphereMesh.new()
			s.radius = 1.0 if kind == "rock" else 4.0
			s.height = 1.4 if kind == "rock" else 6.0
			s.radial_segments = 8
			s.rings = 5
			_append(mesh, s, Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), rock)
	return mesh


static func _append(target: ArrayMesh, src: PrimitiveMesh, xf: Transform3D, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.append_from(src, 0, xf)
	st.set_material(mat)
	st.commit(target)


# --- Props ------------------------------------------------------------------------------------------

func _load_props() -> void:
	var count := int(terrain.meta.prop_count)
	var data := FileAccess.get_file_as_bytes(WorldTerrain.DIR + "props.f32.gz").decompress(count * 24, FileAccess.COMPRESSION_GZIP).to_float32_array()
	_xf.resize(count)
	_kind.resize(count)
	_tint.resize(count)
	for i in count:
		var o := i * 6
		var k := int(data[o + 3])
		var s := data[o + 4]
		if _models[k].kind == "bush":
			s *= 0.7 # smaller tufts: a bush by the road, not a wall of leaves filling the view
		var basis := Basis(Vector3.UP, data[o + 5]).scaled(Vector3(s, s, s))
		var y := data[o + 1] + terrain.lift_at(data[o], data[o + 2]) # (the start's ground was eased: it sits on it)
		var model := _models[k]
		if model.kind == "rock" or model.kind == "cliff":
			y -= 0.25 * s # bed them in so slopes don't show their undersides
		if model.kind == "rock":
			# On a steep face the ground falls away under one side: sit it on the low side, its
			# uphill side buried in the slope, not hanging off the cliff.
			var r := 0.7 * s
			var px := data[o]
			var pz := data[o + 2]
			var low := minf(minf(terrain.height_at(px + r, pz), terrain.height_at(px - r, pz)), minf(terrain.height_at(px, pz + r), terrain.height_at(px, pz - r)))
			y = minf(y, low - 0.1 * s)
		_xf[i] = Transform3D(basis, Vector3(data[o], y, data[o + 2]))
		_kind[i] = k
		_tint[i] = fposmod(sin(data[o] * 12.9898 + data[o + 2] * 78.233) * 43758.5453, 1.0)
		var cell := Vector2i(floori(data[o] / CELL), floori(data[o + 2] / CELL))
		if not _grid.has(cell):
			_grid[cell] = []
		(_grid[cell] as Array).append(i)
	for m in _models:
		_max_near = maxf(_max_near, m.near)


func _build_far() -> void:
	_far_mm.resize(_xf.size())
	_far_idx.resize(_xf.size())
	var buckets := {} ## Vector3i(chunk x, chunk z, kind) -> Array of prop indices
	for i in _xf.size():
		var k := _kind[i]
		if _models[k].far <= 0.0:
			continue
		var chunk: float = FAR_CHUNK.get(_models[k].kind, CHUNK)
		var key := Vector3i(floori(_xf[i].origin.x / chunk), floori(_xf[i].origin.z / chunk), k)
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(i)
	for key: Vector3i in buckets:
		var list: Array = buckets[key]
		var model := _models[key.z]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = model.lod1
		mm.instance_count = list.size()
		for j in list.size():
			var i: int = list[j]
			mm.set_instance_transform(j, _xf[i])
			mm.set_instance_custom_data(j, Color(_tint[i], 0, 0, 0))
			_far_mm[i] = mm
			_far_idx[i] = j
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = model.far
		mmi.visibility_range_end_margin = 80.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if model.far_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _build_near_nodes() -> void:
	for m in _models:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = m.lod0
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		# Where the simple copy casts shadows it casts them close up too (nature.gdshader), so the
		# detailed one needn't: its shadow pass was most of what the near trees cost.
		var lod1_shadows: bool = m.far > 0.0 and m.far_shadow
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if m.kind == "fern" or lod1_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_near_mmi.append(mmi)


## Per kind: Vector2i cell -> its props of that kind (from _grid).
var _kgrid: Array[Dictionary] = []


func _build_kgrid() -> void:
	_kgrid.clear()
	for k in _models.size():
		_kgrid.append({})
	for cell: Vector2i in _grid:
		for i: int in _grid[cell]:
			var g: Dictionary = _kgrid[_kind[i]]
			if not g.has(cell):
				g[cell] = []
			(g[cell] as Array).append(i)


## Each prop's slot in a multimesh buffer, worked out once: its transform row by row (basis
## column x, y, z then origin, for each axis) and its tint as custom data.
var _flat := PackedFloat32Array()


func _build_flat() -> void:
	_flat.resize(_xf.size() * 16)
	for i in _xf.size():
		var t := _xf[i]
		var b := t.basis
		var o := i * 16
		var row := [b.x.x, b.y.x, b.z.x, t.origin.x, b.x.y, b.y.y, b.z.y, t.origin.y, b.x.z, b.y.z, b.z.z, t.origin.z, _tint[i], 0.0, 0.0, 0.0]
		for q in 16:
			_flat[o + q] = row[q]


func _update_near() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	var per_kind: Array[Array] = []
	for k in _models.size():
		per_kind.append([])
	var now := {}
	if _kgrid.is_empty():
		_build_kgrid()
	var cc := Vector2i(floori(c.x / CELL), floori(c.z / CELL))
	# Each kind over its own reach only (a cliff's 260 m had every bush and fern in a 600 m square
	# looked at), and cells wholly out of it skipped.
	for kind in _models.size():
		var reach: float = _models[kind].near + PAD + HYSTERESIS
		var r := int(ceil(reach / CELL))
		var grid: Dictionary = _kgrid[kind]
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := cc + Vector2i(dx, dz)
				var list: Variant = grid.get(cell)
				if list == null:
					continue
				var nx := clampf(c.x, cell.x * CELL, (cell.x + 1) * CELL) - c.x
				var nz := clampf(c.z, cell.y * CELL, (cell.y + 1) * CELL) - c.z
				if nx * nx + nz * nz > reach * reach:
					continue
				for i: int in list:
					if cut.has(i):
						continue
					var k := _kind[i]
					var o := _xf[i].origin
					# PAD: the camera moves on up to REBUILD_MOVE before the next rebuild, and the
					# crossfade follows it, so the set reaches past the near range to cover that.
					# A prop already at LOD0 keeps it for 12 m more, so orbiting the camera
					# round the truck doesn't flip props on the boundary back and forth.
					var near: float = _models[k].near + PAD + (HYSTERESIS if _near.has(i) else 0.0)
					if (o.x - c.x) * (o.x - c.x) + (o.z - c.z) * (o.z - c.z) < near * near:
						now[i] = true
						per_kind[k].append(i)
	# The LOD1 copies stay where they are: close up the shader dissolves them away as the LOD0
	# ones dissolve in (nature.gdshader, lod_near), so nothing swaps from one frame to the next.
	_near = now
	_lod_center = c
	if _flat.size() != _xf.size() * 16:
		_build_flat()
	for k in _models.size():
		var mm := _near_mmi[k].multimesh
		var list := per_kind[k]
		if mm.instance_count < list.size() or mm.instance_count > list.size() * 3 + 64:
			mm.instance_count = 0
			mm.use_custom_data = true
			mm.instance_count = list.size() + 32
		# All of a kind's slots in one go (the multimesh's buffer: 12 floats of transform and 4 of
		# custom data each) rather than two calls into the renderer per prop: rebuilding the near set
		# as you drove took 5-6 ms a time.
		var buf := PackedFloat32Array()
		buf.resize(mm.instance_count * 16)
		var at := 0
		for i: int in list:
			for q in 16:
				buf[at + q] = _flat[i * 16 + q]
			at += 16
		mm.buffer = buf
		# Only these are drawn. The slots past them still hold props that have gone back to
		# LOD1, and drawing those too doubled them up until the next resize wiped them all at
		# once: whole groups of trees winking in and out as you drove.
		mm.visible_instance_count = list.size()


# --- Collision and winch anchors -------------------------------------------------------------------

func _build_collision_and_anchors() -> void:
	var anchors := Node3D.new()
	anchors.name = "Anchors"
	add_child(anchors)
	for i in _xf.size():
		var m := _models[_kind[i]]
		var info: Dictionary = m.info
		var xf := _xf[i]
		var s := xf.basis.get_scale().x
		var shape: Shape3D = null
		var local := Transform3D.IDENTITY
		match m.kind:
			"tree":
				var radius := float(info.get("trunk_radius", 0.28)) * s
				shape = _cylinder(snappedf(radius, 0.02), 6.0)
				local = Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 0))
				var a := Node3D.new()
				a.position = xf.origin
				a.set_meta("trunk_radius", radius)
				a.set_meta("prop", i)
				a.add_to_group("winch_anchor")
				anchors.add_child(a)
				_anchor_of[i] = a
				var cell := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
				if not _anchor_grid.has(cell):
					_anchor_grid[cell] = []
				(_anchor_grid[cell] as Array).append(a)
			"stump":
				shape = _cylinder(snappedf(float(info.get("trunk_radius", 0.3)) * s, 0.02), 1.2)
			"log":
				shape = _cylinder(snappedf(float(info.get("radius", 0.2)) * s, 0.02), float(info.get("length", 6.0)) * s)
				local = Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(0, float(info.get("radius", 0.2)) * s, 0))
			"rock", "cliff":
				var size: Array = info.get("size", [1.6, 1.2, 1.6] if m.kind == "rock" else [8.0, 5.0, 6.0])
				var center: Array = info.get("center", [0.0, size[1] * 0.5, 0.0])
				var key := "box_%s_%.2f" % [m.id, s]
				if not _shapes.has(key):
					var box := BoxShape3D.new()
					box.size = Vector3(size[0], size[1], size[2]) * s * 0.9
					_shapes[key] = box
				shape = _shapes[key]
				local = Transform3D(Basis.IDENTITY, Vector3(center[0], center[1], center[2]) * s)
		if shape == null:
			continue
		var body := _body_for(xf.origin)
		var rot := Transform3D(xf.basis.orthonormalized(), xf.origin)
		_shape_of[i] = [body.get_rid(), PhysicsServer3D.body_get_shape_count(body.get_rid())]
		PhysicsServer3D.body_add_shape(body.get_rid(), shape.get_rid(), body.global_transform.affine_inverse() * rot * local)
	# Trees felled earlier in the campaign stay down.
	for i: int in RutStore.cut:
		if i < _xf.size():
			_remove(i)


# --- Felling (the axe: ControlSwitcher) ------------------------------------------------------------

## The standing tree whose trunk is within `reach` of a ground point, or -1.
func tree_near(p: Vector2, reach: float) -> int:
	var best := -1
	var best_gap := reach
	for a: Node3D in anchors_near(p, reach + 1.0):
		var gap := p.distance_to(Vector2(a.position.x, a.position.z)) - float(a.get_meta("trunk_radius", 0.3))
		if gap < best_gap and a.has_meta("prop"):
			best_gap = gap
			best = int(a.get_meta("prop"))
	return best


## A tree's base, height (m) and trunk radius.
func tree_info(i: int) -> Dictionary:
	var m := _models[_kind[i]]
	var s := _xf[i].basis.get_scale().x
	return {"origin": _xf[i].origin, "height": float(m.height) * s, "radius": float(m.info.get("trunk_radius", 0.28)) * s,
		"basis": _xf[i].basis, "lod0": m.lod0}


## The standing prop of a kind in `kinds` ("tree", "log", "stump", ...) nearest a ground point within
## `reach` of its edge (its trunk's or log's radius taken off), or -1.
func prop_near(p: Vector2, reach: float, kinds: Array) -> int:
	var best := -1
	var best_gap := reach
	var r := int(ceil((reach + 4.0) / CELL))
	var c := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	for dz in range(-1, 2) if r <= 1 else range(-r, r + 1):
		for dx in range(-1, 2) if r <= 1 else range(-r, r + 1):
			for i: int in _grid.get(c + Vector2i(dx, dz), []):
				if cut.has(i) or not str(_models[_kind[i]].kind) in kinds:
					continue
				var info := prop_info(i)
				var gap: float
				if info.kind == "log": # (along its length: the nearest point of its axis)
					var o: Vector3 = info.origin
					var ax: Vector3 = info.axis
					var a := Vector2(o.x, o.z)
					var d := Vector2(ax.x, ax.z) * float(info.length) * 0.5
					var q := Geometry2D.get_closest_point_to_segment(p, a - d, a + d)
					gap = p.distance_to(q) - float(info.radius)
				else:
					gap = p.distance_to(Vector2(info.origin.x, info.origin.z)) - float(info.radius)
				if gap < best_gap:
					best_gap = gap
					best = i
	return best


## A prop's kind, base, radius (a trunk's, a log's), height, and a log's axis and length.
func prop_info(i: int) -> Dictionary:
	var m := _models[_kind[i]]
	var xf := _xf[i]
	var s := xf.basis.get_scale().x
	var info: Dictionary = m.info
	var out := {"kind": m.kind, "origin": xf.origin, "scale": s, "height": float(m.height) * s, "basis": xf.basis}
	match str(m.kind):
		"tree":
			out.radius = float(info.get("trunk_radius", 0.28)) * s
		"stump":
			out.radius = float(info.get("trunk_radius", 0.3)) * s
		"log":
			out.radius = float(info.get("radius", 0.2)) * s
			out.length = float(info.get("length", 6.0)) * s
			out.axis = (xf.basis.orthonormalized() * Vector3.RIGHT).normalized() # (its collision lies along x)
			out.origin = xf.origin + Vector3.UP * float(out.radius)
		_:
			out.radius = 0.5 * s
	return out


## The tree's detailed model as one mesh for a felled trunk to fall with: not bending in the wind, not
## fading with distance (it's a body of its own now).
func felled_mesh(i: int) -> Mesh:
	var m := _models[_kind[i]]
	if m.has("felled"):
		return m.felled
	var out := (m.lod0 as Mesh).duplicate() as Mesh
	for k in out.get_surface_count():
		var mat := out.surface_get_material(k)
		if mat is ShaderMaterial:
			mat = mat.duplicate()
			(mat as ShaderMaterial).set_shader_parameter("sway", 0.0)
			(mat as ShaderMaterial).set_shader_parameter("lod_near", 0.0)
			(out as ArrayMesh).surface_set_material(k, mat)
	m.felled = out
	return out


## Fells tree `i`: gone from the world (drawn, solid, a winch anchor), and remembered.
func cut_tree(i: int) -> void:
	if cut.has(i):
		return
	RutStore.cut[i] = SaveGame.day
	RutStore.save_marks()
	_remove(i)


func _remove(i: int) -> void:
	cut[i] = true
	if _shape_of.has(i):
		PhysicsServer3D.body_set_shape_disabled(_shape_of[i][0], _shape_of[i][1], true)
	if _anchor_of.has(i):
		var a: Node3D = _anchor_of[i]
		var cell := Vector2i(floori(a.position.x / CELL), floori(a.position.z / CELL))
		(_anchor_grid.get(cell, []) as Array).erase(a)
		a.queue_free()
		_anchor_of.erase(i)
	var mm: MultiMesh = _far_mm[i]
	if mm:
		mm.set_instance_transform(_far_idx[i], Transform3D(Basis().scaled(Vector3.ZERO), _xf[i].origin))
	_since_update = UPDATE_PERIOD # the near set drops it next frame


func _cylinder(radius: float, height: float) -> Shape3D:
	var key := "cyl_%.2f_%.2f" % [radius, height]
	if not _shapes.has(key):
		var c := CylinderShape3D.new()
		c.radius = maxf(radius, 0.05)
		c.height = height
		_shapes[key] = c
	return _shapes[key]


func _body_for(p: Vector3) -> StaticBody3D:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	if not _bodies.has(key):
		var body := StaticBody3D.new()
		body.name = "Props_%d_%d" % [key.x, key.y]
		add_child(body)
		_bodies[key] = body
	return _bodies[key]
