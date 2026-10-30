class_name TestTerrain
extends StaticBody3D
## Procedural heightmap for driving tests: a large flat pad for surface zones,
## a mogul field to the east, two hills of different steepness in the far
## corners and rolling noise around the edge.
##
## Surface zones (add_zone) must be added before the node enters the tree.
## Soft zones get a SoftPatch; the terrain mesh hides itself under them.
##
## Bursts dig into it (dig_crater: a bowl with a thrown-up rim), the collision and the mesh (in
## CHUNK-metre pieces, only those dug into rebuilt) taking it on at commit_digs.

const SIZE := 257 ## Samples per side, 1 m apart.
const HALF := (SIZE - 1) / 2

var default_surface := Surface.preset("dirt")
var noise_from := 70.0 ## m from the middle the rolling noise starts (the arena keeps its floor flat)
var features := true ## the mogul field and the two hills
var grid_strength := 0.08 ## how much of the metre grid shows on it (the arena: none)
const CHUNK := 32 ## m a mesh piece

var _shape: HeightMapShape3D
var _mat: ShaderMaterial
var _chunks := {} ## Vector2i -> MeshInstance3D
var _dirty := {} ## Vector2i chunks dug into since the last commit

var _heights := PackedFloat32Array()
var _noise := FastNoiseLite.new()
var _zones: Array[Dictionary] = [] ## {rect: Rect2, surface: Surface, patch: SoftPatch}


## Paints a surface over a world XZ rectangle. Use whole-metre edges.
func add_zone(area: Rect2, surface: Surface) -> void:
	_zones.append({"rect": area, "surface": surface, "patch": null})


func _ready() -> void:
	_noise.seed = 1337
	_noise.frequency = 0.01
	_noise.fractal_octaves = 4
	_heights.resize(SIZE * SIZE)
	for z in SIZE:
		for x in SIZE:
			_heights[z * SIZE + x] = height_at(x - HALF, z - HALF)
	_build_collision()
	_build_mesh()
	for zone in _zones:
		var surface: Surface = zone.surface
		if surface.is_soft():
			var patch := SoftPatch.new()
			patch.setup(zone.rect, surface, sample_height)
			add_child(patch)
			zone.patch = patch


## The zones anew while it's running: the old soft patches go, the new ones are made, the ground's
## colours repainted.
func set_zones(zones: Array) -> void:
	for zone in _zones:
		if zone.patch:
			(zone.patch as Node).queue_free()
	_zones.clear()
	for z: Array in zones:
		_zones.append({"rect": z[0], "surface": z[1], "patch": null})
	for zone in _zones:
		var surface: Surface = zone.surface
		if surface.is_soft():
			var patch := SoftPatch.new()
			patch.setup(zone.rect, surface, sample_height)
			add_child(patch)
			zone.patch = patch
	if _mat:
		var mask := _build_surface_mask()
		_mat.set_shader_parameter("surface_mask", mask)
		_mat.set_shader_parameter("surface_soft", mask)


