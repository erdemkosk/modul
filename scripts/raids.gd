class_name Raids
extends Node3D
## What comes out of the dark.
##
## Outlaws: from the third night on, every other night soon after midnight a band comes out of the
## woods (bigger as the town grows) and makes for it from where it's darkest: each goes for the
## nearest building that isn't burning yet, preferring the unlit ones, lights a torch at its door
## and sets it alight (at the store it carries off some of what's there), then the next; anyone of
## the town who comes near is cut down. Burnt enough, at it long enough, down to a few, or the
## dawn coming, they go back into the woods.
##
## Wolves: some nights a pack comes down to the edge of the town, after anyone out in the dark.
## They shy from the light: in a lamp's or a window's glow they turn back into the dark. They go at
## first light.
##
## The town's answer is light. The watchmen (Bekçi karakolu) and the lookout up a tower shoot what
## they can see: anything in the light, or close by; what stays in the dark they can't. Everyone
## else runs for a house or the store and hides till it's over (if that catches fire, they come
## out). With a tower standing, the band's heard coming before it's there.

signal message(text: String, kind: String)

const FIRST_DAY := 3
const EVERY := 2 ## days between raids
const ARRIVE_HOUR := 0.5
const OUTLAW_TUNIC := Color(0.17, 0.12, 0.11)
const SEE_CLOSE := 12.0 ## m within which a foe is seen in any dark

var village: Village
var nav: Nav
var terrain: WorldTerrain
var weather: Weather
var raiders: Array[Villager] = []
var wolves: Array[Villager] = []
var next_day := FIRST_DAY
var active := false

var _origin := Vector3.ZERO
var _wolf_origin := Vector3.ZERO
var _started := 0.0
var _burnt := 0
var _size := 0
var _think_t := 0.0
var _shoot_t := {} ## tower -> seconds to its next shot
var _wolf_night := -1 ## the day whose night the wolves have had


func _ready() -> void:
	name = "Raids"


## The band's size: a couple at first, more as the town grows.
func band_size() -> int:
	return clampi(2 + village.villagers.size() / 4 + (village.day - FIRST_DAY) / 2, 2, 14)


## Anything out there now (a band, a pack).
func threat() -> bool:
	if active:
		return true
	for w in wolves:
		if is_instance_valid(w) and not w.dead:
			return true
	return false


func _process(dt: float) -> void:
	var h := weather.hour
	if not active and village.day >= next_day and h >= ARRIVE_HOUR and h < 3.5:
		start(band_size())
	if _wolf_night != village.day and (h > 21.5 or h < 3.0) and village.day >= 2:
		_wolf_night = village.day
		if randf() < 0.5:
			_wolves_come()
	_think_t += dt
	if _think_t >= 0.4:
		_think_t = 0.0
		if active:
			_think()
		_think_wolves()
	_tower_shots(dt)


# --- The band -------------------------------------------------------------------------------------

func start(n: int) -> void:
	var store := _main_store()
	if store == null:
		return
	_origin = _edge_point(store.global_position)
	active = true
	_started = village.clock
	_burnt = 0
	_size = n
	for k in n:
		var r := Villager.new()
		r.team = 1
		r.tunic_color = OUTLAW_TUNIC
		r.village = village
		r.nav = nav
		r.hp = 70.0
		r.max_hp = 70.0
		r.attack = 13.0
		r.fighter = true
		add_child(r)
		var p := _origin + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		p.y = nav.height(p.x, p.z)
		r.position = p
		r.arm_with("axe")
		raiders.append(r)
	if not _towers().is_empty():
		message.emit("Gözcü ormanda ses duydu: %s yönünden %d kişi geliyor!" % [_compass(_origin - store.global_position), n], "bad")


## Somewhere out in the woods a few hundred metres from the town, as dark as can be found.
func _edge_point(home: Vector3) -> Vector3:
	var best := home + Vector3(250, 0, 0)
	for k in 40:
		var a := randf() * TAU
		var p := home + Vector3(cos(a), 0, sin(a)) * randf_range(220.0, 320.0)
		if nav.is_open(p):
			best = p
			break
	best.y = nav.height(best.x, best.z)
	return best


static func _compass(d: Vector3) -> String:
	var a := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	var names := ["kuzey", "kuzeydoğu", "doğu", "güneydoğu", "güney", "güneybatı", "batı", "kuzeybatı"]
	return names[int(round(a / 45.0)) % 8]


