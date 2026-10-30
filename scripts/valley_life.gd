class_name ValleyLife
extends Node
## The valley changes under you, so the same road isn't the same drive twice:
##
##   the mud     soaks with the rain and dries in the sun (Weather.wetness): its rut depth, how fast a
##               wheel sinks and digs in and how it drags all go with it (SOAK: from a firm crust,
##               dry, to a bog after days of rain). The mud and bog and deep snow are the terrain's
##               own soft ground (WorldTerrain's Surfaces), put back as they were when you leave.
##   the fords   where a road goes through the river (WarMap.fords) the water rises with the rain:
##               past FLOOD_FROM it's in flood, deeper the wetter, and pushes what's in it
##               downstream and holds it back (a light machine is swept, a heavy one wades).
##   the roads   every morning a road or two may be shut: a slide of boulders, trees down across it
##               (Breakable: rammed through or shot apart); gone the next morning.
##   the wear    a part on your machine worn under WEAR_UNDER (Inventory: what you bolted on) may give
##               on the road now and then while it's driven hard (FATIGUE): the more worn, the likelier.
##
## The day and what's shut today (and what's been cleared) are kept (`path`).

const SOAK := Vector2(0.65, 1.6) ## times the soft ground's sinking, bone dry .. soaked
const FLOOD_FROM := 0.5 ## wetness past which the fords flood
const FLOOD_R := 22.0 ## m round a ford the water reaches
const FLOOD_DEEP := 1.6 ## m at the worst
const BLOCK_NEAR := 320.0 ## m: a shut road put up within this
const WEAR_UNDER := 0.45
const FATIGUE := 0.06 ## chance every FATIGUE_EVERY s, at its worst, that a worn part takes a knock
const FATIGUE_EVERY := 4.0

static var path := "user://valley_life.cfg" ## (tests point it elsewhere)
static var day := 1

var game: Node
var terrain: Node
var weather: Weather
var soak := 1.0
var floods: Array[Dictionary] = [] ## {road, at: Vector2, down: Vector2 (the river's flow), depth, node}
var blocks: Array[Dictionary] = [] ## today's: {kind, road, at: Vector2, across: Vector2, cleared, nodes}
var _base := {} ## Surface -> its own numbers
var _soak_t := 0.0
var _wear_t := 0.0
var _last_hour := -1.0
var _cleared: Array = [] ## (today's blocks cleared, by their index)


func _ready() -> void:
	name = "ValleyLife"
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		day = int(cf.get_value("life", "day", 1))
		_cleared = cf.get_value("life", "cleared", [])
	else:
		day = 1
	var soft: Dictionary = terrain.get("_soft_surfaces") if terrain.get("_soft_surfaces") != null else {}
	for k: Variant in soft:
		var s: Surface = soft[k]
		_base[s] = [s.max_depth, s.static_sink, s.sink_rate, s.dig_rate, s.sink_drag]
	var river := WarMap.river()
	for f: Dictionary in WarMap.fords():
		var down := Vector2.RIGHT
		var pts: PackedVector2Array = river.points
		var best := INF
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(f.at, pts[i], pts[i + 1])
			if q.distance_to(f.at) < best:
				best = q.distance_to(f.at)
				down = (pts[i + 1] - pts[i]).normalized()
		floods.append({"road": f.road, "at": f.at, "down": down, "depth": 0.0, "node": null})
	_lay_blocks()
	_apply_soak()


func _exit_tree() -> void:
	for s: Surface in _base:
		var b: Array = _base[s]
		s.max_depth = b[0]
		s.static_sink = b[1]
		s.sink_rate = b[2]
		s.dig_rate = b[3]
		s.sink_drag = b[4]
	_save()


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("life", "day", day)
	cf.set_value("life", "cleared", _cleared)
	cf.save(path)


## A new morning: the day counted, yesterday's slides gone, today's laid.
func new_day() -> void:
	day += 1
	_cleared = []
	for b in blocks:
		_lower(b)
	_lay_blocks()
	_save()
	var shut := shut_roads()
	if game and game.has_method("say"):
		if not shut.is_empty():
			game.call("say", "Yol kapalı: %s" % ", ".join(shut))


