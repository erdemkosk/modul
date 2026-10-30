class_name WorldTerrain
extends StaticBody3D
## The open world's ground: a 2 km x 2 km heightmap made offline by tools/world/build_world.py
## (assets/world/). Same interface as TestTerrain (height_at, sample_height, surface_at,
## patch_at), so the truck, the player, zombies and the winch work on either.
##
## Collision is one HeightMapShape3D at 1 m. The visible ground is 16 x 16 chunks of 128 m, each
## with five LOD grids (1, 2, 4, 8, 16 m) picked by visibility range; the shader lifts every vertex
## to the heightmap and lights it from the heightmap's own normals, so far chunks still shade
## with full detail. Ground types come from the splat maps (rock, snow, road, meadow, forest
## floor, wet ground, shore); soft ground (mud, bog, deep snow) is a SoftPatch rectangle listed in
## world.json, and the terrain mesh hides itself under each one.

const DIR := "res://assets/world/"
const CHUNK := 128
const LOD_STEPS := [1, 2, 4, 8, 16]
const LOD_END := [170.0, 340.0, 700.0, 1400.0, 0.0] ## Visibility range end per LOD, m (0 = no limit).

var meta := {}
var size := 0 ## Samples per side.
var half := 0 ## Index of the origin sample.
var lake_level := 0.0
var spawn := Transform3D.IDENTITY

var height_texture: ImageTexture
var splat_texture: ImageTexture
var splat2_texture: ImageTexture
var soft_texture: ImageTexture
var material: ShaderMaterial

var _heights := PackedFloat32Array()
var _splat := PackedByteArray()
var _splat2 := PackedByteArray()
var _zones: Array[Dictionary] = [] ## {rect: Rect2, surface: Surface, patch: SoftPatch}
var _surfaces := {}


func _init() -> void:
	name = "WorldTerrain"
	meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "world.json"))
	size = int(meta.size)
	half = int(meta.half)
	lake_level = float(meta.lake.level)
	_heights = _read_gz("heights.f32.gz", size * size * 4).to_float32_array()
	_splat = _read_gz("splat.bin.gz", size * size * 4)
	_splat2 = _read_gz("splat2.bin.gz", size * size * 4)
	for id in ["gravel", "grass", "dirt", "rock", "snowpack", "wet", "asphalt"]:
		_surfaces[id] = Surface.preset(id)
	var s: Dictionary = meta.spawn
	var at := Vector3(s.x, 0.0, s.z)
	_flatten_start(at.x, at.z)
	at.y = height_at(at.x, at.z)
	spawn = Transform3D(Basis(Vector3.UP, deg_to_rad(float(s.heading))), at)
	_build_soft()
	if not RutStore.loaded:
		RutStore.load_marks()
	if not RutStore.churned.is_empty():
		_apply_churned()


## Where you begin (START_R m round the spawn) is easy ground: the slopes eased (the heights drawn
## toward their average over START_BLUR m, wholly in the middle, less and less out to the edge) and
## little mud (_build_soft), as a first cart's small engine needs.
const START_R := 110.0
const START_BLUR := 16


func _flatten_start(cx: float, cz: float) -> void:
	var r := int(START_R) + START_BLUR + 2
	var gx0 := clampi(int(cx) + half - r, 0, size - 1)
	var gx1 := clampi(int(cx) + half + r, 0, size - 1)
	var gz0 := clampi(int(cz) + half - r, 0, size - 1)
	var gz1 := clampi(int(cz) + half + r, 0, size - 1)
	var w := gx1 - gx0 + 1
	var h := gz1 - gz0 + 1
	var rows := PackedFloat32Array()
	rows.resize(w * h)
	for z in h: # (along x, then along z: a box blur each way)
		var acc := 0.0
		var n := 0
		for x in range(-START_BLUR, w + START_BLUR):
			var add := x + START_BLUR
			if add < w:
				acc += _heights[(gz0 + z) * size + gx0 + add]
				n += 1
			var out := x - START_BLUR - 1
			if out >= 0:
				acc -= _heights[(gz0 + z) * size + gx0 + out]
				n -= 1
			if x >= 0 and x < w:
				rows[z * w + x] = acc / n
	var blur := PackedFloat32Array()
	blur.resize(w * h)
	for x in w:
		var acc := 0.0
		var n := 0
		for z in range(-START_BLUR, h + START_BLUR):
			var add := z + START_BLUR
			if add < h:
				acc += rows[add * w + x]
				n += 1
			var out := z - START_BLUR - 1
			if out >= 0:
				acc -= rows[out * w + x]
				n -= 1
			if z >= 0 and z < h:
				blur[z * w + x] = acc / n
	for z in h:
		for x in w:
			var d := Vector2(gx0 + x - half - cx, gz0 + z - half - cz).length()
			var k := smoothstep(START_R, START_R * 0.45, d)
			if k > 0.0:
				var i := (gz0 + z) * size + gx0 + x
				_heights[i] = lerpf(_heights[i], blur[z * w + x], k * 0.9)


