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
## The band has its parts: shooters with rifles lie up in the dark at the edge of the light and
## shoot whoever they can see in it (a lantern makes a mark of whoever carries it; they shoot out
## the lamps too); torchmen make for the unlit, unguarded buildings and fire them; looters go for
## the store and carry off what they can. Hurt badly, one runs; a shooter who falls drops his
## rifle, and what a looter carried is got back.
##
## The town's answer is light, and its few rifles. The watchmen (Bekçi karakolu) and the lookout up a
## tower shoot what they can see: anything in the light, or close by, or that's just fired (its
## flash shows it); what stays in the dark they can't. The militia take the armoury's rifles to
## their posts. Everyone else runs for a house or the store and hides till it's over (if that
## catches fire, they come out). With a tower standing, the band's heard coming before it's there.

signal message(text: String, kind: String)

const FIRST_DAY := 8
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
var level := 1 ## 0 easy, 1 the usual, 2 hard: how soon, how often, how many
var active := false

var _origin := Vector3.ZERO
var _wolf_origin := Vector3.ZERO
var _started := 0.0
var _burnt := 0
var _size := 0
var _think_t := 0.0
var _shoot_t := {} ## tower -> seconds to its next shot
var _wolf_night := -1 ## the day whose night the wolves have had
var loot: Array[Dictionary] = [] ## rifles the outlaws dropped: {at, node, ammo, claimed}
var _lamp_said := false


func _ready() -> void:
	name = "Raids"


## The band's size: a couple at first, more as the town grows.
func band_size() -> int:
	var n := 2 + village.villagers.size() / 4 + (village.day - FIRST_DAY) / 2
	return clampi(roundi(n * [0.6, 1.0, 1.4][level]), 2, 18)


## Days between raids.
func every() -> int:
	return [3, 2, 2][level]


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
	if _wolf_night != village.day and (h > 21.5 or h < 3.0) and village.day >= 5:
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
		# Their parts: about two in five shoot, as many carry the fire, the rest go for the store.
		r.role = "shooter" if k % 5 in [0, 3] else ("looter" if k % 5 == 4 else "torch")
		add_child(r)
		var p := _origin + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		p.y = nav.height(p.x, p.z)
		r.position = p
		if r.role == "shooter":
			r.ranged = 40.0
			r.attack = 22.0
			r.arm_with("rifle")
		else:
			r.arm_with("axe")
		r.died.connect(_on_raider_down)
		raiders.append(r)
	_lamp_said = false
	if not _towers().is_empty():
		message.emit("Gözcü ormanda ses duydu: %s yönünden %d kişi geliyor!" % [_compass(_origin - store.global_position), n], "bad")
	if not village.bells().is_empty():
		village.ring_bells(8, 0.8)
		message.emit("Tehlike çanı çalıyor: herkes saklanıyor!", "bad")


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
			if not is_instance_valid(r) or r.dead or r.down:
				continue
			var d := r.position.distance_to(p)
			if d < bd and (not seen or can_see(p, r)):
				bd = d
				best = r
	return best


## Whether someone at `from` can see `who`: in the light, close, or just shown by its own shot.
func can_see(from: Vector3, who: Villager) -> bool:
	return who.position.distance_to(from) < SEE_CLOSE or who.revealed > 0.0 or village.is_lit(who.position)


## Where the band came from.
func origin() -> Vector3:
	return _origin


