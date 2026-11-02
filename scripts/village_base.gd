extends Node3D
## The town's ground floor: what's built and where, who lives, the stores and what's in them,
## placing and clearing, the roads, light. (Village: village_base -> village_life -> village_defense
## -> village_work -> village.gd)

signal message(text: String, kind: String) ## kind: "info", "good", "bad"


const START_STOCK := {"odun": 40, "tas": 12, "yiyecek": 50}


const EAT_EVERY := 75.0 ## s a villager goes on one food


const ARRIVE_EVERY := 24.0 ## s between newcomers, when there's room and food


const HAUL := {"odun": 6, "tas": 4, "yiyecek": 6}


const PILE_FROM := 20.0 ## m from a store past which, with carters about, a workplace piles its goods


const BUILDERS_PER_SITE := 6


var terrain: WorldTerrain


var props: WorldProps


var nav: Nav


var weather: Weather


var raids: Raids


var seasons: Seasons


## All the stores' goods together (read only: goods are put in and taken out of a store).
var stock: Dictionary:
	get:
		var out := {"odun": 0, "tas": 0, "yiyecek": 0}
		for b in stores():
			for k: String in b.goods:
				out[k] = int(out.get(k, 0)) + int(b.goods[k])
		return out


var buildings: Array[Building] = []


var villagers: Array[Villager] = []


var reserved := {} ## prop index -> the villager going for it


var rock_left := {} ## prop index -> stone left in it


var bush_rest := {} ## prop index -> clock time it bears again


var clock := 0.0


var day := 1


var work_rate := 1.0 ## less when hungry


var loading := false ## (a saved game being put back: nothing to announce)


var saplings := {} ## prop index -> {node, left (s till it's a tree)}


var billets: Array[Dictionary] = [] ## logs lying where a tree was bucked: {node, camp, claimed}


var yards: Array = [] ## Yard, one to a house


var roads: Array = [] ## the plank roads laid: each a polyline [x0, z0, x1, z1, ...]
var walls: Array[Wall] = [] ## the palisades


const BILLET_WOOD := 3 ## wood a log gives sawn up


const SAPLING_TIME := 240.0


const LOG_EVERY := 55.0 ## s a lit hearth goes on one firewood


const COLD_BELOW := 12.0 ## deg C under which a house wants its fire in the day too


var _assign_t := 0.0


var _eat_t := 0.0


var _arrive_t := 0.0


var _spread_t := 0.0


var _last_flash := 0.0


var _last_hour := -1.0


var _hungry := false


var _no_well_said := false


var _burning := {} ## Building -> true while it burns (to say so once)


var _stumps: Node3D


var _heat_t := 0.0


var _last_day := 1


func _ready() -> void:
	name = "Village"
	_stumps = Node3D.new()
	add_child(_stumps)


# --- Starting out -----------------------------------------------------------------------------------


func start(at: Vector3) -> void:
	var store := _place_near("ambar", at, 0.0)
	# The first house beside the store, square to it, the fronts in line, room left between for its
	# yard (Yard.SIDE) and a lane.
	var house: Building = null
	if store:
		var ss: Vector2 = store.def.size
		var hs: Vector2 = BuildingDefs.def("ev").size
		var beside := store.global_transform * Vector3(ss.x * 0.5 + Yard.SIDE + hs.x * 0.5 + 2.5, 0, (ss.y - hs.y) * 0.5)
		house = _place_near("ev", beside, store.global_rotation.y)
	else:
		house = _place_near("ev", at + Vector3(14, 0, 0), 0.0)
	if store:
		store.complete_now()
		for k: String in START_STOCK:
			store.add_goods(k, int(START_STOCK[k]))
	if house:
		house.complete_now()
	var door := store.door() if store else at
	for k in 6:
		var p := door + Vector3(randf_range(-4, 4), 0, randf_range(1, 5))
		spawn_villager(p)
	_house_people()


## Puts a building straight down at or near `at` (the first ones: searched outward till it fits).
func _place_near(kind: String, at: Vector3, yaw: float) -> Building:
	for r in range(0, 60, 3):
		for k in 12:
			var a := k * TAU / 12.0
			var p := at + Vector3(cos(a), 0, sin(a)) * r
			if check(kind, p, yaw) == "":
				return place(kind, p, yaw)
			if r == 0:
				break
	return null


