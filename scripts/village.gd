class_name Village
extends Node3D
## The village: what's in store, its buildings, its people, and who does what.
##
## Every so often each villager with nothing to do is given its next plan, first come first:
##   asleep          at night everyone with a house goes home and sleeps till morning
##   a raid          guards go for the bandits, the tower's archer climbs up, the rest run for a
##                   house or the store and hide there till it's over (Raids)
##   a fire          if something's burning and there's a well, buckets from the well to the fire
##   its workplace   a woodcutter fells the nearest tree in reach and carries the wood home, a
##                   quarryman breaks stone off a rock, a gatherer picks a bush (it bears again later);
##                   with carters about and the store far, it piles it by its own door instead
##   carting         a carter takes its handcart (a drover its ox cart) to the biggest pile and
##                   brings it to the store, or carries a cartload to a building site
##   a site          the free ones carry what a building site (or one being mended) still lacks
##                   from the store, then build
##   nothing         it stands about by the store
## Nothing is anywhere but where it lies: each store holds its own goods (`Building.goods`), and
## what's on the top bar (`stock`) is all the stores' together. A store that burns loses what's in
## it; a raided one is plundered. The oxen eat as much as a villager.
## In the cold (and at night) every lived-in house burns firewood, carried to it from the store; a
## house with none left goes cold, and those who sleep in a cold house are worse for it come morning.
## A lit hearth now and then throws a spark onto the roof: more often when it's dry and windy.
## Workplaces take free villagers up to the number asked of them (`wanted`). People eat; with food
## in store and a bed free someone new comes now and then. Fire leaps from a burning building to
## its neighbours, more readily downwind; a lightning strike in a storm can start one.

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
var roads: Array = [] ## the plank roads laid: [ax, az, bx, bz] each
var _rung := {} ## "<day>-<hour>" -> true: the bell's rung for it
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
	var house := _place_near("ev", at + Vector3(13, 0, 3), 0.5)
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


## A plank road laid from `a` to `b` (each 2 m of it a log from the nearest store, unless `free`):
## as far as the wood goes. The metres laid.
func lay_road(a: Vector3, b: Vector3, free := false) -> float:
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := flat.length()
	if length < 0.5:
		return 0.0
	var n := ceili(length / 2.0)
	var laid := 0
	if not free:
		for k in n:
			var s := store_with("odun", a)
			if s == null or s.take_goods("odun", 1) == 0:
				break
			laid += 1
	else:
		laid = n
	if laid == 0:
		return 0.0
	var end := a + flat / length * minf(laid * 2.0, length)
	roads.append([a.x, a.z, end.x, end.z])
	_road_mesh(a, end)
	var cells: Array[Vector2i] = []
	var steps := ceili(a.distance_to(end) / 0.8)
	for k in steps + 1:
		var c := Nav.cell_of(a.lerp(end, float(k) / steps))
		if not c in cells:
			cells.append(c)
	nav.set_road(cells)
	return minf(laid * 2.0, length)


## The planks themselves: laid across the way every 30 cm on two stringers, each lying on the ground
## where it is, one multimesh to a stretch.
func _road_mesh(a: Vector3, b: Vector3) -> void:
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := flat.length()
	var dir := flat / length
	var side := dir.cross(Vector3.UP)
	var count := int(length / 0.3) + 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var board := BoxMesh.new()
	board.size = Vector3(1.8, 0.06, 0.27)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	board.material = m
	mm.mesh = board
	mm.instance_count = count
	for k in count:
		var c := a + dir * (k * 0.3)
		c.y = nav.height(c.x, c.z) + 0.08
		var hl := nav.height(c.x - side.x * 0.8, c.z - side.z * 0.8)
		var hr := nav.height(c.x + side.x * 0.8, c.z + side.z * 0.8)
		var tilt := atan2(hr - hl, 1.6)
		var basis := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.BACK, -tilt) * Basis(Vector3.UP, randf_range(-0.04, 0.04))
		mm.set_instance_transform(k, Transform3D(basis, c))
		var shade := randf_range(0.42, 0.6)
		mm.set_instance_color(k, Color(shade, shade * 0.76, shade * 0.5))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)


func squares() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role == "square":
			out.append(b)
	return out


func bells() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role == "bell":
			out.append(b)
	return out


## Rings every bell tower (`times` strokes).
func ring_bells(times := 3, gap := 1.6) -> void:
	for b in bells():
		b.ring(times, gap)


## The evening: the square's fire lit (it burns the wood brought for it), the bell for the end of work.
func _evenings() -> void:
	var h := weather.hour
	var evening := h >= 18.3 and h < 23.0
	for b in squares():
		var want := evening and int(b.goods.get("odun", 0)) > 0
		if want and not b.lit:
			b.take_goods("odun", 1)
		b.set_fire(evening and (b.lit or want))
	for hour in [6, 19]:
		var key := "%d-%d" % [day, hour]
		if h >= float(hour) and h < float(hour) + 0.5 and not _rung.has(key):
			_rung[key] = true
			ring_bells(3 if hour == 6 else 5)


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

func _process(dt: float) -> void:
	clock += dt
	if _last_hour >= 0.0 and weather.hour < _last_hour:
		day += 1
		message.emit("Gün %d" % day, "info")
	_last_hour = weather.hour
	Building.set_night(clampf(0.35 - weather.sun_direction().y * 5.0, 0.0, 1.0))
	_eat(dt)
	_arrive(dt)
	_grow_saplings(dt)
	_heat_t += dt
	if _heat_t >= 2.0:
		_hearths(_heat_t)
		_evenings()
		_heat_t = 0.0
	if day != _last_day:
		_last_day = day
		_morning()
	_spread_t += dt
	if _spread_t >= 1.0:
		_fires(_spread_t)
		_spread_t = 0.0
	_lightning()
	_assign_t += dt
	if _assign_t >= 0.3:
		_assign_t = 0.0
		_staff()
		_assign()


func _eat(dt: float) -> void:
	if villagers.is_empty():
		return
	_eat_t += dt
	var every := EAT_EVERY / (villagers.size() + oxen())
	while _eat_t >= every:
		_eat_t -= every
		var s := store_with("yiyecek", Vector3.ZERO)
		if s:
			s.take_goods("yiyecek", 1)
	var hungry := int(stock.yiyecek) <= 0
	if hungry and not _hungry:
		message.emit("Yiyecek bitti! Köylüler aç, yavaş çalışıyorlar.", "bad")
	_hungry = hungry
	work_rate = 0.6 if hungry else 1.0


