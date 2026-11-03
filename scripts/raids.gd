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
## The town's answer is light, and its few rifles. The watchmen (at the armoury) and the lookout up a
## tower shoot what they can see: anything in the light, or close by, or that's just fired (its
## flash shows it); what stays in the dark they can't. The militia take the armoury's rifles to
## their posts. Everyone else runs for a house or the store and hides till it's over (if that
## catches fire, they come out). With a tower standing, the band's heard coming before it's there.

signal message(text: String, kind: String)
signal ended ## a band done with (beaten off, or gone)

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
var camp_men: Array[Villager] = [] ## the outlaws sitting in their camp in the woods (camp)
var camp_at := Vector3.INF ## where their camp is (INF: none)
var camp_known := false ## found: seen from a tower, by someone working near, or told by a prisoner
var _camp_node: Node3D
var _camp_day := -1
var _camp_t := 0.0
var corpses: Array[Villager] = [] ## the band's dead, lying a while to be searched
var allies: Array[Villager] = [] ## a friendly side's soldiers fighting beside the town (called by telegraph)
var guns: Array[Node3D] = [] ## a convoy's tank guns, fired while its men are at the town
var soldiers := "" ## the band now on the town is a side's soldiers ("" outlaws): by day as well
var hud: Node ## (for asking: the band sends one ahead to ask for food first)
var _asked_for := -1 ## the raid day whose band has asked already
var _ask_card: Control


func _ready() -> void:
	name = "Raids"


## The band's size: a couple at first, more as the town grows.
func band_size() -> int:
	var n := 2 + village.villagers.size() / 4 + (village.day - FIRST_DAY) / 2 + (2 if camp_at != Vector3.INF else 0)
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
	if not active and village.day == next_day - 1 and h >= 19.0 and _asked_for != next_day:
		_ask_food()
	if not active and village.day >= next_day and h >= ARRIVE_HOUR and h < 3.5:
		if is_instance_valid(_ask_card):
			_ask_card.queue_free() # (no answer by midnight: taken for a no)
			message.emit("Cevap gelmedi: firariler karanlıkta kasabaya iniyor.", "bad")
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
	_mg_shots(dt)
	_turret_shots(dt)
	if _camp_day != village.day:
		_camp_day = village.day
		_camp_morning()
	_camp_t += dt
	if _camp_t >= 0.5:
		_camp_t = 0.0
		_camp_think()
		_allies_think()


# --- The camp -------------------------------------------------------------------------------------
# Outlaws dig in in the woods a couple of hundred metres off: tents round a fire, a few men about
# it. While it stands the raids come from it, bigger. It can be found (a tower within sight of its
# smoke, someone working near, a prisoner made to talk) and raided: the militia drafted and sent
# there (right-click), they fight it out; cleared, what was in it is the town's, and the raids stop
# a while.
const CAMP_FROM := 5 ## the first day one may be made
const CAMP_SEEN := 220.0 ## m a tower's lookout sees its smoke from


func _camp_morning() -> void:
	if camp_at != Vector3.INF or village.day < CAMP_FROM or _main_store() == null or randf() > 0.3:
		return
	var home := _main_store().global_position
	for k in 40:
		var a := randf() * TAU
		var p := home + Vector3(cos(a), 0, sin(a)) * randf_range(150.0, 220.0)
		if nav.is_open(p):
			p.y = nav.height(p.x, p.z)
			make_camp(p, clampi(3 + village.villagers.size() / 5, 3, 7))
			return


