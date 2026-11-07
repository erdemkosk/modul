class_name Wall
extends Node3D
## A palisade: sharpened logs stood side by side in the ground along a line (smoothed through the
## points it was laid out by, like a road), following the ground. Laid out, it's only a line of
## pale marks; the townsfolk raise it a stretch at a time (RAISE stakes, an odun for every WOOD_PER),
## and each stretch shuts its cells to walking (Nav.set_wall: dear to cross, so the way round
## through a gate is taken; the townsfolk never go through the stakes, Villager._barred). It's laid
## with no gate: they're set in by hand (Village.add_gate_at), in gaps left for them. An outlaw who comes up
## against it hacks at the stakes till they fall and he's through; a breach is mended by raising
## those stakes again. A torch set to it takes, but slowly: green logs rammed into damp ground burn
## a stake through in the better part of a minute, the fire creeping along to its neighbours only
## now and then, and rain puts it out. Along the inside runs a plank walkway on posts, where the
## militia stand to shoot over the points (Village.hold_at).

const STEP := 0.3 ## m between stakes (the line's own spacing: Village.ROAD_STEP)
const WOOD_PER := 4 ## stakes an odun makes
const RAISE := 12 ## stakes raised at a go
const STAKE_HP := 30.0
const GAP := 1.75 ## m either side of a gate's middle left open for it

var village: Node
var nav: Nav
var line := PackedVector3Array() ## each stake's foot
var built := PackedByteArray() ## 1 standing, 0 not yet (or fallen), 2 never (under a building)
var hp := PackedFloat32Array()
var gates: Array[Gate] = []
var claims := {} ## stretch index -> who's raising it
var burning := {} ## stake index -> its flames (GPUParticles3D)
var inward := 1.0 ## which side of the line the town's on (+1: its left, looking along it)
var level := 1 ## 2: made stronger (GÜÇLENDİR): thick logs on a stone footing, three times as hard to hack or burn through
const STRONG := 3.0
const BURN := 0.55 ## a stake's hp burnt away a second
const WALK_H := 1.45 ## m the walkway stands off the ground

var _solid: Array[MultiMeshInstance3D] = [] ## the standing stakes, a MultiMesh to each of the three stakes made (Details: stake_0..2)
var _marks: MultiMeshInstance3D
var _walk: MultiMeshInstance3D
var _walk_frames: MultiMeshInstance3D ## the walkway's trestles, their legs into the ground
var _bind: MultiMeshInstance3D ## the rails binding the standing stakes on the inside
var _trench: MultiMeshInstance3D ## the trench dug along what's still to be raised
var _berm: MultiMeshInstance3D ## the earth banked up round the stakes' feet, outside
var _ropes: MultiMeshInstance3D ## lashings where the rails are tied to the stakes
var _braces: MultiMeshInstance3D ## the raking props that shore it up from inside
const BIND_EVERY := 6 ## stakes a rail spans
var _burn_t := 0.0
static var _stake_mesh: Mesh