func _arrive(dt: float) -> void:
	_arrive_t += dt
	if _arrive_t < ARRIVE_EVERY:
		return
	_arrive_t = 0.0
	if beds() <= villagers.size() or int(stock.yiyecek) < 8:
		return
	var home := _nearest(stores(), Vector3.ZERO) if stores().size() > 0 else null
	if home == null:
		return
	for k in 20:
		var a := randf() * TAU
		var p := home.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(60.0, 90.0)
		if nav.is_open(p):
			var v := spawn_villager(p, villagers.size() >= 4 and randf() < 0.3)
			var d := home.door()
			v.give([{"t": "go", "to": d + Vector3(randf_range(-3, 3), 0, randf_range(1, 4))}], "Köye geliyor")
			_house_people()
			message.emit("Köye yeni biri geldi (%d kişi)" % villagers.size(), "good")
			return


# --- Hearths ------------------------------------------------------------------------------------

func needs_fire() -> bool:
	return weather.is_night() or weather.temperature < COLD_BELOW


func _hearths(t: float) -> void:
	var want := needs_fire()
	var dry := 1.0 - clampf(weather.wetness + Weather.rain_now, 0.0, 1.0)
	var wind := Weather.wind_now.length()
	var night := weather.is_night() or weather.hour > 19.5 or weather.hour < 5.5
	for b in buildings:
		if b.def.role == "light" and b.state == "done":
			if night:
				b.heat_acc += t / (LOG_EVERY * 3.0)
				while b.heat_acc >= 1.0:
					b.heat_acc -= 1.0
					b.take_goods("odun", 1)
				b.set_lit(int(b.goods.get("odun", 0)) > 0)
				if b.lit and randf() < t * 0.0005 * (0.2 + dry) * (wind / 6.0):
					for o in buildings:
						if o != b and o.global_position.distance_to(b.global_position) < 4.0 + o.radius and o.ignite():
							message.emit("Fenerden sıçrayan kıvılcım %s binasını tutuşturdu!" % o.display_name(), "bad")
							break
			else:
				b.set_lit(false)
			continue
		if b.def.role != "house" or b.state != "done":
			continue
		var lived := not b.residents.is_empty()
		b.set_lit(night and lived and b.warm)
		if not want or not lived:
			b.warm = true
			b.set_hearth(false)
			continue
		b.heat_acc += t / LOG_EVERY * (1.0 + clampf(-weather.temperature / 12.0, 0.0, 1.0)) # (bitter cold: up to twice the wood)
		while b.heat_acc >= 1.0:
			b.heat_acc -= 1.0
			if b.take_goods("odun", 1) == 0:
				b.warm = false
		if int(b.goods.get("odun", 0)) > 0:
			b.warm = true
		b.set_hearth(b.warm)
		if not b.warm and weather.is_night():
			b.cold_night = true
		# A spark onto the roof.
		if b.warm and randf() < t * 0.0006 * (0.2 + dry) * (1.0 + wind / 6.0):
			if b.ignite():
				message.emit("Ocaktan sıçrayan kıvılcım %s damını tutuşturdu!" % b.display_name(), "bad")


func _morning() -> void:
	for v in villagers:
		if v.is_child and day - v.born_day >= 4:
			v.grow_up()
			message.emit("%s büyüdü, artık çalışabilir" % v.display_name, "good")
	var cold := 0
	for b in buildings:
		if b.def.role == "house" and b.cold_night:
			b.cold_night = false
			for v in b.residents:
				if is_instance_valid(v) and not v.dead:
					v.hurt(18.0)
					cold += 1
	if cold > 0:
		message.emit("Gece %d kişi soğuk evde üşüdü. Evlere yakacak odun taşınmalı." % cold, "bad")


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


## Firewood to a house running low, or kindling to a lamp, from the store. False if none needs it
## or there's none.
func _plan_firewood(v: Villager) -> bool:
	if not needs_fire() and weather.hour < 15.0:
		return false
	var best: Building = null
	var bd := INF
	for b in buildings:
		if b.state != "done" or (is_instance_valid(b.pile_claim) and b.pile_claim != v):
			continue
		if b.def.role == "house":
			if b.residents.is_empty() or int(b.goods.get("odun", 0)) >= 3:
				continue
		elif b.def.role == "light":
			if int(b.goods.get("odun", 0)) >= 2:
				continue
		elif b.def.role == "square":
			if int(b.goods.get("odun", 0)) >= 3:
				continue
		else:
			continue
		var d := b.global_position.distance_squared_to(v.position)
		if d < bd:
			bd = d
			best = b
	if best == null:
		return false
	var store := store_with("odun", best.global_position)
	if store == null:
		return false
	if v.idle:
		v.abort()
	var house := best
	house.pile_claim = v
	var n := store.take_goods("odun", mini(v.capacity("odun"), 8 if house.def.role == "house" else 3))
	v.owed = {"res": "odun", "n": n, "store": store}
	var into: Array = _go_in(house, v) if house.def.role == "house" else [{"t": "go", "to": house.door()}]
	var back: Array = _go_out(house, v) if house.def.role == "house" else []
	v.give(_go_in(store, v) + [
		{"t": "do", "f": func() -> bool:
			v.set_carry("odun", n)
			return true}] + _go_out(store, v) + into + [
		{"t": "do", "f": func() -> bool:
			house.pile_claim = null
			v.owed = {}
			v.set_carry("", 0)
			if not is_instance_valid(house) or house.state != "done":
				add_anywhere("odun", n, v.position)
				return true
			house.add_goods("odun", n)
			return true}] + back,
		("Yakacak taşıyor: %s" % house.display_name()) if house.def.role == "house" else "Fenere çıra götürüyor", house)
	return true


# --- Fire --------------------------------------------------------------------------------------------

