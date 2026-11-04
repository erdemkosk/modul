class_name RailWorks
extends RefCounted
## The railway as an engineer lays it: the way across the valley that climbs least (route), the
## height it runs at held to what an engine can pull (grade), the land cut and banked to carry it
## (earthworks), and a tunnel only where a hill's too deep to cut (portals). Bridges and trestles are
## drawn with the rails (Village._rail_mesh), wherever the line's still up off the ground.

const MAX_GRADE := 0.05 ## the steepest the line climbs: 5 m in 100
const DECK := 1.6 ## m a bridge's rails stand over the water
const UNDER := 0.35 ## m of ground over the rails that make it a tunnel
const ROOF := 5.8 ## m of ground over the rails where a tunnel needs no gallery
const BED := 3.6 ## m from the rails' middle the cut or bank's flat goes
const BORE_DEEP := 14.0 ## m a cutting may go down before it's a tunnel instead
const BORE_LONG := 80.0 ## m that deep it has to be: anything shorter is cut through
const BANK := 5.0 ## m of bank at most: higher than that, a trestle
const CUT_RUN := 1.3 ## m out for each m up on a cutting's side (not so steep the folk can't climb it)
const STEP := 16 ## m a side of the squares the way's looked for over
const FLAT_ENOUGH := 0.03 ## the grade that costs nothing extra to walk the way over

## The opening of a tunnel, and the facing stone round it, point for point (m across, m up).
const MOUTH: Array[Vector2] = [Vector2(-2.9, -1.0), Vector2(-2.9, 3.6), Vector2(-2.0, 4.9), Vector2(0, 5.5), Vector2(2.0, 4.9), Vector2(2.9, 3.6), Vector2(2.9, -1.0)]
const FACE: Array[Vector2] = [Vector2(-5.4, -1.0), Vector2(-5.4, 5.0), Vector2(-3.6, 7.2), Vector2(0, 7.9), Vector2(3.6, 7.2), Vector2(5.4, 5.0), Vector2(5.4, -1.0)]
const AROUND: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1), Vector2i(1, 2), Vector2i(1, -2), Vector2i(-1, 2), Vector2i(-1, -2)]


## The way across the valley through `at`: out to the two edges it's cheapest to reach, flat ground
## and the valley floors before any climbing, far enough round from each other that it crosses
## the valley. Points from one edge to the other, or nothing.
static func route(v: Node, at: Vector3) -> Array:
	var half: int = v.terrain.half
	var n: int = half * 2 / STEP
	var ground := PackedFloat32Array()
	var wet := PackedFloat32Array()
	ground.resize(n * n)
	wet.resize(n * n)
	for z in n:
		for x in n:
			var p := _place(x, z, half)
			ground[z * n + x] = v.nav.height(p.x, p.z)
			wet[z * n + x] = 0.0
			if v.terrain.water_height_at(p.x, p.z) > -INF:
				wet[z * n + x] = 40.0 # (the lake: only round it)
			elif v.water_at(p) > -INF:
				wet[z * n + x] = 4.0 # (a bridge's worth)
			elif not v.nav.is_open(p):
				wet[z * n + x] = 3.0
	var from := Vector2i(clampi((roundi(at.x) + half) / STEP, 1, n - 2), clampi((roundi(at.z) + half) / STEP, 1, n - 2))
	var out := _search(from, n, ground, wet)
	var a := _best_edge(out, n, from, Vector2.ZERO)
	if a == Vector2i(-1, -1):
		return []
	var path_a := _way_back(out, a, n, from)
	for q in path_a: # (the way back out doesn't run along the way in)
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var c := Vector2i(q.x + dx, q.y + dz)
				if c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and Vector2(c - from).length() > 4.0:
					wet[c.y * n + c.x] = maxf(wet[c.y * n + c.x], 12.0)
	out = _search(from, n, ground, wet)
	var b := _best_edge(out, n, from, Vector2(a - from).normalized())
	if b == Vector2i(-1, -1):
		return []
	var path_b := _way_back(out, b, n, from)
	path_a.reverse()
	var pts: Array = []
	for k in path_a.size():
		if k % 3 == 0 and k < path_a.size() - 2:
			pts.append(_place(path_a[k].x, path_a[k].y, half))
	pts.append(at)
	for k in range(2, path_b.size()):
		if k % 3 == 2 or k == path_b.size() - 1:
			pts.append(_place(path_b[k].x, path_b[k].y, half))
	return pts


static func _place(x: int, z: int, half: int) -> Vector3:
	return Vector3((x + 0.5) * STEP - half, 0, (z + 0.5) * STEP - half)


## Cheapest ways out from `from`: {cost, back}. A grade over FLAT_ENOUGH costs by its square.
static func _search(from: Vector2i, n: int, ground: PackedFloat32Array, wet: PackedFloat32Array) -> Dictionary:
	var cost := PackedFloat32Array()
	cost.resize(n * n)
	cost.fill(INF)
	var back := PackedInt32Array()
	back.resize(n * n)
	back.fill(-1)
	var start := from.y * n + from.x
	cost[start] = 0.0
	var heap_cost: Array[float] = [0.0]
	var heap_at: Array[int] = [start]
	while not heap_at.is_empty():
		var c0 := heap_cost[0]
		var i := heap_at[0]
		var tail_c: float = heap_cost.pop_back()
		var tail_i: int = heap_at.pop_back()
		if not heap_at.is_empty():
			var k := 0
			var m := heap_at.size()
			while true:
				var l := k * 2 + 1
				if l >= m:
					break
				if l + 1 < m and heap_cost[l + 1] < heap_cost[l]:
					l += 1
				if heap_cost[l] >= tail_c:
					break
				heap_cost[k] = heap_cost[l]
				heap_at[k] = heap_at[l]
				k = l
			heap_cost[k] = tail_c
			heap_at[k] = tail_i
		if c0 > cost[i]:
			continue
		var x := i % n
		var z := i / n
		for d in AROUND:
			var nx := x + d.x
			var nz := z + d.y
			if nx < 0 or nz < 0 or nx >= n or nz >= n:
				continue
			var j := nz * n + nx
			var run := Vector2(d).length() * STEP
			var g := absf(ground[j] - ground[i]) / run / FLAT_ENOUGH
			var c := c0 + run * (1.0 + g * g + wet[j])
			if c < cost[j]:
				cost[j] = c
				back[j] = i
				var k2 := heap_at.size()
				heap_cost.append(c)
				heap_at.append(j)
				while k2 > 0:
					var up := (k2 - 1) / 2
					if heap_cost[up] <= c:
						break
					heap_cost[k2] = heap_cost[up]
					heap_at[k2] = heap_at[up]
					k2 = up
				heap_cost[k2] = c
				heap_at[k2] = j
	return {"cost": cost, "back": back}


