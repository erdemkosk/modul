class_name Wall
extends Node3D
## A palisade: sharpened logs stood side by side in the ground along a line (smoothed through the
## points it was laid out by, like a road), following the ground. Laid out, it's only a line of
## pale marks; the townsfolk raise it a stretch at a time (RAISE stakes, an odun for every WOOD_PER),
## and each stretch shuts its cells to walking (Nav.set_wall: dear to cross, so the way round
## through a gate is taken). Its gates (Gate) stand in gaps left for them. An outlaw who comes up
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
const BURN := 0.55 ## a stake's hp burnt away a second
const WALK_H := 1.45 ## m the walkway stands off the ground

var _solid: MultiMeshInstance3D
var _marks: MultiMeshInstance3D
var _walk: MultiMeshInstance3D
var _burn_t := 0.0
static var _stake_mesh: Mesh


static func stake_mesh() -> Mesh:
	if _stake_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.13
		shaft.bottom_radius = 0.14
		shaft.height = 2.5
		shaft.radial_segments = 7
		shaft.rings = 1
		st.append_from(shaft, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.25, 0)))
		var tip := CylinderMesh.new()
		tip.top_radius = 0.0
		tip.bottom_radius = 0.13
		tip.height = 0.38
		tip.radial_segments = 7
		tip.rings = 1
		st.append_from(tip, 0, Transform3D(Basis.IDENTITY, Vector3(0, 2.69, 0)))
		_stake_mesh = st.commit()
	return _stake_mesh


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
	_solid = MultiMeshInstance3D.new()
	add_child(_solid)
	_marks = MultiMeshInstance3D.new()
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marks)
	_walk = MultiMeshInstance3D.new()
	add_child(_walk)
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
	_solid.multimesh = _stakes(up, false)
	_marks.multimesh = _stakes(todo, true)
	_walk.multimesh = _walkway(up)


func _stakes(which: Array[int], ghost: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = stake_mesh()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	if ghost:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.instance_count = which.size()
	for j in which.size():
		var k := which[j]
		mm.set_instance_transform(j, stake_xf(line[k], k, ghost))
		if ghost:
			mm.set_instance_color(j, Color(1.0, 0.95, 0.8, 0.22))
		else:
			var h := fposmod(sin(k * 12.9898) * 43758.5453, 1.0)
			var shade := 0.36 + h * 0.14
			mm.set_instance_color(j, Color(shade, shade * 0.78, shade * 0.55))
	(_marks if ghost else _solid).material_override = m
	return mm


## The walkway along the inside of the standing stretches: planks laid across, a plank to a stake.
func _walkway(up: Array[int]) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var plank := BoxMesh.new()
	plank.size = Vector3(0.9, 0.06, 0.28)
	mm.mesh = plank
	mm.instance_count = up.size()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.38, 0.25)
	m.roughness = 0.95
	_walk.material_override = m
	for j in up.size():
		var k: int = up[j]
		var dir := line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		var left := Vector3.UP.cross(dir).normalized() * inward
		var c := line[k] + left * 0.62
		c.y = nav.height(line[k].x, line[k].z) + WALK_H
		mm.set_instance_transform(j, Transform3D(Basis.looking_at(dir, Vector3.UP), c))
	return mm


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
		hp[k] -= BURN * dt
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
	if ghost:
		return Transform3D(b.scaled(Vector3(0.7, 0.25, 0.7)), g + Vector3.UP * 0.25)
	return Transform3D(b.scaled(Vector3(1.0, 0.9 + h * 0.2, 1.0)), g)


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
func raise(s: int) -> void:
	var cells: Array[Vector2i] = []
	for k in range(s * RAISE, mini((s + 1) * RAISE, line.size())):
		if built[k] == 0 and not in_gap(k):
			built[k] = 1
			hp[k] = STAKE_HP
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
	mi.mesh = stake_mesh()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.3, 0.2)
	mi.material_override = m
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


func _process(dt: float) -> void:
	_burn(dt)
	for g in gates:
		if is_instance_valid(g):
			g.think(dt)