func _fires(t: float) -> void:
	var wind := Weather.wind_now
	for b in buildings:
		if not b.is_burning():
			_burning.erase(b)
			continue
		if not _burning.has(b):
			_burning[b] = true
			message.emit("Yangın! %s yanıyor" % b.display_name(), "bad")
			if b.def.role == "store" and b.goods_total() > 0:
				message.emit("Ambar yanıyor: içindekiler kül oluyor!", "bad")
		var n := b.burning_count()
		if b.def.role in ["store", "work"]:
			for k: String in b.goods:
				var lost := int(ceil(float(b.goods[k]) * 0.0015 * mini(n, 8) * t))
				b.take_goods(k, lost)
		for o in buildings:
			if o == b or o.state == "gone" or o.is_burning():
				continue
			var gap := b.global_position.distance_to(o.global_position) - b.radius - o.radius
			if gap > 5.0:
				continue
			var dir := (o.global_position - b.global_position).normalized()
			var downwind := clampf(Vector2(wind.x, wind.z).dot(Vector2(dir.x, dir.z)) / 6.0, -0.5, 1.5)
			var chance := 0.0035 * mini(n, 8) * (1.0 + downwind) * clampf(1.0 - gap / 5.0, 0.15, 1.0) * (1.0 - Weather.rain_now * 0.7) * t
			if randf() < chance and o.ignite():
				message.emit("Yangın %s binasına sıçradı!" % o.display_name(), "bad")


func _lightning() -> void:
	var f := weather.lightning_flash
	if f > 0.7 and _last_flash <= 0.7 and randf() < 0.3:
		var can: Array[Building] = []
		for b in buildings:
			if b.state == "done":
				can.append(b)
		if not can.is_empty():
			var b: Building = can[randi() % can.size()]
			if b.ignite():
				message.emit("Yıldırım düştü! %s tutuştu" % b.display_name(), "bad")
	_last_flash = f


# --- Giving out work ------------------------------------------------------------------------------

## Workplaces take free villagers up to what's asked, and give back the ones over it.
func _staff() -> void:
	for b in buildings:
		if not b.def.role in ["work", "barracks", "tower", "carts", "oxen", "farm", "forest"]:
			continue
		if b.state != "done":
			continue
		while b.workers.size() > b.wanted:
			var v: Villager = b.workers.pop_back()
			_unstaff(v)
			v.abort()
		while b.workers.size() < b.wanted:
			var pick: Villager = null
			var bd := INF
			for v in villagers:
				if v.workplace == null and (v.plan.is_empty() or v.idle) and not v.sleeping and not v.is_child:
					var d := v.position.distance_squared_to(b.global_position)
					if d < bd:
						bd = d
						pick = v
			if pick == null:
				break
			if pick.idle:
				pick.abort()
			employ(pick, b)


## `v` to work at `b`, with what the work takes in hand.
func employ(v: Villager, b: Building) -> void:
	var pick := v
	pick.workplace = b
	b.workers.append(pick)
	match str(b.def.role):
		"barracks":
			pick.fighter = true
			pick.max_hp = 110.0
			pick.hp = 110.0
			pick.attack = 30.0
			pick.ranged = 32.0
			pick.arm_with("rifle")
		"tower":
			pick.arm_with("rifle")
		"carts":
			pick.give_cart(true)
		"oxen":
			pick.give_ox(true)


## `v` put to work at `b` by hand (the player's choice). Why not, if it can't be ("" if done).
func assign(v: Villager, b: Building) -> String:
	if v.is_child:
		return "%s daha çocuk" % v.display_name
	if not b.def.role in ["work", "farm", "forest", "carts", "oxen", "barracks", "tower"]:
		return "%s bir işyeri değil" % b.display_name()
	if b.state != "done":
		return "%s henüz bitmedi" % b.display_name()
	if v.workplace == b:
		return "%s zaten burada çalışıyor" % v.display_name
	if b.workers.size() >= int(b.def.slots):
		return "%s dolu (%d kişi)" % [b.display_name(), int(b.def.slots)]
	if is_instance_valid(v.workplace):
		v.workplace.workers.erase(v)
		v.workplace.wanted = maxi(0, v.workplace.wanted - 1)
	_unstaff(v)
	v.abort()
	b.wanted = maxi(b.wanted, b.workers.size() + 1)
	employ(v, b)
	return ""


## `v` taken off its work by hand: free to carry and build.
func free_from_work(v: Villager) -> void:
	if not is_instance_valid(v.workplace):
		return
	var b := v.workplace
	b.workers.erase(v)
	b.wanted = maxi(0, b.wanted - 1)
	_unstaff(v)
	v.abort()


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


func _assign() -> void:
	var night := weather.is_night()
	var fires: Array[Building] = []
	for b in buildings:
		if b.is_burning() and b.state != "gone":
			fires.append(b)
	var raid := raids != null and raids.threat()
	for v in villagers:
		if v.dead:
			continue
		if v.sleeping:
			var cover := v.inside
			var unsafe := not is_instance_valid(cover) or cover.state != "done" or cover.is_burning()
			if unsafe or (v.hiding and not raid) or (not v.hiding and not night and not raid):
				v.wake()
			continue
		if raid and _plan_raid(v):
			continue
		if not fires.is_empty() and (v.plan.is_empty() or v.idle) and _plan_fire(v, fires):
			continue
		if not v.plan.is_empty() and not (v.idle and v.workplace == null and _site_needs_hands()):
			continue
		var meal := _meal_key()
		if meal != "" and v.meal_key != meal and (v.plan.is_empty() or v.idle) and not raid:
			_plan_meal(v, meal)
			continue
		if night and is_instance_valid(v.home) and v.home.state == "done":
			_plan_home(v)
			continue
		if v.workplace:
			if v.workplace.state == "done":
				_plan_work(v)
			continue
		if v.is_child:
			if v.plan.is_empty():
				_plan_play(v)
			continue
		if _plan_haul(v) or _plan_build(v) or _plan_firewood(v):
			continue
		if v.plan.is_empty():
			_plan_idle(v)


