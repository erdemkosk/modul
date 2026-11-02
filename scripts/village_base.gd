extends Node3D
## The town's ground floor: what's built and where, who lives, the stores and what's in them,
## placing and clearing, the roads, light. (Village: village_base -> village_life -> village_defense
## -> village_work -> village.gd)

signal message(text: String, kind: String) ## kind: "info", "good", "bad"


const START_STOCK := {"odun": 40, "tas": 12, "yiyecek": 50}


const EAT_EVERY := 75.0 ## s a villager goes on one food


const ARRIVE_EVERY := 24.0 ## s between newcomers, when there's room and food


const HAUL := {"odun": 6, "tas": 4, "yiyecek": 6, "camur": 4, "kerpic": 4}


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
		var out := {"odun": 0, "tas": 0, "yiyecek": 0, "camur": 0, "kerpic": 0}
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
var cut_marks := {} ## prop index -> 1: marked to be felled (KES), 2: urgently (ACİL KES: everyone drops their work for it)
var _marks_mm: MultiMeshInstance3D ## an orange band round each marked trunk
var _marks_top: MultiMeshInstance3D ## and a marker over its crown, to be seen from above


var yards: Array = [] ## Yard, one to a house


var roads: Array = [] ## the plank roads laid: each a polyline [x0, z0, x1, z1, ...]
var walls: Array[Wall] = [] ## the palisades
var rail := PackedVector3Array() ## the railway, from the valley's edge to the station (on the ground)
var train: Train
var seed := 0
var start_people := 6 ## how many come on the train
var start_crew: Array = [] ## the settlers chosen on the title screen (Villager.candidate), in the order they step down
var arriving := false ## the first train in and its load not yet in the station
var supplies := 1.0 ## how much of START_STOCK it brings


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
	# The railway in from the edge of the valley, the station at its end; the first of the town come
	# by train, and what they bring is unloaded there.
	var line := _rail_line(at)
	var station: Building = null
	var at_k := -1
	if line.size() > 20:
		rail = line
		_rail_mesh(rail)
		at_k = _nearest_k(rail, at)
		station = _place_station(rail, at_k)
	if station == null:
		_start_old(at)
		return
	station.complete_now()
	# the station's place along the line (by the line's own length, its rises and falls and all):
	# the coach stops level with it
	train = Train.new()
	train.nav = nav
	train.setup(rail, 0.0, 0.0)
	var s_station := train.s_of(station.global_position)
	train.stop_at = s_station
	train._s = maxf(s_station - 200.0, 0.0)
	add_child(train)
	train.arrived.connect(_train_arrived.bind(station))
	arriving = true
	message.emit("Tren geliyor: ilk yerleşimciler ve yükleri istasyona iniyor.", "info")


## The old start, with no railway: a store and a house put down at once.
func _start_old(at: Vector3) -> void:
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
			store.add_goods(k, roundi(int(START_STOCK[k]) * supplies))
	if house:
		house.complete_now()
	var door := store.door() if store else at
	for k in start_people:
		var p := door + Vector3(randf_range(-4, 4), 0, randf_range(1, 5))
		spawn_villager(p, false, villagers[villagers.size() - 1].family if k % 2 == 1 else "", k % 2, start_crew[k] if k < start_crew.size() else {})
	_house_people()


