class_name SoftPatch
extends MeshInstance3D
## Deformable ground over a rectangle of terrain (mud, snow...).
##
## Wheels stamp ruts into a depth grid. The grid is not collision: the terrain
## underneath stays rigid and the Vehicle lowers each wheel by the rut depth.
## The same grid is uploaded as a texture that pushes this mesh down, so ruts
## are visible and stay where they were dug.
##
## Wet ground seeps into whatever is pressed into it. A rut or a footprint dug
## below the water line fills with muddy water over the next minute or so. It
## fills faster in rain and never in dry snow, and the water stays. Each cell
## remembers when it was dug (a second texture). The shader and the wheels
## (water_at) work out the same water from it.

const CELL := 0.2 ## Grid spacing, m.
const BERM := 0.45 ## Height of the lip pushed up beside a rut, as a fraction of its depth.
const BERM_REACH := 2.1 ## How far the lip extends, in footprint radii.

var surface: Surface
var rect: Rect2 ## World XZ area, metres.
## Tiles of one rut field (the open world): the border vertices may be dug too, because the
## tile next door shares them and is stamped with the same footprint (WorldTerrain.patches_near).
var seamless := false

var _nx := 0
var _nz := 0
var _depth := PackedFloat32Array() ## > 0 dug down, < 0 pushed up.
var _image: Image
var _texture: ImageTexture
var _dirty := false
var touched := false ## Dug into since it was made (saved with the world, RutStore).

const LONG_AGO := -1.0e5 ## Stamp time of ruts from before this session: long since filled.
const STIR_SLOTS := 8
## Ripples spreading from where something went into the water: (x, z, strength, time).
## Shared by every patch; the shader draws them as rings.
static var stirs := PackedVector4Array()
static var _stir_next := 0
static var _stir_last := -100.0

var _stamped := PackedFloat32Array() ## When each cell was last dug into dry (seconds, now()).
var _age_image: Image
var _age_texture: ImageTexture
var _newest := LONG_AGO
var _uniform_tick := 0.0
var _soft_at: Callable ## (x, z) -> Vector2 mud, snow: the open world's soft map (use_world_mask).
var _snowfall_set := -1.0
var _drift_tick := 0.0


## height_at: Callable(x: float, z: float) -> float giving the rigid ground height.
func setup(area: Rect2, ground: Surface, height_at: Callable) -> void:
	rect = area
	surface = ground
	_nx = roundi(area.size.x / CELL) + 1
	_nz = roundi(area.size.y / CELL) + 1
	_depth.resize(_nx * _nz)
	_image = Image.create_from_data(_nx, _nz, false, Image.FORMAT_RF, _depth.to_byte_array())
	_texture = ImageTexture.create_from_image(_image)
	_stamped.resize(_nx * _nz)
	_stamped.fill(LONG_AGO)
	_age_image = Image.create_from_data(_nx, _nz, false, Image.FORMAT_RF, _stamped.to_byte_array())
	_age_texture = ImageTexture.create_from_image(_age_image)
	_build_mesh(height_at)


func _process(_delta: float) -> void:
	if _dirty:
		_image.set_data(_nx, _nz, false, Image.FORMAT_RF, _depth.to_byte_array())
		_texture.update(_image)
		_age_image.set_data(_nx, _nz, false, Image.FORMAT_RF, _stamped.to_byte_array())
		_age_texture.update(_age_image)
		_dirty = false
	# The shader's clock (for the water seeping in) and the ripples, while there is anything
	# to show: fresh ruts still filling, or rings still spreading.
	_uniform_tick -= _delta
	var t := now()
	var stirring := t - _stir_last < 4.5
	if (_uniform_tick <= 0.0 and t - _newest < 600.0) or stirring:
		_uniform_tick = 0.2
		var mat := material_override as ShaderMaterial
		mat.set_shader_parameter("now", t)
		if stirring:
			mat.set_shader_parameter("stirs", stirs)
	if absf(_snowfall_set - Weather.snow_now) > 0.02:
		_snowfall_set = Weather.snow_now
		(material_override as ShaderMaterial).set_shader_parameter("snowfall", _snowfall_set)
	# Falling snow drifts tracks in deep snow back over (the wheels feel it: the depth itself
	# goes back up), about 1.5 cm a minute in a heavy fall.
	_drift_tick -= _delta
	if _drift_tick <= 0.0:
		_drift_tick = 2.0
		if touched and surface.label == "snow" and Weather.snow_now > 0.05:
			_drift(Weather.snow_now * 0.015 / 60.0 * 2.0)