const NAMES := ["Anton", "Pyotr", "Mikhail", "Ivan", "Fyodor", "Nikolai", "Grigori", "Semyon", "Yakov", "Ilya", "Pavel", "Timofey",
	"Marya", "Anna", "Olga", "Vera", "Darya", "Sofia", "Nadia", "Irina", "Agafya", "Polina", "Lidia", "Yelena"]


func spawn_villager(p: Vector3, child := false) -> Villager:
	var v := Villager.new()
	v.is_child = child
	v.born_day = day
	v.display_name = NAMES[randi() % NAMES.size()]
	v.village = self
	v.nav = nav
	add_child(v)
	p.y = nav.height(p.x, p.z)
	v.position = p
	villagers.append(v)
	v.died.connect(_on_villager_died)
	return v


func _on_villager_died(v: Villager) -> void:
	villagers.erase(v)
	if is_instance_valid(v.workplace):
		v.workplace.workers.erase(v)
	if is_instance_valid(v.home):
		v.home.residents.erase(v)
	v.workplace = null
	v.home = null
	message.emit("Bir köylü öldü (%d kişi kaldı)" % villagers.size(), "bad")


# --- Placing ----------------------------------------------------------------------------------------


## The cells a building of `kind` at `pos` turned `yaw` stands on (`grow` m more each side).
func footprint(kind: String, pos: Vector3, yaw: float, grow := 0.0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var sz: Vector2 = BuildingDefs.def(kind).size
	var hx := sz.x * 0.5 + grow
	var hz := sz.y * 0.5 + grow
	var r := sqrt(hx * hx + hz * hz)
	var inv := Basis(Vector3.UP, yaw).inverse()
	var c0 := Nav.cell_of(pos - Vector3(r, 0, r))
	var c1 := Nav.cell_of(pos + Vector3(r, 0, r))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cz)
			var l := inv * (Nav.center_of(c) - Vector3(pos.x, 0, pos.z))
			if absf(l.x) <= hx and absf(l.z) <= hz:
				out.append(c)
	return out


## Why a building can't go there ("" if it can).
func check(kind: String, pos: Vector3, yaw: float) -> String:
	if absf(pos.x) > 980.0 or absf(pos.z) > 980.0:
		return "Haritanın dışında"
	var sz: Vector2 = BuildingDefs.def(kind).size
	var b := Basis(Vector3.UP, yaw)
	var lo := INF
	var hi := -INF
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 0), Vector2(0, 1.4)]:
		var p := pos + b * Vector3(c.x * sz.x * 0.5, 0, c.y * sz.y * 0.5)
		var h := terrain.height_at(p.x, p.z)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	if hi - lo > (3.6 if BuildingDefs.DEFS[kind].role == "farm" else 2.6):
		return "Zemin çok eğimli"
	for c in footprint(kind, pos, yaw, 1.0):
		if not nav.is_ground_open(Nav.center_of(c)):
			return "Su ya da uçurum"
		if not nav.can_build(Nav.center_of(c)):
			return "Başka bir binaya çok yakın"
	return ""


## The height a building sits at: the highest of its corners (its plinth takes up the rest).
func base_height(kind: String, pos: Vector3, yaw: float) -> float:
	var sz: Vector2 = BuildingDefs.def(kind).size
	var b := Basis(Vector3.UP, yaw)
	var hi := -INF
	var sum := 0.0
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 0)]:
		var p := pos + b * Vector3(c.x * sz.x * 0.5, 0, c.y * sz.y * 0.5)
		hi = maxf(hi, terrain.height_at(p.x, p.z))
		sum += terrain.height_at(p.x, p.z)
	if BuildingDefs.DEFS[kind].role == "farm":
		return sum / 5.0 # (a fence follows the ground; its posts are sunk deep)
	if kind in BuildingDefs.YARDS:
		return sum / 5.0 - 0.35 + 0.03 # (the yard's floor, at 0.35 in the model, down on the ground)
	return hi + 0.02