## In a raid: a guard goes for the nearest bandit, the archer climbs its tower, anyone else near one
## runs and hides. False if the raid asks nothing of it just now.
func _plan_raid(v: Villager) -> bool:
	var role := str(v.workplace.def.role) if v.workplace else ""
	if role == "barracks":
		if not v.plan.is_empty() and str(v.plan[0].t) == "fight":
			return true
		var foe := raids.nearest_raider(v.position, 260.0, true)
		if foe == null or foe.position.distance_to(v.workplace.global_position) > 260.0:
			return false # (nothing it can see: it keeps its watch)
		v.abort()
		v.give([{"t": "fight", "foe": foe, "give_up": 80.0}], "Çarpışıyor")
		return true
	if role == "tower":
		return v.perched != null or not v.plan.is_empty()
	if v.job == "Saklanıyor" and not v.plan.is_empty():
		return true
	var near := raids.nearest_raider(v.position, 600.0 if not bells().is_empty() else 35.0)
	if near == null:
		return false
	var shelters: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role in ["house", "store", "barracks"] and not b.is_burning():
			shelters.append(b)
	var to := _nearest(shelters, v.position)
	v.abort()
	if to == null:
		var away := (v.position - near.position).normalized() * 40.0
		v.give([{"t": "go", "to": v.position + away}], "Kaçıyor")
		return true
	v.give(_go_in(to) + [{"t": "do", "f": func() -> bool:
		if is_instance_valid(to) and to.state == "done" and not to.is_burning():
			v.sleep_in(to, true)
		return true}], "Saklanıyor", to)
	return true


func _site_needs_hands() -> bool:
	for b in buildings:
		if not b.under_work():
			continue
		if b.can_work():
			return true
		for r: String in b.cost:
			if b.missing(r) > 0 and int(stock.get(r, 0)) > 0:
				return true
	return false


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


func _plan_home(v: Villager) -> void:
	var h := v.home
	if v.idle:
		v.abort()
	v.give(_go_in(h) + [{"t": "do", "f": func() -> bool:
		if is_instance_valid(h) and h.state == "done" and not h.is_burning():
			v.sleep_in(h)
		return true}], "Eve gidiyor", h)


## Nothing to do: a while spent as people spend it. A word with someone else standing about, a sit
## on the ground, a stretch, a look round, a stroll.
func _plan_idle(v: Villager) -> void:
	# Of an evening, round the fire on the square.
	var sq := _nearest(squares(), v.position)
	if sq and sq.lit and sq.global_position.distance_to(v.position) < 200.0 and randf() < 0.8:
		var a := randf() * TAU
		var seat := sq.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.2, 3.2)
		seat.y = ground_at(seat)
		v.give([{"t": "go", "to": sq.door()}, {"t": "step", "to": seat},
			{"t": "work", "time": randf_range(15.0, 30.0), "anim": "sit" if randf() < 0.6 else "chat", "face": sq.global_position + Vector3.UP},
			{"t": "step", "to": sq.door()}], "Meydanda, ateş başında", sq, true)
		return
	var near: Building = v.workplace if v.workplace else _nearest(stores(), v.position)
	var at := near.door() if near else v.position
	var p := at + Vector3(randf_range(-6, 6), 0, randf_range(1.5, 7))
	# Someone else standing about near: go over and talk.
	for o in villagers:
		if o == v or o.dead or o.sleeping or not o.idle or o.job == "Sohbet ediyor":
			continue
		if o.position.distance_to(v.position) < 14.0 and randf() < 0.6:
			var meet := (v.position + o.position) * 0.5
			var dir := (o.position - v.position)
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.1 else Vector3.RIGHT
			var talk := randf_range(7.0, 13.0)
			v.give([{"t": "go", "to": meet - dir * 0.6}, {"t": "work", "time": talk, "anim": "chat", "face": meet + dir}], "Sohbet ediyor", null, true)
			o.give([{"t": "go", "to": meet + dir * 0.6}, {"t": "work", "time": talk, "anim": "chat", "face": meet - dir}], "Sohbet ediyor", null, true)
			return
	var roll := randf()
	var what: Array
	if roll < 0.35:
		what = [{"t": "go", "to": p}, {"t": "work", "time": randf_range(8.0, 15.0), "anim": "sit"}]
	elif roll < 0.5:
		what = [{"t": "go", "to": p}, {"t": "work", "time": 2.5, "anim": "stretch"}, {"t": "work", "time": randf_range(3.0, 6.0), "anim": "idle"}]
	elif roll < 0.75:
		what = [{"t": "go", "to": p}, {"t": "work", "time": randf_range(4.0, 8.0), "anim": "look"}]
	else:
		what = [{"t": "go", "to": p}, {"t": "work", "time": randf_range(2.0, 5.0), "anim": "idle"}, {"t": "go", "to": at + Vector3(randf_range(-8, 8), 0, randf_range(1.5, 9))}]
	v.give(what, "Boşta", null, true)


## A child at play: running about near home, after the other children if there are any.
func _plan_play(v: Villager) -> void:
	var near: Building = v.home if is_instance_valid(v.home) else _nearest(stores(), v.position)
	var at := near.door() if near else v.position
	var other: Villager = null
	for o in villagers:
		if o != v and o.is_child and not o.sleeping and o.position.distance_to(v.position) < 25.0:
			other = o
	var to := (other.position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))) if other and randf() < 0.6 else at + Vector3(randf_range(-7, 7), 0, randf_range(1, 8))
	v.give([{"t": "go", "to": to}, {"t": "work", "time": randf_range(1.0, 3.0), "anim": "chat" if other else "look"}], "Oynuyor", null, true)


## Lunch about noon, supper before dark: once each, at home if it's near (in through the door, a
## while inside), or else sat down where it is with a bowl.
func _meal_key() -> String:
	var h := weather.hour
	if h >= 12.0 and h < 13.2:
		return "%d-o" % day
	if h >= 18.0 and h < 19.2:
		return "%d-a" % day
	return ""


func _plan_meal(v: Villager, key: String) -> void:
	v.meal_key = key
	if v.idle:
		v.abort()
	var h := v.home
	if is_instance_valid(h) and h.state == "done" and not h.is_burning() and h.global_position.distance_to(v.position) < 120.0:
		v.give(_go_in(h) + [{"t": "do", "f": func() -> bool:
			v.visible = false
			return true}, {"t": "work", "time": randf_range(10.0, 15.0), "anim": "idle"}, {"t": "do", "f": func() -> bool:
			v.visible = true
			return true}] + _go_out(h), "Evde yemek yiyor", h)
	else:
		v.give([{"t": "work", "time": randf_range(10.0, 15.0), "anim": "eat"}], "Yemek yiyor", null)