func make_camp(at: Vector3, n: int, known := false) -> void:
	camp_at = at
	camp_known = false
	_camp_node = Node3D.new()
	add_child(_camp_node)
	_camp_node.global_position = at
	# (a clearing cut for it: the stumps left)
	for i in village._props_in(at, 11.0):
		var info: Dictionary = village.props.prop_info(i)
		if str(info.kind) != "cliff" and Vector2(info.origin.x - at.x, info.origin.z - at.z).length() < 9.0:
			village.props.cut_tree(i)
	village._tents(_camp_node)
	var f := FireFx.flames()
	f.amount = 18
	(f.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.3, 0.15, 0.3)
	f.position = Vector3.UP * 0.3
	_camp_node.add_child(f)
	var smoke := FireFx.smoke(false)
	smoke.amount = 30
	smoke.lifetime = 9.0
	smoke.position = Vector3.UP * 1.0
	_camp_node.add_child(smoke)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.25)
	l.light_energy = 2.6
	l.omni_range = 12.0
	l.position = Vector3.UP * 0.9
	_camp_node.add_child(l)
	var crate := Building.material("wood")
	for k in 4: # (their plunder in crates)
		var c := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.7, 0.5, 0.5)
		c.mesh = cm
		c.material_override = crate
		var a := k * 1.3 + 0.4
		c.position = Vector3(cos(a) * 2.2, 0.25, sin(a) * 2.2)
		c.rotation.y = a
		_camp_node.add_child(c)
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
		r.role = "shooter" if k % 3 == 0 else "torch"
		add_child(r)
		var p := at + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		p.y = nav.height(p.x, p.z)
		r.position = p
		if r.role == "shooter":
			r.ranged = 40.0
			r.attack = 22.0
			r.arm_with("rifle")
		else:
			r.arm_with("axe")
		r.died.connect(_on_raider_down)
		camp_men.append(r)
	camp_known = known


func _camp_found(how: String) -> void:
	camp_known = true
	Ambience.alarm()
	var store := _main_store()
	var dir := _compass(camp_at - store.global_position) if store else ""
	message.emit("%sFirari kampı bulundu: %s yönünde, %d kişi. Milisi topla (TOPLA), seç ve kampa sağ tıkla." % [how, dir, camp_men.size()], "bad")


func _camp_think() -> void:
	if camp_at == Vector3.INF:
		return
	var kept: Array[Villager] = []
	for r in camp_men:
		if not is_instance_valid(r) or r.dead:
			continue
		if r.down:
			if not r in village.downed_outlaws:
				village.downed_outlaws.append(r)
			continue
		kept.append(r)
	camp_men = kept
	if camp_men.is_empty():
		_camp_cleared()
		return
	if not camp_known:
		for t in _towers():
			if t.global_position.distance_to(camp_at) < CAMP_SEEN:
				_camp_found("Gözcü kulesinden duman görüldü. ")
				break
	for v in village.villagers:
		if v.dead or v.down or v.team != 0:
			continue
		if v.position.distance_to(camp_at) < 60.0:
			if not camp_known:
				_camp_found("%s ormanda bir kamp gördü. " % v.display_name)
			# the drafted with no rifle go for the nearest of them
			if v.drafted and not v.armed and (v.plan.is_empty() or v.idle or str(v.plan[0].t) != "fight"):
				var foe := nearest_raider(v.position, 30.0)
				if foe:
					v.abort()
					v.give([{"t": "fight", "foe": foe, "give_up": 40.0}], "Kampa saldırıyor")
	var home := _main_store().global_position if _main_store() else Vector3.ZERO
	for r in camp_men:
		if r.hp < r.max_hp * 0.3 and r.job != "Kaçıyor":
			r.abort()
			var away := camp_at + (camp_at - home).normalized() * 120.0
			away.y = nav.height(away.x, away.z)
			r.give([{"t": "go", "to": away}, {"t": "do", "f": func() -> bool:
				camp_men.erase(r)
				r.queue_free()
				return true}], "Kaçıyor")
			continue
		if r.job == "Kaçıyor":
			continue
		# (they keep to their camp: off after someone too far from it, they go back)
		if r.position.distance_to(camp_at) > 50.0 and r.job != "Kampa dönüyor":
			r.abort()
			var back := camp_at + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
			back.y = nav.height(back.x, back.z)
			r.give([{"t": "go", "to": back}], "Kampa dönüyor")
			continue
		if r.job == "Kampa dönüyor" or (not r.plan.is_empty() and str(r.plan[0].t) == "fight"):
			continue
		var foe: Villager = null
		var bd := 40.0
		for v in village.villagers:
			if v.dead or v.down or v.sleeping or v.team != 0 or v.position.distance_to(camp_at) > 45.0:
				continue
			var d := v.position.distance_to(r.position)
			if d < bd:
				bd = d
				foe = v
		if foe:
			r.abort()
			r.give([{"t": "fight", "foe": foe, "give_up": 30.0}], "Kampı savunuyor")
		elif r.plan.is_empty():
			var p := camp_at + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
			p.y = nav.height(p.x, p.z)
			r.give([{"t": "go", "to": p}, {"t": "work", "time": randf_range(6.0, 14.0), "anim": "idle"}], "Kampta")