## How much of a start's ease there is at (x, z): 1 in the middle, 0 past START_R.
func start_ease(x: float, z: float) -> float:
	var s: Dictionary = meta.spawn
	return smoothstep(START_R * 1.1, START_R * 0.5, Vector2(x - float(s.x), z - float(s.z)).length())


func _read_gz(file: String, raw_size: int) -> PackedByteArray:
	var packed := FileAccess.get_file_as_bytes(DIR + file)
	return packed.decompress(raw_size, FileAccess.COMPRESSION_GZIP)


func _ready() -> void:
	_build_collision()
	_build_textures()
	_build_chunks()


# --- Queries (same as TestTerrain) ----------------------------------------------------------------

## Ground height at any point (bilinear between the 1 m samples, like the collision).
func height_at(x: float, z: float) -> float:
	return sample_height(x, z)


func sample_height(x: float, z: float) -> float:
	var gx := clampf(x + half, 0.0, size - 1.001)
	var gz := clampf(z + half, 0.0, size - 1.001)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - x0
	var fz := gz - z0
	var i := z0 * size + x0
	return lerpf(lerpf(_heights[i], _heights[i + 1], fx), lerpf(_heights[i + size], _heights[i + size + 1], fx), fz)


func surface_at(p: Vector3) -> Surface:
	var zone := _soft_zone(p)
	if zone:
		return zone.surface
	var i := _texel(p) * 4
	var s: Surface
	if _splat[i + 2] > 128:
		s = _surfaces.asphalt if _splat[i] > 200 else _surfaces.gravel # paved: road and rock both
	elif _splat[i + 1] > 140:
		s = _surfaces.snowpack
	elif _splat[i] > 150:
		s = _surfaces.rock
	elif _splat2[i + 1] > 150:
		s = _surfaces.wet
	else:
		s = _surfaces.grass if _splat[i + 3] > 110 else _surfaces.dirt
	if Weather.ice_now > 0.05 and s.label in ["gravel", "wet", "asphalt"]:
		# Frozen in patches: where water lay on the road, in the wheel tracks, in hollows.
		var lies := 0.12
		if Weather.ice_now * (ice_patch(p.x, p.z) + lies) > 0.5:
			return Surface.preset("black_ice")
	return s


## Standing water at a point, m deep (0 = none): a flooded rut or a pool in the mud, or a
## puddle on a road or flat ground after rain (where world_terrain.gdshader draws them).
func water_at(p: Vector3) -> float:
	var patch := patch_at(p)
	if patch:
		return patch.water_at(p)
	return puddle_at(p.x, p.z) * 0.06


## 0..1, a puddle on firm ground: in the dips of roads and flat ground, spreading with the rain
## (world_terrain.gdshader's puddle).
func puddle_at(x: float, z: float) -> float:
	var i := _texel(Vector3(x, 0.0, z)) * 4
	var rock := _splat[i] / 255.0
	if rock > 0.5 or _splat2[i + 3] > 128:
		return 0.0
	var slope := 1.0 - Vector3(sample_height(x - 1.0, z) - sample_height(x + 1.0, z), 2.0,
		sample_height(x, z - 1.0) - sample_height(x, z + 1.0)).normalized().y
	var flat := smoothstep(0.07, 0.015, slope)
	if flat <= 0.0:
		return 0.0
	var n := SoftPatch.fbm(x * 0.07 + 3.1, z * 0.07 + 3.1, 3) + (SoftPatch.fbm(x * 0.6 + 1.7, z * 0.6 + 1.7, 2) - 0.5) * 0.16
	var thr := lerpf(0.86, 0.67, Weather.wet_now) - _splat[i + 2] / 255.0 * 0.12 - _splat2[i + 1] / 255.0 * 0.14
	return smoothstep(thr, thr + 0.012, n) * flat * (1.0 - rock)


## 0..1, where water lies to freeze (the same pattern world_terrain.gdshader glazes).
static func ice_patch(x: float, z: float) -> float:
	var n := _vnoise(x * 0.045, z * 0.045) * 0.7 + _vnoise(x * 0.19 + 3.0, z * 0.19 + 3.0) * 0.3
	return smoothstep(0.42, 0.7, n)


static func _hash12(x: float, y: float) -> float:
	var p3 := Vector3(fposmod(x * 0.1031, 1.0), fposmod(y * 0.1031, 1.0), fposmod(x * 0.1031, 1.0))
	var d := p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3.ONE * 33.33)
	p3 += Vector3.ONE * d
	return fposmod((p3.x + p3.y) * p3.z, 1.0)