## Carry what a site still lacks from the store. False if no site needs anything there's some of.
func _plan_haul(v: Villager) -> bool:
	var best: Building = null
	var best_r := ""
	var bd := INF
	var have := stock
	for b in buildings:
		if not b.under_work():
			continue
		for r: String in b.cost:
			if b.missing(r) > 0 and int(have.get(r, 0)) > 0:
				var d := b.global_position.distance_squared_to(v.position)
				if d < bd:
					bd = d
					best = b
					best_r = r
	if best == null:
		return false
	var store := store_with(best_r, best.global_position)
	if store == null:
		return false
	if v.idle:
		v.abort()
	var cap := v.capacity(best_r)
	var n := store.take_goods(best_r, mini(best.missing(best_r), cap))
	best.incoming[best_r] = int(best.incoming[best_r]) + n
	v.owed = {"site": best, "res": best_r, "n": n, "store": store}
	var site := best
	var r := best_r
	v.give(_go_in(store, v) + [
		{"t": "do", "f": func() -> bool:
			v.set_carry(r, n)
			return site.under_work()}] + _go_out(store, v) + [
		{"t": "go", "to": site.stack_at() if site.state == "site" else _spot_by(site, v.position)},
		{"t": "do", "f": func() -> bool:
			if not site.under_work():
				return false
			site.incoming[r] = int(site.incoming[r]) - n
			if site.state == "site":
				site.deliver(r, n) # (onto the stack at its corner)
				if r == "odun":
					Ambience.log_drop(v.position)
			else:
				site.delivered[r] = int(site.delivered[r]) + n
			v.owed = {}
			v.set_carry("", 0)
			return true},
	], "Taşıyor: %s" % site.display_name(), site)
	return true


## Build at a site whose stuff has come. False if there's none.
func _plan_build(v: Villager) -> bool:
	var best: Building = null
	var bd := INF
	for b in buildings:
		if not b.can_work():
			continue
		var n := 0
		for o in villagers:
			if o.target == b and o.job.begins_with("İnşa"):
				n += 1
		if n >= BUILDERS_PER_SITE:
			continue
		var d := b.global_position.distance_squared_to(v.position)
		if d < bd:
			bd = d
			best = b
	if best == null:
		return false
	if v.idle:
		v.abort()
	var site := best
	if site.state == "repair":
		v.give([
			{"t": "go", "to": _spot_by(site, v.position)},
			{"t": "work", "anim": "build", "face": site.global_position, "tick": func(dt: float) -> bool: return site.add_work(dt)},
		], "Onarıyor: %s" % site.display_name(), site)
		return true
	# A piece off the stack, carried to its place (up the scaffold if it's high), set there.
	var i := site.claim(v)
	if i < 0:
		return false
	var piece = site.pieces[i]
	var spot := site.work_spot(i)
	var at: Vector3 = spot.at
	var level: float = spot.level
	# An armful: up to three more pieces going up beside it, at the same height, in the same trip.
	var batch: Array[int] = [i]
	while batch.size() < 4:
		var j := site.claim(v)
		if j < 0:
			break
		var sj := site.work_spot(j)
		if (sj.at as Vector3).distance_to(at) > 2.5 or float(sj.level) != level:
			site.unclaim_one(j)
			break
		batch.append(j)
	var looks := "tas" if piece.res == "tas" else "odun"
	var steps: Array = [
		{"t": "go", "to": site.stack_at()},
		{"t": "work", "time": 0.9, "anim": "gather", "face": site.global_transform * (site._stack_spot())},
		{"t": "do", "f": func() -> bool:
			v.set_carry(looks, 1)
			return site.state == "site"},
		{"t": "go", "to": at},
	]
	if level > 0.0:
		steps.append({"t": "do", "f": func() -> bool:
			v.climb(site.global_position.y + level)
			return true})
		steps.append({"t": "work", "time": 0.9, "anim": "climb"})
	for k in batch.size():
		var j: int = batch[k]
		steps.append({"t": "work", "time": randf_range(0.5, 0.85), "anim": "build", "face": site.work_spot(j).face})
		steps.append({"t": "do", "f": func() -> bool:
			if k == batch.size() - 1:
				v.set_carry("", 0)
			if is_instance_valid(site):
				site.place(j, v.global_position)
			return true})
	if level > 0.0:
		steps.append({"t": "do", "f": func() -> bool:
			v.climb(ground_at(v.position))
			return true})
		steps.append({"t": "work", "time": 0.8, "anim": "climb"})
	v.give(steps, "İnşa: %s (%s)" % [site.display_name(), site.stage_name().to_lower()], site)
	return true


## A place to stand by a building, on the side toward `from`.
func _spot_by(b: Building, from: Vector3) -> Vector3:
	var d := from - b.global_position
	d.y = 0.0
	if d.length() < 0.1:
		d = Vector3.BACK
	var p := b.global_position + d.normalized() * (b.radius + 1.2) + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	p.y = nav.height(p.x, p.z)
	return p


func _plan_fire(v: Villager, fires: Array[Building]) -> bool:
	var fire: Building = null
	var fd := INF
	for b in fires:
		var d := b.global_position.distance_to(v.position)
		if d < fd and d < 220.0:
			fd = d
			fire = b
	if fire == null:
		return false
	var wells: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role == "well":
			wells.append(b)
	var well := _nearest(wells, fire.global_position)
	if well == null or well.global_position.distance_to(fire.global_position) > 160.0:
		if not _no_well_said:
			_no_well_said = true
			message.emit("Yakında kuyu yok: yangın söndürülemiyor!", "bad")
		return false
	_no_well_said = false
	if v.idle or not v.plan.is_empty():
		v.abort()
	v.give([
		{"t": "go", "to": well.door()},
		{"t": "work", "time": 1.4, "anim": "draw", "face": well.global_position},
		{"t": "do", "f": func() -> bool:
			v.set_carry("su", 1)
			return is_instance_valid(fire) and fire.is_burning()},
		{"t": "go", "to": _spot_by(fire, v.position)},
		{"t": "work", "time": 1.1, "anim": "throw", "face": fire.global_position},
		{"t": "do", "f": func() -> bool:
			v.set_carry("", 0)
			if is_instance_valid(fire):
				fire.douse()
			return true},
	], "Yangın söndürüyor", fire)
	return true


