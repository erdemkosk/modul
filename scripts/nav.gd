class_name Nav
extends Node
## Where the villagers can walk, and the ways they wear into the ground.
##
## A 2 m grid over the whole map (AStarGrid2D, CELL m a cell): the lake, the river (but at its
## fords) and ground too steep to stand on are shut, and so is a building's footprint. Walking
## costs more through the forest and up a slope. There are no roads but the ones walked in.
##
## Every step wears the cell it's on (`wear`): enough feet and it's a path, drawn as trodden earth
## (WorldTerrain.village_mask's red channel), quicker to walk and cheaper to the pathfinder, so the
## more a way is used the more it's chosen and the village's paths find themselves. A path nobody
## walks grows over again, slowly. Ground scorched by a fire (`scorch`) greens again slower still.

const CELL := 2.0
const N := 1024 ## cells a side
const STEEP := 0.8 ## rise over run past which a cell is shut
const WEAR_STEP := 0.06 ## wear a second of walking gives the cell underfoot
const WEAR_FADE := 0.0009 ## wear lost a second by a cell nobody walks
const PATH_AT := 0.05 ## wear from which a cell starts to show (the grass trodden first, then earth)
const SCORCH_FADE := 0.0004 ## scorch lost a second (some forty minutes from black to green)
## Every cell's cost is scaled by this for the pathfinder. Its guess at what's left is the straight
## distance at 1 a cell, while a cell really costs some 1.3-3.5: so far under that it went out in a
## wide flood on a long walk (a band from the woods' edge, ~0.2 s). Scaled, the guess is near the
## open ground's cost and the search goes for the goal; the choice of way is the same but by worn
## paths, now a little under the guess.
const COST_SCALE := 0.6

var terrain: WorldTerrain
var astar := AStarGrid2D.new()
var wear := PackedFloat32Array()
var bridge := {} ## {center: Vector3, along: Vector3, half_len, half_w, y}

var _base := PackedFloat32Array() ## each cell's own cost
var _shut := PackedByteArray() ## 1 the ground's own (water, cliff), 2 a building's
var _road := PackedByteArray() ## 1 under a plank road: quick, never mud, the cheapest way
var _wall := PackedByteArray() ## 1 under a palisade: dear to cross (a way round through a gate is taken), not solid
var _claim := PackedByteArray() ## 1 under a field: walked over, not built on
var _worn := {} ## cell index -> true while it carries any wear
var _scorched := {} ## cell index -> how scorched, 0..1
var _shown := PackedByteArray() ## the mask's red as last written, per cell
var _runs: Array[PackedInt32Array] = [] ## per row of cells: its open runs as (start, end, region)
# Walks are found off the main thread (`path_for`): a long one round to a ford took ~0.2 s, a frame
# stopped dead. The asks wait in `_asks` and go out together; while they're out the grid isn't
# touched, its changes held in `_held` (cell, solid?, weight) till they're back.
var _asks := {} ## asker's id -> {a, b} waiting to go out
var _out: Array = [] ## the asks out now: {who, a, b, ca, cb, ids}
var _task := -1
var _held: Array = []
var _found := {} ## asker's id -> {b, path, at}
var _dirty := false
var _upload_t := 0.0
var _fade_t := 0.0


func _ready() -> void:
	name = "Nav"
	wear.resize(N * N)
	_base.resize(N * N)
	_shut.resize(N * N)
	_road.resize(N * N)
	_wall.resize(N * N)
	_shown.resize(N * N)
	_claim.resize(N * N)
	astar.region = Rect2i(0, 0, N, N)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	_read_ground()
	_shut_water()
	_find_regions()