## A stake's plain shape (a stake still to raise, faint; Main's palisade drawn to the mouse): a log,
## its top hewn to a point. (The standing stakes are the models: Details, stake_0..2.)
static func stake_mesh() -> Mesh:
	if _stake_mesh == null:
		var sides := 8
		var rings: Array = [[0.0, 0.15], [0.9, 0.142], [1.7, 0.136], [2.45, 0.13]]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for r in rings.size() - 1:
			var y0: float = rings[r][0]
			var y1: float = rings[r + 1][0]
			for i in sides:
				var a0 := TAU * i / sides
				var a1 := TAU * (i + 1) / sides
				var w0 := 1.0 + 0.06 * sin(i * 2.3 + r)
				var w1 := 1.0 + 0.06 * sin((i + 1) * 2.3 + r)
				var p00 := Vector3(cos(a0) * rings[r][1] * w0, y0, sin(a0) * rings[r][1] * w0)
				var p01 := Vector3(cos(a1) * rings[r][1] * w1, y0, sin(a1) * rings[r][1] * w1)
				var p10 := Vector3(cos(a0) * rings[r + 1][1] * w0, y1, sin(a0) * rings[r + 1][1] * w0)
				var p11 := Vector3(cos(a1) * rings[r + 1][1] * w1, y1, sin(a1) * rings[r + 1][1] * w1)
				for p in [p00, p10, p11, p00, p11, p01]:
					st.add_vertex(p)
		st.generate_normals()
		st.set_material(bark_material(1))
		var mesh := st.commit()
		# the hewn point: axe-cut facets, off centre a touch
		var tip := SurfaceTool.new()
		tip.begin(Mesh.PRIMITIVE_TRIANGLES)
		var top: float = rings[rings.size() - 1][0]
		var r_top: float = rings[rings.size() - 1][1]
		var apex := Vector3(0.02, top + 0.42, -0.01)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var w0 := 1.0 + 0.06 * sin(i * 2.3 + 3)
			var w1 := 1.0 + 0.06 * sin((i + 1) * 2.3 + 3)
			for p in [Vector3(cos(a0) * r_top * w0, top, sin(a0) * r_top * w0), apex, Vector3(cos(a1) * r_top * w1, top, sin(a1) * r_top * w1)]:
				tip.add_vertex(p)
		tip.generate_normals()
		var cut := StandardMaterial3D.new()
		cut.albedo_color = Color(0.72, 0.58, 0.4)
		cut.roughness = 0.9
		tip.set_material(cut)
		tip.commit(mesh)
		_stake_mesh = mesh
	return _stake_mesh


static var _barks := {}


## The bark of a stake or a rail: weathered grey-brown (a strengthened wall's rails darker).
static func bark_material(lvl: int) -> StandardMaterial3D:
	if not _barks.has(lvl):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.4, 0.31, 0.22) if lvl < 2 else Color(0.3, 0.23, 0.16)
		m.roughness = 0.95
		_barks[lvl] = m
	return _barks[lvl]


func setup(points: PackedVector3Array, v: Node, n: Nav) -> void:
	line = points
	village = v
	nav = n
	built.resize(line.size())
	hp.resize(line.size())
	for k in line.size():
		built[k] = 2 if not nav.is_open(line[k]) else 0
		hp[k] = STAKE_HP


func _ready() -> void:
	for i in 3:
		var mmi := MultiMeshInstance3D.new()
		add_child(mmi)
		_solid.append(mmi)
	_marks = MultiMeshInstance3D.new()
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marks)
	_walk = MultiMeshInstance3D.new()
	add_child(_walk)
	_walk_frames = MultiMeshInstance3D.new()
	add_child(_walk_frames)
	_bind = MultiMeshInstance3D.new()
	add_child(_bind)
	_trench = MultiMeshInstance3D.new()
	_trench.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trench)
	_berm = MultiMeshInstance3D.new()
	add_child(_berm)
	_ropes = MultiMeshInstance3D.new()
	_ropes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ropes)
	_braces = MultiMeshInstance3D.new()
	add_child(_braces)
	# the town's side: where its store is
	var stores: Array = village.stores()
	if not stores.is_empty() and line.size() > 2:
		var mid := line[line.size() / 2]
		var dir := line[line.size() / 2 + 1] - line[line.size() / 2 - 1]
		var left := Vector3.UP.cross(dir).normalized()
		inward = 1.0 if left.dot((stores[0] as Node3D).global_position - mid) > 0.0 else -1.0
	redraw()


## The stakes standing, solid; those still to raise as faint marks.
func redraw() -> void:
	var up: Array[int] = []
	var todo: Array[int] = []
	for k in line.size():
		if built[k] == 1:
			up.append(k)
		elif built[k] == 0 and not in_gap(k):
			todo.append(k)
	for i in 3:
		var mine: Array[int] = []
		for k in up:
			if k % 3 == i:
				mine.append(k)
		_solid[i].multimesh = _stakes(mine, false, i)
	_marks.multimesh = _stakes(todo, true)
	_walk.multimesh = _walkway(up)
	_walk_frames.multimesh = _trestles(up)
	_bind.multimesh = _binding()
	_trench.multimesh = _ditch(todo)
	_dress(up)