## A worker's next round: out to what its workplace works, and back to the store with it.
func _plan_work(v: Villager) -> void:
	var b := v.workplace
	if b.def.role == "tower":
		v.give([{"t": "go", "to": b.door()}, {"t": "do", "f": func() -> bool:
			v.perch_on(b)
			return true},
			{"t": "work", "anim": "aim", "tick": func(_dt: float) -> bool:
				return v.workplace == b and b.state == "done" and (not weather.is_night() or (raids and raids.threat()))},
			{"t": "do", "f": func() -> bool:
				v.get_down()
				return true}], "Gözcü kulesinde", b)
		return
	if b.def.role == "barracks":
		var p := b.door() + Vector3(randf_range(-7, 7), 0, randf_range(1, 8))
		v.give([{"t": "go", "to": p}, {"t": "work", "time": randf_range(5.0, 12.0), "anim": "idle"}], "Nöbette", b, true)
		return
	if b.def.role in ["carts", "oxen"]:
		_plan_cart(v)
		return
	if b.def.role == "farm":
		_plan_farm(v, b)
		return
	if b.def.role == "forest":
		_plan_forest(v, b)
		return
	var res := str(b.def.res)
	var store := _nearest(stores(), b.global_position)
	if store == null:
		b.idle_note = "Depo yok"
		_plan_idle(v)
		return
	# The pile's grown and nobody fetches it: a load of it to the store first.
	if not carters_about() and b.goods_total() >= 9:
		var n := b.take_goods(res, v.capacity(res))
		if n > 0:
			v.give([{"t": "go", "to": b.door()}, {"t": "step", "to": b.station()},
				{"t": "work", "time": 1.2, "anim": "gather", "face": b.global_transform * b.def.get("pile", Vector3.ZERO)},
				{"t": "do", "f": func() -> bool:
					v.set_carry(res, n)
					return true},
				{"t": "step", "to": b.door()}] + _go_in(store, v) + [
				{"t": "do", "f": func() -> bool:
					if is_instance_valid(store) and store.state == "done":
						store.add_goods(res, v.carry_n)
					else:
						add_anywhere(res, v.carry_n, v.position)
					v.set_carry("", 0)
					return true}] + _go_out(store, v), "%s: depoya taşıyor" % b.display_name(), b)
			return
	# Logs lying from a tree already down: one fetched and sawn.
	if res == "odun":
		var bl := _billet_for(b)
		if not bl.is_empty():
			bl.claimed = v
			var at: Vector3 = (bl.node as Node3D).global_position
			v.give([{"t": "go", "to": at + (b.global_position - at).normalized() * 0.9},
				{"t": "work", "time": 1.4, "anim": "gather", "face": at},
				{"t": "do", "f": func() -> bool:
					if is_instance_valid(bl.node):
						(bl.node as Node).queue_free()
					billets.erase(bl)
					v.set_carry("odun", BILLET_WOOD)
					Ambience.log_drop(v.position)
					return true}] + _work_at(b, v, res), "%s: tomruk taşıyor" % b.display_name(), b)
			return
	var kind: String = {"odun": "tree", "tas": "rock", "yiyecek": "bush"}[res]
	var i := find_prop(b.global_position, float(b.def.reach), kind)
	if i < 0:
		b.idle_note = {"odun": "Yakında ağaç kalmadı", "tas": "Yakında kaya kalmadı", "yiyecek": "Kışın çalılar yemiş vermez" if seasons and seasons.winter() else "Yakında yemiş kalmadı"}[res]
		_plan_idle(v)
		return
	b.idle_note = ""
	reserved[i] = v
	var info := props.prop_info(i)
	var o: Vector3 = info.origin
	var away := Vector3(v.position.x - o.x, 0, v.position.z - o.z)
	if away.length() < 0.1:
		away = Vector3.BACK
	var spot := o + away.normalized() * (float(info.radius) + 0.75)
	spot.y = nav.height(spot.x, spot.z)
	var steps: Array = [{"t": "go", "to": spot}]
	match res:
		"odun":
			# Felled, limbed where it lies, bucked into logs; the first log shouldered.
			var info2 := props.tree_info(i)
			var fall := Vector3(o.x - spot.x, 0, o.z - spot.z).normalized()
			var trunk_mid: Vector3 = o + fall * float(info2.height) * 0.45
			var side := fall.cross(Vector3.UP).normalized()
			var limb_at := trunk_mid + side * (float(info2.radius) + 0.8)
			limb_at.y = nav.height(limb_at.x, limb_at.z)
			steps.append({"t": "work", "time": 7.0, "anim": "chop", "face": o})
			steps.append({"t": "do", "f": func() -> bool:
				reserved.erase(i)
				if props.cut.has(i):
					return false
				fell_tree(i, fall)
				return true})
			steps.append({"t": "work", "time": 3.0, "anim": "idle", "face": trunk_mid}) # (watching it come down)
			steps.append({"t": "go", "to": limb_at})
			steps.append({"t": "work", "time": 4.0, "anim": "limb", "face": trunk_mid})
			steps.append({"t": "work", "time": 3.0, "anim": "saw", "face": trunk_mid})
			steps.append({"t": "do", "f": func() -> bool:
				_buck(i, o, fall, float(info2.height), float(info2.radius), b)
				var bl := _billet_for(b, v.position)
				if not bl.is_empty():
					if is_instance_valid(bl.node):
						(bl.node as Node).queue_free()
					billets.erase(bl)
				v.set_carry("odun", BILLET_WOOD)
				return true})
		"tas":
			steps.append({"t": "work", "time": 8.0, "anim": "mine", "face": o})
			steps.append({"t": "do", "f": func() -> bool:
				reserved.erase(i)
				if props.cut.has(i):
					return false
				var left := int(rock_left.get(i, 15)) - 3
				rock_left[i] = left
				if left <= 0:
					props.cut_tree(i)
				v.set_carry("tas", 3)
				return true})
		"yiyecek":
			steps.append({"t": "work", "time": 5.0, "anim": "gather", "face": o})
			steps.append({"t": "do", "f": func() -> bool:
				reserved.erase(i)
				bush_rest[i] = clock + 240.0
				v.set_carry("yiyecek", 3)
				return true})
	# What's gathered is brought to the yard and worked there: sawn, dressed, sorted; it's piled there.
	steps.append_array(_work_at(b, v, res))
	v.give(steps, "%s: %s" % [b.display_name(), {"odun": "ağaç kesiyor", "tas": "taş kırıyor", "yiyecek": "yemiş topluyor"}[res]], b)