func _camp_cleared() -> void:
	var got := {"yiyecek": randi_range(20, 40), "odun": randi_range(10, 20), "tas": randi_range(1, 10)}
	var store := _main_store()
	if store:
		for r: String in got:
			village.add_anywhere(r, int(got[r]), store.global_position)
	var arms: Array = village.call("armories")
	if not arms.is_empty():
		(arms[0] as Building).ammo += 12
	message.emit("Firari kampı dağıtıldı! Ganimet depoya: %d yiyecek, %d odun, %d taş%s. Baskınlar bir süre durur." % [got.yiyecek, got.odun, got.tas, "; silahlığa 12 fişek" if not arms.is_empty() else ""], "good")
	next_day = maxi(next_day, village.day + 4)
	camp_at = Vector3.INF
	camp_known = false
	if is_instance_valid(_camp_node):
		var node := _camp_node
		var tw := node.create_tween()
		tw.tween_interval(8.0)
		tw.tween_callback(node.queue_free)
	_camp_node = null


# --- The band -------------------------------------------------------------------------------------

## The evening before, one of the band comes to the edge of the town, hat in hand and a rifle on his
## back: they're starving, give them food and they'll go their way. Given, there's no raid this time
## (and now and then one of them stays, sick of the woods); refused, or no answer by midnight, they
## come in the dark as ever.
func _ask_food() -> void:
	_asked_for = next_day
	if hud == null or _main_store() == null:
		return
	var n := band_size()
	var want := n * 4
	var have := int(village.stock.get("yiyecek", 0))
	var day := next_day
	_ask_card = hud.ask("FİRARİLER KAPIDA",
		"Ormandan biri geldi: yırtık bir asker kaputu, sırtında tüfek, elinde şapkası. \"%d kişiyiz, aç kaldık. %d yiyecek verin, yolumuza gidelim. Vermezseniz gece gelip kendimiz alırız.\"" % [n, want],
		[{"label": "VER (%d yiyecek)" % want, "ok": have >= want, "tip": "Depoda %d yiyecek var" % have, "f": func() -> void:
			if village.pay({"yiyecek": want}, _main_store().global_position) and next_day == day:
				next_day = day + every()
				if randf() < 0.35:
					var at := _main_store().door() + Vector3(randf_range(-4, 4), 0, randf_range(3, 6))
					at.y = nav.height(at.x, at.z)
					var v: Villager = village.spawn_villager(at, false, "", 0)
					v.origin = "asker"
					v.give([{"t": "go", "to": at + Vector3(2, 0, 2)}], "Ormandan geldi, kalmak istiyor")
					message.emit("Firariler yiyeceği alıp gitti; biri kaldı: ormandan bıkmış, kasabaya katılmak istiyor.", "good")
				else:
					message.emit("Firariler yiyeceği alıp ormana döndü. Bu gece baskın yok.", "good")},
		village.talk_option(func() -> void:
			if next_day == day:
				next_day = day + every(), func() -> void: pass),
		{"label": "REDDET", "f": func() -> void:
			message.emit("Firari tükürüp ormana döndü. Gece gelecekler: sur, fener ve tüfekler hazır olsun.", "bad")}])

## A band of `n` on the town: out of the woods (or from `from`, an armoured train's side, the
## camp); `soldiers` a side's men ("merkez", "isyan") in its colours, more of them with rifles.
func start(n: int, from := Vector3.INF, soldiers := "") -> void:
	var store := _main_store()
	if store == null:
		return
	_origin = from if from != Vector3.INF else _edge_point(store.global_position)
	self.soldiers = soldiers
	active = true
	_started = village.clock
	_burnt = 0
	_size = n
	for k in n:
		var r := Villager.new()
		r.team = 1
		r.tunic_color = OUTLAW_TUNIC if soldiers == "" else (Color(0.36, 0.38, 0.27) if soldiers == "merkez" else Color(0.3, 0.1, 0.08))
		r.village = village
		r.nav = nav
		r.hp = 70.0
		r.max_hp = 70.0
		r.attack = 13.0
		r.fighter = true
		# Their parts: about two in five shoot, as many carry the fire, the rest go for the store.
		r.role = "shooter" if k % 5 in [0, 3] or (soldiers != "" and k % 2 == 0) else ("looter" if k % 5 == 4 else "torch")
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
	Ambience.alarm()
	_to_arms()
	if not _towers().is_empty():
		message.emit("Gözcü ormanda ses duydu: %s yönünden %d kişi geliyor!" % [_compass(_origin - store.global_position), n], "bad")
	if not village.bells().is_empty():
		village.ring_bells(8, 0.8)
		message.emit("Tehlike çanı çalıyor: herkes saklanıyor!", "bad")