## Analytic height; matches the collision samples at whole-metre coordinates.
func height_at(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * 6.0
	h *= smoothstep(noise_from, noise_from + 30.0, Vector2(x, z).length())
	if not features:
		return h
	# Mogul field: alternating bumps that twist the chassis and unload wheels.
	if x > 40.0 and x < 100.0 and absf(z) < 25.0:
		var edge := minf(minf(x - 40.0, 100.0 - x), 25.0 - absf(z))
		h += 0.55 * sin(x * 0.75) * sin(z * 0.75) * clampf(edge / 6.0, 0.0, 1.0)
	h += _hill(x, z, Vector2(-95.0, -95.0), 16.0, 18.0) # ~28° at its steepest
	h += _hill(x, z, Vector2(95.0, -95.0), 14.0, 12.0) # ~35° at its steepest
	for r: Rect2 in flat_areas: # (the arena's shooting range: its lane levelled, eased in at the sides)
		var out := maxf(maxf(r.position.x - x, x - r.end.x), maxf(r.position.y - z, z - r.end.y))
		if out < FLAT_EASE:
			h = lerpf(h, 0.0, 1.0 - smoothstep(0.0, FLAT_EASE, out))
	return h


## Ground levelled to 0 (set before it enters the tree): ShootingRange's lane.
var flat_areas: Array[Rect2] = []
const FLAT_EASE := 10.0 ## m beyond a flat area it eases back into the land


## Height of the rigid ground between samples (bilinear, like the collision).
func sample_height(x: float, z: float) -> float:
	var gx := x + HALF
	var gz := z + HALF
	var x0 := clampi(floori(gx), 0, SIZE - 2)
	var z0 := clampi(floori(gz), 0, SIZE - 2)
	var fx := gx - x0
	var fz := gz - z0
	var i := z0 * SIZE + x0
	return lerpf(lerpf(_heights[i], _heights[i + 1], fx), lerpf(_heights[i + SIZE], _heights[i + SIZE + 1], fx), fz)


func surface_at(p: Vector3) -> Surface:
	var zone := _zone_at(p)
	return zone.surface if zone else default_surface


func patch_at(p: Vector3) -> SoftPatch:
	var zone := _zone_at(p)
	return zone.patch if zone else null


func _zone_at(p: Vector3) -> Dictionary:
	var flat := Vector2(p.x, p.z)
	# Later zones win, so small zones can sit on top of big ones.
	for i in range(_zones.size() - 1, -1, -1):
		var r: Rect2 = _zones[i].rect
		if r.has_point(flat):
			return _zones[i]
	return {}


static func _hill(x: float, z: float, center: Vector2, height: float, radius: float) -> float:
	var d2 := Vector2(x, z).distance_squared_to(center)
	return height * exp(-d2 / (2.0 * radius * radius))


func _sample(x: int, z: int) -> float:
	return _heights[clampi(z, 0, SIZE - 1) * SIZE + clampi(x, 0, SIZE - 1)]


func _build_collision() -> void:
	_shape = HeightMapShape3D.new()
	_shape.map_width = SIZE
	_shape.map_depth = SIZE
	_shape.map_data = _heights
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	add_child(cs)


## A bowl `depth` deep over `radius` at p (its rim thrown up round it), into the rigid ground's
## samples. Call commit_digs() after a batch.
func dig_crater(p: Vector3, radius: float, depth: float, rim := 0.22) -> void:
	var cx := p.x + HALF
	var cz := p.z + HALF
	var reach := ceili(radius * 1.6)
	for z in range(floori(cz) - reach, ceili(cz) + reach + 1):
		for x in range(floori(cx) - reach, ceili(cx) + reach + 1):
			if x < 1 or z < 1 or x >= SIZE - 1 or z >= SIZE - 1:
				continue
			var d := Vector2(x - cx, z - cz).length() / radius
			var dh := 0.0
			if d < 1.0:
				dh = -depth * (1.0 - d * d)
			elif d < 1.6:
				dh = depth * rim * sin((d - 1.0) / 0.6 * PI) # (the thrown-up rim)
			if dh == 0.0:
				continue
			var i := z * SIZE + x
			_heights[i] = maxf(_heights[i] + dh, -6.0)
			_dirty[Vector2i(clampi((x - 1) / CHUNK, 0, (SIZE - 2) / CHUNK), clampi((z - 1) / CHUNK, 0, (SIZE - 2) / CHUNK))] = true
			_dirty[Vector2i(clampi(x / CHUNK, 0, (SIZE - 2) / CHUNK), clampi(z / CHUNK, 0, (SIZE - 2) / CHUNK))] = true


func commit_digs() -> void:
	if _dirty.is_empty():
		return
	_shape.map_data = _heights
	for c: Vector2i in _dirty:
		_build_chunk(c)
	_dirty.clear()


## One texel per 1 m cell: rgb = surface colour, a = 1 where a SoftPatch draws instead.
func _build_surface_mask() -> ImageTexture:
	var img := Image.create(SIZE - 1, SIZE - 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(default_surface.color, 0.0))
	for zone in _zones:
		var surface: Surface = zone.surface
		var r: Rect2 = zone.rect
		var cell_rect := Rect2i(Vector2i(r.position) + Vector2i(HALF, HALF), Vector2i(r.size))
		img.fill_rect(cell_rect, Color(surface.color, 1.0 if surface.is_soft() or surface.label == "pit" else 0.0)) # (a pit: open)
	return ImageTexture.create_from_image(img)


func _build_mesh() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/terrain_grid.gdshader")
	var mask := _build_surface_mask()
	_mat.set_shader_parameter("surface_mask", mask)
	_mat.set_shader_parameter("surface_soft", mask)
	_mat.set_shader_parameter("grid_strength", grid_strength)
	_mat.set_shader_parameter("half_size", float(HALF))
	var n := (SIZE - 1 + CHUNK - 1) / CHUNK
	for cz in n:
		for cx in n:
			_build_chunk(Vector2i(cx, cz))


## One CHUNK x CHUNK piece of the mesh, from the samples as they are now.
func _build_chunk(c: Vector2i) -> void:
	var x0 := c.x * CHUNK
	var z0 := c.y * CHUNK
	var w := mini(CHUNK, SIZE - 1 - x0) + 1
	var d := mini(CHUNK, SIZE - 1 - z0) + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(w * d)
	normals.resize(w * d)
	for z in d:
		for x in w:
			var gx := x0 + x
			var gz := z0 + z
			var i := z * w + x
			verts[i] = Vector3(gx - HALF, _heights[gz * SIZE + gx], gz - HALF)
			normals[i] = Vector3(_sample(gx - 1, gz) - _sample(gx + 1, gz), 2.0, _sample(gx, gz - 1) - _sample(gx, gz + 1)).normalized()
	var indices := PackedInt32Array()
	indices.resize((w - 1) * (d - 1) * 6)
	var k := 0
	for z in d - 1:
		for x in w - 1:
			var a := z * w + x
			var b := a + w
			for idx in [a, a + 1, b, a + 1, b + 1, b]:
				indices[k] = idx
				k += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi: MeshInstance3D = _chunks.get(c)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.material_override = _mat
		add_child(mi)
		_chunks[c] = mi
	mi.mesh = mesh