## A building site (or, `instant`, the building itself) of `kind` at `pos` turned `yaw`. What grows
## on its ground (trees, bushes, rocks) is cleared away.
func place(kind: String, pos: Vector3, yaw: float) -> Building:
	var b := Building.new()
	b.setup(kind)
	add_child(b)
	b.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, base_height(kind, pos, yaw), pos.z))
	b.cells = footprint(kind, pos, yaw, 0.0 if BuildingDefs.DEFS[kind].role == "farm" else 0.5) # (a margin: paths keep off the walls)
	b.nav = nav
	if b.def.role == "farm":
		nav.set_field(b.cells, true)
	else:
		nav.set_building(b.cells, true)
	_clear_ground(kind, pos, yaw)
	b.finished.connect(_on_finished)
	b.ruined.connect(_on_ruined)
	buildings.append(b)
	b.begin()
	return b


func _clear_ground(kind: String, pos: Vector3, yaw: float) -> void:
	var sz: Vector2 = BuildingDefs.def(kind).size
	var inv := Basis(Vector3.UP, yaw).inverse()
	var reach := sz.length() * 0.5 + 3.0
	for i in _props_in(pos, reach):
		var info := props.prop_info(i)
		var l := inv * (Vector3(info.origin.x, 0, info.origin.z) - Vector3(pos.x, 0, pos.z))
		if absf(l.x) <= sz.x * 0.5 + 1.5 and absf(l.z) <= sz.y * 0.5 + 2.5 and str(info.kind) != "cliff":
			props.cut_tree(i)
			reserved.erase(i)


## Where a foot stands at `p`: the ground, or a building's floor, porch or loading platform.
func ground_at(p: Vector3) -> float:
	var g := nav.height(p.x, p.z)
	for b in buildings:
		if b.state == "ghost" or b.state == "gone" or b.def.role in ["farm", "light"]:
			continue
		var d := Vector2(p.x - b.global_position.x, p.z - b.global_position.z)
		if d.length() > b.radius + 3.0:
			continue
		var l := b.global_transform.affine_inverse() * Vector3(p.x, b.global_position.y, p.z)
		var sz: Vector2 = b.def.size
		var deck := 1.7 if b.kind in ["ev", "ambar"] else 0.0
		if absf(l.x) <= sz.x * 0.5 and l.z >= -sz.y * 0.5 and l.z <= sz.y * 0.5 + deck:
			g = maxf(g, b.global_position.y + (0.47 if l.z <= sz.y * 0.5 else 0.45))
	return g


## Every standing prop with its foot within `reach` of `pos`.
func _props_in(pos: Vector3, reach: float) -> Array[int]:
	var out: Array[int] = []
	var k := int(ceil(reach / WorldProps.CELL))
	var c := Vector2i(floori(pos.x / WorldProps.CELL), floori(pos.z / WorldProps.CELL))
	for dz in range(-k, k + 1):
		for dx in range(-k, k + 1):
			for i: int in props._grid.get(c + Vector2i(dx, dz), []):
				if props.cut.has(i):
					continue
				var o: Vector3 = props._xf[i].origin
				if Vector2(o.x - pos.x, o.z - pos.z).length() <= reach:
					out.append(i)
	return out


## Pulls a building down (a site, a ruin or a standing one): half of what went into it comes back.
func remove_building(b: Building) -> void:
	if not buildings.has(b):
		return
	for r: String in b.delivered:
		var back := int(b.delivered[r]) if b.under_work() else int(b.delivered[r]) / 2
		add_anywhere(r, back, b.global_position)
	for r: String in b.goods: # (what was in it, or piled by it)
		add_anywhere(r, int(b.goods[r]), b.global_position)
	b.goods.clear()
	_let_go(b)
	buildings.erase(b)
	var y := _yard_of(b)
	if y:
		yards.erase(y)
		y.queue_free()
	if b.def.role == "farm":
		nav.set_field(b.cells, false)
	else:
		nav.set_building(b.cells, false)
	b.demolish()
	message.emit("%s yıkıldı" % b.display_name(), "info")


## Everyone working at, living in or headed for `b` is let go of it.
func _let_go(b: Building) -> void:
	for v in villagers:
		if v.workplace == b:
			_unstaff(v)
			v.abort()
		elif v.target == b:
			v.abort()
		if v.home == b:
			v.home = null
			if v.sleeping:
				v.wake()
	b.workers.clear()
	b.residents.clear()