func _read_ground() -> void:
	var h := terrain._heights
	var sp := terrain._splat
	var sp2 := terrain._splat2
	var s := terrain.size
	for cz in N:
		var iz := cz * 2 + 1
		for cx in N:
			var ix := cx * 2 + 1
			var i := iz * s + ix
			var gx := absf(h[i + 1] - h[i - 1]) * 0.5
			var gz := absf(h[i + s] - h[i - s]) * 0.5
			var steep := maxf(gx, gz)
			var c := cz * N + cx
			if steep > STEEP:
				_shut[c] = 1
				_grid(Vector2i(cx, cz), true, 0.0)
				continue
			var forest := sp2[i * 4] / 255.0
			var road := sp[i * 4 + 2] / 255.0
			var cost := 1.3 + forest * 0.9 + steep * 2.5 - road * 0.55
			_base[c] = cost
			_grid(Vector2i(cx, cz), false, cost * COST_SCALE)


func _shut_water() -> void:
	var lake: Dictionary = terrain.meta.lake
	var lx := float(lake.x)
	var lz := float(lake.z)
	var rx := float(lake.rx)
	var rz := float(lake.rz)
	var c0 := cell_of(Vector3(lx - rx, 0, lz - rz))
	var c1 := cell_of(Vector3(lx + rx, 0, lz + rz))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var p := center_of(Vector2i(cx, cz))
			if terrain.is_water(p.x, p.z):
				_shut_cell(Vector2i(cx, cz))
	# The river: shut along its bed, but at a ford (wade it) or the bridge.
	var open_at: Array[Vector2] = []
	for f: Dictionary in terrain.meta.get("fords", []):
		open_at.append(Vector2(float(f.x), float(f.z)))
	var bridges: Array = terrain.meta.get("bridges", [])
	if not bridges.is_empty():
		var b: Dictionary = bridges[0]
		var yaw := deg_to_rad(float(b.yaw))
		var along := Vector3(sin(yaw), 0.0, cos(yaw))
		bridge = {"center": Vector3(float(b.x), float(b.y), float(b.z)), "along": along,
			"half_len": float(b.len) * 0.5, "half_w": float(b.width) * 0.5, "y": float(b.y)}
	var river: Dictionary = terrain.meta.river
	var hw := float(river.half_width) - 0.5
	var pts: Array = river.points
	for k in range(pts.size() - 1):
		var a := Vector2(float(pts[k][0]), float(pts[k][2]))
		var b2 := Vector2(float(pts[k + 1][0]), float(pts[k + 1][2]))
		var lo := cell_of(Vector3(minf(a.x, b2.x) - hw, 0, minf(a.y, b2.y) - hw))
		var hi := cell_of(Vector3(maxf(a.x, b2.x) + hw, 0, maxf(a.y, b2.y) + hw))
		for cz in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				var p := center_of(Vector2i(cx, cz))
				var q := Vector2(p.x, p.z)
				if q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b2)) > hw:
					continue
				var keep := false
				for f in open_at:
					if q.distance_to(f) < 9.0:
						keep = true
				if on_bridge(p):
					keep = true
				if not keep:
					_shut_cell(Vector2i(cx, cz))


func _shut_cell(c: Vector2i) -> void:
	_shut[c.y * N + c.x] = 1
	_grid(c, true, 0.0)


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((p.x + 1024.0) / CELL), 0, N - 1), clampi(floori((p.z + 1024.0) / CELL), 0, N - 1))


static func center_of(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL - 1024.0 + CELL * 0.5, 0.0, c.y * CELL - 1024.0 + CELL * 0.5)


func on_bridge(p: Vector3) -> bool:
	if bridge.is_empty():
		return false
	var d: Vector3 = p - bridge.center
	d.y = 0.0
	var along: Vector3 = bridge.along
	var a := d.dot(along)
	var side := (d - along * a).length()
	return absf(a) <= float(bridge.half_len) + 1.0 and side <= float(bridge.half_w)


## Where a foot stands at (x, z): on the ground, or on the bridge's deck.
func height(x: float, z: float) -> float:
	var g := terrain.height_at(x, z)
	if not bridge.is_empty() and on_bridge(Vector3(x, 0, z)):
		return maxf(g, float(bridge.y))
	return g