## Two rails along the inside of each standing stretch, low and high, a rail to every few stakes.
func _binding() -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Details.mesh("rail")
	var xfs: Array[Transform3D] = []
	var k := 0
	while k + BIND_EVERY < line.size():
		var whole := true
		for j in range(k, k + BIND_EVERY + 1):
			if built[j] != 1:
				whole = false
				break
		if whole:
			var a := line[k]
			var b := line[k + BIND_EVERY]
			var dir := Vector3(b.x - a.x, 0, b.z - a.z)
			var len := dir.length() + 0.25
			dir = dir.normalized() if dir.length() > 0.001 else Vector3.RIGHT
			var left := Vector3.UP.cross(dir).normalized() * inward
			var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).scaled(Vector3(len, 1, 1))
			for hgt in [0.75, 1.95]:
				var mid := (a + b) * 0.5 + left * 0.19
				mid.y = (nav.height(a.x, a.z) + nav.height(b.x, b.z)) * 0.5 + hgt - 0.3
				xfs.append(Transform3D(basis, mid))
		k += BIND_EVERY
	mm.instance_count = xfs.size()
	for j in xfs.size():
		mm.set_instance_transform(j, xfs[j])
		var shade := (0.74 if level >= 2 else 0.92) + fposmod(sin(j * 3.7) * 437.5, 1.0) * 0.14
		mm.set_instance_color(j, Color(shade, shade * 0.97, shade * 0.94))
	return mm


## What makes a standing palisade look built rather than stuck in: the earth thrown up against its
## feet on the outside (grassed over, stones in it), withies lashing the rails to the stakes, and
## every so often a raking prop shoring it from inside. (The models: Details berm, lashing, brace.)
func _dress(up: Array[int]) -> void:
	var stand := {}
	for k in up:
		stand[k] = true
	var bank: Array[Transform3D] = []
	var ties: Array[Transform3D] = []
	var props: Array[Transform3D] = []
	for k in up:
		var dir := line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		var left := Vector3.UP.cross(dir).normalized() * inward
		var g := line[k]
		g.y = nav.height(g.x, g.z)
		var h := fposmod(sin(k * 41.7) * 2671.3, 1.0)
		# the bank: low, long mounds run into one another, outside and a little off the line
		if k % 4 == 0:
			var heap := g - left * (0.5 + h * 0.15)
			heap.y = minf(nav.height(heap.x, heap.z), g.y) - 0.05 # (never standing off a bank that drops away)
			bank.append(Transform3D(Basis.looking_at(dir, Vector3.UP).rotated(Vector3.UP, (h - 0.5) * 0.3).scaled(Vector3(0.85 + h * 0.3, 0.7 + h * 0.4, 1.0)), heap))
		if k % BIND_EVERY == 0 and stand.has(mini(k + BIND_EVERY, line.size() - 1)):
			for hgt in [0.75, 1.95]:
				var at: Vector3 = g + left * 0.1 + Vector3.UP * (float(hgt) - 0.3)
				ties.append(Transform3D(Basis.looking_at(dir, Vector3.UP), at))
		if k % 9 == 4 and stand.has(maxi(k - 1, 0)) and stand.has(mini(k + 1, line.size() - 1)):
			# a prop: from the ground 1.6 m inside up to just under the top rail
			var foot := g + left * 1.6
			foot.y = nav.height(foot.x, foot.z)
			var top := g + left * 0.22 + Vector3.UP * 1.75
			var along := top - foot
			var b := Basis.looking_at(along.normalized(), Vector3.UP if absf(along.normalized().y) < 0.99 else Vector3.FORWARD)
			props.append(Transform3D(b.scaled(Vector3(1, 1, along.length())), (foot + top) * 0.5))
	_berm.multimesh = _mm(Details.mesh("berm"), bank)
	_ropes.multimesh = _mm(Details.mesh("lashing"), ties)
	_braces.multimesh = _mm(Details.mesh("brace"), props)


static func _mm(mesh: Mesh, xfs: Array[Transform3D]) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	return mm


## The trench dug along the stretches still to be raised, the spoil thrown up outside it.
func _ditch(todo: Array[int]) -> MultiMesh:
	var xfs: Array[Transform3D] = []
	for j in range(0, todo.size(), 2):
		var k := todo[j]
		var dir := line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		var p := line[k]
		p.y = nav.height(p.x, p.z) + 0.01
		var b := Basis.looking_at(dir, Vector3.UP) # (its +x, where the spoil's thrown, outward)
		if inward < 0.0:
			b = b.rotated(Vector3.UP, PI)
		xfs.append(Transform3D(b, p))
	return _mm(Details.mesh("ditch"), xfs)