## A raider down: a shooter's rifle left lying, a looter's haul got back.
func _on_raider_down(r: Villager) -> void:
	if r.role == "shooter":
		var node := Node3D.new()
		add_child(node)
		node.global_position = r.position + Vector3.UP * 0.06
		node.rotation.y = randf() * TAU
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.3, 0.2, 0.12)
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.2, 0.2, 0.21)
		iron.metallic = 0.6
		for part: Array in [[Vector3(0.06, 0.06, 0.75), Vector3(0, 0, 0.1), wood], [Vector3(0.03, 0.03, 0.7), Vector3(0, 0.02, -0.55), iron]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = part[0]
			mi.mesh = bm
			mi.position = part[1]
			mi.material_override = part[2]
			node.add_child(mi)
		loot.append({"at": r.position, "node": node, "ammo": randi_range(3, 12), "claimed": false})
		message.emit("Bir haydut nişancı düştü: tüfeği yerde kaldı.", "good")
	if r.has_meta("haul"):
		var store := _main_store()
		var haul: Dictionary = r.get_meta("haul")
		if store:
			for res: String in haul:
				store.add_goods(res, int(haul[res]))
		message.emit("Yağmacı düştü: taşıdığı mal geri alındı.", "good")


func _think() -> void:
	var kept: Array[Villager] = []
	for r in raiders:
		if is_instance_valid(r) and r.down and not r.dead:
			if not r in village.downed_outlaws: # (out of the fight: it lies there to be taken or to bleed out)
				village.downed_outlaws.append(r)
		elif is_instance_valid(r):
			kept.append(r)
	raiders = kept
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
			if r.role != "shooter":
				r.arm_with("axe")
			r.give([{"t": "go", "to": _origin}, {"t": "do", "f": func() -> bool:
				r.queue_free()
				raiders.erase(r)
				return true}], "Kaçıyor")
			continue
		if r.hp < r.max_hp * 0.35 and r.job != "Kaçıyor":
			# Hurt badly: back into the woods.
			r.abort()
			r.give([{"t": "go", "to": _origin}, {"t": "do", "f": func() -> bool:
				raiders.erase(r)
				r.queue_free()
				return true}], "Kaçıyor")
			continue
		if not r.plan.is_empty():
			continue
		if r.role == "shooter":
			_think_shooter(r)
			continue
		var foe := _victim_near(r.position, 12.0)
		if foe:
			r.give([{"t": "fight", "foe": foe, "give_up": 20.0}], "Saldırıyor")
			continue
		if r.role == "looter" and not r.has_meta("haul"):
			var store := _main_store()
			if store:
				r.give([{"t": "go", "to": store.door() + Vector3(randf_range(-1.5, 1.5), 0, randf_range(0.0, 1.0))},
					{"t": "work", "time": 3.0, "anim": "gather", "face": store.global_position},
					{"t": "do", "f": func() -> bool:
						if not is_instance_valid(store):
							return false
						var haul := _plunder(store)
						r.set_meta("haul", haul)
						r.set_carry("yiyecek", 1)
						return true},
					{"t": "go", "to": _origin},
					{"t": "do", "f": func() -> bool:
						raiders.erase(r)
						r.queue_free()
						return true}], "Yağmalıyor", store)
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
		next_day = village.day + every()
		_finish_quietly()


## A shooter: whoever it can see within its reach gets shot at; with nobody in sight it creeps up
## to a dark spot at the edge of the light and lies there watching, shooting out a lamp if one's near.
func _think_shooter(r: Villager) -> void:
	var foe: Villager = null
	var bd := r.ranged
	for v in village.villagers:
		if v.dead or v.down or v.sleeping or v.perched:
			continue
		var d := v.position.distance_to(r.position)
		if d < bd and can_see(r.position, v):
			bd = d
			foe = v
	if foe:
		r.give([{"t": "fight", "foe": foe, "give_up": r.ranged + 8.0}], "Ateş ediyor")
		return
	var mark := _lit_mark(r.position)
	if mark == Vector3.INF:
		var store := _main_store()
		if store:
			r.give([{"t": "go", "to": store.global_position + (r.position - store.global_position).normalized() * 50.0}], "Sokuluyor")
		return
	var away := _origin - mark
	away.y = 0.0
	away = away.normalized().rotated(Vector3.UP, randf_range(-0.6, 0.6)) if away.length() > 0.1 else Vector3.RIGHT
	var spot := mark + away * 26.0
	for k in 3:
		if village.is_lit(spot):
			spot += away * 6.0
	spot.y = nav.height(spot.x, spot.z)
	r.give([{"t": "go", "to": spot}, {"t": "work", "time": randf_range(3.0, 6.0), "anim": "aim", "face": mark},
		{"t": "do", "f": func() -> bool:
			_shoot_lamp(r)
			return true}], "Pusuda")


## The nearest thing lit up (a lantern carried, a lamp, a lit house) within 160 m of `p`.
func _lit_mark(p: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := 160.0
	for v in village.villagers:
		if v.lantern_on() and not v.sleeping:
			var d := v.position.distance_to(p)
			if d < bd:
				bd = d
				best = v.position
	for b in village.buildings:
		if b.lit and b.state == "done":
			var d := b.global_position.distance_to(p)
			if d < bd:
				bd = d
				best = b.door()
	return best


## A lamp within a shot of `r`, put out with a bullet (its kindling spilt): the dark's their friend.
func _shoot_lamp(r: Villager) -> void:
	if r.dead:
		return
	for b in village.buildings:
		if b.def.role == "light" and b.lit and b.state == "done" and b.global_position.distance_to(r.position) < 42.0 and randf() < 0.5:
			r.revealed = 2.5
			_flash(r.muzzle())
			b.take_goods("odun", int(b.goods.get("odun", 0)))
			b.set_lit(false)
			if not _lamp_said:
				_lamp_said = true
				message.emit("Haydutlar %s vurup söndürdü!" % b.display_name().to_lower(), "bad")
			return


## Someone of the town out in the open near `p` (not hidden, not up a tower).
func _victim_near(p: Vector3, reach: float) -> Villager:
	var best: Villager = null
	var bd := reach
	for v in village.villagers:
		if v.dead or v.sleeping or v.perched or v.down:
			continue
		var d := v.position.distance_to(p)
		if d < bd:
			bd = d
			best = v
	return best


## Someone of the town with a rifle who'd see a torchman at `p`.
func _guarded(p: Vector3) -> bool:
	if not village.is_lit(p):
		return false
	for v in village.villagers:
		if not v.dead and not v.down and not v.sleeping and v.ranged > 0.0 and v.position.distance_to(p) < 30.0:
			return true
	return false


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
		if _guarded(b.door()):
			continue # (a rifle watching it in the light: not that one)
		var d := b.global_position.distance_to(p) * (2.0 if village.is_lit(b.door()) else 1.0)
		if d < bd:
			bd = d
			best = b
	return best


func _plunder(store: Building) -> Dictionary:
	var took: Array[String] = []
	var haul := {}
	for r: String in store.goods:
		var n := store.take_goods(r, int(store.goods[r]) / 3)
		if n > 0:
			haul[r] = n
			took.append("%d %s" % [n, BuildingDefs.RES_NAMES[r].to_lower()])
	if not took.is_empty():
		message.emit("Haydutlar depoyu yağmaladı: " + ", ".join(took), "bad")
	return haul


func _end(text: String, kind: String) -> void:
	active = false
	next_day = village.day + every()
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
		man.look_at(Vector3(foe.position.x, man.position.y, foe.position.z), Vector3.UP)
		shoot(man.muzzle(), foe, randf_range(28.0, 40.0), 0.6)


## A rifle shot from `from` at `foe` (by `by`): a flash, a streak, and `dmg` if it hits (`chance`,
## halved if the foe's behind cover). The flash shows the shooter for a moment to anyone looking.
func shoot(from: Vector3, foe: Villager, dmg: float, chance: float, by: Villager = null) -> void:
	var to := foe.position + Vector3.UP * 1.0 + Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4))
	if by:
		by.revealed = 2.5
		chance *= by.aim()
		by.learn("nisan", 12.0)
	if foe.in_cover:
		chance *= 0.5
	_flash(from)
	var streak := MeshInstance3D.new()
	var m := BoxMesh.new()
	var length := from.distance_to(to)
	m.size = Vector3(0.012, 0.012, length)
	streak.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.6, 0.45)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.material_override = mat
	add_child(streak)
	streak.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
	var st := streak.create_tween()
	st.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	st.tween_callback(streak.queue_free)
	if randf() < chance:
		foe.hurt(dmg, by)