static func _vnoise(x: float, y: float) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var a := lerpf(_hash12(ix, iy), _hash12(ix + 1.0, iy), ux)
	var b := lerpf(_hash12(ix, iy + 1.0), _hash12(ix + 1.0, iy + 1.0), ux)
	return lerpf(a, b, uy)


func patch_at(p: Vector3) -> SoftPatch:
	var zone := _soft_zone(p)
	return _ensure_patch(zone.tile) if zone else null


## Every rut patch within `r` of a point (made if it isn't yet): a footprint near a tile edge
## is pressed into the tiles on both sides, so ruts run on across the seam.
func patches_near(p: Vector3, r: float) -> Array[SoftPatch]:
	var out: Array[SoftPatch] = []
	var a := _tile_of(p.x - r, p.z - r)
	var b := _tile_of(p.x + r, p.z + r)
	for tz in range(a.y, b.y + 1):
		for tx in range(a.x, b.x + 1):
			var t := Vector2i(tx, tz)
			if _tile_kind[tz * _tiles_per_side + tx] == 0:
				continue
			var patch := _ensure_patch(t)
			if patch and patch.rect.grow(r).has_point(Vector2(p.x, p.z)):
				out.append(patch)
	return out


## 0..1 splat weights at a point: {rock, snow, road, meadow, forest, wet, shore}.
func ground_at(x: float, z: float) -> Dictionary:
	var i := _texel(Vector3(x, 0.0, z)) * 4
	return {
		"rock": _splat[i] / 255.0, "snow": _splat[i + 1] / 255.0, "road": _splat[i + 2] / 255.0,
		"meadow": _splat[i + 3] / 255.0, "forest": _splat2[i] / 255.0, "wet": _splat2[i + 1] / 255.0,
		"shore": _splat2[i + 2] / 255.0,
	}


## Under the lake or the river surface.
func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < water_height_at(x, z) - 0.05


## Water surface height at a point, or -INF where there is none.
func water_height_at(x: float, z: float) -> float:
	var lake: Dictionary = meta.lake
	var lx := (x - float(lake.x)) / float(lake.rx)
	var lz := (z - float(lake.z)) / float(lake.rz)
	if lx * lx + lz * lz < 1.0:
		return lake_level
	return -INF


func _texel(p: Vector3) -> int:
	var x := clampi(roundi(p.x) + half, 0, size - 1)
	var z := clampi(roundi(p.z) + half, 0, size - 1)
	return z * size + x


func _zone_at(p: Vector3) -> Dictionary:
	var flat := Vector2(p.x, p.z)
	for i in range(_zones.size() - 1, -1, -1):
		var r: Rect2 = _zones[i].rect
		if r.has_point(flat):
			return _zones[i]
	return {}


# --- Building ---------------------------------------------------------------------------------------

var _shape: HeightMapShape3D


func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	_shape = shape
	shape.map_width = size
	shape.map_depth = size
	shape.map_data = _heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)


func _build_textures() -> void:
	height_texture = ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_RF, _heights.to_byte_array()))
	var splat_img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, _splat)
	splat_img.generate_mipmaps()
	splat_texture = ImageTexture.create_from_image(splat_img)
	var splat2_img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, _splat2)
	splat2_img.generate_mipmaps()
	splat2_texture = ImageTexture.create_from_image(splat2_img)
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/world_terrain.gdshader")
	material.set_shader_parameter("heightmap", height_texture)
	material.set_shader_parameter("splat", splat_texture)
	material.set_shader_parameter("splat2", splat2_texture)
	material.set_shader_parameter("soft_map", soft_map)
	material.set_shader_parameter("patch_flags", patch_flags)
	material.set_shader_parameter("tile_size", float(TILE))
	material.set_shader_parameter("map_half", float(half))
	material.set_shader_parameter("map_size", float(size))


func _build_chunks() -> void:
	var meshes: Array[ArrayMesh] = []
	for step: int in LOD_STEPS:
		meshes.append(_grid_mesh(step))
	var per_side := (size - 1) / CHUNK
	for cz in per_side:
		for cx in per_side:
			var origin := Vector3(cx * CHUNK - half, 0.0, cz * CHUNK - half)
			var lo := INF
			var hi := -INF
			for sz in range(0, CHUNK + 1, 8):
				for sx in range(0, CHUNK + 1, 8):
					var hh := _heights[(cz * CHUNK + sz) * size + cx * CHUNK + sx]
					lo = minf(lo, hh)
					hi = maxf(hi, hh)
			var aabb := AABB(Vector3(0.0, lo - 12.0, 0.0), Vector3(CHUNK, hi - lo + 24.0, CHUNK))
			for l in LOD_STEPS.size():
				var mi := MeshInstance3D.new()
				mi.mesh = meshes[l]
				mi.material_override = material
				mi.position = origin
				mi.custom_aabb = aabb
				mi.visibility_range_begin = 0.0 if l == 0 else LOD_END[l - 1]
				mi.visibility_range_end = LOD_END[l]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if l < 3 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)


