class_name RailWorks
extends RefCounted
## What the line is built on: the height it runs at, held to what an engine can pull (grade), and the
## tunnel mouths where the hills stand in its way (portals). Bridges and trestles are drawn with the
## rails (Village._rail_mesh), wherever grade() has left the line up off the ground.

const MAX_GRADE := 0.05 ## the steepest the line climbs: 5 m in 100
const COVER := 4.0 ## m of ground a stretch stands above what the grade can reach before it's bored through
const MIN_BORE := 70.0 ## m: anything shorter is a hump to ride over, not a tunnel
const DECK := 1.6 ## m a bridge's rails stand over the water
const UNDER := 0.35 ## m of ground over the rails that make it a tunnel
const ROOF := 5.8 ## m of ground over the rails where a tunnel needs no gallery

## The opening of a tunnel, and the facing stone round it, point for point (m across, m up).
const MOUTH: Array[Vector2] = [Vector2(-2.9, -1.0), Vector2(-2.9, 3.6), Vector2(-2.0, 4.9), Vector2(0, 5.5), Vector2(2.0, 4.9), Vector2(2.9, 3.6), Vector2(2.9, -1.0)]
const FACE: Array[Vector2] = [Vector2(-5.4, -1.0), Vector2(-5.4, 5.0), Vector2(-3.6, 7.2), Vector2(0, 7.9), Vector2(3.6, 7.2), Vector2(5.4, 5.0), Vector2(5.4, -1.0)]


## `line`'s points given the heights it runs at. `ground` is the land under each point, `least` the
## lowest the rails may go there (a bridge's deck), -INF where it doesn't matter. The ground that
## can't be reached at the grade is shaved off and left to a tunnel, what's left is ridden over at
## the grade, on trestles where the land falls away faster than the line may.
static func grade(line: PackedVector3Array, ground: PackedFloat32Array, least: PackedFloat32Array) -> PackedVector3Array:
	var n := line.size()
	var ds := PackedFloat32Array()
	ds.resize(n)
	for k in range(1, n):
		ds[k] = Vector2(line[k].x - line[k - 1].x, line[k].z - line[k - 1].z).length()
	var need := PackedFloat32Array()
	need.resize(n)
	for k in n:
		need[k] = maxf(ground[k], least[k])
	var low := _envelope(need, ds, -1.0)
	var cap := PackedFloat32Array()
	cap.resize(n)
	for k in n:
		cap[k] = minf(need[k], low[k] + COVER)
	var high := _envelope(cap, ds, 1.0)
	for pass_ in 4: # (the humps too short to bore are given back, and ridden over)
		var changed := false
		var k := 0
		while k < n:
			if ground[k] <= high[k] + UNDER:
				k += 1
				continue
			var a := k
			var m := 0.0
			while k < n and ground[k] > high[k] + UNDER:
				m += ds[k]
				k += 1
			if m < MIN_BORE:
				changed = true
				for j in range(a, k):
					cap[j] = need[j]
		if not changed:
			break
		high = _envelope(cap, ds, 1.0)
	for k in n:
		line[k].y = high[k]
	return line


## The nearest heights to `h` that never climb steeper than the grade: from above (`sgn` 1, never
## under `h`) or from below (-1, never over it).
static func _envelope(h: PackedFloat32Array, ds: PackedFloat32Array, sgn: float) -> PackedFloat32Array:
	var e := h.duplicate()
	var n := e.size()
	for k in range(1, n):
		e[k] = maxf(e[k] * sgn, e[k - 1] * sgn - MAX_GRADE * ds[k]) * sgn
	for k in range(n - 2, -1, -1):
		e[k] = maxf(e[k] * sgn, e[k + 1] * sgn - MAX_GRADE * ds[k + 1]) * sgn
	return e


## The stretches of `line` under the ground: [first, last] point of each.
static func bores(line: PackedVector3Array, nav: Nav) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var k := 0
	while k < line.size():
		if nav.height(line[k].x, line[k].z) <= line[k].y + UNDER:
			k += 1
			continue
		var a := k
		while k < line.size() and nav.height(line[k].x, line[k].z) > line[k].y + UNDER:
			k += 1
		if not out.is_empty() and a - out[out.size() - 1].y < 40:
			out[out.size() - 1].y = k - 1
		else:
			out.append(Vector2i(a, k - 1))
	return out


## Each tunnel's two mouths: a dressed stone face on the hillside, dark inside, and a stone gallery
## running in till there's ground enough over the train to hide it.
static func portals(parent: Node3D, line: PackedVector3Array, nav: Nav) -> void:
	var stone := SurfaceTool.new()
	stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for b in bores(line, nav):
		if b.x > 4:
			_mouth(stone, dark, line, nav, b.x, 1, b.y)
			any = true
		if b.y < line.size() - 5:
			_mouth(stone, dark, line, nav, b.y, -1, b.x)
			any = true
	if not any:
		return
	stone.generate_normals()
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.3, 0.29, 0.27)
	sm.roughness = 1.0
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var smi := MeshInstance3D.new()
	smi.mesh = stone.commit()
	smi.material_override = sm
	parent.add_child(smi)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.015, 0.012, 0.01)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dmi := MeshInstance3D.new()
	dmi.mesh = dark.commit()
	dmi.material_override = dm
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(dmi)


## One mouth at point `at`, the tunnel going on in the direction `step` (+1, -1) as far as `end`.
static func _mouth(stone: SurfaceTool, dark: SurfaceTool, line: PackedVector3Array, nav: Nav, at: int, step: int, end: int) -> void:
	# the face, set a little out from where the rails go under
	var k0 := clampi(at - step * 6, 0, line.size() - 1)
	var ring := _ring(line, k0, MOUTH)
	var out := _ring(line, k0, FACE)
	for j in ring.size() - 1:
		_quad(stone, out[j], out[j + 1], ring[j + 1], ring[j])
	# the gallery in
	var last: Array[Vector3] = ring
	var k := k0
	var walls := FACE.duplicate()
	for j in walls.size():
		walls[j] = MOUTH[j] + (MOUTH[j] * Vector2(0.12, 0.07))
	var prev_out := _ring(line, k0, walls)
	var dark_done := false
	while true:
		k += step * 12
		if (step > 0 and k >= end) or (step < 0 and k <= end) or k < 0 or k >= line.size():
			break
		var r := _ring(line, k, MOUTH)
		var o := _ring(line, k, walls)
		for j in r.size() - 1:
			_quad(stone, prev_out[j], prev_out[j + 1], o[j + 1], o[j])
		for j in r.size() - 1: # (no light in there)
			_quad(dark, last[j], last[j + 1], r[j + 1], r[j])
		if not dark_done:
			dark_done = true
			var c := (r[0] + r[r.size() - 1]) * 0.5
			for j in r.size() - 1: # (a dark that the train goes into)
				dark.add_vertex(c)
				dark.add_vertex(r[j])
				dark.add_vertex(r[j + 1])
		last = r
		prev_out = o
		if nav.height(line[k].x, line[k].z) - line[k].y > ROOF:
			break


## The outline `shape` set square to the line at point `k`.
static func _ring(line: PackedVector3Array, k: int, shape: Array) -> Array[Vector3]:
	var dir := line[mini(k + 6, line.size() - 1)] - line[maxi(k - 6, 0)]
	dir.y = 0.0
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP)
	var out: Array[Vector3] = []
	for p: Vector2 in shape:
		out.append(line[k] + side * p.x + Vector3.UP * p.y)
	return out


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