func _main_store() -> Building:
	var s := village.stores()
	return s[0] if not s.is_empty() else (village.buildings[0] if not village.buildings.is_empty() else null)


func _towers() -> Array[Building]:
	var out: Array[Building] = []
	for b in village.buildings:
		if b.state == "done" and b.def.role == "tower":
			out.append(b)
	return out


## The outlaw or wolf nearest `p` within `reach` (only one that can be seen from `p`, if `seen`).
func nearest_raider(p: Vector3, reach: float, seen := false) -> Villager:
	var best: Villager = null
	var bd := reach
	for list: Array[Villager] in [raiders, wolves]:
		for r in list:
			if not is_instance_valid(r) or r.dead:
				continue
			var d := r.position.distance_to(p)
			if d < bd and (not seen or can_see(p, r)):
				bd = d
				best = r
	return best


## Whether someone at `from` can see `who`: in the light, or close.
func can_see(from: Vector3, who: Villager) -> bool:
	return who.position.distance_to(from) < SEE_CLOSE or village.is_lit(who.position)


func _think() -> void:
	var live := 0
	for r in raiders:
		if not r.dead:
			live += 1
	if live == 0:
		_end("Baskın püskürtüldü! Haydutların hepsi düştü.", "good")
		return
	var dawn := weather.hour > 5.0 and weather.hour < 12.0
	var leaving := _burnt >= _size + 2 or village.clock - _started > 300.0 or live * 3 < _size or dawn
	for r in raiders:
		if r.dead:
			continue
		if leaving and r.job != "Kaçıyor":
			r.abort()
			r.arm_with("axe")
			r.give([{"t": "go", "to": _origin}, {"t": "do", "f": func() -> bool:
				r.queue_free()
				raiders.erase(r)
				return true}], "Kaçıyor")
			continue
		if not r.plan.is_empty():
			continue
		var foe := _victim_near(r.position, 12.0)
		if foe:
			r.give([{"t": "fight", "foe": foe, "give_up": 20.0}], "Saldırıyor")
			continue
		var b := _next_target(r.position)
		if b == null:
			continue
		r.give([
			{"t": "go", "to": b.door() + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-0.5, 1.0))},
			{"t": "do", "f": func() -> bool:
				r.arm_with("torch") # (lit at the door: the dark's what got it this far)
				return true},
			{"t": "work", "time": 2.5, "anim": "torch", "face": b.global_position},
			{"t": "do", "f": func() -> bool:
				r.arm_with("axe")
				if not is_instance_valid(b) or b.state == "gone":
					return false
				if b.ignite():
					_burnt += 1
				if b.def.role == "store":
					_plunder(b)
				return true},
		], "Yakıyor", b)
	if leaving and raiders.all(func(r: Villager) -> bool: return r.dead or r.job == "Kaçıyor"):
		message.emit("Haydutlar ormana çekiliyor.", "info")
		active = false # (the rest only walk off)
		next_day = village.day + EVERY
		_finish_quietly()


## Someone of the town out in the open near `p` (not hidden, not up a tower).
func _victim_near(p: Vector3, reach: float) -> Villager:
	var best: Villager = null
	var bd := reach
	for v in village.villagers:
		if v.dead or v.sleeping or v.perched:
			continue
		var d := v.position.distance_to(p)
		if d < bd:
			bd = d
			best = v
	return best


## The nearest building there's still something to burn in: an unlit one counts as half as far.
func _next_target(p: Vector3) -> Building:
	var best: Building = null
	var bd := INF
	for b in village.buildings:
		if b.state == "gone" or b.state == "ruin" or b.is_burning() or b.def.role == "light":
			continue
		var can := false
		for piece in b.pieces:
			if piece.alive and piece.built and BuildingDefs.STUFF[piece.stuff].burns:
				can = true
				break
		if not can:
			continue
		var d := b.global_position.distance_to(p) * (2.0 if village.is_lit(b.door()) else 1.0)
		if d < bd:
			bd = d
			best = b
	return best


func _plunder(store: Building) -> void:
	var took: Array[String] = []
	for r: String in store.goods:
		var n := store.take_goods(r, int(store.goods[r]) / 3)
		if n > 0:
			took.append("%d %s" % [n, BuildingDefs.RES_NAMES[r].to_lower()])
	if not took.is_empty():
		message.emit("Haydutlar depoyu yağmaladı: " + ", ".join(took), "bad")