## A CHUNK x CHUNK grid with `step` m spacing and a 4 m skirt round the edge (y = -1 marks skirt
## vertices; the shader drops them below the ground) that hides cracks between LODs.
func _grid_mesh(step: int) -> ArrayMesh:
	var n := CHUNK / step + 1
	var verts := PackedVector3Array()
	verts.resize(n * n)
	for z in n:
		for x in n:
			verts[z * n + x] = Vector3(x * step, 0.0, z * step)
	var indices := PackedInt32Array()
	for z in n - 1:
		for x in n - 1:
			var a := z * n + x
			var c := a + n
			indices.append_array([a, a + 1, c, a + 1, c + 1, c])
	var ring := PackedInt32Array()
	for x in n:
		ring.append(x)
	for z in range(1, n):
		ring.append(z * n + n - 1)
	for x in range(n - 2, -1, -1):
		ring.append((n - 1) * n + x)
	for z in range(n - 2, 0, -1):
		ring.append(z * n)
	var first_low := verts.size()
	for i in ring:
		verts.append(Vector3(verts[i].x, -1.0, verts[i].z))
	for k in ring.size():
		var k2 := (k + 1) % ring.size()
		indices.append_array([ring[k], ring[k2], first_low + k, ring[k2], first_low + k2, first_low + k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Soft ground: where it really is ---------------------------------------------------------------
# Mud and deep snow aren't rectangles. A map of the whole valley (4 m texels, R = mud,
# G = deep snow, 0..1) is worked out once from what makes ground soft: wet ground and
# hollows where water stands, the river banks and the lake shore, puddled stretches of
# road, the marshy areas in world.json (now only a nudge, with feathered edges), and
# snow up high. Noise gives every patch a ragged, natural outline. Ground is soft where
# the value passes 0.5; the terrain shader paints it there (with a dark wet fringe round
# it), and deformable rut patches (SoftPatch) are built in 32 m tiles only near whoever
# is moving, and drawn only over the soft part.

const SOFT_RES := 512 ## Map texels per side (4 m each).
const TILE := 32 ## Rut-patch tile size, m.

var soft_map: ImageTexture ## RG8: mud, deep snow.
var patch_flags: ImageTexture ## R8, one texel per tile: 1 where a rut patch draws the ground.
var _soft := PackedByteArray()
var _tile_kind := PackedByteArray() ## Per tile: 0 firm, 1 mud, 2 bog, 3 snow.
var _tiles := {} ## Vector2i -> SoftPatch
var _flags_img: Image
var _tiles_per_side := 0
var _soft_surfaces := {}


func _build_soft() -> void:
	var n := SOFT_RES
	var step := float(size - 1) / n
	var noise := FastNoiseLite.new()
	noise.seed = 4127
	noise.fractal_octaves = 4
	noise.frequency = 0.022 * step
	var big := noise.get_image(n, n).get_data()
	noise.seed = 991
	noise.frequency = 0.075 * step
	noise.fractal_octaves = 3
	var mid := noise.get_image(n, n).get_data()
	# River banks: distance (in texels) from the river line, stamped.
	var river := PackedFloat32Array()
	river.resize(n * n)
	river.fill(99.0)
	for q in meta.river.points:
		var cx := (float(q[0]) + half) / step
		var cz := (float(q[2]) + half) / step
		for dz in range(-7, 8):
			for dx in range(-7, 8):
				var tx := int(cx) + dx
				var tz := int(cz) + dz
				if tx < 0 or tz < 0 or tx >= n or tz >= n:
					continue
				var d := Vector2(tx + 0.5 - cx, tz + 0.5 - cz).length()
				var k := tz * n + tx
				river[k] = minf(river[k], d)
	# The marked marshes and snowfields, feathered: 1 deep inside, 0 at 20 m outside.
	var zone_mud := PackedFloat32Array()
	zone_mud.resize(n * n)
	var zone_snow := PackedFloat32Array()
	zone_snow.resize(n * n)
	var bog_rects: Array[Rect2] = []
	for z: Dictionary in meta.soft:
		var r := Rect2(z.rect[0], z.rect[1], z.rect[2], z.rect[3])
		var is_snow: bool = z.surface == "snow"
		if z.surface == "bog":
			bog_rects.append(r)
		var t0 := Vector2i(int((r.position.x - 24.0 + half) / step), int((r.position.y - 24.0 + half) / step))
		var t1 := Vector2i(int((r.end.x + 24.0 + half) / step), int((r.end.y + 24.0 + half) / step))
		for tz in range(maxi(t0.y, 0), mini(t1.y + 1, n)):
			for tx in range(maxi(t0.x, 0), mini(t1.x + 1, n)):
				var wx := (tx + 0.5) * step - half
				var wz := (tz + 0.5) * step - half
				var inside := minf(minf(wx - r.position.x, r.end.x - wx), minf(wz - r.position.y, r.end.y - wz))
				var v := smoothstep(-20.0, 14.0, inside)
				var k := tz * n + tx
				if is_snow:
					zone_snow[k] = maxf(zone_snow[k], v)
				else:
					zone_mud[k] = maxf(zone_mud[k], v)
	var lo := float(meta.height_range[0])
	var hi := float(meta.height_range[1])
	var snowline := lerpf(lo, hi, 0.68)
	_soft.resize(n * n * 2)
	for tz in n:
		for tx in n:
			var k := tz * n + tx
			var gx := clampi(int((tx + 0.5) * step), 1, size - 2)
			var gz := clampi(int((tz + 0.5) * step), 1, size - 2)
			var gi := gz * size + gx
			var si := gi * 4
			var rock := _splat[si] / 255.0
			var snow_s := _splat[si + 1] / 255.0
			var road := _splat[si + 2] / 255.0
			var wet := _splat2[si + 1] / 255.0
			var shore := _splat2[si + 2] / 255.0
			var h := _heights[gi]
			var avg := (_heights[gz * size + clampi(gx - 10, 0, size - 1)] + _heights[gz * size + clampi(gx + 10, 0, size - 1)]
				+ _heights[clampi(gz - 10, 0, size - 1) * size + gx] + _heights[clampi(gz + 10, 0, size - 1) * size + gx]) * 0.25
			var hollow := clampf((avg - h) / 1.5, 0.0, 1.0)
			var blob := 0.5 + (big[k] / 255.0 - 0.5) * 1.2 + (mid[k] / 255.0 - 0.5) * 0.5
			var mud := zone_mud[k] * (0.3 + blob)
			mud = maxf(mud, wet * (blob - 0.05))
			mud = maxf(mud, hollow * (blob - 0.05) * 0.95)
			mud = maxf(mud, road * smoothstep(0.66, 0.82, mid[k] / 255.0 + (big[k] / 255.0 - 0.5) * 0.3) * 0.95)
			mud = maxf(mud, smoothstep(5.5, 2.0, river[k]) * (0.2 + blob))
			mud = maxf(mud, shore * (0.1 + blob) * 0.9)
			mud *= 1.0 - rock * 0.95
			mud *= 1.0 - 0.9 * start_ease((tx + 0.5) * step - half, (tz + 0.5) * step - half) # (the start's dry)
			var snow := zone_snow[k] * (0.3 + blob)
			snow = maxf(snow, snow_s * blob)
			snow = maxf(snow, smoothstep(snowline, snowline + 35.0, h) * (0.05 + blob) * (1.0 - rock * 0.8))
			_soft[k * 2] = clampi(int(mud * 255.0), 0, 255)
			_soft[k * 2 + 1] = clampi(int(snow * 255.0), 0, 255)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RG8, _soft)
	soft_map = ImageTexture.create_from_image(img)
	# Tiles: which have soft ground in them, and what kind.
	_tiles_per_side = (size - 1) / TILE
	_tile_kind.resize(_tiles_per_side * _tiles_per_side)
	var per := TILE / step
	for tz in _tiles_per_side:
		for tx in _tiles_per_side:
			var best_m := 0
			var best_s := 0
			for z in range(int(tz * per), int((tz + 1) * per)):
				for x in range(int(tx * per), int((tx + 1) * per)):
					var k := (z * n + x) * 2
					best_m = maxi(best_m, _soft[k])
					best_s = maxi(best_s, _soft[k + 1])
			var kind := 0
			if maxi(best_m, best_s) > 118:
				kind = 3 if best_s > best_m else 1
				if kind == 1:
					var c := Vector2((tx + 0.5) * TILE - half, (tz + 0.5) * TILE - half)
					for r in bog_rects:
						if r.grow(8.0).has_point(c):
							kind = 2
			_tile_kind[tz * _tiles_per_side + tx] = kind
	_flags_img = Image.create(_tiles_per_side, _tiles_per_side, false, Image.FORMAT_R8)
	patch_flags = ImageTexture.create_from_image(_flags_img)
	# The 1 m mask the grass reads (no grass in mud or deep snow).
	var grass_data := PackedByteArray()
	grass_data.resize(n * n)
	for k in n * n:
		grass_data[k] = 255 if maxi(_soft[k * 2], _soft[k * 2 + 1]) > 128 else 0
	var grass := Image.create_from_data(n, n, false, Image.FORMAT_R8, grass_data)
	grass.resize(size - 1, size - 1, Image.INTERPOLATE_NEAREST)
	_grass_img = grass
	soft_texture = ImageTexture.create_from_image(grass)
	for id in ["mud", "bog", "snow"]:
		_soft_surfaces[id] = Surface.preset(id)


## Mud and snow 0..1 at a point (bilinear in the map, as the shader samples it).
func soft_at(x: float, z: float) -> Vector2:
	var n := SOFT_RES
	var step := float(size - 1) / n
	var fx := clampf((x + half) / step - 0.5, 0.0, n - 1.001)
	var fz := clampf((z + half) / step - 0.5, 0.0, n - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var ax := fx - x0
	var az := fz - z0
	var out := Vector2.ZERO
	for c in 2:
		var a := _soft[(z0 * n + x0) * 2 + c]
		var b := _soft[(z0 * n + x0 + 1) * 2 + c]
		var d := _soft[((z0 + 1) * n + x0) * 2 + c]
		var e := _soft[((z0 + 1) * n + x0 + 1) * 2 + c]
		out[c] = lerpf(lerpf(a, b, ax), lerpf(d, e, ax), az) / 255.0
	return out


func _tile_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int((x + half) / TILE), 0, _tiles_per_side - 1), clampi(int((z + half) / TILE), 0, _tiles_per_side - 1))