## The railway's line: in from a place on the valley's edge (picked by the seed) to `at` and on out
## to another edge across the valley, the walkable way each time, smoothed into long easy curves, a
## point every 0.3 m on the ground.
func _rail_line(at: Vector3) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else 1
	var a0 := rng.randf() * TAU
	var from := _edge_point(a0)
	var to := _edge_point(a0 + PI + rng.randf_range(-0.6, 0.6))
	if from == Vector3.INF or to == Vector3.INF:
		return PackedVector3Array()
	var way_in := nav.find_path(from, at)
	var way_out := nav.find_path(at, to)
	if way_in.size() < 4 or way_out.size() < 4:
		return PackedVector3Array()
	# (every so many points of the walk, then a smooth curve through them: a railway bends gently)
	# (a point every 40 m or so of the walk, none too near the station: long, even bends)
	var pts: Array = []
	for k in range(0, way_in.size() - 10, 20):
		pts.append(way_in[k])
	pts.append(at)
	for k in range(20, way_out.size() - 10, 20):
		pts.append(way_out[k])
	pts.append(way_out[way_out.size() - 1])
	# (eased twice: each point drawn toward its neighbours' middle, the ends left)
	for pass_ in 2:
		var eased: Array = [pts[0]]
		for k in range(1, pts.size() - 1):
			var p: Vector3 = pts[k]
			if (p - at).length() < 1.0:
				eased.append(p)
			else:
				eased.append(p.lerp(((pts[k - 1] as Vector3) + (pts[k + 1] as Vector3)) * 0.5, 0.5))
		eased.append(pts[pts.size() - 1])
		pts = eased
	# (out to the very edge of the map at both ends: it comes from somewhere and goes somewhere)
	pts.push_front(_to_edge(pts[0], pts[0] - pts[1]))
	pts.append(_to_edge(pts[pts.size() - 1], pts[pts.size() - 1] - pts[pts.size() - 2]))
	return _bridged(road_curve(pts))


## The water's surface at `p` (the lake, or the river where its channel is), or -INF.
func water_at(p: Vector3) -> float:
	var w := terrain.water_height_at(p.x, p.z)
	if _river.is_empty():
		var hw := float(terrain.meta.river.get("half_width", 9.0))
		for q: Variant in terrain.meta.river.points:
			if q is Array and (q as Array).size() > 2:
				_river.append(Vector4(float(q[0]), float(q[1]), float(q[2]), hw))
	for q in _river:
		if Vector2(q.x - p.x, q.z - p.z).length() < q.w + 2.0:
			w = maxf(w, q.y)
	return w


var _river: Array[Vector4] = [] ## the river's line: x, surface y, z, half its width


## Where the line crosses water, a bridge: the rails carried 1.6 m over the water on a trestle, eased
## up to it and down again over 24 m either side. (The points' heights become the rails' bed's.)
func _bridged(line: PackedVector3Array) -> PackedVector3Array:
	var n := line.size()
	var wet := PackedFloat32Array()
	wet.resize(n)
	var any := false
	for k in n:
		wet[k] = water_at(line[k])
		any = any or wet[k] > -INF
	if not any:
		return line
	var lift := PackedFloat32Array()
	lift.resize(n)
	for k in n:
		lift[k] = -INF
	var k := 0
	while k < n:
		if wet[k] == -INF:
			k += 1
			continue
		var a := k
		var top := -INF
		while k < n and wet[k] > -INF:
			top = maxf(top, wet[k])
			k += 1
		var deck := top + 1.6
		var ramp := 80 # (points: 24 m)
		for j in range(maxi(a - ramp, 0), mini(k + ramp, n)):
			var u := 1.0
			if j < a:
				u = smoothstep(0.0, 1.0, float(j - (a - ramp)) / ramp)
			elif j >= k:
				u = smoothstep(0.0, 1.0, 1.0 - float(j - k) / ramp)
			lift[j] = maxf(lift[j], lerpf(line[j].y, deck, u))
	for j in n:
		if lift[j] > line[j].y:
			line[j].y = lift[j]
	return line


## From `p` on along `dir` to the edge of the map.
func _to_edge(p: Vector3, dir: Vector3) -> Vector3:
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else p.normalized()
	var lim := float(terrain.half) - 2.0
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, ((lim if dir.x > 0.0 else -lim) - p.x) / dir.x)
	if absf(dir.z) > 0.001:
		t = minf(t, ((lim if dir.z > 0.0 else -lim) - p.z) / dir.z)
	return p + dir * maxf(t, 0.0)


## A walkable point on the valley's edge round from angle `a`.
func _edge_point(a: float) -> Vector3:
	var half := float(terrain.half) - 60.0
	for k in 24:
		var p := Vector3(cos(a + k * 0.26), 0, sin(a + k * 0.26)) * half
		if nav.is_open(p):
			return p
	return Vector3.INF