## An arrow loosed from `from` at `foe` (by `by`): no flash, hardly a sound, so the archer isn't
## shown; the shaft flies, and `dmg` if it hits (`chance`, halved behind cover).
func arrow(from: Vector3, foe: Villager, dmg: float, chance: float, by: Villager = null) -> void:
	if by:
		chance *= by.aim()
		by.learn("okcu", 12.0)
	if foe.in_cover:
		chance *= 0.5
	var to := foe.position + Vector3.UP * 1.1 + Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.3), randf_range(-0.5, 0.5))
	var hit := randf() < chance
	_fly_arrow(from, to, func() -> void:
		if hit and is_instance_valid(foe) and not foe.dead:
			foe.hurt(dmg, by))


func _fly_arrow(from: Vector3, to: Vector3, landed: Callable) -> void:
	var a := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.015, 0.015, 0.75)
	a.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.42, 0.26)
	a.material_override = mat
	add_child(a)
	var time := clampf(from.distance_to(to) / 45.0, 0.12, 0.9)
	var arc := Vector3.UP * from.distance_to(to) * 0.06
	var tw := a.create_tween()
	tw.tween_method(func(u: float) -> void:
		var p := from.lerp(to, u) + arc * 4.0 * u * (1.0 - u)
		var ahead := from.lerp(to, minf(u + 0.05, 1.0)) + arc * 4.0 * (u + 0.05) * (1.0 - u - 0.05)
		if p.distance_to(ahead) > 0.001:
			a.look_at_from_position(p, ahead, Vector3.UP)
		else:
			a.global_position = p, 0.0, 1.0, time)
	tw.tween_callback(landed)
	tw.tween_interval(4.0)
	tw.tween_callback(a.queue_free)
	Ambience.knock(from, 3.2) # (the string's twang, soft)