## A fight starting: the game back to its own pace (no fast-forwarding through it), and the militia
## under the player's hand: each to its armoury for a rifle if it hasn't one, then to a post, and
## from then on where it's sent (right-click), shooting by itself at what it can see.
func _to_arms() -> void:
	if hud and Engine.time_scale > 1.0:
		hud.game.set_speed(1.0)
		message.emit("Çatışma başladı: hız 1x. Milis emrinde: seç, sağ tıkla mevzi göster.", "bad")
	for side: String in Village.SIDES:
		if village.help_why_not(side) == "":
			message.emit("%s dost: TELGRAF'tan yardım isteyebilirsin." % Village.SIDES[side], "info")
			break
	for v: Villager in village.villagers:
		if v.dead or v.down or v.is_child or not v.militia or v.drafted or v.has_trait("no_rifle"):
			continue
		v.drafted = true
		v.set_meta("called_up", true)
		if v.sleeping:
			v.wake()
		v.abort()
		if v.armed:
			village.hold_at(v, village.default_post(v))
		else:
			var a: Building = village.armory_for(v)
			if a:
				village.arm(v, a)


## Over: those called up let go again (they put their rifles back as before).
func _stand_down() -> void:
	for v: Villager in village.villagers:
		if v.has_meta("called_up"):
			v.remove_meta("called_up")
			v.drafted = false
			v.focus = null


## Somewhere out in the woods a few hundred metres from the town, as dark as can be found.
func _edge_point(home: Vector3) -> Vector3:
	if camp_at != Vector3.INF:
		return camp_at # (they come from their camp)
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


## The soldiers come to help don't wait to be found: each goes for the nearest of the band, closing
## to rifle range (into the lamplight if it's dark) and shooting.
func _allies_think() -> void:
	for a in allies:
		if not is_instance_valid(a) or a.dead or a.down:
			continue
		if not a.plan.is_empty() and str(a.plan[0].get("t", "")) == "fight":
			continue
		var foe: Villager = null
		var bd := 160.0
		for list: Array[Villager] in [raiders, camp_men]:
			for r in list:
				if is_instance_valid(r) and not r.dead and not r.down:
					var d := r.position.distance_to(a.position)
					if d < bd:
						bd = d
						foe = r
		if foe == null:
			continue
		a.abort()
		if bd <= a.ranged * 0.9 and can_see(a.position, foe):
			a.give([{"t": "fight", "foe": foe, "give_up": a.ranged + 10.0}], "Ateş ediyor")
		else:
			var to := foe.position + (a.position - foe.position).normalized() * minf(a.ranged * 0.6, 10.0 if not village.is_lit(foe.position) else 25.0)
			to.y = nav.height(to.x, to.z)
			a.give([{"t": "go", "to": to}, {"t": "fight", "foe": foe, "give_up": a.ranged + 10.0}], "Düşmana yürüyor")


## The town and whoever's fighting beside it: what the raiders go for.
func town_folk() -> Array[Villager]:
	var out: Array[Villager] = village.villagers.duplicate()
	for a in allies:
		if is_instance_valid(a) and not a.dead:
			out.append(a)
	return out


## The outlaw or wolf nearest `p` within `reach` (only one that can be seen from `p`, if `seen`).
func nearest_raider(p: Vector3, reach: float, seen := false) -> Villager:
	var best: Villager = null
	var bd := reach
	for list: Array[Villager] in [raiders, wolves, camp_men]:
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
	corpses.append(r)
	corpses = corpses.filter(func(c: Villager) -> bool: return is_instance_valid(c))
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
		message.emit("Bir firari nişancı düştü: tüfeği yerde kaldı.", "good")
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
		_end("Baskın püskürtüldü! Firarilerin hepsi düştü.", "good")
		return
	var dawn := weather.hour > 5.0 and weather.hour < 12.0 and soldiers == ""
	# they don't stay to raze it all: gone when enough's burning, when it's taken too long, when
	# they've lost too many, or at dawn
	var standing := village.buildings.filter(func(b: Building) -> bool: return b.state == "done").size()
	var burning := village.buildings.filter(func(b: Building) -> bool: return b.is_burning()).size()
	var leaving := _burnt >= mini(_size + 2, maxi(2, standing / 4)) or burning * 3 >= maxi(standing, 3) or village.clock - _started > 220.0 or live * 3 < _size or dawn
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
		message.emit("Firariler ormana çekiliyor." if soldiers == "" else "Askerler geri çekiliyor.", "info")
		active = false # (the rest only walk off)
		next_day = village.day + every()
		soldiers = ""
		_finish_quietly()
		_stand_down()
		ended.emit()