## {tile, surface} where the ground is soft, else {}.
func _soft_zone(p: Vector3) -> Dictionary:
	var t := _tile_of(p.x, p.z)
	var kind := _tile_kind[t.y * _tiles_per_side + t.x]
	if kind == 0:
		return {}
	var s := soft_at(p.x, p.z)
	if maxf(s.x, s.y) < 0.5:
		return {}
	return {"tile": t, "surface": _soft_surfaces[["", "mud", "bog", "snow"][kind]]}


## The rut patch for a tile, built when first needed.
func _ensure_patch(t: Vector2i) -> SoftPatch:
	if _tiles.has(t):
		return _tiles[t]
	if _building.has(t):
		WorkerThreadPool.wait_for_task_completion(_building[t][0])
		return _finish_patch(t)
	var kind := _tile_kind[t.y * _tiles_per_side + t.x]
	if kind == 0:
		return null
	var patch := SoftPatch.new()
	_roads_ready()
	_build_patch(patch, t)
	_building[t] = [-1, patch]
	return _finish_patch(t)


## Tiles being made on a worker thread: Vector2i -> [task id, SoftPatch]. A tile's mesh, its
## old tracks and saved ruts take ~30 ms to work out, too long for one frame: the ones ahead
## of whoever is moving are made off the main thread and only added to the scene here.
var _building := {}
const BUILDS_AT_ONCE := 3