func _nearest_k(line: PackedVector3Array, p: Vector3) -> int:
	var best := 0
	var bd := INF
	for k in line.size():
		var d := Vector2(line[k].x - p.x, line[k].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = k
	return best


## How far along `line` the point nearest `p` is (m).
func _rail_s(line: PackedVector3Array, p: Vector3) -> float:
	return _nearest_k(line, p) * ROAD_STEP


## Where the station stands (INF with none): the camera starts there.
func station_at() -> Vector3:
	for b in buildings:
		if b.kind == "istasyon":
			return b.global_position
	return Vector3.INF


func _rail_len(line: PackedVector3Array) -> float:
	return (line.size() - 1) * ROAD_STEP


## The track: a ballast bed, sleepers across every 0.66 m, two rails, all on the ground as it lies;
## the trees in the way felled.
func _rail_mesh(line: PackedVector3Array) -> void:
	var lines := line
	for k in range(0, lines.size(), 8):
		for i in _props_in(lines[k], 4.0):
			var info := props.prop_info(i)
			if str(info.kind) != "cliff" and Vector2(info.origin.x - lines[k].x, info.origin.z - lines[k].z).length() < 3.6:
				props.cut_tree(i)
				reserved.erase(i)
	var bed := SurfaceTool.new()
	bed.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_rails: Array = []
	for k in lines.size():
		var c := lines[k]
		var dir := lines[mini(k + 1, lines.size() - 1)] - lines[maxi(k - 1, 0)]
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		var side := dir.cross(Vector3.UP)
		var g := maxf(nav.height(c.x, c.z), c.y) # (up on a bridge: the line's own height)
		var up := c.y - nav.height(c.x, c.z) > 0.3
		var l := Vector3(c.x, g, c.z) - side * 1.6 + Vector3.UP * 0.02
		var rr := Vector3(c.x, g, c.z) + side * 1.6 + Vector3.UP * 0.02
		l.y = (g - 0.1) if up else nav.height(l.x, l.z) + 0.03
		rr.y = (g - 0.1) if up else nav.height(rr.x, rr.z) + 0.03
		var top := Vector3(c.x, g + 0.14, c.z)
		var rl := [top - side * 0.76 + Vector3.UP * 0.18, top + side * 0.76 + Vector3.UP * 0.18]
		if k > 0 and not up:
			# the bed: two slopes up to its crown
			_quad(bed, prev_l, l, top, (prev_l + prev_r) * 0.5 + Vector3.UP * 0.12)
			_quad(bed, (prev_l + prev_r) * 0.5 + Vector3.UP * 0.12, top, rr, prev_r)
		if k > 0:
			for j in 2:
				var a: Vector3 = prev_rails[j]
				var b: Vector3 = rl[j]
				_quad(rails, a + side * 0.04, b + side * 0.04, b - side * 0.04, a - side * 0.04)
				_quad(rails, a - side * 0.04, b - side * 0.04, b - side * 0.04 - Vector3.UP * 0.12, a - side * 0.04 - Vector3.UP * 0.12)
				_quad(rails, a + side * 0.04 - Vector3.UP * 0.12, b + side * 0.04 - Vector3.UP * 0.12, b + side * 0.04, a + side * 0.04)
		prev_l = l
		prev_r = rr
		prev_rails = rl
	bed.generate_normals()
	rails.generate_normals()
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.36, 0.33, 0.29)
	bm.roughness = 1.0
	var bmi := MeshInstance3D.new()
	bmi.mesh = bed.commit()
	bmi.material_override = bm
	add_child(bmi)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.28, 0.27, 0.26)
	rm.metallic = 0.7
	rm.roughness = 0.45
	var rmi := MeshInstance3D.new()
	rmi.mesh = rails.commit()
	rmi.material_override = rm
	add_child(rmi)
	# the sleepers
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sl := BoxMesh.new()
	sl.size = Vector3(2.5, 0.14, 0.24)
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 0.95
	sl.material = sm
	mm.mesh = sl
	var every := 2
	mm.instance_count = lines.size() / every
	for j in mm.instance_count:
		var k := j * every
		var c := lines[k]
		var dir := lines[mini(k + 1, lines.size() - 1)] - lines[maxi(k - 1, 0)]
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		mm.set_instance_transform(j, Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(c.x, maxf(nav.height(c.x, c.z), c.y) + 0.2, c.z)))
		var shade := randf_range(0.26, 0.38)
		mm.set_instance_color(j, Color(shade, shade * 0.8, shade * 0.6))
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = mm
	add_child(smi)
	# the trestle under it where it's up off the ground: a bent of two piles every 3 m, braced
	var piles: Array[Transform3D] = []
	for k in range(0, lines.size(), 10):
		var c := lines[k]
		var g := nav.height(c.x, c.z)
		if c.y - g < 0.6:
			continue
		var dir := lines[mini(k + 1, lines.size() - 1)] - lines[maxi(k - 1, 0)]
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
		var side := dir.cross(Vector3.UP)
		var bottom := minf(g, water_at(c) if water_at(c) > -INF else g) - 1.5 # (driven into the bed)
		var h := c.y + 0.1 - bottom
		for sx in [-1.1, 1.1]:
			var at: Vector3 = Vector3(c.x, bottom + h * 0.5, c.z) + side * sx
			piles.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, h, 1)), at))
		# the cap across them, and a brace
		piles.append(Transform3D(Basis.looking_at(side, Vector3.UP).scaled(Vector3(1, 1, 2.8)) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x, c.y, c.z)))
	if not piles.is_empty():
		var pm := MultiMesh.new()
		pm.transform_format = MultiMesh.TRANSFORM_3D
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.16
		cyl.bottom_radius = 0.18
		cyl.height = 1.0
		cyl.radial_segments = 7
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.32, 0.24, 0.17)
		wm.roughness = 0.95
		cyl.material = wm
		pm.mesh = cyl
		pm.instance_count = piles.size()
		for j in piles.size():
			pm.set_instance_transform(j, piles[j])
		var pmi := MultiMeshInstance3D.new()
		pmi.multimesh = pm
		add_child(pmi)
	# (the line's cells: walked along like a road, never built on)
	var cells: Array[Vector2i] = []
	for k in range(0, lines.size(), 3):
		var cc := Nav.cell_of(lines[k])
		if not cc in cells:
			cells.append(cc)
	nav.set_road(cells)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