func _on_finished(b: Building) -> void:
	if loading:
		return
	message.emit("%s %s" % [b.display_name(), "onarıldı" if b.repaired else "tamamlandı"], "good")
	if b.def.role == "armory" and not b.has_meta("stocked"):
		b.set_meta("stocked", true)
		b.arms = 2
		b.ammo = 40
		message.emit("Silahlık hazır: kasabanın eski iki Mosin tüfeği ve 40 fişek rafta. Kartından tüfekçi ya da okçu yetiştir.", "good")
	if b.def.role == "house":
		_house_people()
		if not _yard_of(b):
			var y := Yard.new()
			y.house = b
			y.village = self
			y.nav = nav
			yards.append(y)
			add_child(y)
	if b.def.role == "light" and not b.repaired:
		b.add_goods("odun", 2) # (it's put up with its first kindling)


func _on_ruined(b: Building) -> void:
	message.emit("%s harabeye döndü! Seçip Onar ya da Yık." % b.display_name(), "bad")
	if b.def.role == "store" and b.goods_total() > 0:
		message.emit("Ambardakiler enkazın altında kaldı; onarılınca geri gelir.", "bad")
	_let_go(b)


func _yard_of(b: Building) -> Yard:
	for y in yards:
		if is_instance_valid(y) and y.house == b:
			return y
	return null


## A plank road straight from `a` to `b` (old saves, tests).
func lay_road(a: Vector3, b: Vector3, free := false) -> float:
	return lay_path([a, b], free)


const ROAD_STEP := 0.3 ## m between planks
const ROAD_HALF := 0.9 ## m from a road's middle to its edge


## A plank road through `pts`, its bends smoothed (a Catmull-Rom curve through them); leaving
## `start_dir` (the way the road it starts from runs) it bends away from it smoothly. As far as the
## store's wood goes (an odun for every 2 m) unless `free`. Where it meets or crosses a road already
## there it joins it, its planks stopping at the other's edge. Returns the metres laid.
func lay_path(pts: Array, free := false, start_dir := Vector3.ZERO) -> float:
	var line := road_curve(pts, start_dir)
	if line.size() < 2:
		return 0.0
	var length := (line.size() - 1) * ROAD_STEP
	var n := ceili(length / 2.0)
	var laid := 0
	if not free:
		for k in n:
			var st := store_with("odun", line[0])
			if st == null or st.take_goods("odun", 1) == 0:
				break
			laid += 1
	else:
		laid = n
	if laid == 0:
		return 0.0
	line = line.slice(0, mini(line.size(), int(laid * 2.0 / ROAD_STEP) + 1))
	_road_mesh(line)
	# (kept as a polyline, every few planks and the end: enough to lay it again the same)
	var flat: Array = []
	for k in line.size():
		if k % 4 == 0 or k == line.size() - 1:
			flat.append(snappedf(line[k].x, 0.01))
			flat.append(snappedf(line[k].z, 0.01))
	roads.append(flat)
	var cells: Array[Vector2i] = []
	for q in line:
		var c := Nav.cell_of(q)
		if not c in cells:
			cells.append(c)
	nav.set_road(cells)
	return (line.size() - 1) * ROAD_STEP


