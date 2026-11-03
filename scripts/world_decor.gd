class_name WorldDecor
extends Node3D
## Everything on top of the open world's ground (scripts/world_terrain.gd): trees and rocks
## (WorldProps), grass round the camera, the lake and the river, distant mountains beyond the map so the valley never ends at a cliff of sky, and
## invisible walls at the map edge.

const GRASS_GRID := 250
const GRASS_SPACING := 0.4

var terrain: WorldTerrain
var props: WorldProps

var _grass: MultiMeshInstance3D


func _ready() -> void:
	props = WorldProps.new()
	props.terrain = terrain
	add_child(props)
	_build_grass()
	_build_water()
	_build_horizon()
	_build_bounds()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and _grass:
		var p := cam.global_position
		_grass.global_position = Vector3(snappedf(p.x, GRASS_SPACING), 0.0, snappedf(p.z, GRASS_SPACING))
		if _grass_far:
			_grass_far.global_position = Vector3(snappedf(p.x, FAR_SPACING), 0.0, snappedf(p.z, FAR_SPACING))


# --- Grass ------------------------------------------------------------------------------------------

## The sparse field beyond the fine one: broader clumps a metre apart out to ~100 m, so the
## meadow doesn't end in a ring round you (grass.gdshader inner_radius).
const FAR_GRID := 180
const FAR_SPACING := 1.1
var _grass_far: MultiMeshInstance3D


func _build_grass() -> void:
	_grass = _grass_field(GRASS_GRID, GRASS_SPACING, 0.0, 1.0, "Grass")
	_grass_far = _grass_field(FAR_GRID, FAR_SPACING, float(GRASS_GRID / 2) * GRASS_SPACING * 0.76, 1.45, "GrassFar")


func _grass_field(grid: int, spacing: float, inner: float, clump: float, node_name: String) -> MultiMeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/grass.gdshader")
	mat.set_shader_parameter("heightmap", terrain.height_texture)
	mat.set_shader_parameter("splat", terrain.splat_texture)
	mat.set_shader_parameter("splat2", terrain.splat2_texture)
	mat.set_shader_parameter("soft_mask", terrain.soft_texture)
	mat.set_shader_parameter("soft_map", terrain.soft_map)
	mat.set_shader_parameter("map_half", float(terrain.half))
	mat.set_shader_parameter("map_size", float(terrain.size))
	mat.set_shader_parameter("village_mask", terrain.village_mask)
	mat.set_shader_parameter("lake_level", terrain.lake_level)
	mat.set_shader_parameter("grid", grid)
	mat.set_shader_parameter("spacing", spacing)
	mat.set_shader_parameter("inner_radius", inner)
	mat.set_shader_parameter("clump_scale", clump)
	var mesh := _clump_mesh()
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = grid * grid
	for i in mm.instance_count: # the shader places them; they only need a valid transform
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := grid * spacing * 0.5 + 10.0
	mmi.custom_aabb = AABB(Vector3(-r, -50, -r), Vector3(r * 2.0, 500, r * 2.0))
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mmi)
	return mmi


## Six broad, bent blades round the origin, 0.3-0.85 m tall: a painted tuft, not a photo of grass;
## y is the height (the shader bends by it).
func _clump_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for b in 6:
		var a := rng.randf() * TAU
		var base := Vector2(cos(a), sin(a)) * rng.randf_range(0.0, 0.17)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0.0, sin(face))
		var lean := Vector3(-side.z, 0.0, side.x) * rng.randf_range(0.04, 0.26)
		var height := rng.randf_range(0.3, 0.85)
		var w := rng.randf_range(0.03, 0.05)
		var first := verts.size()
		for seg in 4:
			var t := seg / 3.0
			var c := Vector3(base.x, 0.0, base.y) + lean * t * t + Vector3.UP * height * t
			var half_w := w * (1.0 - t * 0.85)
			verts.append(c - side * half_w)
			verts.append(c + side * half_w)
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
		for seg in 3:
			var i := first + seg * 2
			indices.append_array([i, i + 1, i + 2, i + 1, i + 3, i + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Water ------------------------------------------------------------------------------------------

## Reeds and rushes in the shallows round the lake: clumps of thin blades where the bank goes under
## the water, browner toward the tips, swaying with the grass's wind.
func _reeds(lake: Dictionary) -> void:
	var blade := CylinderMesh.new()
	blade.top_radius = 0.0
	blade.bottom_radius = 0.025
	blade.height = 1.6
	blade.radial_segments = 3
	blade.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.42, 0.18)
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	blade.material = m
	var head := CylinderMesh.new()
	head.top_radius = 0.035
	head.bottom_radius = 0.035
	head.height = 0.22
	head.radial_segments = 5
	head.rings = 1
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.32, 0.2, 0.11)
	head.material = hm
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091
	var blades: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var lvl := terrain.lake_level
	for k in 900:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.82, 1.08)
		var c := Vector3(float(lake.x) + cos(a) * float(lake.rx) * r, 0, float(lake.z) + sin(a) * float(lake.rz) * r)
		var h := terrain.height_at(c.x, c.z)
		if h < lvl - 0.6 or h > lvl + 0.35:
			continue # (only where the bank goes under the water)
		for b in rng.randi_range(5, 9):
			var p := c + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
			var tall := rng.randf_range(0.7, 1.3)
			var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.18))
			var at := Vector3(p.x, maxf(terrain.height_at(p.x, p.z), lvl - 0.6) + 0.8 * tall, p.z)
			blades.append(Transform3D(tilt * Basis.from_scale(Vector3(1, tall, 1)), at))
			if rng.randf() < 0.2:
				heads.append(Transform3D(tilt, at + tilt * Vector3(0, 0.7 * tall, 0)))
	for pair: Array in [[blade, blades], [head, heads]]:
		var list: Array = pair[1]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.visibility_range_end = 260.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _build_water() -> void:
	var lake: Dictionary = terrain.meta.lake
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.append(Vector3(lake.x, terrain.lake_level, lake.z))
	uvs.append(Vector2.ZERO)
	var segs := 128
	for i in segs:
		var a := TAU * i / segs
		verts.append(Vector3(float(lake.x) + cos(a) * float(lake.rx), terrain.lake_level, float(lake.z) + sin(a) * float(lake.rz)))
		uvs.append(Vector2.ZERO)
		indices.append_array([0, 1 + (i + 1) % segs, 1 + i])
	add_child(_water_mesh(verts, uvs, indices, 0.0, "Lake"))
	_reeds(lake)

	# The river: a ribbon along the polyline at its water height, UV in metres (x along, y across).
	var pts: Array = terrain.meta.river.points
	var hw := float(terrain.meta.river.half_width) + 3.0
	verts = PackedVector3Array()
	uvs = PackedVector2Array()
	indices = PackedInt32Array()
	var along := 0.0
	for i in pts.size():
		var p := Vector3(pts[i][0], pts[i][1], pts[i][2])
		var prev := Vector3(pts[maxi(i - 1, 0)][0], 0.0, pts[maxi(i - 1, 0)][2])
		var next := Vector3(pts[mini(i + 1, pts.size() - 1)][0], 0.0, pts[mini(i + 1, pts.size() - 1)][2])
		var dir := (next - prev)
		dir.y = 0.0
		dir = dir.normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		if i > 0:
			along += Vector2(p.x - pts[i - 1][0], p.z - pts[i - 1][2]).length()
		verts.append(p - side * hw)
		verts.append(p + side * hw)
		uvs.append(Vector2(along, -hw))
		uvs.append(Vector2(along, hw))
		if i > 0:
			var a := (i - 1) * 2
			indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	add_child(_water_mesh(verts, uvs, indices, 0.8, "River"))