static func now() -> float:
	return Time.get_ticks_msec() * 0.001


## How wet this ground is for standing water, 0..1: wet mud always seeps a little, rain
## soaks it; snow only holds water once it rains on it (slush).
static func wet_level(ground: Surface, weather_wet: float) -> float:
	if ground.label == "snow":
		return clampf(weather_wet * 0.7, 0.0, 1.0)
	return clampf(maxf(ground.wetness * 0.55, weather_wet), 0.0, 1.0)


## (water line below the surface in m, seconds to fill) for a wetness. soft_ground.gdshader
## uses the same numbers: a rut deeper than the line fills up to it.
static func water_rule(wet: float) -> Vector2:
	return Vector2(lerpf(0.16, 0.025, wet), lerpf(90.0, 12.0, wet))


## Depth of standing water over a point, m (0 where there is none): in a flooded rut or
## footprint, or a pool in the hollows of the wettest mud (as soft_ground.gdshader draws them).
func water_at(p: Vector3) -> float:
	var x := clampi(roundi((p.x - rect.position.x) / CELL), 0, _nx - 1)
	var z := clampi(roundi((p.z - rect.position.y) / CELL), 0, _nz - 1)
	var i := z * _nx + x
	var water := _water_in(i)
	if _soft_at.is_valid() and surface.label != "snow":
		var soft: float = (_soft_at.call(p.x, p.z) as Vector2).x
		var pa := pool_amount(p.x, p.z, soft, Weather.wet_now)
		if pa > 0.0:
			var d := _depth[i]
			var lumps := ((_gloop(p.x * 0.9, p.z * 0.9) - 0.45) * 0.15 - 0.02) * smoothstep(0.5, 0.7, soft)
			lumps *= lerpf(1.0, 0.3, clampf(absf(d) * 10.0, 0.0, 1.0))
			water = maxf(water, -0.1 + 0.05 * pa - (lumps - d))
	return water


func _water_in(i: int) -> float:
	var d := _depth[i]
	if d <= 0.0:
		return 0.0
	var rule := water_rule(wet_level(surface, Weather.wet_now))
	if d <= rule.x:
		return 0.0
	var fill := 1.0 - exp(-(now() - _stamped[i]) / rule.y)
	var water := fill * (d - rule.x)
	if surface.label == "snow":
		water *= 1.0 - clampf(Weather.ice_now * 1.4, 0.0, 1.0) # slush only in a thaw
	return water


## 0..1: how much the hollows between the heaps hold water (soft_ground.gdshader pool_amount).
static func pool_amount(x: float, z: float, soft: float, weather_wet: float) -> float:
	return smoothstep(0.8, 0.95, soft + (fbm(x * 0.2 + 11.0, z * 0.2 + 11.0, 3) - 0.5) * 0.5 + weather_wet * 0.08)


# The shaders' value noise, to agree with them on where the water is.
static func _hash12(x: float, y: float) -> float:
	var p3 := Vector3(fposmod(x * 0.1031, 1.0), fposmod(y * 0.1031, 1.0), fposmod(x * 0.1031, 1.0))
	p3 += Vector3.ONE * p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3.ONE * 33.33)
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


static func fbm(x: float, y: float, octaves: int) -> float:
	var amp := 0.5
	var s := 0.0
	for o in octaves:
		s += amp * _vnoise(x, y)
		var nx := 1.6 * x - 1.2 * y
		y = 1.2 * x + 1.6 * y
		x = nx
		amp *= 0.5
	return s


static func _gloop(x: float, y: float) -> float:
	var g := smoothstep(0.25, 0.8, fbm(x, y, 3))
	return g * g


## Something went into the water here: rings spread out from it (every patch draws them).
static func add_stir(p: Vector3, strength: float) -> void:
	if stirs.size() < STIR_SLOTS:
		stirs.resize(STIR_SLOTS)
		for k in STIR_SLOTS:
			stirs[k] = Vector4(0.0, 0.0, 0.0, -100.0)
	stirs[_stir_next] = Vector4(p.x, p.z, strength, now())
	_stir_next = (_stir_next + 1) % STIR_SLOTS
	_stir_last = now()