## The stakes in `which`: standing (the model `variant`, each its own shade), or still to raise
## (`ghost`: faint marks of the plain shape).
func _stakes(which: Array[int], ghost: bool, variant := 0) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = stake_mesh() if ghost else Details.mesh("stake_%d" % variant)
	mm.instance_count = which.size()
	for j in which.size():
		var k := which[j]
		mm.set_instance_transform(j, stake_xf(line[k], k, ghost))
		if ghost:
			mm.set_instance_color(j, Color(0.95, 0.85, 0.68, 0.13))
		else:
			var h := fposmod(sin(k * 12.9898) * 43758.5453, 1.0)
			var shade := (0.72 if level >= 2 else 0.88) + h * 0.2
			mm.set_instance_color(j, Color(shade, shade * (0.96 + h * 0.04), shade * 0.92))
	if ghost:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_marks.material_override = m
	return mm


## The walkway along the inside of the standing stretches: planks laid across, a plank to a stake.
func _walkway(up: Array[int]) -> MultiMesh:
	var xfs: Array[Transform3D] = []
	for k: int in up:
		xfs.append(_walk_xf(k))
	return _mm(Details.mesh("walk_board"), xfs)


## The walkway's trestles: one under every third plank whose neighbours stand too, its legs down
## into the ground.
func _trestles(up: Array[int]) -> MultiMesh:
	var stand := {}
	for k in up:
		stand[k] = true
	var xfs: Array[Transform3D] = []
	for k: int in up:
		if k % 3 == 1 and stand.has(k - 1) and stand.has(k + 1):
			xfs.append(_walk_xf(k))
	return _mm(Details.mesh("walk_frame"), xfs)


## A walkway plank's place over stake `k`.
func _walk_xf(k: int) -> Transform3D:
	var dir := line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	var left := Vector3.UP.cross(dir).normalized() * inward
	var c := line[k] + left * 0.62
	c.y = nav.height(line[k].x, line[k].z) + WALK_H
	return Transform3D(Basis.looking_at(dir, Vector3.UP), c)


## A spot on the walkway near `p`: {at (standing on it), down (on the ground beside it)}, or empty
## where none's standing.
func walk_spot(p: Vector3) -> Dictionary:
	var n := nearest(p)
	if n.is_empty() or built[int(n.k)] != 1:
		return {}
	var left := Vector3.UP.cross(n.dir as Vector3).normalized() * inward
	var at: Vector3 = (n.at as Vector3) + left * 0.62
	var down := at + left * 0.8
	at.y = nav.height(at.x, at.z) + WALK_H + 0.03
	down.y = nav.height(down.x, down.z)
	return {"at": at, "down": down}


## A torch put to it at `p`: the nearest standing stake takes (slowly).
func ignite(p: Vector3) -> void:
	var n := nearest(p)
	if n.is_empty():
		return
	var k := int(n.k)
	if built[k] == 1 and not burning.has(k) and Weather.rain_now < 0.2:
		_light(k)


func _light(k: int) -> void:
	var f := FireFx.flames()
	f.amount = 8
	(f.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.15, 0.6, 0.15)
	add_child(f)
	f.global_position = line[k] + Vector3.UP * (nav.height(line[k].x, line[k].z) - line[k].y + 1.2)
	burning[k] = f


func _burn(dt: float) -> void:
	if burning.is_empty():
		return
	_burn_t += dt
	var spread := _burn_t >= 1.0
	if spread:
		_burn_t = 0.0
	for k: int in burning.keys():
		var f: Node = burning[k]
		if built[k] != 1 or Weather.rain_now > 0.3:
			burning.erase(k)
			f.queue_free()
			continue
		hp[k] -= BURN * dt / (STRONG if level >= 2 else 1.0)
		if hp[k] <= 0.0:
			burning.erase(k)
			f.queue_free()
			hit(line[k], 0.0) # (burnt through: it falls)
			continue
		# the fire creeps along now and then (wet ground and green wood: seldom)
		if spread and randf() < 0.06 * (1.0 - Weather.wet_now):
			var j: int = k + (1 if randf() < 0.5 else -1)
			if j >= 0 and j < line.size() and built[j] == 1 and not burning.has(j):
				_light(j)