func is_open(p: Vector3) -> bool:
	var c := cell_of(p)
	return _shut[c.y * N + c.x] == 0


## What shuts the cell at `p`: 0 nothing, 1 the land itself (a cliff, water), 2 a building.
func shut_kind(p: Vector3) -> int:
	var c := cell_of(p)
	return _shut[c.y * N + c.x]


func is_ground_open(p: Vector3) -> bool:
	var c := cell_of(p)
	return _shut[c.y * N + c.x] != 1


## Free to build on: open ground, no building, no field.
func can_build(p: Vector3) -> bool:
	var c := cell_of(p)
	return _shut[c.y * N + c.x] == 0 and _claim[c.y * N + c.x] == 0


## A field's cells claimed (or let go): no grass on them, nothing built on them, but walked over.
## Its grass stands till its farmers cut it (cut_grass); let go, the grass comes back.
func set_field(cells: Array[Vector2i], on: bool) -> void:
	for c in cells:
		var i := c.y * N + c.x
		_claim[i] = 1 if on else 0
		if not on:
			var px := terrain.village_img.get_pixel(c.x, c.y)
			px.g = 0.0
			terrain.village_img.set_pixel(c.x, c.y, px)
	_dirty = true


## A field's cells mown and turned: no grass on them.
func cut_grass(cells: Array[Vector2i]) -> void:
	for c in cells:
		var px := terrain.village_img.get_pixel(c.x, c.y)
		px.g = 0.85
		terrain.village_img.set_pixel(c.x, c.y, px)
	_dirty = true


## A workyard's ground (or let go, the grass back over it): trodden earth over the rounded
## `size` (m) round `xf`, its edge giving out into the grass over `margin` m (the mask's alpha:
## world_terrain and grass shaders). Fenced or not, there's no line round it.
## `ragged`: the edge left uneven (a site's trodden ground, not a laid-out yard): it reaches out
## further here and stops short there, and out longest before the door.
func set_yard(xf: Transform3D, size: Vector2, on: bool, margin := 2.5, ragged := false) -> void:
	var half := size * 0.5
	var reach := half.length() + margin
	var c0 := cell_of(xf.origin - Vector3(reach, 0, reach))
	var c1 := cell_of(xf.origin + Vector3(reach, 0, reach))
	var inv := xf.affine_inverse()
	var corner := minf(minf(half.x, half.y), 1.0 if ragged else 3.0)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var l := inv * center_of(Vector2i(cx, cz))
			var q := Vector2(absf(l.x), absf(l.z)) - (half - Vector2(corner, corner))
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - corner
			if ragged:
				var h := absi(hash(Vector2i(cx, cz))) % 1000 / 1000.0
				d += (h - 0.5) * margin * 0.9
				if l.z > 0.0 and absf(l.x) < 1.5: # (the door's side: worn out further)
					d -= margin * 0.6
			var v := clampf(1.0 - d / margin, 0.0, 1.0)
			if ragged:
				v = v * v * (3.0 - 2.0 * v)
			if v <= 0.0:
				continue
			var px := terrain.village_img.get_pixel(cx, cz)
			px.a = maxf(px.a, v) if on else 0.0
			terrain.village_img.set_pixel(cx, cz, px)
	_dirty = true


## A building's cells shut (or opened again).
func set_building(cells: Array[Vector2i], on: bool) -> void:
	for c in cells:
		var i := c.y * N + c.x
		if _shut[i] == 1:
			continue
		_shut[i] = 2 if on else 0
		_grid(c, on, -1.0)
		var px := terrain.village_img.get_pixel(c.x, c.y)
		px.g = 1.0 if on else 0.0
		if not on:
			wear[i] = maxf(wear[i], 0.5) # (the yard it stood on stays bare a while)
			_worn[i] = true
		terrain.village_img.set_pixel(c.x, c.y, px)
	_dirty = true