## The patch's data, off the scene tree (safe on a worker thread: it only reads the terrain).
func _build_patch(patch: SoftPatch, t: Vector2i) -> void:
	var kind := _tile_kind[t.y * _tiles_per_side + t.x]
	var rect := Rect2(t.x * TILE - half, t.y * TILE - half, TILE, TILE)
	patch.setup(rect, _soft_surfaces[["", "mud", "bog", "snow"][kind]], sample_height)
	patch.use_world_mask(soft_map, float(half), float(size), soft_at)
	_old_tracks(patch, rect)
	patch.settle() # old tracks hold their water already
	var key := "%d,%d" % [t.x, t.y]
	if RutStore.ruts.has(key):
		patch.load_depth(RutStore.ruts[key])


func _roads_ready() -> void:
	if _track_roads.is_empty():
		_track_roads = WarMap.roads().values()


## A made patch into the scene.
func _finish_patch(t: Vector2i) -> SoftPatch:
	var patch: SoftPatch = _building[t][1]
	_building.erase(t)
	add_child(patch)
	_tiles[t] = patch
	_flags_img.set_pixel(t.x, t.y, Color(1, 0, 0))
	patch_flags.update(_flags_img)
	return patch


## The roads, read here on the main thread for _old_tracks (WarMap's lazy statics aren't safe to
## fill from two threads at once).
var _track_roads: Array = []


## Starts making a tile on a worker thread (if it isn't made or on its way).
func _request_patch(t: Vector2i) -> void:
	if _tiles.has(t) or _building.has(t) or _tile_kind[t.y * _tiles_per_side + t.x] == 0:
		return
	_roads_ready()
	var patch := SoftPatch.new()
	_building[t] = [WorkerThreadPool.add_task(_build_patch.bind(patch, t), false, "rut patch"), patch]


## The patch under a point if it's made already, else null: for the dead, who leave footprints
## only where the ground is made already (round whoever is moving: _process), so that one of
## them wandering onto a new tile far off neither stalls the frame nor has it made at all.
func patch_if_ready(p: Vector3) -> SoftPatch:
	var zone := _soft_zone(p)
	return _tiles.get(zone.tile) if not zone.is_empty() else null