## The station beside the line at point `k` (or a little along it), its platform to the track, on
## whichever side is open.
func _place_station(line: PackedVector3Array, k: int) -> Building:
	var n := line.size()
	var dir := (line[mini(k + 20, n - 1)] - line[maxi(k - 20, 0)])
	dir.y = 0.0
	dir = dir.normalized()
	var ss: Vector2 = BuildingDefs.def("istasyon").size
	for sgn in [1.0, -1.0]:
		var side: Vector3 = dir.cross(Vector3.UP) * sgn
		for back in [0.0, 6.0, -6.0, 12.0, -12.0]:
			var p: Vector3 = line[k] - dir * back + side * (ss.y * 0.5 + 3.4 + 2.6)
			var face := -side # (its front, the platform, toward the track)
			var yaw := atan2(face.x, face.z)
			if check("istasyon", p, yaw) == "":
				return place("istasyon", p, yaw)
	return null


## The train in: the settlers step down from the coach one by one, then unload the boxcar by hand,
## carrying what it brought onto the platform and into the station (the food first). With it empty
## the train steams on, out of the valley the other way.
var _cargo := {} ## what's still in the boxcar


func _train_arrived(station: Building) -> void:
	if not is_instance_valid(station) or not is_instance_valid(train):
		return
	var to_station := station.global_position - train.door(Vector3.ZERO)
	to_station.y = 0.0
	var sd := to_station.normalized()
	_cargo = {"yiyecek": roundi(int(START_STOCK.yiyecek) * supplies), "odun": roundi(int(START_STOCK.odun) * supplies), "tas": roundi(int(START_STOCK.tas) * supplies)}
	for k in start_people:
		get_tree().create_timer(0.8 + k * 0.7, false).timeout.connect(func() -> void:
			if not is_instance_valid(train):
				return
			var p := train.door(sd)
			p.y = ground_at(p)
			# (they come as couples, a man and his wife; an odd one out alone)
			var fam := ""
			if k % 2 == 1:
				fam = villagers[villagers.size() - 1].family
			var v := spawn_villager(p, false, fam, k % 2, start_crew[k] if k < start_crew.size() else {})
			_unload_trip(v, station, sd))