## A practice shot at the armoury's target: a rifle's crack and flash, or an arrow thudding in.
func practice(from: Vector3, at: Vector3, kind: String) -> void:
	var to := at + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), 0)
	if kind == "rifle":
		_flash(from)
		var streak := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.012, 0.012, from.distance_to(to))
		streak.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.6, 0.45)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		streak.material_override = mat
		add_child(streak)
		streak.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
		var st := streak.create_tween()
		st.tween_property(mat, "albedo_color:a", 0.0, 0.15)
		st.tween_callback(streak.queue_free)
	else:
		_fly_arrow(from, to, func() -> void: pass)


func _flash(at: Vector3) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.5)
	flash.light_energy = 6.0
	flash.omni_range = 9.0
	flash.light_volumetric_fog_energy = 0.2
	add_child(flash)
	flash.global_position = at
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.12)
	ft.tween_callback(flash.queue_free)
	# the flame at the muzzle, there and gone; then a puff of powder smoke drifting off
	var fire := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.09
	fm.height = 0.18
	fm.radial_segments = 8
	fm.rings = 4
	fire.mesh = fm
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.82, 0.45)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire.material_override = glow
	add_child(fire)
	fire.global_position = at
	var fw := fire.create_tween()
	fw.tween_property(fire, "scale", Vector3.ONE * 2.2, 0.06)
	fw.parallel().tween_property(glow, "albedo_color:a", 0.0, 0.08)
	fw.tween_callback(fire.queue_free)
	var puff := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.16
	pm.height = 0.3
	pm.radial_segments = 8
	pm.rings = 4
	puff.mesh = pm
	var smoke := StandardMaterial3D.new()
	smoke.albedo_color = Color(0.62, 0.62, 0.6, 0.22)
	smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke.cull_mode = BaseMaterial3D.CULL_DISABLED
	puff.material_override = smoke
	add_child(puff)
	puff.global_position = at
	var pw := puff.create_tween()
	pw.tween_property(puff, "scale", Vector3.ONE * 4.0, 1.6).set_ease(Tween.EASE_OUT)
	pw.parallel().tween_property(puff, "global_position", at + Vector3.UP * 0.6 + Weather.wind_now * 0.25, 1.6)
	pw.parallel().tween_property(smoke, "albedo_color:a", 0.0, 1.6)
	pw.tween_callback(puff.queue_free)
	Ambience.knock(at, 0.45) # (the crack of it)