## Back to the yard with what's carried, worked at its station (sawn on the trestles, dressed on
## the bench, sorted on the table), piled there, and out the front.
func _work_at(b: Building, v: Villager, res: String) -> Array:
	var how := str(b.def.get("work", "gather"))
	return [{"t": "go", "to": b.door()}, {"t": "step", "to": b.station()},
		{"t": "work", "time": {"saw": 5.0, "chisel": 5.0}.get(how, 2.5), "anim": how, "face": b.station_face()},
		{"t": "do", "f": func() -> bool:
			if v.carry_n > 0:
				if res == "odun":
					Ambience.log_drop(v.position)
				if is_instance_valid(b) and b.state == "done":
					b.add_goods(res, v.carry_n)
				else:
					add_anywhere(res, v.carry_n, v.position)
			v.set_carry("", 0)
			return true},
		{"t": "step", "to": b.door()}]


## The nearest log lying for camp `b` (or for no camp left standing) not already being fetched.
func _billet_for(b: Building, near := Vector3.INF) -> Dictionary:
	var at := b.global_position if near == Vector3.INF else near
	var best := {}
	var bd := INF
	for bl in billets:
		if is_instance_valid(bl.claimed) or not is_instance_valid(bl.node):
			continue
		if bl.camp != b and is_instance_valid(bl.camp) and (bl.camp as Building).state != "gone":
			continue
		var d := (bl.node as Node3D).global_position.distance_to(at)
		if d < bd:
			bd = d
			best = bl
	return best


## The fallen tree bucked where it lies: its crown and branches lopped off (left as slash that
## rots away), its trunk sawn into logs along where it fell, for its camp to fetch.
func _buck(i: int, base: Vector3, fall: Vector3, height: float, radius: float, camp: Building) -> void:
	for n: Node in get_children():
		if n.has_meta("felled") and int(n.get_meta("felled")) == i:
			n.queue_free()
	var count := clampi(int(height / 4.0), 2, 5)
	for k in count:
		var c := base + fall * (1.4 + k * 2.1)
		c.y = nav.height(c.x, c.z) + radius * 0.95
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius * 0.95
		cm.bottom_radius = radius
		cm.height = 1.9
		cm.radial_segments = 10
		mi.mesh = cm
		mi.material_override = Building.material("log")
		add_child(mi)
		mi.global_transform = Transform3D(Basis.looking_at(fall, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), c)
		billets.append({"node": mi, "camp": camp, "claimed": null})
	# the slash: a few branches where the crown came down, rotting away after a while
	var slash := StandardMaterial3D.new()
	slash.albedo_color = Color(0.2, 0.27, 0.13)
	for k in 6:
		var at := base + fall * (height * randf_range(0.6, 0.95)) + fall.cross(Vector3.UP) * randf_range(-1.5, 1.5)
		at.y = nav.height(at.x, at.z) + 0.15
		var br := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.02
		bm.bottom_radius = 0.05
		bm.height = randf_range(1.0, 2.0)
		bm.radial_segments = 5
		br.mesh = bm
		br.material_override = slash
		add_child(br)
		br.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5 + randf_range(-0.2, 0.2)), at)
		var tw := br.create_tween()
		tw.tween_interval(randf_range(60.0, 90.0))
		tw.tween_property(br, "position:y", at.y - 0.4, 8.0)
		tw.tween_callback(br.queue_free)


## A farmer's next stint: sow the field, hoe it while it grows, reap it when it's ripe and carry
## the sheaves home (or pile them by the field, with carters about).
func _plan_farm(v: Villager, b: Building) -> void:
	var c := b.crop
	if c == null or c.burning > 0.0:
		_plan_idle(v)
		return
	match c.stage:
		"fallow", "sowing":
			b.idle_note = ""
			v.give([{"t": "go", "to": c.spot()}, {"t": "work", "time": 4.0, "anim": "sow", "done": func() -> void:
				if is_instance_valid(c):
					c.sow(0.1)}], "Tarla: ekiyor", b)
		"growing":
			b.idle_note = "Ekin büyüyor: %%%d" % int(c.growth * 100.0)
			v.give([{"t": "go", "to": c.spot()}, {"t": "work", "time": 6.0, "anim": "hoe", "done": func() -> void:
				if is_instance_valid(c):
					c.tend()}], "Tarla: çapalıyor", b, true)
		"ripe":
			b.idle_note = "Hasat: %d yiyecek kaldı" % c.left()
			var store := _nearest(stores(), b.global_position)
			var pile := store == null or (carters_about() and b.global_position.distance_to(store.global_position) > PILE_FROM)
			var drop_at: Building = b if pile else store
			v.give([
				{"t": "go", "to": c.spot()},
				{"t": "work", "time": 4.0, "anim": "reap"},
				{"t": "do", "f": func() -> bool:
					if not is_instance_valid(c):
						return false
					var n := c.reap(6)
					if n <= 0:
						return false
					v.set_carry("yiyecek", n)
					return true},
			] + (_go_in(drop_at, v) if drop_at != b else [{"t": "go", "to": drop_at.door() + Vector3(randf_range(-2, 2), 0, randf_range(0, 2))}]) + [
				{"t": "do", "f": func() -> bool:
					if v.carry_n > 0:
						if is_instance_valid(drop_at) and drop_at.state == "done":
							drop_at.add_goods(v.carry_res, v.carry_n)
						else:
							add_anywhere(v.carry_res, v.carry_n, v.position)
					v.set_carry("", 0)
					return true},
			] + (_go_out(drop_at, v) if drop_at != b else []), "Tarla: biçiyor", b)