## One more load out of the boxcar for `v` (another after it, till it's empty).
func _unload_trip(v: Villager, station: Building, sd: Vector3) -> void:
	if not is_instance_valid(v) or v.dead or not is_instance_valid(station):
		return
	var res := ""
	for r: String in ["yiyecek", "odun", "tas"]:
		if int(_cargo.get(r, 0)) > 0:
			res = r
			break
	if res == "" or not is_instance_valid(train):
		_cargo_done(station)
		v.give([{"t": "go", "to": station.door() + Vector3(randf_range(-3, 3), 0, randf_range(0.5, 2.0))},
			{"t": "work", "time": randf_range(3.0, 6.0), "anim": "look"}], "Trenden indi", null, true)
		return
	var n := mini(v.capacity(res), int(_cargo[res]))
	_cargo[res] = int(_cargo[res]) - n
	var at := train.cargo_door(sd)
	at.y = ground_at(at)
	v.give([{"t": "go", "to": at},
		{"t": "work", "time": 0.7, "anim": "gather", "face": train.cargo_door(sd)},
		{"t": "do", "f": func() -> bool:
			v.set_carry(res, n)
			return true},
		{"t": "go", "to": station.door()},
		{"t": "do", "f": func() -> bool:
			v.set_carry("", 0)
			if is_instance_valid(station):
				station.add_goods(res, n)
			_unload_trip(v, station, sd)
			return true}], "Trenden yük indiriyor", station)


func _cargo_done(station: Building) -> void:
	if not is_instance_valid(train) or train.has_meta("leaving"):
		return
	for r: String in _cargo:
		if int(_cargo[r]) > 0:
			return
	train.set_meta("leaving", true)
	arriving = false
	message.emit("Yük indi. Tren yoluna devam ediyor. Ev kurun; o zamana dek kamp ateşinde yatarlar.", "good")
	get_tree().create_timer(3.0, false).timeout.connect(func() -> void:
		if is_instance_valid(train):
			train.leave())


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


const SURNAMES := ["Ivanov", "Petrov", "Smirnov", "Kuznetsov", "Popov", "Sokolov", "Lebedev", "Kozlov", "Novikov",
	"Morozov", "Volkov", "Orlov", "Zaitsev", "Belov", "Medvedev", "Yegorov", "Fedorov", "Gusev"]


## A newcomer at `p`: a child or not, of `fam` (a new family if ""), a woman or a man (`woman`: -1
## either), named and given its knacks.
func spawn_villager(p: Vector3, child := false, fam := "", woman := -1, data := {}) -> Villager:
	var v := Villager.new()
	v.is_child = child
	v.born_day = day
	if not data.is_empty(): # (a settler chosen on the title screen: as they were chosen)
		v.female = bool(data.female)
		v.family = str(data.family)
		v.display_name = str(data.name)
		for k: String in data.skills:
			v.skills[k] = float(data.skills[k])
			v.prio[k] = 1
		for k: String in data.keen:
			v.keen.append(k)
		for t: String in data.traits:
			v.traits.append(t)
		v.look_seed = int(data.look_seed)
		v.apply_traits()
	else:
		v.female = randf() < 0.5 if woman < 0 else woman == 1
		v.family = fam if fam != "" else _new_family()
		v.display_name = full_name(v, NAMES[(12 + randi() % 12) if v.female else randi() % 12])
		var rng := RandomNumberGenerator.new()
		rng.seed = randi() # (not randomize(): those spawned in the same tick would come out alike)
		v.roll_skills(rng)
	v.village = self
	v.nav = nav
	add_child(v)
	p.y = nav.height(p.x, p.z)
	v.position = p
	villagers.append(v)
	v.died.connect(_on_villager_died)
	return v