## The cheapest square on the map's edge, well round from the way `other` (if it's given).
static func _best_edge(found: Dictionary, n: int, from: Vector2i, other: Vector2) -> Vector2i:
	var cost: PackedFloat32Array = found.cost
	var best := Vector2i(-1, -1)
	var bc := INF
	for k in n:
		for c: Vector2i in [Vector2i(k, 0), Vector2i(k, n - 1), Vector2i(0, k), Vector2i(n - 1, k)]:
			if other != Vector2.ZERO and Vector2(c - from).normalized().dot(other) > -0.3:
				continue
			if cost[c.y * n + c.x] < bc:
				bc = cost[c.y * n + c.x]
				best = c
	return best


## The squares from `from` out to `to`.
static func _way_back(found: Dictionary, to: Vector2i, n: int, from: Vector2i) -> Array[Vector2i]:
	var back: PackedInt32Array = found.back
	var out: Array[Vector2i] = []
	var i := to.y * n + to.x
	while i >= 0:
		out.append(Vector2i(i % n, i / n))
		i = back[i]
	out.reverse()
	return out


## `line`'s points given the heights it runs at. `ground` is the land under each point, `least` the
## lowest the rails may go there (a bridge's deck), -INF where it doesn't matter. Held to the grade,
## as near the land as it can be: as much cut out of the rises as is banked into the dips.
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
	var high := _envelope(need, ds, 1.0)
	var low := _envelope(need, ds, -1.0)
	for k in n:
		need[k] = maxf((high[k] + low[k]) * 0.5, least[k])
	var lie := _envelope(need, ds, 1.0)
	for k in n:
		line[k].y = lie[k]
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


## Whether each point of `line` runs too deep to cut, the land as it first lay.
static func _deep(line: PackedVector3Array, terrain: WorldTerrain) -> PackedByteArray:
	var n := line.size()
	var out := PackedByteArray()
	out.resize(n)
	var k := 0
	while k < n:
		if terrain.height_at(line[k].x, line[k].z) - line[k].y <= BORE_DEEP:
			k += 1
			continue
		var a := k
		var m := 0.0
		while k < n and terrain.height_at(line[k].x, line[k].z) - line[k].y > BORE_DEEP:
			m += line[k].distance_to(line[maxi(k - 1, 0)])
			k += 1
		if m >= BORE_LONG:
			for j in range(a, k):
				out[j] = 1
	return out


## The land made to carry the line: rises cut down to it with sloped sides (rock shows on them), dips
## banked up to it, what stood there felled. Water's left alone, and what's too high for a bank
## and too deep for a cutting: trestles and tunnels. (Done again from the rails on a loaded game.)
static func earthworks(v: Node, line: PackedVector3Array) -> void:
	var t: WorldTerrain = v.terrain
	var deep := _deep(line, t)
	var h := t._heights
	var size := t.size
	var half := t.half
	var felled := false
	var touched := {}
	for k in range(0, line.size(), 6):
		if deep[k] == 1:
			continue
		var c := line[k]
		var d := t.height_at(c.x, c.z) - c.y
		var cut := d > 0.05
		if not cut and (d > -0.05 or d < -BANK or v.water_at(c) > -INF):
			continue
		var r := minf(BED + absf(d) * (CUT_RUN if cut else 1.5) + 1.5, 40.0)
		var gx0 := clampi(floori(c.x - r) + half, 0, size - 1)
		var gx1 := clampi(ceili(c.x + r) + half, 0, size - 1)
		var gz0 := clampi(floori(c.z - r) + half, 0, size - 1)
		var gz1 := clampi(ceili(c.z + r) + half, 0, size - 1)
		for gz in range(gz0, gz1 + 1):
			var dz := float(gz - half) - c.z
			for gx in range(gx0, gx1 + 1):
				var dx := float(gx - half) - c.x
				var off := maxf(sqrt(dx * dx + dz * dz) - BED, 0.0)
				var i := gz * size + gx
				if cut:
					h[i] = minf(h[i], c.y + off / CUT_RUN)
				elif c.y - off / 1.5 > h[i]:
					h[i] = c.y - off / 1.5
		for gz in range(gz0, gz1 + 1, 2):
			for gx in range(gx0, gx1 + 1, 2):
				touched[Vector2i(gx / 2, gz / 2)] = true
		for i: int in v._props_in(c, r):
			RutStore.cut[i] = SaveGame.day
			v.props._remove(i)
			felled = true
	if felled:
		RutStore.save_marks()
	t._heights = h
	t._dig_dirty = true
	t.commit_digs()
	v.nav.regrade(touched.keys(), v.water_at)


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