## A carter's next run: a cartload to a building site, else the biggest pile to the store.
func _plan_cart(v: Villager) -> void:
	if _plan_haul(v) or _plan_firewood(v):
		return
	var best: Building = null
	var most := 3
	for b in buildings:
		if not b.def.role in ["work", "farm"] or b.state == "gone":
			continue
		if is_instance_valid(b.pile_claim) and b.pile_claim != v:
			continue
		var n := b.goods_total()
		if n > most:
			most = n
			best = b
	if best == null:
		_plan_idle(v)
		v.job = "Arabacı: bekliyor" if v.vehicle == "hand" else "Öküz arabası: bekliyor"
		return
	var store := _nearest(stores(), best.global_position)
	if store == null:
		_plan_idle(v)
		return
	best.pile_claim = v
	var from := best
	v.give([
		{"t": "go", "to": from.door() + Vector3(1.5, 0, 0.5)},
		{"t": "work", "time": 2.0, "anim": "gather", "face": from.global_position},
		{"t": "do", "f": func() -> bool:
			from.pile_claim = null
			var res := ""
			var top := 0
			for k: String in from.goods:
				if int(from.goods[k]) > top:
					top = int(from.goods[k])
					res = k
			if res == "":
				return false
			v.set_carry(res, from.take_goods(res, v.capacity(res)))
			return true},
		{"t": "go", "to": store.door() + Vector3(randf_range(-2, 2), 0, randf_range(0.5, 2))},
		{"t": "do", "f": func() -> bool:
			if v.carry_n > 0:
				if is_instance_valid(store) and store.state == "done":
					store.add_goods(v.carry_res, v.carry_n)
				else:
					add_anywhere(v.carry_res, v.carry_n, v.position)
			v.set_carry("", 0)
			return true},
	], "%s: %s yığınını taşıyor" % ["Arabacı" if v.vehicle == "hand" else "Öküz arabası", from.display_name()], from)


## The nearest standing prop of `kind` ("tree", "rock", "bush") within `reach` of `p` that no one's
## going for (a bush not resting), on ground a villager can get to.
func find_prop(p: Vector3, reach: float, kind: String) -> int:
	var best := -1
	var bd := INF
	for i in _props_in(p, reach):
		if reserved.has(i):
			continue
		if str(props._models[props._kind[i]].kind) != kind:
			continue
		if kind == "bush" and (float(bush_rest.get(i, -1.0)) > clock or (seasons and seasons.winter())):
			continue
		var o: Vector3 = props._xf[i].origin
		if not nav.is_open(o + Vector3(1.2, 0, 0)) and not nav.is_open(o - Vector3(1.2, 0, 0)):
			continue
		if absf(terrain.height_at(o.x, o.z) - o.y) > 3.0:
			continue
		var d := Vector2(o.x - p.x, o.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


## The tree comes down away from the axe, hinged at its foot, and lies a while; a stump stays.
func fell_tree(i: int, away: Vector3) -> void:
	var info := props.tree_info(i)
	var mesh := props.felled_mesh(i)
	props.cut_tree(i)
	var o: Vector3 = info.origin
	Ambience.play("tree_crack", o + Vector3.UP * 2.0, 2.0)
	var land := o + Vector3(away.x, 0, away.z).normalized() * float(info.height) * 0.5
	get_tree().create_timer(2.5).timeout.connect(func() -> void: Ambience.play("tree_fall", land, 4.0))
	var pivot := Node3D.new()
	pivot.set_meta("felled", i)
	add_child(pivot)
	pivot.global_position = o + Vector3.UP * 0.4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(info.basis, Vector3.DOWN * 0.4)
	pivot.add_child(mi)
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.RIGHT
	var axis := Vector3.UP.cross(away.normalized()).normalized()
	var tw := pivot.create_tween()
	tw.tween_property(pivot, "quaternion", Quaternion(axis, PI * 0.47), 2.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(pivot, "quaternion", Quaternion(axis, PI * 0.5), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(25.0)
	tw.tween_property(pivot, "position:y", pivot.position.y - 2.0, 5.0)
	tw.tween_callback(pivot.queue_free)
	add_stump(o + Vector3.UP * 0.2, float(info.radius) * 1.15, i)


func add_stump(at: Vector3, r: float, prop := -1) -> void:
	var stump := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * 1.2
	c.height = 0.7
	c.radial_segments = 9
	stump.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.22, 0.15)
	m.roughness = 0.95
	stump.material_override = m
	stump.position = at
	stump.set_meta("prop", prop)
	_stumps.add_child(stump)


## A sapling on the stump of tree `i`; in SAPLING_TIME (or `left`) it's the tree again.
func plant(i: int, left := SAPLING_TIME) -> void:
	if saplings.has(i) or not props.cut.has(i):
		return
	# The very tree that stood there, small: the same kind, turned the same way, grown up into it.
	var info := props.tree_info(i)
	var n := Node3D.new()
	add_child(n)
	n.position = info.origin
	var young := MeshInstance3D.new()
	young.mesh = props.felled_mesh(i)
	young.basis = info.basis
	n.add_child(young)
	saplings[i] = {"node": n, "left": left}
	_grow_one(i, 0.0)


func _grow_one(i: int, dt: float) -> void:
	var s: Dictionary = saplings[i]
	s.left = float(s.left) - dt
	var k := 1.0 - clampf(float(s.left) / SAPLING_TIME, 0.0, 1.0)
	(s.node as Node3D).scale = Vector3.ONE * lerpf(0.06, 1.0, k * k * (3.0 - 2.0 * k)) # (slow at first, then shooting up)
	if float(s.left) <= 0.0:
		(s.node as Node3D).queue_free()
		saplings.erase(i)
		props.regrow(i)
		for st: Node in _stumps.get_children():
			if int(st.get_meta("prop", -1)) == i:
				st.queue_free()


func _grow_saplings(dt: float) -> void:
	for i: int in saplings.keys():
		_grow_one(i, dt)


## A forester's next stint: a sapling on the nearest stump in reach without one.
func _plan_forest(v: Villager, b: Building) -> void:
	var best := -1
	var bd := float(b.def.reach)
	var at := Vector3.ZERO
	for st: Node3D in _stumps.get_children():
		var i := int(st.get_meta("prop", -1))
		if i < 0 or saplings.has(i) or reserved.has(i) or not props.cut.has(i):
			continue
		var d := st.position.distance_to(b.global_position)
		if d < bd:
			bd = d
			best = i
			at = st.position
	if best < 0:
		b.idle_note = "Yakında dikilecek kütük yok"
		_plan_idle(v)
		return
	b.idle_note = ""
	reserved[best] = v
	var i := best
	var spot := at + (v.position - at).normalized() * 1.0
	v.give([
		{"t": "go", "to": spot},
		{"t": "work", "time": 5.0, "anim": "dig", "face": at},
		{"t": "do", "f": func() -> bool:
			reserved.erase(i)
			plant(i)
			return true},
	], "Ormancı: fidan dikiyor", b)