## A shooter: whoever it can see within its reach gets shot at; with nobody in sight it creeps up
## to a dark spot at the edge of the light and lies there watching, shooting out a lamp if one's near.
func _think_shooter(r: Villager) -> void:
	var foe: Villager = null
	var bd := r.ranged
	for v in town_folk():
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
				message.emit("Firariler %s vurup söndürdü!" % b.display_name().to_lower(), "bad")
			return


## Someone of the town out in the open near `p` (not hidden, not up a tower).
func _victim_near(p: Vector3, reach: float) -> Villager:
	var best: Villager = null
	var bd := reach
	for v in town_folk():
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
	for v in town_folk():
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
		message.emit("Firariler depoyu yağmaladı: " + ", ".join(took), "bad")
	return haul


func _end(text: String, kind: String) -> void:
	active = false
	next_day = village.day + every()
	message.emit(text, kind)
	soldiers = ""
	_finish_quietly()
	_stand_down()
	ended.emit()


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
		for list: Array[Villager] in [raiders, wolves, camp_men]:
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


## A hostile armoured train's turret gun, while its men are at the town: a heavy crack and a gout of
## flame every few seconds at whoever of the town it can see within 90 m, a shell's burst where it
## lands (and a wide one, as often as not).
var _turret_t := 0.0


func _turret_shots(dt: float) -> void:
	if soldiers == "" or not active:
		return
	var muzzles: Array[Vector3] = []
	if is_instance_valid(village.armoured):
		var tr: Train = village.armoured
		muzzles.append(tr._cars[tr._cars.size() - 1].global_position + Vector3.UP * 4.2 if not tr._cars.is_empty() else tr.engine_at() + Vector3.UP * 4.0)
	for g in guns:
		if is_instance_valid(g):
			muzzles.append(g.global_position)
	if muzzles.is_empty():
		return
	_turret_t -= dt
	if _turret_t > 0.0:
		return
	_turret_t = randf_range(4.0, 7.0)
	var gun: Vector3 = muzzles.pick_random()
	var foe: Villager = null
	var bd := 90.0
	for v in town_folk():
		if v.dead or v.down or v.sleeping or v.team != 0:
			continue
		var d := v.position.distance_to(gun)
		if d < bd and can_see(gun, v):
			bd = d
			foe = v
	if foe == null:
		return
	_flash(gun, "war/shell")
	_flash(gun + Vector3.UP * 0.2, "")
	var at := foe.position + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	at.y = nav.height(at.x, at.z)
	get_tree().create_timer(0.25, false).timeout.connect(func() -> void:
		_flash(at + Vector3.UP * 0.5, "war/shell")
		FireFx.explosion(self, at, 0.7)
		for v in town_folk():
			if not v.dead and v.team == 0 and v.position.distance_to(at) < 3.5:
				v.hurt(randf_range(18.0, 30.0) * (0.5 if v.in_cover else 1.0)))


## The Maxims: a gunner at the gun (within a couple of metres of where it stands) and one it can see
## in 65 m: a burst of eight, a shot every fifth of a second, wide of the mark more often than a
## rifle, a cartridge off the armoury's rack a burst; then a pause. No cartridges, no bursts.
var _mg := {} ## nest -> [seconds to the next shot, shots left in the burst]