## Today's shut roads (the same for the same day): one or two, somewhere on the valley's roads.
func _lay_blocks() -> void:
	blocks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + day * 131
	var roads := WarMap.roads()
	var keys: Array = roads.keys()
	keys.sort()
	var start: Vector3 = (terrain.get("spawn") as Transform3D).origin if terrain.get("spawn") != null else Vector3.ZERO
	var n := 1 + rng.randi() % 2
	for tries in 40:
		if blocks.size() >= n or keys.is_empty():
			break
		var k: String = keys[rng.randi() % keys.size()]
		var pts: PackedVector2Array = roads[k]
		if pts.size() < 6:
			continue
		var i := rng.randi_range(2, pts.size() - 3)
		var at := pts[i]
		if at.distance_to(Vector2(start.x, start.z)) < 250.0:
			continue
		var far := true
		for b in blocks:
			far = far and (b.at as Vector2).distance_to(at) > 400.0
		if not far:
			continue
		var along := (pts[i + 1] - pts[i - 1]).normalized()
		blocks.append({"kind": "slide" if rng.randf() < 0.55 else "trees", "road": k, "at": at, "across": Vector2(-along.y, along.x),
			"cleared": blocks.size() in _cleared, "nodes": [], "seed": rng.randi()})


## What's shut today (and not cleared), in words.
func shut_roads() -> PackedStringArray:
	var out := PackedStringArray()
	for b in blocks:
		if not b.cleared:
			out.append("%s (%s)" % [WarMap.road_name(b.road), "heyelan" if b.kind == "slide" else "devrik ağaçlar"])
	return out