## The road's line through `pts`, a point every ROAD_STEP along it, on the ground.
func road_curve(pts: Array, start_dir := Vector3.ZERO) -> PackedVector3Array:
	var p: Array[Vector3] = []
	for q: Vector3 in pts:
		var f := Vector3(q.x, 0, q.z)
		if p.is_empty() or p.back().distance_to(f) > 0.4:
			p.append(f)
	var out := PackedVector3Array()
	if p.size() < 2:
		return out
	# the curve's ends: carried on the way the road it leaves runs, or straight on
	var head := p[0] * 2.0 - p[1]
	if start_dir != Vector3.ZERO:
		var d := Vector3(start_dir.x, 0, start_dir.z).normalized()
		if d.dot(p[1] - p[0]) < 0.0:
			d = -d
		head = p[0] - d * p[0].distance_to(p[1])
	var c: Array[Vector3] = [head]
	c.append_array(p)
	c.append(p.back() * 2.0 - p[p.size() - 2])
	var dense: Array[Vector3] = []
	for i in range(1, c.size() - 2):
		var steps := maxi(4, int(c[i].distance_to(c[i + 1]) / 0.2))
		for s in steps:
			dense.append(_catmull(c[i - 1], c[i], c[i + 1], c[i + 2], float(s) / steps))
	dense.append(p.back())
	# evenly along it
	out.append(dense[0])
	var carry := 0.0
	for i in range(1, dense.size()):
		var a := dense[i - 1]
		var b := dense[i]
		var seg := a.distance_to(b)
		var at := ROAD_STEP - carry
		while at <= seg:
			out.append(a.lerp(b, at / seg))
			at += ROAD_STEP
		carry = seg - (at - ROAD_STEP)
	for k in out.size():
		out[k].y = nav.height(out[k].x, out[k].z)
	return out


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## A palisade laid out through `pts` (bent smoothly as a road is): its stakes marked out, to be raised
## by the townsfolk. Where it crosses a road a gate's set in; with no road crossed, one gate on the
## side toward the store. Returns it.
func lay_wall(pts: Array, start_dir := Vector3.ZERO) -> Wall:
	var line := road_curve(pts, start_dir)
	if line.size() < 4:
		return null
	var w := Wall.new()
	w.setup(line, self, nav)
	add_child(w)
	walls.append(w)
	var lines := road_lines()
	var k := 0
	while k < line.size():
		if _road_dist(line[k], lines) < 1.0:
			var a := k
			while k < line.size() and _road_dist(line[k], lines) < 1.0:
				k += 1
			w.add_gate((a + k - 1) / 2)
			k += int(Wall.GAP * 2.0 / Wall.STEP)
		k += 1
	if w.gates.is_empty():
		var st := _nearest(stores(), line[line.size() / 2])
		var at: Vector3 = st.global_position if st else line[line.size() / 2]
		w.add_gate(int(w.nearest(at).k))
	return w


## A gate set into the palisade nearest `p` (within 3 m): 6 odun. Why not ("" done).
func add_gate_at(p: Vector3) -> String:
	var best: Wall = null
	var hit := {}
	for w in walls:
		var n := w.nearest(p)
		if not n.is_empty() and float(n.dist) < 3.0 and (hit.is_empty() or float(n.dist) < float(hit.dist)):
			hit = n
			best = w
	if best == null:
		return "Bir surun üstüne koy"
	for g in best.gates:
		if g.global_position.distance_to(hit.at) < Wall.GAP * 2.2:
			return "Orada zaten bir kapı var"
	var st := store_with("odun", p)
	if st == null or int(st.goods.get("odun", 0)) < 6:
		return "Depoda 6 odun yok"
	st.take_goods("odun", 6)
	best.add_gate(int(hit.k))
	return ""


## What stands in an outlaw's way just ahead of it going from `from` to `to`: a gate shut, or a
## palisade's standing stakes ({gate} / {wall, at}; empty if nothing).
func barrier_at(from: Vector3, to: Vector3) -> Dictionary:
	for w in walls:
		for g in w.gates:
			if is_instance_valid(g) and g.blocks() and g.global_position.distance_to(from) < 2.4:
				return {"gate": g}
	# the next stretch of its way crossing standing stakes (the grid's points can lie a metre off the
	# line, so it's the stretch walked that's looked at, not where it ends)
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(1, 1)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(1, 1)
	for w in walls:
		if not is_instance_valid(w):
			continue
		for k in w.line.size():
			if w.built[k] != 1:
				continue
			var q := Vector2(w.line[k].x, w.line[k].z)
			if q.x < lo.x or q.y < lo.y or q.x > hi.x or q.y > hi.y:
				continue
			if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) < 0.45 and a.distance_to(q) < 2.0:
				return {"wall": w, "at": w.line[k]}
	return {}


## The roads already laid, each as its points on the ground.
func road_lines() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	for rd: Array in roads:
		var line := PackedVector3Array()
		for k in range(0, rd.size() - 1, 2):
			line.append(Vector3(float(rd[k]), 0, float(rd[k + 1])))
		out.append(line)
	return out


## The nearest point on a road within `reach` of `p`, and the way the road runs there:
## {at, dir, end} (empty if none). At one of the road's ends `end` is true and `dir` points out of
## it, the way a road carried on from there would go.
func road_snap(p: Vector3, reach := 3.0) -> Dictionary:
	var best := {}
	var bd := reach
	var f := Vector3(p.x, 0, p.z)
	for line in road_lines():
		for k in range(1, line.size()):
			var a := line[k - 1]
			var b := line[k]
			var q := Geometry3D.get_closest_point_to_segment(f, a, b)
			var d := q.distance_to(f)
			if d < bd:
				bd = d
				var dir := (b - a).normalized()
				var end := false
				if q.distance_to(line[0]) < 1.2:
					end = true
					dir = (line[0] - line[1]).normalized()
				elif q.distance_to(line[line.size() - 1]) < 1.2:
					end = true
					q = line[line.size() - 1]
				q.y = nav.height(q.x, q.z)
				best = {"at": q, "dir": dir, "end": end}
	return best