func _mg_shots(dt: float) -> void:
	for b in village.buildings:
		if b.def.role != "mg" or b.state != "done":
			continue
		var man: Villager = null
		for v in b.workers:
			if not v.dead and not v.down and v.position.distance_to(b.station()) < 2.5:
				man = v
				break
		if man == null:
			continue
		var st: Array = _mg.get(b, [0.0, 0])
		st[0] = float(st[0]) - dt
		_mg[b] = st
		if float(st[0]) > 0.0:
			continue
		var gun := b.global_transform * Vector3(0, 0.95, 1.2)
		var foe: Villager = null
		var bd := 65.0
		for list: Array[Villager] in [raiders, wolves, camp_men]:
			for r in list:
				if is_instance_valid(r) and not r.dead and not r.down and can_see(gun, r):
					var d := r.position.distance_to(gun)
					if d < bd:
						bd = d
						foe = r
		if foe == null:
			st[1] = 0
			continue
		if int(st[1]) <= 0:
			var arms: Array = village.call("armories")
			var rack: Building = null
			for a: Building in arms:
				if a.ammo > 0:
					rack = a
					break
			if rack == null:
				b.idle_note = "Fişek yok: silahlıkta fişek kalmadı"
				st[0] = 3.0
				continue
			rack.ammo -= 1
			b.idle_note = ""
			st[1] = 8
		st[1] = int(st[1]) - 1
		st[0] = 0.2 if int(st[1]) > 0 else 1.6
		man.look_at(Vector3(foe.position.x, man.position.y, foe.position.z), Vector3.UP)
		shoot(gun, foe, randf_range(18.0, 26.0), clampf(0.45 - bd / 260.0, 0.15, 0.4), null, "war/burst_shot")


## How much of `foe` a shot from `from` can see: what stands between them close in front of it (a
## log wall, sandbags, a palisade, the lip of a trench, a rock, a tree's trunk), and how high the
## shooter is above it (from up a tower or a rise, a man in a trench or behind a low wall shows
## more; shooting uphill, less). [the multiplier on the chance to hit, what covers it]. The same for
## both sides.
func cover(from: Vector3, foe: Villager) -> Array:
	var to := foe.position
	var dir := Vector3(from.x - to.x, 0, from.z - to.z)
	var dist := dir.length()
	if dist < 0.5:
		return [1.0, ""]
	dir /= dist
	var best := 1.0
	var what := ""
	var rise := (from.y - 1.4) - to.y # (the shooter's eye over the man's feet)
	var nav_: Nav = village.nav
	# close in front of it, toward the shooter
	var d := 0.6
	while d < minf(3.2, dist - 0.5):
		var q := to + dir * d
		var k := nav_.shut_kind(q)
		var m := 1.0
		var name := ""
		if k == 2:
			var b := _building_at(q)
			if b:
				match str(b.def.role):
					"obstacle":
						m = 1.0 # (wire stops no bullet)
					"post", "mg":
						m = 0.28
						name = "kum torbası"
					"tower":
						m = 0.4
						name = "kule"
					_:
						m = 0.22
						name = "duvar (%s)" % b.display_name().to_lower()
		elif k == 1:
			m = 0.35
			name = "kaya"
		if m < best:
			best = m
			what = name
		d += 0.35
	# a whole house between them, further out (not the corner the shooter's leaning round: the last
	# metre and a half by it are let be)
	var far := 3.2
	while far < dist - 1.5 and best > 0.12:
		var q := to + dir * far
		if nav_.shut_kind(q) == 2:
			var b := _building_at(q)
			if b and not str(b.def.role) in ["obstacle", "post", "mg"] and b.state == "done":
				best = 0.12
				what = "arada %s" % b.display_name().to_lower()
		far += 1.0
	# hugging a wall or leaning round a corner: half of it out of sight
	if best > 0.65:
		for k in 8:
			var side := to + Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * 1.1
			if nav_.shut_kind(side) == 2:
				var b := _building_at(side)
				if b and not str(b.def.role) in ["obstacle"] and b.state == "done":
					best = 0.65
					what = "duvar dibi / köşe"
					break
	# a palisade between, or on its walkway behind the points
	if foe.in_cover and foe.perched == null and foe.position.y - village.nav.height(foe.position.x, foe.position.z) > 0.8:
		if 0.45 < best:
			best = 0.45
			what = "sur"
	for w in village.walls:
		if not is_instance_valid(w):
			continue
		var n: Dictionary = w.nearest(to + dir * 0.9)
		if not n.is_empty() and float(n.dist) < 0.8 and w.built[int(n.k)] == 1 and 0.4 < best:
			best = 0.4
			what = "kazık sur"
	# a trench: down in it, unless looked into from well above
	if village.in_trench(to):
		var m := 0.35 if rise < 2.5 else 0.7
		if m < best:
			best = m
			what = "hendek"
	# a tree trunk or a boulder in the way, close to it
	if best > 0.4:
		var c := to + dir * 1.2
		for i in village._props_in(c, 1.5):
			if village.props.cut.has(i):
				continue
			var info: Dictionary = village.props.prop_info(i)
			var kind := str(info.kind)
			if not kind in ["tree", "rock", "cliff"]:
				continue
			if Vector2(info.origin.x - c.x, info.origin.z - c.z).length() < (1.4 if kind != "tree" else 0.9):
				var m := 0.6 if kind == "tree" else 0.4
				if m < best:
					best = m
					what = "ağaç" if kind == "tree" else "kaya"
	# height: from above the cover counts for less and the shot's easier; from below, harder
	if rise > 0.5 and best < 1.0:
		best = lerpf(best, 1.0, clampf((rise - 0.5) / 8.0, 0.0, 0.6))
	var h := clampf(1.0 + rise * 0.05, 0.75, 1.35)
	return [best * h, what]


