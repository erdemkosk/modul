class_name WaveArena
extends Node3D
## ARENA's ground: a walled yard N x N cells of CELL m (140 m across), laid out as a maze of
## containers, concrete barriers and sandbags, a new one each round (seeded): walls to hide
## behind and go round, lanes to be caught in, cover in the cells (blocks, crates, drums that go
## up). A maze cut through every cell (so all of it's reachable), then a share of its walls taken
## out again so there are loops to flank by; where two cells are open to each other, sometimes a
## stub of wall stands at each end. The yard's outer wall is poured concrete, too high to get over;
## over it all round is the stadium (Stadium) and its crowd, floodlights along its roof.
##
## The cells are also how the other side finds its way to you (route): the next cell on the
## shortest way through the open sides, until you're in sight.

const N := 7
const CELL := 20.0 ## m
const HALF := N * CELL * 0.5 ## 70 m
const WALL_H := 4.5 ## m (the outer wall)
const OPEN := 0.3 ## of the maze's walls taken out again (loops)
const START := Vector2i(3, 3) ## your cell (the middle)

var terrain: Node
var open := {} ## [Vector2i, Vector2i] (the lower first) -> true: no wall between
var _layout: Array[Node] = []
var _lights: Array[SpotLight3D] = []
var stadium: Stadium


func _ready() -> void:
	add_to_group("wave_arena")
	_outer()
	stadium = Stadium.new()
	stadium.terrain = terrain
	add_child(stadium)


## The yard's ground for a run (before the terrain's built): concrete, and patches by `seed_` of
## mud, gravel, standing water, a bog, or snow and ice in the cold.
static func ground(t: TestTerrain, seed_: int, cold: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	t.default_surface = Surface.preset("concrete")
	t.noise_from = 400.0 # (flat under the stadium too)
	t.grid_strength = 0.0
	var kinds := ["snow", "ice", "snow", "gravel"] if cold else ["mud", "mud", "gravel", "wet", "bog", "dirt"]
	for k in 9:
		var c := Vector2(rng.randf_range(-HALF + 8.0, HALF - 8.0), rng.randf_range(-HALF + 8.0, HALF - 8.0))
		if c.length() < 10.0:
			continue # (not under where you start)
		var s := Vector2(rng.randf_range(8.0, 22.0), rng.randf_range(8.0, 22.0))
		t.add_zone(Rect2(c - s * 0.5, s), Surface.preset(kinds[rng.randi() % kinds.size()]))


func _h(x: float, z: float) -> float:
	return float(terrain.call("height_at", x, z))


## A cell's middle on the ground.
func center(c: Vector2i) -> Vector3:
	var x := -HALF + (c.x + 0.5) * CELL
	var z := -HALF + (c.y + 0.5) * CELL
	return Vector3(x, _h(x, z), z)


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((p.x + HALF) / CELL), 0, N - 1), clampi(floori((p.z + HALF) / CELL), 0, N - 1))


static func _edge(a: Vector2i, b: Vector2i) -> Array:
	return [a, b] if (a.x < b.x or (a.x == b.x and a.y < b.y)) else [b, a]


func is_open(a: Vector2i, b: Vector2i) -> bool:
	return open.has(_edge(a, b))


const _DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < N and c.y < N


# --- The outer wall, its masts ----------------------------------------------------------------------

func _outer() -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.5, 0.49, 0.46)
	concrete.roughness = 0.95
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.75, 0.52, 0.08)
	stripe.roughness = 0.7
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	for k in 4:
		var side := (1.0 if k % 2 == 0 else -1.0)
		var mid := (Vector3.BACK if k < 2 else Vector3.RIGHT) * side * (HALF + 0.5)
		var length := N * CELL + 2.0
		var size := Vector3(length, WALL_H, 1.0) if k < 2 else Vector3(1.0, WALL_H, length)
		var at := mid + Vector3.UP * (_h(mid.x, mid.z) + WALL_H * 0.5 - 0.3)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = concrete
		mi.mesh = bm
		mi.position = at
		add_child(mi)
		# a band of works yellow along its foot on the inside
		var band := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(length, 0.5, 0.05) if k < 2 else Vector3(0.05, 0.5, length)
		sb.material = stripe
		band.mesh = sb
		band.position = at + Vector3.DOWN * (WALL_H * 0.5 - 0.6) - (Vector3.BACK if k < 2 else Vector3.RIGHT) * side * 0.53
		add_child(band)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = at
		body.add_child(cs)
	# the floodlights on the stadium's roof edge: at its corners and its sides' middles, on the yard
	for k in 8:
		var a := k * TAU / 8.0
		var p := Vector3(cos(a), 0.0, sin(a))
		p = p / maxf(absf(p.x), absf(p.z)) * (Stadium.ROOF_FROM - 1.0)
		var l := SpotLight3D.new()
		l.position = p + Vector3.UP * (Stadium.ROOF_H - 1.5)
		add_child(l)
		l.look_at(-p * 0.25, Vector3.UP)
		l.spot_range = 190.0
		l.spot_angle = 40.0
		l.spot_attenuation = 0.4
		l.light_energy = 0.0
		l.light_color = Color(0.94, 0.97, 1.0)
		l.light_cull_mask = 0xFFFFF & ~Stadium.LAYER # (the yard only: the stands have their own glow)
		_lights.append(l)


func set_night(on: bool) -> void:
	for l in _lights:
		l.light_energy = 4.5 if on else 0.0
	stadium.set_night(on)


# --- A round's layout ---------------------------------------------------------------------------------