## How far `p` is from the middle of the nearest road (INF with none).
func _road_dist(p: Vector3, lines: Array[PackedVector3Array]) -> float:
	var f := Vector3(p.x, 0, p.z)
	var bd := INF
	for line in lines:
		for k in range(1, line.size()):
			var q := Geometry3D.get_closest_point_to_segment(f, line[k - 1], line[k])
			bd = minf(bd, q.distance_to(f))
	return bd


## The planks themselves along `line`: laid across the way every ROAD_STEP on the ground where it
## lies, tilted to its slope; one multimesh to a road. Where a road's already there, its planks are
## left to it (the new one stops at its edge: a junction, a crossing). `ghost`: the preview's look,
## green up to `afford` planks, red past them, none left out.
func _road_mesh(line: PackedVector3Array, ghost := false, afford := -1, into: MultiMeshInstance3D = null) -> MultiMeshInstance3D:
	var lines := road_lines()
	var keep: Array[int] = []
	for k in line.size():
		if ghost or _road_dist(line[k], lines) > ROAD_HALF + 0.12:
			keep.append(k)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var board := BoxMesh.new()
	board.size = Vector3(1.8, 0.06, 0.27)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	if ghost:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	board.material = m
	mm.mesh = board
	mm.instance_count = keep.size()
	for j in keep.size():
		var k := keep[j]
		var c := line[k]
		var dir := line[mini(k + 1, line.size() - 1)] - line[maxi(k - 1, 0)]
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		var side := dir.cross(Vector3.UP)
		c.y = nav.height(c.x, c.z) + 0.08
		var hl := nav.height(c.x - side.x * 0.8, c.z - side.z * 0.8)
		var hr := nav.height(c.x + side.x * 0.8, c.z + side.z * 0.8)
		var tilt := atan2(hr - hl, 1.6)
		var basis := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.BACK, -tilt) * Basis(Vector3.UP, randf_range(-0.04, 0.04) if not ghost else 0.0)
		mm.set_instance_transform(j, Transform3D(basis, c))
		if ghost:
			mm.set_instance_color(j, Color(0.45, 1.0, 0.55, 0.55) if afford < 0 or k <= afford else Color(1.0, 0.35, 0.3, 0.55))
		else:
			var shade := randf_range(0.42, 0.6)
			mm.set_instance_color(j, Color(shade, shade * 0.76, shade * 0.5))
	var mi := into if into else MultiMeshInstance3D.new()
	mi.multimesh = mm
	if mi.get_parent() == null:
		add_child(mi)
	return mi


## Sets a damaged building or a ruin to be mended. Why not, if it can't be ("" if it can).
func repair(b: Building) -> String:
	if b.is_burning():
		return "Önce yangın sönmeli"
	if b.fallen_count() == 0:
		return "Onarılacak bir yeri yok"
	if not b.start_repair():
		return "Şu an onarılamaz"
	_let_go(b)
	return ""


# --- Goods ----------------------------------------------------------------------------------------


## Puts `n` of `r` in the store nearest `p` (lost if there's none).
func add_anywhere(r: String, n: int, p: Vector3) -> void:
	if n <= 0:
		return
	var s := _nearest(stores(), p)
	if s:
		s.add_goods(r, n)


## The store nearest `p` that has some `r`.
func store_with(r: String, p: Vector3) -> Building:
	var best: Building = null
	var bd := INF
	for b in stores():
		if int(b.goods.get(r, 0)) <= 0:
			continue
		var d := b.global_position.distance_squared_to(p)
		if d < bd:
			bd = d
			best = b
	return best