## A stake's place: sunk a little into the ground, each a touch taller or shorter and leaning
## (`ghost`: only a short mark).
func stake_xf(at: Vector3, k: int, ghost := false) -> Transform3D:
	var h := fposmod(sin(k * 78.233) * 43758.5453, 1.0)
	var g := Vector3(at.x, nav.height(at.x, at.z) - 0.3, at.z)
	var b := Basis(Vector3.UP, h * TAU).rotated(Vector3.RIGHT, (h - 0.5) * 0.06)
	if ghost: # (still to be raised: its full height, faint, over the trench)
		return Transform3D(b.scaled(Vector3(0.95, 0.9 + h * 0.2, 0.95)), g)
	var thick := 1.45 if level >= 2 else 1.0 # (a strengthened wall: logs half again as thick)
	return Transform3D(b.scaled(Vector3(thick, 0.9 + h * 0.2 + (0.12 if level >= 2 else 0.0), thick)), g)


func in_gap(k: int) -> bool:
	for g in gates:
		if is_instance_valid(g) and g.global_position.distance_to(line[k]) < GAP:
			return true
	return false


func stretches() -> int:
	return ceili(float(line.size()) / RAISE)


## The stakes still to raise in stretch `s`.
func left_in(s: int) -> int:
	var n := 0
	for k in range(s * RAISE, mini((s + 1) * RAISE, line.size())):
		if built[k] == 0 and not in_gap(k):
			n += 1
	return n


func stretch_at(s: int) -> Vector3:
	var a := s * RAISE
	var b := mini((s + 1) * RAISE, line.size()) - 1
	return line[(a + b) / 2]


## The nearest stretch to `p` with stakes to raise that nobody's raising.
func next_stretch(p: Vector3) -> int:
	var best := -1
	var bd := INF
	for s in stretches():
		var who: Variant = claims.get(s)
		if who != null and is_instance_valid(who) and str((who as Villager).job).begins_with("Sur"):
			continue
		if left_in(s) == 0:
			continue
		var d := stretch_at(s).distance_squared_to(p)
		if d < bd:
			bd = d
			best = s
	return best


func done() -> bool:
	for s in stretches():
		if left_in(s) > 0:
			return false
	return true


## Stretch `s` stood up.
## A stake's hit points: three times as many on a strengthened wall.
func stake_hp() -> float:
	return STAKE_HP * (STRONG if level >= 2 else 1.0)


## What strengthening it would take: half an odun a standing stake, a stone for every eight.
func strengthen_cost() -> Dictionary:
	var up := 0
	for k in built:
		if k == 1:
			up += 1
	return {"odun": ceili(up / 2.0), "tas": ceili(up / 8.0)}


## Strengthened: every standing stake's hit points (and any raised after) three times over, the
## stones of its footing laid along it.
func strengthen() -> void:
	level = 2
	for k in line.size():
		if built[k] == 1:
			hp[k] = maxf(hp[k], 0.0) / STAKE_HP * stake_hp()
	_footing()
	redraw()


var _foot: MultiMeshInstance3D


## A strengthened wall's footing: fieldstones along its foot, a stone to every few stakes.
func _footing() -> void:
	if level < 2:
		return
	if _foot == null:
		_foot = MultiMeshInstance3D.new()
		add_child(_foot)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Details.mesh("footing")
	var spots: Array[int] = []
	for k in range(0, line.size(), 3):
		if built[k] != 2:
			spots.append(k)
	mm.instance_count = spots.size()
	for j in spots.size():
		var p := line[spots[j]]
		p.y = nav.height(p.x, p.z) - 0.04
		mm.set_instance_transform(j, Transform3D(Basis(Vector3.UP, spots[j] * 1.7), p))
	_foot.multimesh = mm


func raise(s: int) -> void:
	var cells: Array[Vector2i] = []
	for k in range(s * RAISE, mini((s + 1) * RAISE, line.size())):
		if built[k] == 0 and not in_gap(k):
			built[k] = 1
			hp[k] = stake_hp()
			var c := Nav.cell_of(line[k])
			if not c in cells:
				cells.append(c)
	nav.set_wall(cells, true)
	claims.erase(s)
	redraw()