func _end(text: String, kind: String) -> void:
	active = false
	next_day = village.day + EVERY
	message.emit(text, kind)
	_finish_quietly()


func _finish_quietly() -> void:
	var keep: Array[Villager] = []
	for r in raiders:
		if is_instance_valid(r) and not r.dead:
			keep.append(r)
	raiders = keep


# --- Wolves ---------------------------------------------------------------------------------------

func _wolves_come() -> void:
	var store := _main_store()
	if store == null:
		return
	_wolf_origin = _edge_point(store.global_position)
	for k in randi_range(3, 5):
		var w := Wolf.new()
		w.team = 1
		w.village = village
		w.nav = nav
		w.hp = 45.0
		w.max_hp = 45.0
		w.attack = 11.0
		w.fighter = true
		add_child(w)
		var p := _wolf_origin + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		p.y = nav.height(p.x, p.z)
		w.position = p
		wolves.append(w)
	if not _towers().is_empty():
		message.emit("Kurt uluması! Bir sürü %s yönünde." % _compass(_wolf_origin - store.global_position), "bad")


## A wolf in the light turns back into the dark; one in the dark goes for whoever's out in it; at
## first light they all go.
func _think_wolves() -> void:
	var keep: Array[Villager] = []
	for w in wolves:
		if is_instance_valid(w) and not w.dead:
			keep.append(w)
	wolves = keep
	if wolves.is_empty():
		return
	var day := not weather.is_night()
	for w in wolves:
		if day:
			if w.job != "Kaçıyor":
				w.abort()
				w.give([{"t": "go", "to": _wolf_origin}, {"t": "do", "f": func() -> bool:
					w.queue_free()
					return true}], "Kaçıyor")
			continue
		if village.is_lit(w.position) and w.job != "Işıktan kaçıyor":
			w.abort()
			var store := _main_store()
			var away := (w.position - (store.global_position if store else w.position)).normalized()
			if away.length() < 0.1:
				away = Vector3.RIGHT
			w.give([{"t": "go", "to": w.position + away * 25.0}], "Işıktan kaçıyor")
			continue
		if not w.plan.is_empty():
			continue
		var prey := _victim_near(w.position, 70.0)
		if prey and (not village.is_lit(prey.position) or prey.position.distance_to(w.position) < 4.0):
			w.give([{"t": "fight", "foe": prey, "give_up": 30.0}], "Avlanıyor")
			continue
		var store := _main_store()
		if store:
			var a := randf() * TAU
			var p := store.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(40.0, 80.0)
			if not village.is_lit(p):
				w.give([{"t": "go", "to": p}, {"t": "work", "time": randf_range(3.0, 7.0), "anim": "idle"}], "Dolanıyor")


# --- Shots ----------------------------------------------------------------------------------------

## The lookouts up the towers shoot what they can see in reach.
func _tower_shots(dt: float) -> void:
	for t in _towers():
		var man: Villager = null
		for v in t.workers:
			if v.perched == t:
				man = v
		if man == null:
			continue
		_shoot_t[t] = float(_shoot_t.get(t, 0.0)) - dt
		if float(_shoot_t[t]) > 0.0:
			continue
		var foe: Villager = null
		var bd := 70.0
		for list: Array[Villager] in [raiders, wolves]:
			for r in list:
				if is_instance_valid(r) and not r.dead and village.is_lit(r.position):
					var d := r.position.distance_to(t.global_position)
					if d < bd:
						bd = d
						foe = r
		if foe == null:
			continue
		_shoot_t[t] = randf_range(2.2, 3.0)
		shoot(man.position + Vector3.UP * 1.4, foe, randf_range(28.0, 40.0), 0.6)


## A rifle shot from `from` at `foe`: a flash, a streak, and `dmg` if it hits (`chance`).
func shoot(from: Vector3, foe: Villager, dmg: float, chance: float) -> void:
	var to := foe.position + Vector3.UP * 1.0 + Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4))
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.5)
	flash.light_energy = 6.0
	flash.omni_range = 9.0
	add_child(flash)
	flash.global_position = from
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.12)
	ft.tween_callback(flash.queue_free)
	var streak := MeshInstance3D.new()
	var m := BoxMesh.new()
	var length := from.distance_to(to)
	m.size = Vector3(0.025, 0.025, length)
	streak.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.6, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.material_override = mat
	add_child(streak)
	streak.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
	var st := streak.create_tween()
	st.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	st.tween_callback(streak.queue_free)
	if randf() < chance:
		foe.hurt(dmg, null)