## Where a road runs through soft ground, the trucks before you have left two
## ruts along it (the safe line through a mined stretch: Minefield.TRACK_HALF).
func _old_tracks(patch: SoftPatch, rect: Rect2) -> void:
	var area := rect.grow(2.0)
	for pts: PackedVector2Array in _track_roads:
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			if not area.intersects(Rect2(a, Vector2.ZERO).expand(b)):
				continue
			var dir := (b - a).normalized()
			var side := Vector2(-dir.y, dir.x)
			var seg := a.distance_to(b)
			var t := 0.0
			while t <= seg:
				var c := a + dir * t
				for s: float in [-1.05, 1.05]:
					var p: Vector2 = c + side * s
					if area.has_point(p):
						var depth := 0.07 + 0.04 * sin(p.x * 0.7 + p.y * 0.3)
						patch.stamp(Vector3(p.x, 0.0, p.y), Vector3(dir.x, 0.0, dir.y), 0.2, 0.3, depth)
				t += 0.25


## Into RutStore: every patch that has been dug into, and the churned ground.
func save_marks() -> void:
	for t: Vector2i in _tiles:
		var p: SoftPatch = _tiles[t]
		if p.touched:
			RutStore.ruts["%d,%d" % [t.x, t.y]] = p.depth_bytes()
	RutStore.save_marks()


var _churn_dirty := false
var _churn_upload := 0.0


## Wheels spinning (or many passes) on wet grass or bare earth tear it up:
## the ground there turns to mud, for good. `amount` is roughly metres of
## slip; wetter ground goes quicker.
func churn(p: Vector3, amount: float) -> void:
	var n := SOFT_RES
	var step := float(size - 1) / n
	var add := int(ceil(amount * 9.0))
	if add <= 0:
		return
	# The four texels round the point (the map is read bilinearly).
	var fx := clampf((p.x + half) / step - 0.5, 0.0, n - 1.001)
	var fz := clampf((p.z + half) / step - 0.5, 0.0, n - 1.001)
	var v := 0
	for dz in 2:
		for dx in 2:
			var k := (int(fz) + dz) * n + int(fx) + dx
			var cur := _soft[k * 2]
			if cur >= 210:
				continue
			v = mini(cur + add, 210)
			_soft[k * 2] = v
			RutStore.churned[k] = v
	_churn_dirty = true
	if v > 128:
		clear_grass(p, 1.2) # churned to mud: the grass is gone
		var t := _tile_of(p.x, p.z)
		if _tile_kind[t.y * _tiles_per_side + t.x] == 0:
			_tile_kind[t.y * _tiles_per_side + t.x] = 1 # now there's mud in this tile


## Churned ground from earlier days back onto the map.
func _apply_churned() -> void:
	for k in RutStore.churned:
		var i := int(k)
		if i >= 0 and i < SOFT_RES * SOFT_RES:
			_soft[i * 2] = maxi(_soft[i * 2], int(RutStore.churned[k]))
			var x := (i % SOFT_RES) * float(size - 1) / SOFT_RES - half
			var z := (i / SOFT_RES) * float(size - 1) / SOFT_RES - half
			if _soft[i * 2] > 128:
				var t := _tile_of(x, z)
				if _tile_kind[t.y * _tiles_per_side + t.x] == 0:
					_tile_kind[t.y * _tiles_per_side + t.x] = 1
	soft_map.update(Image.create_from_data(SOFT_RES, SOFT_RES, false, Image.FORMAT_RG8, _soft))


var _near_check := 0.0


func _exit_tree() -> void:
	for t: Vector2i in _building:
		if _building[t][0] >= 0:
			WorkerThreadPool.wait_for_task_completion(_building[t][0])


## Rut patches come up a little ahead of whoever is moving, one per frame.
func _process(delta: float) -> void:
	_churn_upload -= delta
	if _churn_dirty and _churn_upload <= 0.0:
		_churn_dirty = false
		_churn_upload = 0.5
		_upload_grass()
		soft_map.update(Image.create_from_data(SOFT_RES, SOFT_RES, false, Image.FORMAT_RG8, _soft))
	for t: Vector2i in _building.keys():
		var id: int = _building[t][0]
		if id >= 0 and WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_finish_patch(t)
			break # one into the scene a frame
	_near_check -= delta
	if _near_check > 0.0 or _building.size() >= BUILDS_AT_ONCE:
		return
	_near_check = 0.15
	for node in get_tree().get_nodes_in_group(Hearing.GROUP):
		var p: Vector3 = (node as Node3D).global_position
		# Where it'll be in a few seconds first: driving fast it outran the rings round it, and a
		# wheel on a tile not made yet had it made there and then (~40 ms).
		var vel: Vector3 = node.linear_velocity if node is RigidBody3D else (node.velocity if node is CharacterBody3D else Vector3.ZERO)
		if vel.length() > 4.0:
			for s: float in [1.5, 3.0]:
				var q := p + vel * s
				var ta := _tile_of(q.x, q.z)
				if not _tiles.has(ta) and not _building.has(ta) and _tile_kind[ta.y * _tiles_per_side + ta.x] != 0:
					_request_patch(ta)
					if _building.size() >= BUILDS_AT_ONCE:
						return
		var c := _tile_of(p.x, p.z)
		for ring in 3: # the nearest first
			for dz in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dz)) != ring:
						continue
					var t := c + Vector2i(dx, dz)
					if t.x < 0 or t.y < 0 or t.x >= _tiles_per_side or t.y >= _tiles_per_side or _tiles.has(t) or _building.has(t):
						continue
					if _tile_kind[t.y * _tiles_per_side + t.x] != 0:
						_request_patch(t)
						if _building.size() >= BUILDS_AT_ONCE:
							return