## What a hauler took for a site and never brought goes back.
func give_back(owed: Dictionary) -> void:
	var site: Variant = owed.get("site")
	if is_instance_valid(site):
		(site as Building).incoming[owed.res] = int((site as Building).incoming[owed.res]) - int(owed.n)
	var from: Variant = owed.get("store")
	if is_instance_valid(from) and (from as Building).state == "done":
		(from as Building).add_goods(owed.res, int(owed.n))
	else:
		add_anywhere(owed.res, int(owed.n), (site as Building).global_position if is_instance_valid(site) else Vector3.ZERO)
	for b in buildings: # (a house it was taking firewood to)
		if b.pile_claim and not is_instance_valid(b.pile_claim):
			b.pile_claim = null


func carters_about() -> bool:
	for b in buildings:
		if b.state == "done" and b.def.role in ["carts", "oxen"] and not b.workers.is_empty():
			return true
	return false


func oxen() -> int:
	var n := 0
	for v in villagers:
		if v.vehicle == "ox":
			n += 1
	return n


# --- Who's where -------------------------------------------------------------------------------------


func beds() -> int:
	var n := 0
	for b in buildings:
		if b.state == "done" and b.def.role == "house":
			n += int(b.def.beds)
	return n


func free_count() -> int:
	var n := 0
	for v in villagers:
		if v.workplace == null and not v.is_child:
			n += 1
	return n


func _house_people() -> void:
	for v in villagers:
		if is_instance_valid(v.home) and v.home.state == "done":
			continue
		v.home = null
		for b in buildings:
			if b.state == "done" and b.def.role == "house" and b.residents.size() < int(b.def.beds):
				b.residents.append(v)
				v.home = b
				break


func stores() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role == "store":
			out.append(b)
	return out


func _nearest(list: Array[Building], p: Vector3) -> Building:
	var best: Building = null
	var bd := INF
	for b in list:
		var d := b.global_position.distance_squared_to(p)
		if d < bd:
			bd = d
			best = b
	return best


func set_wanted(b: Building, n: int) -> void:
	b.wanted = clampi(n, 0, int(b.def.get("slots", 0)))


func release(v: Villager) -> void:
	for i in reserved.keys():
		if reserved[i] == v:
			reserved.erase(i)
	for b in buildings:
		if b.pile_claim == v:
			b.pile_claim = null
		if not b.claims.is_empty():
			b.unclaim(v)


# --- The clock ------------------------------------------------------------------------------------


## Whether `p` can be seen: by day anywhere; by night only in the light of a lamp, a lit window, a
## fire or a lantern.
func is_lit(p: Vector3) -> bool:
	if not weather.is_night():
		return true
	for b in buildings:
		var reach := b.light_reach()
		if b.is_burning():
			reach = maxf(reach, 18.0)
		if reach > 0.0 and b.global_position.distance_to(p) < reach:
			return true
	for v in villagers:
		if v.lantern_on() and v.position.distance_to(p) < Villager.LANTERN_REACH:
			return true
	return false


## Off its workplace, and out of a guard's gear.
func _unstaff(v: Villager) -> void:
	if v.fighter:
		v.fighter = false
		v.max_hp = 50.0
		v.hp = minf(v.hp, 50.0)
		v.attack = 9.0
		v.ranged = 0.0
	v.arm_with("")
	if v.has_cart:
		v.give_cart(false)
	v.workplace = null


## In through `b`'s door: up to it, the door swung open, a few steps inside. (A cart stays at the
## door; a building with no door standing is gone into the old way.)
func _go_in(b: Building, v: Villager = null) -> Array:
	if not b.has_door() or (v and v.has_cart):
		return [{"t": "go", "to": b.door()}]
	return [{"t": "go", "to": b.door()}, {"t": "do", "f": func() -> bool:
		if is_instance_valid(b):
			b.open_door()
		return true}, {"t": "step", "to": b.inside()}]


## And out again.
func _go_out(b: Building, v: Villager = null) -> Array:
	if not b.has_door() or (v and v.has_cart):
		return []
	return [{"t": "do", "f": func() -> bool:
		if is_instance_valid(b):
			b.open_door()
		return true}, {"t": "step", "to": b.door()}]


## A place to stand by a building, on the side toward `from`.
func _spot_by(b: Building, from: Vector3) -> Vector3:
	var d := from - b.global_position
	d.y = 0.0
	if d.length() < 0.1:
		d = Vector3.BACK
	var p := b.global_position + d.normalized() * (b.radius + 1.2) + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	p.y = nav.height(p.x, p.z)
	return p