## "Ivan Petrov", "Marya Petrova".
func full_name(v: Villager, first: String) -> String:
	return "%s %s%s" % [first, v.family, "a" if v.female else ""]


func _new_family() -> String:
	var used := {}
	for o in villagers:
		used[o.family] = true
	var free: Array = SURNAMES.filter(func(s: String) -> bool: return not used.has(s))
	return free[randi() % free.size()] if not free.is_empty() else SURNAMES[randi() % SURNAMES.size()]


## Everyone of family `f`.
func family_of(f: String) -> Array[Villager]:
	var out: Array[Villager] = []
	for o in villagers:
		if o.family == f and not o.dead:
			out.append(o)
	return out


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
	if kind == "camur" and not mud_near(pos):
		return "Yakında çamur yok: ıslak zemine, kıyıya kur"
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
		if d.length() > b.radius + (10.0 if b.kind == "istasyon" else 3.0):
			continue
		var l := b.global_transform.affine_inverse() * Vector3(p.x, b.global_position.y, p.z)
		var sz: Vector2 = b.def.size
		if b.kind == "istasyon" and absf(l.x) <= sz.x * 0.5 + 3.0 and l.z > sz.y * 0.5 and l.z <= sz.y * 0.5 + 3.4:
			g = maxf(g, b.global_position.y + 0.96) # (on the platform's boards)
			continue
		var deck := 1.7 if b.kind in ["ev", "ambar"] else 0.0
		if absf(l.x) <= sz.x * 0.5 and l.z >= -sz.y * 0.5 and l.z <= sz.y * 0.5 + deck:
			g = maxf(g, b.global_position.y + (0.47 if l.z <= sz.y * 0.5 else 0.45))
	return g


## Every standing prop with its foot within `reach` of `pos`.
# --- Trees marked to be felled (KES) -------------------------------------------------------------

## The standing trees in `area` (the ground's x, z) marked to be felled (`urgent`: by everyone, now),
## or unmarked (`on` false). How many changed.
func mark_trees(area: Rect2, on: bool, urgent := false) -> int:
	var n := 0
	var c := area.get_center()
	for i in _props_in(Vector3(c.x, 0, c.y), area.size.length() * 0.5 + 1.0):
		var o: Vector3 = props._xf[i].origin
		if not area.has_point(Vector2(o.x, o.z)) or str(props._models[props._kind[i]].kind) != "tree":
			continue
		var level := 2 if urgent else 1
		if on and int(cut_marks.get(i, 0)) < level:
			cut_marks[i] = level
			n += 1
		elif not on and cut_marks.has(i):
			cut_marks.erase(i)
			n += 1
	_show_marks()
	return n