## Whatever is dug now has been there a long time (old tracks, loaded ruts): it holds its water.
func settle() -> void:
	_stamped.fill(LONG_AGO)
	_newest = LONG_AGO
	_dirty = true


func contains(p: Vector3) -> bool:
	return rect.has_point(Vector2(p.x, p.z))


## Rut depth under a point: the deepest of the four surrounding cells, never
## negative. (Interpolating would read back slightly less than a wheel just
## stamped, and that loss can cancel out digging entirely.)
func depth_at(p: Vector3) -> float:
	var x0 := clampi(floori((p.x - rect.position.x) / CELL), 0, _nx - 2)
	var z0 := clampi(floori((p.z - rect.position.y) / CELL), 0, _nz - 2)
	var i := z0 * _nx + x0
	return maxf(maxf(maxf(_depth[i], _depth[i + 1]), maxf(_depth[i + _nx], _depth[i + _nx + 1])), 0.0)


## Presses an elliptical tire footprint into the grid. Cells only ever get
## deeper; untouched cells around the rut get a small raised lip.
func stamp(center: Vector3, forward: Vector3, half_width: float, half_length: float, depth: float) -> void:
	var f := Vector2(forward.x, forward.z)
	f = f.normalized() if f.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	var side := Vector2(-f.y, f.x)
	var c := Vector2(center.x - rect.position.x, center.z - rect.position.y)
	var reach := maxf(half_width, half_length) * BERM_REACH
	# Border vertices stay at zero so the patch edge meets the terrain mesh (unless the tile next
	# door shares them: seamless).
	var edge := 0 if seamless else 1
	var stamp_time := now()
	if half_width < 0.12:
		# A boot (a wheel's spray and rings come from TruckMudFx): in snow it kicks up a puff of
		# powder; into standing water (not ice) it splashes.
		var water := water_at(center)
		if surface.label == "snow" or Weather.snow_cover_now > 0.3:
			Splash.burst(center, Splash.SNOW, 0.35) # a puff of powder off the boot
		elif water > 0.01 and Weather.ice_now < 0.5:
			add_stir(center, clampf(water * 8.0, 0.4, 1.0))
			Splash.burst(center, Splash.WATER, clampf(water * 6.0, 0.3, 0.8))
	var x_min := maxi(edge, floori((c.x - reach) / CELL))
	var x_max := mini(_nx - 1 - edge, ceili((c.x + reach) / CELL))
	var z_min := maxi(edge, floori((c.y - reach) / CELL))
	var z_max := mini(_nz - 1 - edge, ceili((c.y + reach) / CELL))
	for z in range(z_min, z_max + 1):
		for x in range(x_min, x_max + 1):
			var local := Vector2(x * CELL, z * CELL) - c
			var a := local.dot(f) / half_length
			var b := local.dot(side) / half_width
			var e := sqrt(a * a + b * b)
			var i := z * _nx + x
			if e < 1.0:
				var want := depth * (1.0 - 0.5 * smoothstep(0.75, 1.0, e))
				if want > _depth[i]:
					# Freshly dug dry ground starts to fill from now; a cell already under water
					# keeps it (the water runs straight back in round the tyre).
					if _water_in(i) < 0.005 or Weather.ice_now > 0.3: # (frozen: the tyre breaks the ice)
						_stamped[i] = stamp_time
						_newest = stamp_time
					_depth[i] = want
					_dirty = true
					touched = true
			elif e < BERM_REACH and _depth[i] <= 0.0:
				var lip := -depth * BERM * (1.0 - (e - 1.0) / (BERM_REACH - 1.0))
				if lip < _depth[i]:
					_depth[i] = lip
					_dirty = true