## The building standing over point `p`, if one does.
func _building_at(p: Vector3) -> Building:
	var best: Building = null
	var bd := INF
	for b in village.buildings:
		if b.state == "gone" or b.state == "ghost":
			continue
		var sz: Vector2 = b.def.size
		var local := b.global_transform.affine_inverse() * p
		if absf(local.x) <= sz.x * 0.5 + 0.4 and absf(local.z) <= sz.y * 0.5 + 0.4:
			var dd := Vector2(local.x, local.z).length()
			if dd < bd:
				bd = dd
				best = b
	return best


## A rifle shot from `from` at `foe` (by `by`): a flash, a streak, and `dmg` if it hits (`chance`,
## halved if the foe's behind cover). The flash shows the shooter for a moment to anyone looking.
func shoot(from: Vector3, foe: Villager, dmg: float, chance: float, by: Villager = null, sound := "war/rifle") -> void:
	var to := foe.position + Vector3.UP * 1.0 + Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4))
	if by:
		by.revealed = 2.5
		chance *= by.aim()
		by.learn("nisan", 12.0)
	chance *= float(cover(from, foe)[0])
	_flash(from, sound)
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
	else:
		# a miss: it strikes the ground beyond, in a kick of dust (snow in the winter)
		var past := to + (to - from).normalized() * randf_range(0.5, 3.0)
		past.y = nav.height(past.x, past.z) + 0.05
		_impact(past)


## Where a shot strikes: dust (or snow) kicked up, a few bits flung out.
var _dust: GPUParticles3D


func _impact(at: Vector3) -> void:
	if _dust == null:
		var pm := ParticleProcessMaterial.new()
		pm.gravity = Vector3(0, -4.0, 0)
		pm.damping_min = 1.5
		pm.damping_max = 3.0
		pm.scale_min = 0.5
		pm.scale_max = 1.2
		var g := Gradient.new()
		g.set_color(0, Color(0.55, 0.48, 0.38, 0.75))
		g.set_color(1, Color(0.6, 0.55, 0.47, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		_dust = GPUParticles3D.new()
		_dust.amount = 200
		_dust.lifetime = 0.9
		_dust.emitting = false
		_dust.process_material = pm
		_dust.draw_pass_1 = FireFx._quad(0.25, false)
		_dust.visibility_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 2000, 4000))
		_dust.local_coords = false
		_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_dust)
	var snowy := Weather.snow_cover_now > 0.3
	var c := Color(0.85, 0.88, 0.92, 0.8) if snowy else Color(0.55, 0.48, 0.38, 0.75)
	for k in 5:
		var vel := Vector3(randf_range(-1.2, 1.2), randf_range(1.5, 3.5), randf_range(-1.2, 1.2))
		_dust.emit_particle(Transform3D(Basis.IDENTITY, at), vel, c, Color(1, 1, 1, 1),
			GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR)


## An arrow loosed from `from` at `foe` (by `by`): no flash, hardly a sound, so the archer isn't
## shown; the shaft flies, and `dmg` if it hits (`chance`, halved behind cover).
func arrow(from: Vector3, foe: Villager, dmg: float, chance: float, by: Villager = null) -> void:
	if by:
		chance *= by.aim()
		by.learn("okcu", 12.0)
	chance *= float(cover(from, foe)[0])
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


func _flash(at: Vector3, sound := "war/rifle") -> void:
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
	if sound != "":
		Ambience.play(sound, at, -2.0 if sound == "war/burst_shot" else 0.0, 1.0, 400.0) # (the crack of it, heard far off)