## A band of orange cloth tied round each marked trunk at chest height, and an orange marker
## pointing down at it over its crown (the view's from above).
func _show_marks() -> void:
	for i: int in cut_marks.keys():
		if props.cut.has(i):
			cut_marks.erase(i)
	if _marks_mm == null:
		_marks_mm = MultiMeshInstance3D.new()
		var band := CylinderMesh.new()
		band.top_radius = 1.0
		band.bottom_radius = 1.0
		band.height = 0.22
		band.radial_segments = 12
		band.rings = 1
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 1.0, 1.0)
		m.vertex_color_use_as_albedo = true # (each band's own colour: orange, or red for an urgent one)
		m.emission_enabled = true
		m.emission = Color(0.6, 0.25, 0.05)
		m.emission_energy_multiplier = 0.35
		band.material = m
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = band
		_marks_mm.multimesh = mm
		_marks_mm.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_marks_mm)
	if _marks_top == null:
		_marks_top = MultiMeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.7
		cone.bottom_radius = 0.0
		cone.height = 1.3
		cone.radial_segments = 4
		cone.rings = 1
		cone.material = (_marks_mm.multimesh.mesh as CylinderMesh).material
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_colors = true
		mm2.mesh = cone
		_marks_top.multimesh = mm2
		_marks_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_marks_top.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_marks_top)
	var mm := _marks_mm.multimesh
	var top := _marks_top.multimesh
	mm.instance_count = cut_marks.size()
	top.instance_count = cut_marks.size()
	var k := 0
	for i: int in cut_marks:
		var info := props.tree_info(i)
		var r := float(info.radius) + 0.04
		var o: Vector3 = info.origin
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(r, 1.0, r)), o + Vector3.UP * 1.4))
		top.set_instance_transform(k, Transform3D(Basis(Vector3.UP, 0.785), o + Vector3.UP * (float(info.height) + 1.6)))
		var col := Color(0.95, 0.12, 0.08) if int(cut_marks[i]) >= 2 else Color(1.0, 0.45, 0.08)
		mm.set_instance_color(k, col)
		top.set_instance_color(k, col)
		k += 1


## The marked tree nearest `p` within `reach` (in `area` if it has one; `urgent`: only an urgent
## one) that nobody's after, or -1.
func marked_tree(p: Vector3, reach: float, area := Rect2(), urgent := false) -> int:
	var best := -1
	var bd := INF
	for i: int in cut_marks:
		if reserved.has(i) or props.cut.has(i) or (urgent and int(cut_marks[i]) < 2):
			continue
		var o: Vector3 = props._xf[i].origin
		if area.has_area() and not area.has_point(Vector2(o.x, o.z)):
			continue
		var d := Vector2(o.x - p.x, o.z - p.z).length()
		if d <= reach and d < bd:
			bd = d
			best = i
	return best


## How many trees are marked urgently and not yet felled.
func urgent_count() -> int:
	var n := 0
	for i: int in cut_marks:
		if int(cut_marks[i]) >= 2 and not props.cut.has(i):
			n += 1
	return n


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
	if b.upgraded_now != "":
		var what := b.upgraded_now
		b.upgraded_now = ""
		match what:
			"oda": message.emit("%s büyütüldü: artık %d yatak" % [b.display_name(), b.beds()], "good")
			"siva": message.emit("%s sıvandı: daha az yakacak yakar" % b.display_name(), "good")
			"soba": message.emit("%s evine kerpiç soba yapıldı" % b.display_name(), "good")
		_house_people()
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
			add_yard(b)
	if b.def.role == "light" and not b.repaired:
		b.add_goods("odun", 2) # (it's put up with its first kindling)


func _on_ruined(b: Building) -> void:
	message.emit("%s harabeye döndü! Seçip Onar ya da Yık." % b.display_name(), "bad")
	if b.def.role == "store" and b.goods_total() > 0:
		message.emit("Ambardakiler enkazın altında kaldı; onarılınca geri gelir.", "bad")
	_let_go(b)


## A house's yard laid out round it (what's in it from `Building.yard_has`).
func add_yard(b: Building) -> Yard:
	var y := Yard.new()
	y.house = b
	y.village = self
	y.nav = nav
	yards.append(y)
	add_child(y)
	return y


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


## How muddy the ground at `p` is, 0..1: mud in it, wet ground, a shore.
func muddiness(p: Vector3) -> float:
	var g := terrain.ground_at(p.x, p.z)
	return maxf(terrain.soft_at(p.x, p.z).x, maxf(float(g.wet), float(g.shore) * 0.8))


## Whether there's mud enough round `p` for a mud pit.
func mud_near(p: Vector3) -> bool:
	var n := 0
	for gz in range(-3, 4):
		for gx in range(-3, 4):
			var q := p + Vector3(gx, 0, gz) * 9.0
			if muddiness(q) > 0.35 and not terrain.is_water(q.x, q.z):
				n += 1
	return n >= 3