func _water_mesh(verts: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, flow: float, node_name: String) -> MeshInstance3D:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/water.gdshader")
	mat.set_shader_parameter("flow_speed", flow)
	if flow > 0.0:
		mat.set_shader_parameter("clarity", 0.9)
		mat.set_shader_parameter("shallow_color", Color(0.24, 0.34, 0.3))
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- Beyond the map ---------------------------------------------------------------------------------

## A coarse ring of mountains from the map edge out to ~9 km: heights continue the map's edge and
## climb into peaks; coloured by height and slope (forest, rock, snow). Fog does the rest.
func _build_horizon() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 99
	noise.frequency = 0.00045
	noise.fractal_octaves = 5
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var extent := 9000.0
	var n := 241
	var step := extent * 2.0 / (n - 1)
	var edge := float(terrain.half)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	colors.resize(n * n)
	for z in n:
		for x in n:
			var wx := -extent + x * step
			var wz := -extent + z * step
			var out := maxf(absf(wx), absf(wz)) - edge
			var edge_h := terrain.height_at(clampf(wx, -edge, edge), clampf(wz, -edge, edge))
			var peaks := (noise.get_noise_2d(wx, wz) * 0.5 + 0.5)
			peaks = 120.0 + peaks * peaks * 900.0
			var k := smoothstep(0.0, 2500.0, out)
			var h := lerpf(edge_h, peaks, k)
			if out <= 0.0:
				h = -200.0 # under the map: never seen
			verts[z * n + x] = Vector3(wx, h, wz)
	var indices := PackedInt32Array()
	for z in n - 1:
		for x in n - 1:
			var a := z * n + x
			var b := a + 1
			var c := a + n
			var d := c + 1
			var inside := true
			for v in [a, b, c, d]:
				var p := verts[v]
				if maxf(absf(p.x), absf(p.z)) > edge - 1.0:
					inside = false
			if not inside:
				indices.append_array([a, b, c, b, d, c])
	var st_normals := PackedVector3Array()
	st_normals.resize(n * n)
	for z in n:
		for x in n:
			var hl := verts[z * n + maxi(x - 1, 0)].y
			var hr := verts[z * n + mini(x + 1, n - 1)].y
			var hd := verts[maxi(z - 1, 0) * n + x].y
			var hu := verts[mini(z + 1, n - 1) * n + x].y
			var nrm := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			st_normals[z * n + x] = nrm
			var h := verts[z * n + x].y
			var col := Color(0.13, 0.19, 0.11).lerp(Color(0.34, 0.33, 0.31), smoothstep(0.85, 0.6, nrm.y))
			col = col.lerp(Color(0.85, 0.88, 0.93), smoothstep(380.0, 560.0, h + nrm.y * 80.0))
			colors[z * n + x] = col
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = st_normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Forest, rock, gullies and a ragged snowline (the vertex colours are only a fallback).
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/horizon.gdshader")
	var mi := MeshInstance3D.new()
	mi.name = "Horizon"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_bounds() -> void:
	var edge := float(terrain.half) - 24.0
	var body := StaticBody3D.new()
	body.name = "MapEdge"
	for side in 4:
		var box := BoxShape3D.new()
		var along := side < 2
		box.size = Vector3(4.0, 2000.0, edge * 2.0 + 8.0) if along else Vector3(edge * 2.0 + 8.0, 2000.0, 4.0)
		var cs := CollisionShape3D.new()
		cs.shape = box
		var sgn := 1.0 if side % 2 == 0 else -1.0
		cs.position = Vector3(sgn * (edge + 2.0), 0.0, 0.0) if along else Vector3(0.0, 0.0, sgn * (edge + 2.0))
		body.add_child(cs)
	add_child(body)