func _build_mesh(height_at: Callable) -> void:
	var count := _nx * _nz
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	verts.resize(count)
	uvs.resize(count)
	normals.resize(count)
	for z in _nz:
		for x in _nx:
			var i := z * _nx + x
			var wx := rect.position.x + x * CELL
			var wz := rect.position.y + z * CELL
			verts[i] = Vector3(wx, height_at.call(wx, wz), wz)
			uvs[i] = Vector2(float(x) / (_nx - 1), float(z) / (_nz - 1))
	# The ground's own slope, for the shader to bend its lumps and ruts onto.
	for z in _nz:
		for x in _nx:
			var i := z * _nx + x
			var hx0 := verts[z * _nx + maxi(x - 1, 0)].y
			var hx1 := verts[z * _nx + mini(x + 1, _nx - 1)].y
			var hz0 := verts[maxi(z - 1, 0) * _nx + x].y
			var hz1 := verts[mini(z + 1, _nz - 1) * _nx + x].y
			var sx := float(mini(x + 1, _nx - 1) - maxi(x - 1, 0)) * CELL
			var sz := float(mini(z + 1, _nz - 1) - maxi(z - 1, 0)) * CELL
			normals[i] = Vector3(-(hx1 - hx0) / sx, 1.0, -(hz1 - hz0) / sz).normalized()

	var indices := PackedInt32Array()
	indices.resize((_nx - 1) * (_nz - 1) * 6)
	var k := 0
	for z in _nz - 1:
		for x in _nx - 1:
			var a := z * _nx + x
			var c := a + _nx
			for idx in [a, a + 1, c, a + 1, c + 1, c]:
				indices[k] = idx
				k += 1

	_add_skirt(verts, uvs, normals, indices)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh
	extra_cull_margin = surface.max_depth + 0.5

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/soft_ground.gdshader")
	mat.set_shader_parameter("depth_tex", _texture)
	mat.set_shader_parameter("age_tex", _age_texture)
	mat.set_shader_parameter("ground_wet", wet_level(surface, 0.0))
	mat.set_shader_parameter("is_snow", surface.label == "snow")
	mat.set_shader_parameter("now", now())
	mat.set_shader_parameter("top_color", surface.color)
	mat.set_shader_parameter("deep_color", surface.deep_color)
	mat.set_shader_parameter("max_depth", surface.max_depth)
	mat.set_shader_parameter("wetness", surface.wetness)
	material_override = mat


## A short wall hanging down from the patch border. The patch's fine grid meets
## the terrain's 1 m grid in T-junctions, which leave pixel cracks; the skirt
## fills them.
func _add_skirt(verts: PackedVector3Array, uvs: PackedVector2Array, normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var ring := PackedInt32Array()
	for x in _nx:
		ring.append(x)
	for z in range(1, _nz):
		ring.append(z * _nx + _nx - 1)
	for x in range(_nx - 2, -1, -1):
		ring.append((_nz - 1) * _nx + x)
	for z in range(_nz - 2, 0, -1):
		ring.append(z * _nx)

	var first_low := verts.size()
	for i in ring:
		verts.append(verts[i] + Vector3.DOWN * 0.3)
		uvs.append(uvs[i])
		normals.append(Vector3.UP)
	for k in ring.size():
		var k2 := (k + 1) % ring.size()
		var a := ring[k]
		var b := ring[k2]
		var a_low := first_low + k
		var b_low := first_low + k2
		indices.append_array(PackedInt32Array([a, b, a_low, b, b_low, a_low]))


## Open world: draw only where the soft-ground map says the ground is soft
## (WorldTerrain), with the terrain's own mud or snow look.
func use_world_mask(soft_map: Texture2D, map_half: float, map_size: float, soft_at := Callable()) -> void:
	_soft_at = soft_at
	var mat := material_override as ShaderMaterial
	mat.set_shader_parameter("use_mask", true)
	seamless = true
	mat.set_shader_parameter("soft_map", soft_map)
	mat.set_shader_parameter("map_half", map_half)
	mat.set_shader_parameter("map_size", map_size)
	mat.set_shader_parameter("is_snow", surface.label == "snow")


## The depth grid, packed for saving (RutStore).
func depth_bytes() -> PackedByteArray:
	return _depth.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)


## Puts a saved depth grid back: the ruts are where you left them.
func load_depth(packed: PackedByteArray) -> void:
	var raw := packed.decompress(_depth.size() * 4, FileAccess.COMPRESSION_ZSTD)
	if raw.size() == _depth.size() * 4:
		_depth = raw.to_float32_array()
		_dirty = true
		touched = true
		settle()


## Fresh snow settling into every track: dug cells come back up by `amount` m.
func _drift(amount: float) -> void:
	var changed := false
	for i in _depth.size():
		if _depth[i] > 0.0:
			_depth[i] = maxf(_depth[i] - amount, 0.0)
			changed = true
	if changed:
		_dirty = true