# --- Digging: shell holes and trenches cut into the ground itself --------------------------------

var _dug := {} ## Vector3i -> true: what is already dug, so a rebuild doesn't dig it twice.
var _dig_dirty := false


## A shell hole: a bowl `depth` deep and `radius` across, with a low rim of thrown-up earth.
## Call commit_digs() after a batch of them.
func dig_crater(p: Vector3, radius: float, depth: float, rim := 0.22) -> void:
	var key := Vector3i(roundi(p.x * 2.0), 0, roundi(p.z * 2.0))
	if _dug.has(key):
		return
	_dug[key] = true
	clear_grass(p, radius * 1.5)
	var reach := radius * 1.7
	_each_sample(p.x - reach, p.z - reach, p.x + reach, p.z + reach, func(x: float, z: float) -> float:
		var d := Vector2(x - p.x, z - p.z).length() / radius
		if d < 1.0:
			return -depth * (1.0 - d * d) + rim * smoothstep(0.75, 1.0, d)
		if d < 1.7:
			return rim * (1.0 - smoothstep(1.0, 1.7, d))
		return 0.0)


## A trench from a to b (ground plan), `width` across the top and `depth` deep, with steep sides.
func dig_trench(a: Vector2, b: Vector2, width: float, depth: float) -> void:
	var key := Vector3i(roundi(a.x + b.x), 1, roundi(a.y + b.y))
	if _dug.has(key):
		return
	_dug[key] = true
	var half_w := width * 0.5
	for i in int(a.distance_to(b) / 1.5) + 1:
		var c := a.lerp(b, minf(i * 1.5 / maxf(a.distance_to(b), 0.01), 1.0))
		clear_grass(Vector3(c.x, 0.0, c.y), half_w + 0.8)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (half_w + 1.0)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (half_w + 1.0)
	_each_sample(lo.x, lo.y, hi.x, hi.y, func(x: float, z: float) -> float:
		var q := Geometry2D.get_closest_point_to_segment(Vector2(x, z), a, b)
		var d := q.distance_to(Vector2(x, z))
		return -depth * (1.0 - smoothstep(half_w - 0.35, half_w + 0.15, d)))


## Adds f(x, z) to every height sample in the box (world metres).
func _each_sample(x0: float, z0: float, x1: float, z1: float, f: Callable) -> void:
	var gx0 := clampi(floori(x0 + half), 0, size - 1)
	var gx1 := clampi(ceili(x1 + half), 0, size - 1)
	var gz0 := clampi(floori(z0 + half), 0, size - 1)
	var gz1 := clampi(ceili(z1 + half), 0, size - 1)
	for gz in range(gz0, gz1 + 1):
		for gx in range(gx0, gx1 + 1):
			var dh: float = f.call(float(gx - half), float(gz - half))
			if dh != 0.0:
				_heights[gz * size + gx] += dh
				_dig_dirty = true


## Sends the dug heights to the collision and the ground shader (one upload per batch).
func commit_digs() -> void:
	if not _dig_dirty:
		_upload_grass()
		return
	_dig_dirty = false
	if _shape:
		_shape.map_data = _heights
	if height_texture:
		height_texture.update(Image.create_from_data(size, size, false, Image.FORMAT_RF, _heights.to_byte_array()))
	_upload_grass()


var _grass_img: Image
var _grass_dirty := false


## No grass in a circle round p (trampled camps, wrecks, holes); sent with commit_digs(),
## or with the next churn upload.
func clear_grass(p: Vector3, radius: float) -> void:
	if _grass_img == null:
		return
	var n := _grass_img.get_width()
	var r := ceili(radius)
	var cx := floori(p.x + half)
	var cz := floori(p.z + half)
	for z in range(maxi(cz - r, 0), mini(cz + r + 1, n)):
		for x in range(maxi(cx - r, 0), mini(cx + r + 1, n)):
			if Vector2(x - cx, z - cz).length() <= radius:
				_grass_img.set_pixel(x, z, Color(1, 0, 0))
	_grass_dirty = true


func _upload_grass() -> void:
	if _grass_dirty and soft_texture:
		_grass_dirty = false
		soft_texture.update(_grass_img)