## Struck at `at` (an axe): the nearest standing stake takes it; down, it falls outward and its
## cell opens again if no other stake still stands in it. True if one fell.
func hit(at: Vector3, dmg: float) -> bool:
	var best := -1
	var bd := 2.0
	for k in line.size():
		if built[k] == 1:
			var d := line[k].distance_to(at)
			if d < bd:
				bd = d
				best = k
	if best < 0:
		return false
	hp[best] -= dmg
	if hp[best] > 0.0 and dmg > 0.0:
		return false
	if burning.has(best):
		(burning[best] as Node).queue_free()
		burning.erase(best)
	built[best] = 0
	_fall(best)
	var c := Nav.cell_of(line[best])
	var still := false
	for k in line.size():
		if built[k] == 1 and Nav.cell_of(line[k]) == c:
			still = true
			break
	if not still:
		nav.set_wall([c], false)
	redraw()
	return true


func _fall(k: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Details.mesh("stake_%d" % (k % 3))
	add_child(mi)
	var xf := stake_xf(line[k], k)
	mi.global_transform = xf
	var dir := (line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]).cross(Vector3.UP).normalized()
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_transform", Transform3D(xf.basis.rotated(dir.cross(Vector3.UP).normalized(), PI * 0.48), xf.origin + dir * 0.2), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(40.0)
	tw.tween_callback(mi.queue_free)


## Pulled down whole (the player's YIK): its cells opened, its gates gone.
func pull_down() -> void:
	var cells: Array[Vector2i] = []
	for k in line.size():
		if built[k] == 1:
			cells.append(Nav.cell_of(line[k]))
	nav.set_wall(cells, false)
	for g in gates:
		if is_instance_valid(g):
			g.set_locked(false)
			g.queue_free()
	queue_free()


## The point on its line nearest `p`, and the way it runs there.
func nearest(p: Vector3) -> Dictionary:
	var bd := INF
	var bi := -1
	for k in line.size():
		var d := Vector2(line[k].x - p.x, line[k].z - p.z).length()
		if d < bd:
			bd = d
			bi = k
	if bi < 0:
		return {}
	var dir := line[mini(bi + 1, line.size() - 1)] - line[maxi(bi - 1, 0)]
	dir.y = 0.0
	return {"at": line[bi], "dir": dir.normalized(), "dist": bd, "k": bi}


## A gate set in at stake `k`: the stakes in its gap taken out (their cells opened).
func add_gate(k: int) -> Gate:
	var g := Gate.new()
	g.wall = self
	var dir := line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]
	dir.y = 0.0
	var at := line[k]
	at.y = nav.height(at.x, at.z)
	g.transform = Transform3D(Basis.looking_at(dir.normalized().cross(Vector3.UP), Vector3.UP), at) # (the wall stands at the origin)
	add_child(g)
	gates.append(g)
	var cells: Array[Vector2i] = []
	for j in line.size():
		if built[j] == 1 and in_gap(j):
			built[j] = 0
			cells.append(Nav.cell_of(line[j]))
	nav.set_wall(cells, false)
	redraw()
	return g


## The stakes within `r` of `p` taken out for good (a tower stands on the line in their place).
func clear_under(p: Vector3, r: float) -> void:
	var cells: Array[Vector2i] = []
	for k in line.size():
		if Vector2(line[k].x - p.x, line[k].z - p.z).length() < r and built[k] != 2:
			if built[k] == 1:
				cells.append(Nav.cell_of(line[k]))
			built[k] = 2
	if not cells.is_empty():
		nav.set_wall(cells, false)
	redraw()


## The cells of `g`'s gap.
func gate_cells(g: Gate) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for j in line.size():
		if g.global_position.distance_to(line[j]) < GAP:
			cells.append(Nav.cell_of(line[j]))
	return cells


## `g` taken out: the stakes of its gap are to be raised again.
func remove_gate(g: Gate) -> void:
	g.set_locked(false)
	gates.erase(g)
	g.queue_free()
	redraw()


func _process(dt: float) -> void:
	_burn(dt)
	for g in gates:
		if is_instance_valid(g):
			g.think(dt)