func _raise(k: int) -> void:
	var b: Dictionary = blocks[k]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(b.seed)
	var across := Vector3(b.across.x, 0.0, b.across.y)
	var along := Vector3(-b.across.y, 0.0, b.across.x)
	var mid := Vector3(b.at.x, 0.0, b.at.y)
	if b.kind == "slide":
		for i in 7:
			var p := mid + across * (-7.5 + i * 2.5 + rng.randf_range(-0.5, 0.5)) + along * rng.randf_range(-1.5, 1.5)
			p.y = float(terrain.call("height_at", p.x, p.z)) - 0.25
			var br := Breakable.make("boulder", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
			game.add_child(br)
			b.nodes.append(br)
	else:
		for i in 2:
			var p := mid + along * (i * 3.0 - 1.5) + across * rng.randf_range(-1.0, 1.0)
			p.y = float(terrain.call("height_at", p.x, p.z))
			var yaw := atan2(-across.z, across.x) + rng.randf_range(-0.25, 0.25)
			var br := Breakable.make("log", Transform3D(Basis(Vector3.UP, yaw), p))
			game.add_child(br)
			b.nodes.append(br)


func _lower(b: Dictionary) -> void:
	for n: Variant in b.nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	b.nodes = []


func _apply_soak() -> void:
	var w := weather.wetness if weather else 0.3
	soak = lerpf(SOAK.x, SOAK.y, w)
	for s: Surface in _base:
		var b: Array = _base[s]
		s.max_depth = float(b[0]) * sqrt(soak)
		s.static_sink = float(b[1]) * soak
		s.sink_rate = float(b[2]) * soak
		s.dig_rate = float(b[3]) * soak
		s.sink_drag = float(b[4]) * soak


## How the ground is, in words (the HUD).
func ground_word() -> String:
	var w := weather.wetness if weather else 0.3
	if w < 0.15:
		return "kuru: çamur sertleşti"
	if w < 0.45:
		return "nemli"
	if w < 0.75:
		return "ıslak: çamur yumuşak"
	return "sırılsıklam: bataklık derin"


func _physics_process(dt: float) -> void:
	if weather:
		if _last_hour >= 0.0 and _last_hour > 20.0 and weather.hour < 4.0:
			new_day()
		_last_hour = weather.hour
	_soak_t -= dt
	if _soak_t <= 0.0:
		_soak_t = 2.0
		_apply_soak()
	var me := _me()
	if me == null:
		return
	# the shut roads near you put up, far ones taken down; one broken through is cleared
	for k in blocks.size():
		var b: Dictionary = blocks[k]
		var d := Vector2(me.global_position.x, me.global_position.z).distance_to(b.at)
		var up := not (b.nodes as Array).is_empty()
		if not b.cleared and d < BLOCK_NEAR and not up:
			_raise(k)
			if game.has_method("say"):
				game.call("say", "Yol kapalı ileride: %s · %s" % [WarMap.road_name(b.road), "heyelan" if b.kind == "slide" else "devrik ağaçlar"])
		elif up and (d > BLOCK_NEAR + 80.0 or b.cleared):
			if d > BLOCK_NEAR + 80.0:
				_lower(b)
		if up and not b.cleared:
			var whole := 0
			for n: Variant in b.nodes:
				if is_instance_valid(n) and not (n as Breakable).broken:
					whole += 1
			if whole <= (b.nodes as Array).size() / 3:
				b.cleared = true
				_cleared.append(k)
				_save()
				if game.has_method("say"):
					game.call("say", "Yol açıldı: %s" % WarMap.road_name(b.road))
	_flood(dt)
	_fatigue(dt, me)


## The fords: in flood past FLOOD_FROM, pushing and holding back what's in them.
func _flood(_dt: float) -> void:
	var w := weather.wetness if weather else 0.0
	var level := clampf((w - FLOOD_FROM) / (1.0 - FLOOD_FROM), 0.0, 1.0)
	for f in floods:
		f.depth = level * FLOOD_DEEP
		_show_flood(f)
		if f.depth <= 0.01:
			continue
		for n: Node in get_tree().get_nodes_in_group("machines"):
			var m := n as Machine
			var off := Vector2(m.global_position.x, m.global_position.z).distance_to(f.at)
			if off > FLOOD_R or not m.alive:
				continue
			var deep := float(f.depth) * (1.0 - off / FLOOD_R)
			var down := Vector3(f.down.x, 0.0, f.down.y)
			var v := m.linear_velocity
			# the current: as strong on anything, so a light one's swept; the water holds it back
			m.apply_central_force(down * 2600.0 * deep - Vector3(v.x, 0.0, v.z) * 900.0 * deep)


func _show_flood(f: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var node: MeshInstance3D = f.node
	if f.depth <= 0.01:
		if node:
			node.visible = false
		return
	if node == null:
		node = MeshInstance3D.new()
		var cm := CylinderMesh.new() # (a round sheet of brown water over the ford)
		cm.top_radius = FLOOD_R
		cm.bottom_radius = FLOOD_R
		cm.height = 0.05
		cm.radial_segments = 48
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.25, 0.17, 0.78)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.1
		m.metallic_specular = 0.8
		cm.material = m
		node.mesh = cm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		game.add_child(node)
		f.node = node
	node.visible = true
	var y := float(terrain.call("height_at", f.at.x, f.at.y))
	if terrain.has_method("water_height_at"): # (the river risen over its banks)
		y = maxf(y, float(terrain.call("water_height_at", f.at.x, f.at.y)))
	node.global_position = Vector3(f.at.x, y + float(f.depth) * 0.6, f.at.y)


## The fords in flood, in words.
func flooded() -> PackedStringArray:
	var out := PackedStringArray()
	for f in floods:
		if float(f.depth) > 0.3:
			out.append("%s geçidi taşkın (%.1f m)" % [WarMap.road_name(f.road), float(f.depth)])
	return out


## A worn part on your machine, driven hard, may give.
func _fatigue(dt: float, me: Machine) -> void:
	_wear_t += dt
	if _wear_t < FATIGUE_EVERY:
		return
	_wear_t = 0.0
	if absf(me.speed) < 3.0 or me.building:
		return
	for i in range(me.design.size() - 1, -1, -1):
		var p: Dictionary = me.design[i]
		var frac := clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0)
		if frac >= WEAR_UNDER or Parts.is_cab(p.id):
			continue
		if randf() < FATIGUE * (1.0 - frac / WEAR_UNDER) * clampf(absf(me.speed) / 10.0, 0.4, 1.5):
			var name_ := str(Parts.def(p.id).name)
			var n0 := me.design.size()
			me.damage_part(i, Parts.hp_of(p.id) * 0.12, Vector3.INF)
			if me.design.size() < n0 and game.has_method("say"):
				game.call("say", "▲ Yıpranmış %s yolda dayanmadı, koptu" % name_)
			return


func _me() -> Machine:
	var mv: Variant = game.get("machine") if game else null
	return mv as Machine if is_instance_valid(mv) else null