## `what` done to a house (BuildingDefs.UPGRADES): its stuff to be carried in and built
## (Building.start_upgrade); the back room's ground staked out first.
func upgrade(b: Building, what := "oda") -> String:
	if b.def.role != "house":
		return "Yalnızca evlere yapılır"
	if b.has_upgrade(what):
		return "Bu evde zaten var"
	if b.upgrading != "":
		return "Bu evde zaten iş var"
	if b.is_burning():
		return "Önce yangın sönmeli"
	if b.state != "done" or b.fallen_count() > 0:
		return "Önce onarılmalı"
	if what != "oda":
		if not b.start_upgrade(what):
			return "Şu an yapılamaz"
		_let_go(b)
		return ""
	var y0 := b.global_position.y
	for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var l := BuildingDefs.ANNEX.position + BuildingDefs.ANNEX.size * c
		var w := b.global_transform * Vector3(l.x, 0, l.y)
		var h := terrain.height_at(w.x, w.z)
		if h > y0 + 0.25 or h < y0 - 2.8:
			return "Evin arkası çok eğimli"
	for c in _annex_cells(b):
		if not nav.is_ground_open(Nav.center_of(c)):
			return "Evin arkasında su ya da uçurum var"
	var room := BuildingDefs.ANNEX.grow(0.4)
	for o in buildings:
		if o == b or o.state == "gone":
			continue
		var os: Vector2 = o.def.size
		for c: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2.ZERO]:
			var l := b.global_transform.affine_inverse() * (o.global_transform * Vector3(c.x * os.x, 0, c.y * os.y))
			if room.has_point(Vector2(l.x, l.z)):
				return "Evin arkasında %s var" % o.display_name()
	if not b.start_upgrade("oda"):
		return "Şu an büyütülemez"
	_close_annex(b)
	_let_go(b)
	return ""


## The nav cells under a house's back room.
func _annex_cells(b: Building) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := BuildingDefs.ANNEX.grow(0.3)
	var inv := b.global_transform.affine_inverse()
	var reach := b.radius + r.size.length() + 6.0
	var c0 := Nav.cell_of(b.global_position - Vector3(reach, 0, reach))
	var c1 := Nav.cell_of(b.global_position + Vector3(reach, 0, reach))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cz)
			var l := inv * Nav.center_of(c)
			if r.has_point(Vector2(l.x, l.z)):
				out.append(c)
	return out


## The back room's ground shut to walkers, and the yard laid out again round it.
func _close_annex(b: Building) -> void:
	var cells := _annex_cells(b)
	nav.set_building(cells, true)
	for c in cells:
		if not c in b.cells:
			b.cells.append(c)
	var old := _yard_of(b)
	if old:
		yards.erase(old)
		remove_child(old) # (its fence let go at once)
		old.free()
		add_yard(b)


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
			n += b.beds()
	return n


func free_count() -> int:
	var n := 0
	for v in villagers:
		if v.workplace == null and not v.is_child:
			n += 1
	return n


## The homeless housed: a family together in one house if one has the beds, else wherever's room.
func _house_people() -> void:
	for v in villagers:
		if is_instance_valid(v.home) and v.home.state == "done":
			continue
		v.home = null
	var done := {}
	for v in villagers:
		if v.home != null or done.has(v.family):
			continue
		done[v.family] = true
		var fam: Array[Villager] = []
		for o in villagers:
			if o.family == v.family and o.home == null:
				fam.append(o)
		# (a house the family's already in first, then one with room for them all, then any room)
		var best: Building = null
		for b in buildings:
			if b.state != "done" or b.def.role != "house":
				continue
			var free := b.beds() - b.residents.size()
			if free <= 0:
				continue
			var theirs := b.residents.any(func(o: Variant) -> bool: return is_instance_valid(o) and (o as Villager).family == v.family)
			if theirs or free >= fam.size():
				best = b
				break
			if best == null:
				best = b
		if best == null:
			continue
		for o in fam:
			if best.residents.size() < best.beds():
				best.residents.append(o)
				o.home = best


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