## The maze for a round (by `seed_`): its walls, stubs and cover; the last round's taken away.
func lay_out(seed_: int) -> void:
	for n in _layout:
		if is_instance_valid(n):
			n.queue_free()
	_layout.clear()
	open.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	# the maze: a walk that cuts through to every cell
	var seen := {START: true}
	var stack: Array[Vector2i] = [START]
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var next: Array[Vector2i] = []
		for d: Vector2i in _DIRS:
			var n2 := c + d
			if _inside(n2) and not seen.has(n2):
				next.append(n2)
		if next.is_empty():
			stack.pop_back()
			continue
		var pick := next[rng.randi() % next.size()]
		open[_edge(c, pick)] = true
		seen[pick] = true
		stack.append(pick)
	# loops: some of the walls taken out again; round where you start always open
	for x in N:
		for y in N:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(x, y)
				var b := a + d
				if not _inside(b) or open.has(_edge(a, b)):
					continue
				if rng.randf() < OPEN or a == START or b == START:
					open[_edge(a, b)] = true
	# the walls, and stubs at the ends of some open sides
	for x in N:
		for y in N:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := Vector2i(x, y)
				var b := a + d
				if not _inside(b):
					continue
				if not open.has(_edge(a, b)):
					_wall(a, b, rng)
				elif rng.randf() < 0.35 and a != START and b != START:
					_stubs(a, b, rng)
	# cover in the cells
	for x in N:
		for y in N:
			var c := Vector2i(x, y)
			if c != START:
				_cover(c, rng)


## The line between cells `a` and `b` (b to the right of or below a): its middle and its way along.
func _side(a: Vector2i, b: Vector2i) -> Array:
	var ca := center(a)
	var cb := center(b)
	var mid := (ca + cb) * 0.5
	var along := Vector3.BACK if b.x != a.x else Vector3.RIGHT
	return [mid, along]


func _put(kind: String, at: Vector3, yaw: float) -> Breakable:
	at.y = _h(at.x, at.z)
	var br := Breakable.make(kind, Transform3D(Basis(Vector3.UP, yaw), at))
	get_parent().add_child(br)
	_layout.append(br)
	return br


## A wall the length of the side: containers end to end, or a double row of concrete barriers, or
## sandbags with blocks.
func _wall(a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	var s := _side(a, b)
	var mid: Vector3 = s[0]
	var along: Vector3 = s[1]
	var yaw := atan2(along.x, along.z) + PI * 0.5 # (a box's length is its x)
	var r := rng.randf()
	if r < 0.55:
		for k in 3:
			_put("container", mid + along * (k - 1) * 6.4, yaw)
		if rng.randf() < 0.25:
			# one stacked on: a taller wall there
			var top := _put("container", mid + along * (rng.randi() % 3 - 1) * 6.4, yaw)
			top.position.y += Breakable.SIZES.container.y
	elif r < 0.85:
		for k in 6:
			for row: float in [-0.35, 0.35]:
				_put("barrier", mid + along * (k - 2.5) * 3.2 + along.cross(Vector3.UP) * row, yaw)
	else:
		for k in 5:
			_put("sandbags" if k % 2 == 0 else "block", mid + along * (k - 2) * 3.6, yaw)


## Stubs: a short piece of wall at each end of an open side (a doorway between the cells).
func _stubs(a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	var s := _side(a, b)
	var mid: Vector3 = s[0]
	var along: Vector3 = s[1]
	var yaw := atan2(along.x, along.z) + PI * 0.5
	var kind := "container" if rng.randf() < 0.5 else "block"
	var off := CELL * 0.5 - (3.2 if kind == "container" else 1.2)
	for sgn: float in [-1.0, 1.0]:
		_put(kind, mid + along * sgn * off, yaw)


## What's in a cell to fight round: nothing, a pair of blocks, a crate stack, a sandbag nest, drums
## (they go up), never on its middle (where a crate may come down, a rival come in).
func _cover(c: Vector2i, rng: RandomNumberGenerator) -> void:
	var at := center(c)
	var a := rng.randf() * TAU
	var o := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(4.0, 6.5)
	match rng.randi() % 6:
		0:
			pass
		1:
			_put("block", at + o, a)
			_put("block", at + o + Vector3(cos(a + 1.57), 0.0, sin(a + 1.57)) * 2.2, a)
		2:
			for k in 3:
				_put("crate", at + o + Vector3(k * 1.3, 0.0, 0.0), 0.0)
		3:
			for k in 3:
				_put("sandbags", at + o + Vector3(cos(a + k * 0.8), 0.0, sin(a + k * 0.8)) * 2.4, a + k * 0.8 + PI * 0.5)
		4:
			for k in 4:
				_put("drum", at + o + Vector3(randf_range(-0.8, 0.8), 0.0, randf_range(-0.8, 0.8)), 0.0)
		5:
			_put("barrier", at + o, a)
			_put("barrier", at - o, a)


# --- The way through ---------------------------------------------------------------------------------

## The cells' way from where `from` is to where `to` is, through the open sides (the cells in order,
## the first the next one to go to); empty if they're in the same cell.
func path(from: Vector3, to: Vector3) -> Array[Vector2i]:
	var a := cell_of(from)
	var b := cell_of(to)
	var out: Array[Vector2i] = []
	if a == b:
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


## Where a machine at `from` after one at `to` should head this moment (AiDriver's route): straight
## for `goal` if it's in the same or the next open cell, else the middle of the next cell on the way.
func route(m: Machine, target: Machine, goal: Vector3) -> Vector3:
	var p := path(m.global_position, target.global_position)
	if p.size() <= 1:
		return goal
	return center(p[0])


## The cells furthest from yours by the way through (where the other side comes in).
func far_cells(from: Vector3, n: int) -> Array[Vector2i]:
	var all: Array[Vector2i] = []
	for x in N:
		for y in N:
			all.append(Vector2i(x, y))
	all.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return path(center(a), from).size() > path(center(b), from).size())
	return all.slice(0, n)