## The open cell nearest `c` (itself if it's open), searching out to `reach` cells.
func _open_near(c: Vector2i, reach := 8) -> Vector2i:
	if _shut[c.y * N + c.x] == 0:
		return c
	for r in range(1, reach + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var q := c + Vector2i(dx, dz)
				if q.x < 0 or q.y < 0 or q.x >= N or q.y >= N:
					continue
				if _shut[q.y * N + q.x] == 0:
					return q
	return c


## The ground's own regions (water and cliffs part them; a building doesn't): a walk to another
## one, or into the lake, sent the pathfinder through every cell it could reach before it gave up
## (~0.5 s). Found once, as the open runs along each row joined to the runs they touch in the
## next.
func _find_regions() -> void:
	var parent := PackedInt32Array()
	var above := PackedInt32Array()
	_runs.clear()
	for z in N:
		var row := PackedInt32Array()
		var start := z * N
		var stop := start + N
		var x := _shut.find(0, start)
		var k := 0 # (the run above being looked at)
		while x >= 0 and x < stop:
			var e := _shut.find(1, x)
			if e < 0 or e > stop:
				e = stop
			var id := parent.size()
			parent.append(id)
			var s0 := x - start
			var e0 := e - start
			while k < above.size() and above[k + 1] <= s0:
				k += 3
			var j := k
			while j < above.size() and above[j] < e0:
				var ra := _root(parent, above[j + 2])
				var rb := _root(parent, id)
				if ra != rb:
					parent[rb] = ra
				j += 3
			row.append_array([s0, e0, id])
			x = _shut.find(0, e)
		_runs.append(row)
		above = row
	for row in _runs:
		for k in range(2, row.size(), 3):
			row[k] = _root(parent, row[k])


static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


## The region a cell is in, -1 shut by the ground.
func _region(c: Vector2i) -> int:
	var row := _runs[c.y]
	var lo := 0
	var hi := row.size() / 3 - 1
	while lo <= hi:
		var m := (lo + hi) / 2
		if c.x < row[m * 3]:
			hi = m - 1
		elif c.x >= row[m * 3 + 1]:
			lo = m + 1
		else:
			return row[m * 3 + 2]
	return -1


## A change to the pathfinder's grid: a cell shut (or opened, `weight` < 0 leaving its cost be),
## or its cost. Held while a search is out.
func _grid(c: Vector2i, solid: bool, weight: float) -> void:
	if _task >= 0:
		_held.append([c, solid, weight])
		return
	if solid or weight < 0.0:
		astar.set_point_solid(c, solid)
	if weight > 0.0:
		astar.set_point_weight_scale(c, weight)


## The walk from `a` to `b` for `who` (see find_path), once it's been found: empty till then (a
## frame or so; it asks again each frame, and a newer ask, to somewhere else, takes its place).
## One found for near the same `b` will do: a foe chased has moved on a little meanwhile.
func path_for(who: Object, a: Vector3, b: Vector3) -> PackedVector3Array:
	var id := who.get_instance_id()
	var got: Dictionary = _found.get(id, {})
	if not got.is_empty() and (got.b as Vector3).distance_to(b) < 4.0:
		_found.erase(id)
		return got.path
	var asked: Dictionary = _asks.get(id, {})
	if asked.is_empty() or (asked.b as Vector3).distance_to(b) >= 4.0:
		_asks[id] = {"a": a, "b": b}
	return PackedVector3Array()


func _send_asks() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		for h: Array in _held:
			_grid(h[0], h[1], h[2])
		_held.clear()
		var now := Time.get_ticks_msec()
		for o: Dictionary in _out:
			_found[o.who] = {"b": o.b, "path": _path_from(o.ids, o.b), "at": now}
		_out.clear()
		for id: int in _found.keys(): # (no one came for it: its asker's gone, or asks elsewhere)
			if now - int(_found[id].at) > 5000:
				_found.erase(id)
	if _asks.is_empty():
		return
	for id: int in _asks:
		var ask: Dictionary = _asks[id]
		var ends := _ends(ask.a, ask.b)
		_out.append({"who": id, "a": ask.a, "b": ask.b, "ca": ends[0], "cb": ends[1]})
	_asks.clear()
	_task = WorkerThreadPool.add_task(_search)


func _search() -> void: # (on a worker thread: only the grid, which nothing touches meanwhile)
	for o: Dictionary in _out:
		o.ids = astar.get_id_path(o.ca, o.cb, true)


## A walk from `a` to `b`: the points to pass through (on the ground), the last `b` itself. Straight
## runs are thinned to their ends. With no way through it goes as near as it can (the last cell of
## its own region on the line back from `b`), then straight on. Found here and now, waiting for
## any search out: the villagers ask with path_for.
func find_path(a: Vector3, b: Vector3) -> PackedVector3Array:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		for h: Array in _held:
			_grid(h[0], h[1], h[2])
		_held.clear()
		for o: Dictionary in _out: # (their askers ask again)
			_asks[o.who] = {"a": o.a, "b": o.b}
		_out.clear()
	var ends := _ends(a, b)
	return _path_from(astar.get_id_path(ends[0], ends[1], true), b)


## The cells a walk from `a` to `b` is searched between.
func _ends(a: Vector3, b: Vector3) -> Array[Vector2i]:
	var ca := _open_near(cell_of(a))
	var cb := _open_near(cell_of(b))
	var home := _region(ca)
	if home >= 0 and _region(cb) != home:
		var n := maxi(absi(ca.x - cb.x), absi(ca.y - cb.y))
		for k in range(1, n + 1):
			var q := Vector2i((Vector2(cb).lerp(Vector2(ca), float(k) / n)).round())
			if _region(q) == home:
				cb = q
				break
	return [ca, cb]


func _path_from(ids: Array[Vector2i], b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var last_dir := Vector2i.ZERO
	for k in range(1, ids.size()):
		var dir := ids[k] - ids[k - 1]
		if dir == last_dir and out.size() > 0:
			out[out.size() - 1] = _point(ids[k])
		else:
			out.append(_point(ids[k]))
		last_dir = dir
	# the last stretch straight to where it was asked, unless that's in a building: then the way
	# stops at its wall (no one walks in through the logs)
	if shut_kind(b) == 2 and ids.size() > 1:
		return out
	if out.size() > 0:
		out.remove_at(out.size() - 1)
	var end := b
	end.y = height(b.x, b.z)
	out.append(end)
	return out


func _point(c: Vector2i) -> Vector3:
	var p := center_of(c)
	p.y = height(p.x, p.z)
	return p


## The wear and the scorching as they were saved.
func restore(saved_wear: PackedFloat32Array, scorched: Dictionary) -> void:
	if saved_wear.size() == wear.size():
		for i in wear.size():
			if saved_wear[i] > 0.0:
				wear[i] = saved_wear[i]
				_worn[i] = true
				_show(Vector2i(i % N, i / N), i)
	for i: int in scorched:
		_scorched[i] = float(scorched[i])
		_set_scorch(Vector2i(i % N, i / N), float(scorched[i]))
	_dirty = true


## A fire's heat on the ground round `p`, out to `r` m.
func scorch(p: Vector3, r: float, amount: float) -> void:
	var c0 := cell_of(p - Vector3(r, 0, r))
	var c1 := cell_of(p + Vector3(r, 0, r))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cz)
			var d := Vector2(center_of(c).x - p.x, center_of(c).z - p.z).length()
			if d > r:
				continue
			var i := cz * N + cx
			var v := minf(float(_scorched.get(i, 0.0)) + amount * (1.0 - d / r * 0.6), 1.0)
			_scorched[i] = v
			_set_scorch(c, v)
	_dirty = true


func _set_scorch(c: Vector2i, v: float) -> void:
	var px := terrain.village_img.get_pixel(c.x, c.y)
	px.b = v
	terrain.village_img.set_pixel(c.x, c.y, px)


## A foot on (x, z) for `dt` seconds.
func tread(p: Vector3, dt: float, weight := 1.0) -> void:
	var c := cell_of(p)
	var i := c.y * N + c.x
	if _shut[i] != 0:
		return
	wear[i] = minf(wear[i] + WEAR_STEP * dt * weight, 1.6)
	_worn[i] = true
	_show(c, i)


## How trodden the ground at a point is, 0..1 (a plank road counts as worn smooth).
func worn(p: Vector3) -> float:
	var c := cell_of(p)
	if _road[c.y * N + c.x] == 1:
		return 1.0
	return clampf(wear[c.y * N + c.x], 0.0, 1.0)


## Planks laid over these cells: the cheapest way through, quick and never mud.
func set_road(cells: Array[Vector2i]) -> void:
	for c in cells:
		var i := c.y * N + c.x
		if _shut[i] != 0:
			continue
		_road[i] = 1
		_grid(c, false, _base[i] * COST_SCALE * 0.3)


## A palisade's cells (`on`) or no longer (breached, pulled down). Not solid: a way through one costs
## four hundred times a step, so any way round through a gate is taken; one who comes to it with no way
## round (an outlaw) hacks through (Villager._walk).
func set_wall(cells: Array[Vector2i], on: bool) -> void:
	for c in cells:
		var i := c.y * N + c.x
		if _shut[i] != 0:
			continue
		_wall[i] = 1 if on else 0
		_grid(c, false, _base[i] * COST_SCALE * (400.0 if on else (0.3 if _road[i] == 1 else 1.0)))


func on_wall(p: Vector3) -> bool:
	var c := cell_of(p)
	return _wall[c.y * N + c.x] == 1


func on_road(p: Vector3) -> bool:
	var c := cell_of(p)
	return _road[c.y * N + c.x] == 1


func _show(c: Vector2i, i: int) -> void:
	var v := clampi(int(clampf((wear[i] - PATH_AT) / (1.0 - PATH_AT), 0.0, 1.0) * 255.0), 0, 255)
	if absi(v - int(_shown[i])) < 12 and not (v == 0 and _shown[i] != 0):
		return
	_shown[i] = v
	var px := terrain.village_img.get_pixel(c.x, c.y)
	px.r = v / 255.0
	terrain.village_img.set_pixel(c.x, c.y, px)
	if _shut[i] == 0 and _road[i] == 0 and _wall[i] == 0:
		_grid(c, false, _base[i] * COST_SCALE * lerpf(1.0, 0.42, v / 255.0))
	_dirty = true


func _exit_tree() -> void:
	# (a search still out when the game's left or reloaded: the grid would go from under it)
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(dt: float) -> void:
	_send_asks()
	_fade_t += dt
	if _fade_t >= 4.0:
		var gone: Array = []
		for i: int in _worn:
			wear[i] = maxf(wear[i] - WEAR_FADE * _fade_t, 0.0)
			_show(Vector2i(i % N, i / N), i)
			if wear[i] <= 0.0:
				gone.append(i)
		for i in gone:
			_worn.erase(i)
		var cooled: Array = []
		for i: int in _scorched:
			var v := float(_scorched[i]) - SCORCH_FADE * _fade_t
			_scorched[i] = maxf(v, 0.0)
			_set_scorch(Vector2i(i % N, i / N), maxf(v, 0.0))
			if v <= 0.0:
				cooled.append(i)
		for i in cooled:
			_scorched.erase(i)
		if not _scorched.is_empty():
			_dirty = true
		_fade_t = 0.0
	_upload_t += dt
	if _dirty and _upload_t > 0.35:
		_upload_t = 0.0
		_dirty = false
		terrain.village_mask.update(terrain.village_img)
