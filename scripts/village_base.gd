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
		var out := {"odun": 0, "tas": 0, "yiyecek": 0, "camur": 0, "kerpic": 0, "ot": 0}
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
var traps: Array = [] ## stake pits: {at: Vector3, armed: bool, node: Node3D}
var mines: Array = [] ## land mines: {at: Vector3, node: Node3D} (gone once they go off)
var trenches: Array = [] ## {a: Vector2, b: Vector2, done: float 0..1} a 3 m length each, dug by the free hands
var downed_outlaws: Array[Villager] = [] ## outlaws lying wounded after a fight: to be taken to a jail, or to bleed out
var cut_marks := {} ## prop index -> 1: marked to be felled (KES), 2: urgently (ACİL KES: everyone drops their work for it)
var _marks_mm: MultiMeshInstance3D ## an orange band round each marked trunk
var _marks_top: MultiMeshInstance3D ## and a marker over its crown, to be seen from above


var yards: Array = [] ## Yard, one to a house


var roads: Array = [] ## the plank roads laid: each a polyline [x0, z0, x1, z1, ...]
var walls: Array[Wall] = [] ## the palisades
var rail := PackedVector3Array() ## the railway, from the valley's edge to the station (on the ground)
var train: Train
var next_train := 4 ## the day the next train's due up the line (it may be late)
var announced := false ## the town's founding wired to the mainland: settlers come out by train since
var rubles := 40 ## the town's purse: what the train paid, spent on what's sent for
var repute := 0 ## how well the town's thought of by the Centre, up the line (more settlers on each train)
var rebels := 0 ## how well by Free Kordal, the rebels in the woods and on the line (their armoured trains)
var armoured: Train ## (the armoured train standing at the station, if one is)
var armoured_next := 7 ## the first day one may come
var convoy: Convoy ## a side's trucks (and maybe a tank) come by road, if there are
var convoy_next := 9 ## the first day they may
var relief: Convoy ## a friendly side's men on their way or here, called by telegraph
var help_ready := 0 ## the day a side may be asked again
var _help_coming := "" ## (a side asked, the column not yet set out)
var selling: Array[String] = [] ## the goods put on the train when it comes (PRICES)
var loading_until := -1.0 ## the clock when the train standing at the platform leaves (-1: none)
var express := false ## a train wired for: tomorrow, and not late
var cemetery: Cemetery ## (made with the first grave)
var hud: Node ## (for the telegraph's news that wants an answer: ask)
var _news_card: Control
var _news_last := 0 ## the day the last news came over the wire
var drift := 0.0 ## snow lying on the line (0 clear .. 1 buried): past drift_shut() no train gets through
var _drift_mm: MultiMeshInstance3D
var _drift_shown := -1.0
var _shut_said := false
var known: Array[String] = [] ## what's been found out in a reading room (BuildingDefs.TECHS)
var studying := "" ## what the reading rooms are on just now ("" nothing chosen)
var study_pts := 0.0 ## how far into it
var seed := 0
var start_people := 6 ## how many come on the train
var start_crew: Array = [] ## the settlers chosen on the title screen (Villager.candidate), in the order they step down
var arriving := false ## the first train in and its load not yet in the station
var supplies := 1.0 ## how much of START_STOCK it brings


const BILLET_WOOD := 3 ## wood a log gives sawn up


const SAPLING_TIME := 240.0


const LOG_EVERY := 55.0 ## s a lit hearth goes on one firewood
const COAL_LASTS := 3 ## a coal burns as long as this many firewood


## What a house has to burn, in firewood's worth (its coal counted as COAL_LASTS each).
static func house_fuel(b: Building) -> int:
	return int(b.goods.get("odun", 0)) + int(b.goods.get("komur", 0)) * COAL_LASTS + b.coal_burn


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
	dress_line()
	# the station's place along the line (by the line's own length, its rises and falls and all):
	# the coach stops level with it
	train = Train.new()
	train.quiet = true
	train.nav = nav
	train.setup(rail, 0.0, 0.0)
	var s_station := train.s_of(station.global_position)
	train.stop_at = s_station
	train._s = maxf(s_station - 200.0, 0.0)
	add_child(train)
	train.arrived.connect(_train_arrived.bind(station))
	arriving = true
	message.emit("Tren geliyor: ilk yerleşimciler ve yükleri istasyona iniyor.", "info")


# --- The train: what's sent for, paid for in kind, brought up the line now and then --------------

const COIN := "mirka" ## Zarovya's money (the country's made up; so is its coin)
const CALL_PRICE := 30 ## mirka to wire for a train tomorrow (TREN ÇAĞIR)

## What the train buys, a ruble or a few each; of what's marked to be sold, KEEP of each stays
## behind; a train takes LOAD at most. Every ruble earned is that much more repute up the line: the
## better the town's thought of, the more settlers each train brings out to it (once it's announced).
const PRICES := {"odun": 1, "tas": 1, "kerpic": 2, "komur": 3, "demir": 4}
const KEEP := 30
const LOAD := 150
const SETTLERS_PER := 50 ## repute for each settler more a train brings (two at the least)
const SETTLERS_MAX := 8
const LOAD_HOURS := 2.0 ## how long the train stands at the platform (game hours): what's to be sold must be there by then
const SPUR_MAX := 160.0 ## how far a side line runs from the main line, at most (m)
const SPUR_GAUGE := 0.55 ## a side line's narrow gauge, of the main line's


# --- What's found out: a reading room works at one thing at a time -------------------------------

func knows(tech: String) -> bool:
	return tech == "" or tech in known


## Whether `tech` can be taken up now (not known, and what it comes after is).
func can_study(tech: String) -> bool:
	return not knows(tech) and knows(str(BuildingDefs.TECHS[tech].get("after", "")))


## The reading rooms set to `tech` (what's been put into another is kept for it no longer).
func study(tech: String) -> void:
	if tech == studying or not can_study(tech):
		return
	studying = tech
	study_pts = 0.0


## `pts` more on what's being studied; found out when it's enough.
func add_study(pts: float) -> void:
	if studying == "":
		return
	study_pts += pts
	var t: Dictionary = BuildingDefs.TECHS[studying]
	if study_pts >= float(t.pts):
		known.append(studying)
		message.emit("Araştırma tamam: %s. %s" % [t.name, t.desc], "good")
		studying = ""
		study_pts = 0.0


## `cost` taken out of the stores (the nearest `at` first), if they hold it all. Whether they did.
func pay(cost: Dictionary, at: Vector3) -> bool:
	for r: String in cost:
		if int(stock.get(r, 0)) < int(cost[r]):
			return false
	for r: String in cost:
		var left := int(cost[r])
		while left > 0:
			var s := store_with(r, at)
			if s == null:
				break
			left -= s.take_goods(r, left)
	return true


## The station (the railway's end), or null.
func depot() -> Building:
	for b in buildings:
		if b.kind == "istasyon" and b.state == "done":
			return b
	return null


## The town's founding wired to the mainland: from now on the settlers come by train. "" or why not.
func announce() -> String:
	if not knows("telgraf"):
		return "Önce telgraf araştırılmalı"
	if announced:
		return "Köy zaten bildirildi"
	announced = true
	repute += SETTLERS_PER
	message.emit("Köyün kuruluşu Zarovya merkezine bildirildi: göçmenler bundan böyle trenle gelecek.", "good")
	return ""


## How many a train brings, the town's name being what it is (beds aside).
func settlers_due() -> int:
	return clampi(2 + repute / SETTLERS_PER, 2, SETTLERS_MAX)


## A train wired for (CALL_PRICE): it comes tomorrow and isn't late. "" or why not.
func call_train() -> String:
	if not knows("telgraf"):
		return "Önce telgraf araştırılmalı"
	if is_instance_valid(train) or express:
		return "Tren zaten yolda"
	if line_shut():
		return "Hat karla kapalı: önce küreyin (Atölye: HAT KÜRE)"
	if next_train - day <= 1:
		return "Tren zaten yarın geliyor"
	if rubles < CALL_PRICE:
		return "Kasada %d %s gerek" % [CALL_PRICE, COIN]
	rubles -= CALL_PRICE
	express = true
	next_train = day + 1
	return ""


## Of a morning: the train, if it's due (now and then it's late a day or two).
func _train_morning() -> void:
	if not knows("telgraf") or depot() == null or rail.size() < 2 or is_instance_valid(train) or day < next_train:
		return
	if is_instance_valid(armoured):
		next_train = day + 1 # (the platform's taken)
		return
	if line_shut():
		next_train = day + 1
		message.emit("Hat karla kapalı: tren gelemedi. Atölyeden HAT KÜRE seçip rayları açtırın.", "bad")
		return
	if not express and randf() < 0.25 + drift * 0.5: # (snow on the line: later still)
		var late := 1 + randi() % 2
		next_train = day + late
		message.emit("Tren gecikti: %d gün daha bekleniyor." % late, "info")
		return
	express = false
	var st := depot()
	train = Train.new()
	train.nav = nav
	train.setup(rail, 0.0, 0.0)
	train.stop_at = train.s_of(st.global_position)
	train._s = maxf(train.stop_at - 200.0, 0.0)
	add_child(train)
	train.arrived.connect(_train_in.bind(st))
	message.emit("Tren düdüğü: tren istasyona geliyor.", "info")


## The snow on the line. It drifts in as it falls (and a little in any winter wind), melts off in the
## thaw; the shovels (a workshop set to HAT KÜRE) and the engines' ploughs clear it. Past drift_shut()
## the line's shut: no train gets up it, none can be wired for.
const DRIFT_PER_DAY := 0.6 ## in a day of full snow
const DRIFT_WIND := 0.15 ## a winter's day without snow
const MELT_PER_DAY := 0.8


func drift_shut() -> float:
	return 0.9 if knows("kar_sabani") else 0.6


func line_shut() -> bool:
	return drift >= drift_shut()


## The line's state in a word or two, for the cards ("" when it's clear).
func line_state() -> String:
	if line_shut():
		return "HAT KARLA KAPALI (%%%d kar): HAT KÜRE ile açtırın" % roundi(drift * 100.0)
	if drift > 0.15:
		return "Hatta kar var (%%%d, %%%d olunca kapanır): tren gecikebilir" % [roundi(drift * 100.0), roundi(drift_shut() * 100.0)]
	return ""


func _drift_tick(dt: float) -> void:
	if rail.size() < 2 or seasons == null:
		return
	var per_day := maxf(weather.day_length_minutes * 60.0, 60.0)
	var grow := weather.snow_intensity * DRIFT_PER_DAY + (DRIFT_WIND if seasons.winter() else 0.0)
	if knows("kar_sabani"):
		grow *= 0.7
	var melt := MELT_PER_DAY * clampf(weather.temperature / 6.0, 0.0, 1.0) if not seasons.winter() else 0.0
	var was := line_shut()
	drift = clampf(drift + (grow - melt) * dt / per_day, 0.0, 1.0)
	if line_shut() and not was and not _shut_said:
		_shut_said = true
		message.emit("Kar hattı kapattı: tren gelemez. Bir atölyede HAT KÜRE seçin.", "bad")
	elif was and not line_shut():
		_shut_said = false
		message.emit("Hat açıldı: tren yeniden gelebilir.", "good")
	if absf(drift - _drift_shown) > 0.02:
		_drift_show()


## Snow banked on the line, along its length: mounds over the sleepers, as deep as the drift.
func _drift_show() -> void:
	_drift_shown = drift
	if _drift_mm == null:
		if drift < 0.03:
			return
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 1.0
		mesh.radial_segments = 8
		mesh.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.93, 0.95, 0.98)
		mat.roughness = 0.9
		mesh.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var spots: Array[Transform3D] = []
		for k in range(4, rail.size() - 4, 5):
			var c := rail[k]
			if c.y - nav.height(c.x, c.z) > 0.3:
				continue # (up on a bridge: the wind takes it)
			var dir := rail[k + 2] - rail[k - 2]
			dir.y = 0.0
			var yaw := atan2(dir.x, dir.z) + randf_range(-0.2, 0.2)
			var off := dir.normalized().cross(Vector3.UP) * randf_range(-0.6, 0.6)
			spots.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, nav.height(c.x, c.z) + 0.05, c.z) + off))
		mm.instance_count = spots.size()
		for i in spots.size():
			mm.set_instance_transform(i, spots[i])
		_drift_mm = MultiMeshInstance3D.new()
		_drift_mm.multimesh = mm
		_drift_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_drift_mm.set_meta("spots", spots)
		add_child(_drift_mm)
	_drift_mm.visible = drift > 0.03
	if not _drift_mm.visible:
		return
	var spots: Array = _drift_mm.get_meta("spots")
	var mm := _drift_mm.multimesh
	var h := 0.1 + drift * 0.75
	for i in spots.size():
		var t: Transform3D = spots[i]
		var j := sin(i * 1.7) * 0.25 + 1.0
		mm.set_instance_transform(i, Transform3D(t.basis * Basis.from_scale(Vector3(2.1 * j, h * j, 1.6)), t.origin))


## In at the station: the settlers step down, and it stands a while before it goes on.
func _train_in(st: Building) -> void:
	drift *= 0.2 if knows("kar_sabani") else 0.6 # (the engine's plough throws some of it off)
	_settlers_off(st)
	_mail(st)
	next_train = day + 3 + randi() % 4
	# It stands a while: what's to be sold is carried to the platform meanwhile, and goes on as it leaves.
	var secs := maxf(weather.day_length_minutes * 60.0, 60.0) * LOAD_HOURS / 24.0
	loading_until = clock + secs
	if not selling.is_empty():
		message.emit("Tren perona yanaştı: %d saat bekleyecek. Satılacak mallar perona taşınmalı." % int(LOAD_HOURS), "info")
	var tr := train
	get_tree().create_timer(secs, false).timeout.connect(func() -> void:
		loading_until = -1.0
		if is_instance_valid(st):
			_sell(st)
		if is_instance_valid(tr):
			tr.leave())


## What the train brings besides people: the post bag, a letter or two for those whose folk know
## where they've gone (news good and bad, a mood for days), and a crate of bandages for the
## feldsher, if there's one.
const LETTERS_GOOD := [
	["Annesinden mektup: köyde herkes sağ salim", 8.0],
	["Kardeşi esirlikten kurtulmuş, yazıyor", 10.0],
	["Eski bir dosttan mektup ve biraz tütün", 5.0],
	["Nişanlısından mektup: bekliyormuş", 9.0],
	["Ailesinden haber: tarlayı ekebilmişler", 6.0],
]
const LETTERS_BAD := [
	["Mektup geldi: babası salgında ölmüş", -10.0],
	["Köyünün yakıldığını gazeteden okudu", -8.0],
	["Kardeşinden aylardır haber yok, mektuplar geri dönmüş", -6.0],
	["Cepheden kara haber: bir arkadaşı düşmüş", -7.0],
]
const PAPER := [
	"Gazete geldi: başkentte yeni hükümet, cephede ateşkes söylentisi.",
	"Gazete geldi: Kordal Hattı'na yeni köprü yapılacakmış.",
	"Gazete geldi: güneyde kıtlık, tahıl fiyatları yükseliyor.",
	"Gazete geldi: firari askerler için af çıkabilirmiş.",
	"Gazete geldi: Zarovya'nın doğusuna daha çok göçmen yollanacak.",
	"Gazete geldi: savaş esirleri yurtlarına dönmeye başladı.",
]


func _mail(st: Building) -> void:
	var secs := maxf(weather.day_length_minutes * 60.0, 60.0) * 2.0
	var folk: Array[Villager] = []
	for p in villagers:
		if not p.dead and not p.leaving and not p.is_child:
			folk.append(p)
	folk.shuffle()
	var got: Array[String] = []
	for p in folk.slice(0, mini(folk.size(), randi_range(1, 2))):
		var good := randf() < 0.65
		var pick: Array = LETTERS_GOOD.pick_random() if good else LETTERS_BAD.pick_random()
		p.think("letter", str(pick[0]), float(pick[1]), secs)
		got.append("%s (%s)" % [p.display_name, "iyi haber" if good else "kötü haber"])
	if not got.is_empty():
		message.emit("Postayla mektup geldi: %s." % ", ".join(got), "info")
	if randf() < 0.6:
		message.emit(PAPER.pick_random(), "info")
	for b in buildings:
		if b.def.role == "healer" and b.state == "done":
			add_anywhere("ot", 4, st.global_position)
			message.emit("Trenle felçere bir sandık sargı bezi ve ilaç geldi (4).", "good")
			break


## News over the wire of a morning, now and then (not more than one every few days), some of it
## wanting an answer: an armoured train coming through that wants feeding, a wagon of the wounded
## from the front looking for beds, a patrol up the line after deserters, a crate sent by the
## Centre. What's answered moves the town's name up the line (repute) one way or the other.
func _news_morning(force := "") -> void:
	if hud == null or not knows("telgraf") or depot() == null:
		return
	if force == "" and (day - _news_last < 3 or randf() > 0.4):
		return
	if is_instance_valid(_news_card):
		return
	_news_last = day
	var deserters: Array[Villager] = []
	for p in villagers:
		if not p.dead and not p.leaving and p.origin == "asker":
			deserters.append(p)
	var picks := ["zirhli", "yarali", "yardim"]
	if not deserters.is_empty():
		picks.append("devriye")
	match force if force != "" else picks.pick_random():
		"zirhli":
			var food := 10 + villagers.size()
			var wood := 15
			var ok := int(stock.get("yiyecek", 0)) >= food and int(stock.get("odun", 0)) >= wood
			_news_card = hud.ask("TELGRAF · ZIRHLI TREN",
				"\"ZIRHLI TREN YARIN HATTAN GECIYOR STOP ASKERE %d YIYECEK %d ODUN HAZIRLAYIN STOP\"\nVerirseniz Merkez'in gözünde itibarınız artar. Vermezseniz hat bir süre size kapalı tutulur." % [food, wood],
				[{"label": "HAZIRLA", "ok": ok, "tip": "%d yiyecek, %d odun gider" % [food, wood], "f": func() -> void:
					if pay({"yiyecek": food, "odun": wood}, depot().global_position):
						repute += 15
						rubles += 10
						message.emit("Zırhlı tren erzakı aldı, komutan teşekkür etti: itibar arttı, kasaya 10 %s girdi." % COIN, "good")},
				{"label": "REDDET", "f": func() -> void:
					repute = maxi(repute - 20, 0)
					next_train = maxi(next_train, day + 3)
					message.emit("Erzak verilmedi: Merkez kızgın, tren birkaç gün uğramayacak.", "bad")}])
		"yarali":
			var n := randi_range(2, 3)
			var free := beds() - villagers.filter(func(o: Villager) -> bool: return not o.dead).size()
			_news_card = hud.ask("TELGRAF · YARALI VAGONU",
				"\"CEPHEDEN YARALI VAGONU STOP %d ASKER YATAK ARIYOR STOP KABUL EDER MISINIZ STOP\"\nBakılırlarsa iyileşip kasabada kalırlar. Boş yatak: %d." % [n, free],
				[{"label": "KABUL ET", "ok": free >= n, "tip": "%d yatak gerek" % n, "f": func() -> void:
					var st := depot()
					for k in n:
						var at := st.door() + Vector3(randf_range(-3, 3), 0, randf_range(1, 4))
						at.y = ground_at(at)
						var v := spawn_villager(at, false, "", 0)
						v.origin = "asker"
						v.hp = v.max_hp * 0.4
						v.call("_wound", 15.0, null)
						v.think("hurt", "Cepheden yaralı geldi", -6.0, maxf(weather.day_length_minutes * 60.0, 60.0))
						v.give([{"t": "go", "to": at + Vector3(1, 0, 2)}], "Yaralı, istasyonda bekliyor")
					_house_people()
					repute += 10
					message.emit("%d yaralı asker istasyonda indirildi: felçer baksın." % n, "good")},
				{"label": "YER YOK", "f": func() -> void:
					message.emit("Yaralı vagonu bir sonraki kasabaya gitti.", "info")}])
		"devriye":
			var who: Villager = deserters.pick_random()
			_news_card = hud.ask("TELGRAF · DEVRİYE",
				"\"ASKER KACAKLARINI ARAYAN DEVRIYE YOLDA STOP\"\nKasabada cepheden gelenler var. %s korkuyla telgrafhanenin önünde bekliyor. Onu saklarsanız devriye bulabilir; teslim ederseniz Merkez memnun olur, kasaba üzülür." % who.display_name,
				[{"label": "SAKLA", "f": func() -> void:
					if randf() < 0.3 and is_instance_valid(who) and not who.dead:
						repute = maxi(repute - 15, 0)
						_taken_away(who, "Devriye %s'i buldu ve götürdü" % who.display_name)
					else:
						message.emit("Devriye kasabayı aradı, kimseyi bulamadan gitti.", "good")
						if is_instance_valid(who):
							who.think("saved", "Kasaba onu sakladı", 10.0, maxf(weather.day_length_minutes * 60.0, 60.0) * 2.0)},
				{"label": "TESLİM ET", "f": func() -> void:
					repute += 20
					if is_instance_valid(who) and not who.dead:
						_taken_away(who, "%s devriyeye teslim edildi" % who.display_name)
						for o in villagers:
							if o != who and not o.dead:
								o.think("betrayed", "Biri devriyeye teslim edildi", -6.0, maxf(weather.day_length_minutes * 60.0, 60.0))}])
		"yardim":
			add_anywhere("yiyecek", 20, depot().global_position)
			_news_card = hud.ask("TELGRAF · MERKEZ",
				"\"MERKEZDEN KORDAL KOYLERINE ERZAK STOP SIZE 20 YIYECEK BIRAKILDI STOP\"\nİstasyona bir çuval un ve kuru balık bırakıldı.",
				[{"label": "TAMAM", "f": func() -> void: pass}])


## Led off to the station by those who came for them, and gone.
func _taken_away(v: Villager, why: String) -> void:
	v.abort()
	v.leaving = true
	if is_instance_valid(v.workplace):
		v.workplace.workers.erase(v)
	v.workplace = null
	message.emit(why + ".", "bad")
	var to := depot().door() if depot() else v.position
	v.give([{"t": "go", "to": to}, {"t": "do", "f": func() -> bool:
		villagers.erase(v)
		if is_instance_valid(v.home):
			v.home.residents.erase(v)
		v.home = null
		v.queue_free()
		return true}], "Götürülüyor")


## The war on the line: two sides, the Centre (the government's men) and Free Kordal (the rebels),
## and now and then one's armoured train stops at the station, its commander with something to
## ask: food, wood, a lad for the army, the town's rifles. Given, that side thinks better of the
## town and the other worse; refused, worse, and a side that's come to hate the town (HOSTILE)
## doesn't ask: its men come down off the train shooting. A side that's fond of it (FRIENDLY)
## brings something: the Centre money, the rebels rifles.
const SIDES := {"merkez": "Merkez", "isyan": "Özgür Kordal"}
const HOSTILE := -30
const FRIENDLY := 30


func standing(side: String) -> int:
	return repute if side == "merkez" else rebels


func _shift(side: String, by: int) -> void:
	if side == "merkez":
		repute += by
	else:
		rebels += by
	repute = clampi(repute, -100, 400)
	rebels = clampi(rebels, -100, 100)


func standing_text() -> String:
	var parts: Array[String] = []
	for side: String in SIDES:
		var s := standing(side)
		parts.append("%s %+d%s" % [SIDES[side], s, " (DÜŞMAN)" if s <= HOSTILE else (" (dost)" if s >= FRIENDLY else "")])
	return " · ".join(parts)


func _armoured_morning() -> void:
	if day < armoured_next or depot() == null or rail.size() < 2 or is_instance_valid(train) or is_instance_valid(armoured) or line_shut():
		return
	if randf() > 0.35:
		return
	armoured_next = day + 4 + randi() % 3
	send_armoured("merkez" if randf() < 0.5 else "isyan")


## An armoured train of `side` up the line to the station.
func send_armoured(side: String) -> void:
	var st := depot()
	if st == null or is_instance_valid(armoured) or is_instance_valid(train):
		return
	armoured = Train.new()
	armoured.armour = side
	armoured.nav = nav
	armoured.setup(rail, 0.0, 0.0)
	armoured.stop_at = armoured.s_of(st.global_position)
	armoured._s = maxf(armoured.stop_at - 200.0, 0.0)
	add_child(armoured)
	armoured.arrived.connect(_armoured_in.bind(st, side))
	var hostile := standing(side) <= HOSTILE
	message.emit("Zırhlı tren geliyor: %s bayrağı taşıyor%s" % [SIDES[side], ", silahlar kasabaya dönük!" if hostile else "."], "bad" if hostile else "info")
	if hostile and not (call("bells") as Array).is_empty():
		call("ring_bells", 8, 0.8)


func _armoured_in(st: Building, side: String) -> void:
	var tr := armoured
	if not is_instance_valid(tr):
		return
	var name: String = SIDES[side]
	if standing(side) <= HOSTILE:
		# (no asking: they come off it shooting, and it waits for them)
		var n := clampi(3 + villagers.size() / 5, 3, 10)
		raids.start(n, st.door() + (tr.door(Vector3.ZERO) - st.door()) * 0.6, side)
		message.emit("%s askerleri trenden iniyor: kasabaya saldırıyorlar!" % name, "bad")
		raids.ended.connect(func() -> void:
			if is_instance_valid(tr):
				tr.leave(), CONNECT_ONE_SHOT)
		return
	if standing(side) >= FRIENDLY:
		if side == "merkez":
			rubles += 25
			message.emit("Merkez'in zırhlı treni uğradı: komutan kasabaya 25 %s bıraktı." % COIN, "good")
		else:
			var a: Building = call("armories")[0] if not (call("armories") as Array).is_empty() else null
			if a:
				a.arms += 1
				a.ammo += 15
				message.emit("Özgür Kordal'ın treni uğradı: silahlığa bir tüfek ve 15 fişek bıraktılar.", "good")
	var food := 12 + villagers.size()
	var wood := 12
	var opts: Array = []
	var body := ""
	var leave := func() -> void:
		if is_instance_valid(tr):
			get_tree().create_timer(4.0, false).timeout.connect(func() -> void:
				if is_instance_valid(tr):
					tr.leave())
	var other := "isyan" if side == "merkez" else "merkez"
	if side == "merkez":
		body = "Merkez'in zırhlı treni perona yanaştı. Bir yüzbaşı iniyor: \"Ordu için %d yiyecek ve %d odun. Bir de cepheye bir genç.\"\nVerirseniz Merkez sizi korur; isyancılar duyar." % [food, wood]
	else:
		body = "Özgür Kordal'ın kızıl bantlı treni perona yanaştı. Sakallı bir komiser iniyor: \"Ormandaki yoldaşlara %d yiyecek ve %d odun. Silahınız varsa bir tüfek de.\"\nVerirseniz isyancılar sizi korur; Merkez duyar." % [food, wood]
	var ok := int(stock.get("yiyecek", 0)) >= food and int(stock.get("odun", 0)) >= wood
	opts.append({"label": "ERZAK VER", "ok": ok, "tip": "%d yiyecek, %d odun" % [food, wood], "f": func() -> void:
		if pay({"yiyecek": food, "odun": wood}, st.global_position):
			_shift(side, 15)
			_shift(other, -8)
			message.emit("%s erzakı aldı. (%s)" % [name, standing_text()], "info")
		leave.call()})
	if side == "merkez":
		var lads := villagers.filter(func(o: Villager) -> bool: return not o.dead and not o.leaving and not o.is_child and not o.down)
		opts.append({"label": "BİR GENÇ VER", "ok": lads.size() > 2, "tip": "Bir kasabalı orduya gider; kasaya 30 %s" % COIN, "f": func() -> void:
			var who: Villager = lads.pick_random()
			if is_instance_valid(who):
				rubles += 30
				_shift(side, 25)
				_shift(other, -12)
				_taken_away(who, "%s orduya yazıldı, trene bindi" % who.display_name)
				for o in villagers:
					if o != who and not o.dead and o.family == who.family:
						o.think("conscript", "%s cepheye gitti" % who.display_name.split(" ")[0], -10.0, maxf(weather.day_length_minutes * 60.0, 60.0) * 2.0)
			leave.call()})
	else:
		var a2: Building = call("armories")[0] if not (call("armories") as Array).is_empty() else null
		opts.append({"label": "TÜFEK VER", "ok": a2 != null and a2.arms > 0, "tip": "Silahlıktan bir tüfek gider", "f": func() -> void:
			if is_instance_valid(a2) and a2.arms > 0:
				a2.arms -= 1
				_shift(side, 20)
				_shift(other, -12)
				message.emit("İsyancılar tüfeği aldı. (%s)" % standing_text(), "info")
			leave.call()})
	opts.append(talk_option(func() -> void:
		leave.call(), func() -> void:
		_shift(side, -12)
		leave.call()))
	opts.append({"label": "REDDET", "f": func() -> void:
		_shift(side, -20)
		if randf() < 0.4:
			# (they take it anyway)
			var took: Array[String] = []
			for s in stores():
				for r: String in s.goods.keys():
					var n := s.take_goods(r, int(s.goods[r]) / 4)
					if n > 0:
						took.append("%d %s" % [n, BuildingDefs.RES_NAMES[r].to_lower()])
			message.emit("Askerler depoya zorla girdi: %s alındı. (%s)" % [", ".join(took), standing_text()], "bad")
		else:
			message.emit("%s eli boş döndü, ama bunu unutmayacak. (%s)" % [name, standing_text()], "bad")
		leave.call()})
	if hud:
		var card: WeakRef = weakref(hud.ask("ZIRHLI TREN · %s" % Ui.upper(name), body, opts))
		# (it won't stand there forever: no answer in three hours is taken for a no)
		get_tree().create_timer(maxf(weather.day_length_minutes * 60.0, 60.0) * 3.0 / 24.0, false).timeout.connect(func() -> void:
			var c: Control = card.get_ref()
			if c and not c.is_queued_for_deletion():
				c.queue_free()
				(opts[-1].f as Callable).call())
	else:
		leave.call()


## Help by telegraph: a side that thinks well of the town (FRIENDLY) sends men when asked, but not
## at once (HELP_HOURS for them to muster and come), and it's a favour: their goodwill goes down by
## HELP_COST. They fight beside the town till the fight's over (or a day, if there's none), then go.
const HELP_HOURS := 2.0
const HELP_COST := 12


## Why the side can't be asked just now ("" if it can).
func help_why_not(side: String) -> String:
	if not knows("telgraf"):
		return "Önce telgraf"
	if standing(side) < FRIENDLY:
		return "%s yeterince dost değil (+%d gerek)" % [SIDES[side], FRIENDLY]
	if _help_coming != "" or is_instance_valid(relief):
		return "Yardım zaten yolda"
	if day < help_ready:
		return "%d gün sonra yeniden istenebilir" % (help_ready - day)
	if stores().is_empty():
		return "Kasaba yok"
	return ""


func call_help(side: String) -> String:
	var why := help_why_not(side)
	if why != "":
		return why
	_shift(side, -HELP_COST)
	help_ready = day + 3
	_help_coming = side
	var secs := maxf(weather.day_length_minutes * 60.0, 60.0) * HELP_HOURS / 24.0
	message.emit("%s'e telgraf çekildi: askerler toplanıyor, ~%d saat içinde yola çıkacaklar. (%s)" % [SIDES[side], int(HELP_HOURS), standing_text()], "good")
	get_tree().create_timer(secs, false).timeout.connect(func() -> void:
		_help_coming = ""
		_send_relief(side))
	return ""


func _send_relief(side: String) -> void:
	var home: Vector3 = stores()[0].global_position
	# from the side the trouble's coming from if there is any, else anywhere open
	var toward := Vector3.ZERO
	if raids.active:
		toward = (raids.origin() - home)
		toward.y = 0.0
	for k in 30:
		var dir := toward.normalized() if toward.length() > 1.0 and k < 10 else Vector3(cos(randf() * TAU), 0, sin(randf() * TAU))
		dir = dir.rotated(Vector3.UP, randf_range(-0.5, 0.5)) if k < 10 else dir
		var from := home + dir * 240.0
		var to := home + dir * 30.0
		var ok := 0
		for i in 41:
			var p := from.lerp(to, i / 40.0)
			if nav.height(p.x, p.z) > terrain.lake_level + 0.5 and nav.is_ground_open(p):
				ok += 1
		if ok < 34:
			continue
		relief = Convoy.new()
		relief.village = self
		relief.side = side
		relief.ally = true
		relief.tank = standing(side) >= FRIENDLY + 20
		add_child(relief)
		relief.lay(from, to)
		relief.gone.connect(func() -> void: relief = null)
		message.emit("%s askerleri yolda: kamyonlar %s yönünden geliyor." % [SIDES[side], Raids._compass(dir)], "good")
		return
	message.emit("Yardım kasabaya yol bulamadı.", "bad")


## The relief come: its men down off the trucks and to posts facing the trouble, fighting beside
## the town (raids.allies); when it's over (or a day on, if nothing comes), back up and away.
func relief_arrives(c: Convoy) -> void:
	var n := 8 if c.tank else 6
	var at := c.halt_point()
	for k in n:
		var a := Villager.new()
		a.village = self
		a.nav = nav
		a.team = 0
		a.tunic_color = Color(0.36, 0.38, 0.27) if c.side == "merkez" else Color(0.3, 0.1, 0.08)
		add_child(a)
		var p := at + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		p.y = nav.height(p.x, p.z)
		a.position = p
		a.held = "rifle"
		a.armed = true
		a.ammo = 40
		a.ranged = 45.0
		a.attack = 28.0
		a.max_hp = 100.0
		a.hp = 100.0
		a.fighter = true
		a.militia = true
		a.display_name = "%s askeri" % SIDES[c.side]
		a.arm_with("rifle")
		a.died.connect(func(_d: Villager) -> void: raids.allies.erase(a))
		raids.allies.append(a)
		call("hold_at", a, call("default_post", a))
	if c.gun:
		pass # (their tank's gun's for the enemy: it stands guard where it halted)
	message.emit("%s askerleri geldi: mevzilere geçiyorlar." % SIDES[c.side], "good")
	var day_s := maxf(weather.day_length_minutes * 60.0, 60.0)
	for v in villagers:
		if not v.dead:
			v.think("relief", "%s yardıma geldi" % SIDES[c.side], 6.0, day_s * 0.5)
	var leave_after := func() -> void:
		for a in raids.allies.duplicate():
			if is_instance_valid(a):
				raids.allies.erase(a)
				a.queue_free()
		if is_instance_valid(c):
			c.leave()
		message.emit("Yardıma gelen askerler dönüyor.", "info")
	if raids.active:
		raids.ended.connect(func() -> void: get_tree().create_timer(20.0, false).timeout.connect(leave_after), CONNECT_ONE_SHOT)
	else:
		get_tree().create_timer(day_s, false).timeout.connect(func() -> void:
			if raids.active:
				raids.ended.connect(leave_after, CONNECT_ONE_SHOT)
			else:
				leave_after.call())


## By road: a side's convoy now and then, out of the woods to the town's edge (Convoy). Not in the
## deep snow; never while an armoured train or another convoy's about.
func _convoy_morning() -> void:
	if day < convoy_next or is_instance_valid(convoy) or is_instance_valid(armoured) or stores().is_empty():
		return
	if seasons and seasons.winter() and Weather.snow_cover_now > 0.6:
		return
	if randf() > 0.4:
		return
	convoy_next = day + 5 + randi() % 4
	send_convoy("merkez" if randf() < 0.5 else "isyan", day >= 14 or randf() < 0.35)


func send_convoy(side: String, with_tank: bool) -> void:
	var home: Vector3 = stores()[0].global_position
	for k in 30:
		var a := randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var from := home + dir * 240.0
		var to := home + dir * 38.0
		var ok := 0
		var n := 40
		for i in n + 1:
			var p := from.lerp(to, float(i) / n)
			if nav.height(p.x, p.z) > terrain.lake_level + 0.5 and nav.is_ground_open(p):
				ok += 1
		if ok < n * 0.85:
			continue
		convoy = Convoy.new()
		convoy.village = self
		convoy.side = side
		convoy.tank = with_tank
		add_child(convoy)
		convoy.lay(from, to)
		convoy.gone.connect(func() -> void: convoy = null)
		var hostile := standing(side) <= HOSTILE
		message.emit("%s yönünden motor sesleri: %s %s geliyor%s" % [Raids._compass(dir), SIDES[side], "kamyonları ve bir tank" if with_tank else "kamyonları", ", silahlar kasabaya dönük!" if hostile else "."], "bad" if hostile else "info")
		var day_s := maxf(weather.day_length_minutes * 60.0, 60.0)
		for v in villagers:
			v.think("soldiers", "Kasabaya asker geliyor", -5.0 * (0.4 if v.has_trait("brave") else (1.6 if v.has_trait("coward") else 1.0)), day_s * 0.5)
		if hostile and not (call("bells") as Array).is_empty():
			call("ring_bells", 8, 0.8)
		return


## The officer at the town: what his side wants, and the town's answer.
func convoy_demands(c: Convoy, tries := 0) -> void:
	var side := c.side
	var name: String = SIDES[side]
	var other := "isyan" if side == "merkez" else "merkez"
	var food := 14 + villagers.size() * 2
	var wood := 20
	var iron := mini(int(stock.get("demir", 0)), 6)
	var want := {"yiyecek": food, "odun": wood}
	if iron > 0:
		want["demir"] = iron
	var half := {}
	for r: String in want:
		half[r] = int(want[r]) / 2
	var day_s := maxf(weather.day_length_minutes * 60.0, 60.0)
	var mood_all := func(id: String, text: String, by: float) -> void:
		for v in villagers:
			if not v.dead:
				v.think(id, text, by, day_s)
	var can := func(cost: Dictionary) -> bool:
		for r: String in cost:
			if int(stock.get(r, 0)) < int(cost[r]):
				return false
		return true
	var body := ("Bir yüzbaşı kamyondan iniyor, arkasında süngülü askerler: \"Ordu aç. %s. Bugün yüklenir, yarın yola çıkarız.\"" if side == "merkez" else
		"Kızıl kolluklu bir komiser iniyor, tabancası belinde: \"Devrim için %s. Vermezseniz kendimiz alırız.\"") % BuildingDefs.cost_text_of(want)
	if c.tank:
		body += "\nTankın namlusu kasabaya dönük."
	var opts: Array = []
	opts.append({"label": "VER", "ok": can.call(want), "tip": BuildingDefs.cost_text_of(want), "f": func() -> void:
		pay(want, c.halt_point())
		_shift(side, 12)
		_shift(other, -6)
		mood_all.call("convoy", "Erzakımız askere gitti", -3.0)
		message.emit("%s istediğini aldı, konvoy dönüyor. (%s)" % [name, standing_text()], "info")
		c.leave()})
	opts.append({"label": "PAZARLIK (yarısı)", "ok": can.call(half), "tip": BuildingDefs.cost_text_of(half) + ": yarısına razı olabilirler, olmayabilirler", "f": func() -> void:
		if randf() < 0.5:
			pay(half, c.halt_point())
			_shift(side, 4)
			mood_all.call("convoy", "Askerle pazarlık ettik, yarısını verdik", 2.0)
			message.emit("Subay söylendi ama yarısını alıp gitti. (%s)" % standing_text(), "good")
			c.leave()
		else:
			_shift(side, -8)
			message.emit("Subay pazarlığa kızdı.", "bad")
			_convoy_refused(c, 0.35)})
	# talking: up to three goes, each one trying the officer's patience a little more
	opts.append(talk_option(func() -> void:
		_shift(side, 2)
		c.leave(), func() -> void:
		_shift(side, -4)
		if tries < 2:
			convoy_demands(c, tries + 1)
		else:
			_convoy_refused(c, 0.35 + (0.1 if c.tank else 0.0)), tries))
	opts.append({"label": "REDDET", "f": func() -> void:
		_shift(side, -15)
		_convoy_refused(c, 0.2 + (0.25 if standing(side) < 0 else 0.0) + (0.1 if c.tank else 0.0))})
	if hud:
		hud.ask("KONVOY · %s" % Ui.upper(name), body, opts)
	else:
		c.leave()


## Refused: they come in shooting (`chance`), or go, and the town stood up to them.
func _convoy_refused(c: Convoy, chance: float) -> void:
	if randf() < chance:
		convoy_attacks(c)
	else:
		var day_s := maxf(weather.day_length_minutes * 60.0, 60.0)
		for v in villagers:
			if not v.dead:
				v.think("stood", "Askere boyun eğmedik", 6.0, day_s)
		message.emit("Subay tehdit savurdu ama konvoy geri döndü. Kasaba dik durdu. (%s)" % standing_text(), "good")
		c.leave()


## The convoy's men come off shooting, the tank's gun with them; when it's over they go.
func convoy_attacks(c: Convoy) -> void:
	var n := clampi(3 + villagers.size() / 5, 3, 10)
	raids.start(n, c.halt_point(), c.side)
	if c.gun:
		raids.guns.append(c.gun)
	message.emit("%s askerleri kamyonlardan atlıyor: kasabaya saldırıyorlar!" % SIDES[c.side], "bad")
	raids.ended.connect(func() -> void:
		var day_s := maxf(weather.day_length_minutes * 60.0, 60.0)
		for v in villagers:
			if not v.dead:
				v.think("repelled", "Askerleri püskürttük", 8.0, day_s)
		convoy_next = maxi(convoy_next, day + 8) # (it cost them: they'll think twice before the next)
		if is_instance_valid(c):
			if c.gun:
				raids.guns.erase(c.gun)
			c.leave(), CONNECT_ONE_SHOT)


## The town's best talker, to go out and reason with whoever's come wanting (the most persuasive
## grown-up on their feet), and the odds they'll talk them round.
func best_talker() -> Villager:
	var best: Villager = null
	for v in villagers:
		if v.dead or v.down or v.is_child or v.leaving:
			continue
		if best == null or v.skill("ikna") > best.skill("ikna"):
			best = v
	return best


func talk_odds(v: Villager) -> float:
	return clampf(0.15 + v.skill("ikna") * 0.07, 0.15, 0.85) * v.mood_mul()


## The option a question card offers for it: "İKNA ET (Name · İkna 6, %57)"; `won` if they're talked
## round, `lost` if not. The talker learns from it either way.
func talk_option(won: Callable, lost: Callable, tries := 0) -> Dictionary:
	var v := best_talker()
	if v == null:
		return {"label": "İKNA ET", "ok": false, "f": func() -> void: pass}
	var odds := talk_odds(v) * (1.0 - 0.12 * tries) # (each go at it, they're a little harder to move)
	var first := v.display_name.split(" ")[0]
	return {"label": ("İKNA ET (%s · %%%d)" if tries == 0 else "YENİDEN DENE (%s · %%%d)") % [first, roundi(odds * 100.0)],
		"tip": "%s konuşmaya çıkar (İkna %d). Başarırsa bir şey vermeden giderler; başaramazsa kızarlar." % [v.display_name, int(v.skill("ikna"))],
		"f": func() -> void:
			if is_instance_valid(v):
				v.learn("ikna", 90.0)
			if randf() < odds:
				var day_s := maxf(weather.day_length_minutes * 60.0, 60.0)
				if is_instance_valid(v):
					v.think("persuaded", "Onları ikna etti", 10.0, day_s)
				for o in villagers:
					if o != v and not o.dead:
						o.think("talked", "%s onları laf ile geri çevirdi" % first, 4.0, day_s)
				message.emit("%s konuştu, ikna etti: eli boş döndüler." % first, "good")
				won.call()
			else:
				message.emit("%s konuştu ama ikna edemedi; öfkelendiler." % first, "bad")
				lost.call()}


## Where the train loads from: the station, and whatever's on a side line.
func platform() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and (b == depot() or b.spur):
			out.append(b)
	return out


## What's marked to be sold put on the train as it leaves: only what's on the platform (the station
## and the side lines), the workshops' piles there first, never the stores below KEEP of each, LOAD
## at most; paid for.
func _sell(_st: Building) -> void:
	var room := LOAD
	var earned := 0
	var sold: Array[String] = []
	var spare := stock
	var on := platform()
	on.sort_custom(func(a: Building, b: Building) -> bool: return a.def.role != "store" and b.def.role == "store")
	for r in selling:
		var n := 0
		for b in on:
			var want := mini(room - n, int(b.goods.get(r, 0)))
			if b.def.role == "store":
				want = mini(want, int(spare.get(r, 0)) - KEEP)
			if want <= 0:
				continue
			var got := b.take_goods(r, want)
			if b.def.role == "store":
				spare[r] = int(spare.get(r, 0)) - got
			n += got
		if n <= 0:
			continue
		room -= n
		earned += n * int(PRICES[r])
		sold.append("%d %s" % [n, BuildingDefs.RES_NAMES[r].to_lower()])
	if earned > 0:
		rubles += earned
		repute += earned
		message.emit("Trene yüklendi: %s. Kasaya %d %s girdi." % [", ".join(sold), earned, COIN], "good")


## A side line from the main line to `b`: straight, from its door to the nearest of the main line.
func spur_line(b: Building) -> PackedVector3Array:
	var out := PackedVector3Array()
	if rail.size() < 2:
		return out
	var from := b.door()
	var to := rail[_nearest_k(rail, from)]
	var d := Vector3(to.x - from.x, 0, to.z - from.z)
	var n := maxi(int(d.length() / ROAD_STEP), 2)
	for k in n + 1:
		var p := from + d * (float(k) / n)
		p.y = nav.height(p.x, p.z)
		out.append(p)
	return out


## What a side line to `b` costs: iron for the rails, wood for the sleepers, by its length.
func spur_cost(b: Building) -> Dictionary:
	var length := (spur_line(b).size() - 1) * ROAD_STEP
	return {"demir": ceili(length / 5.0), "odun": ceili(length / 2.0)}


## A side line laid to `b`. "" or why not.
func lay_spur(b: Building) -> String:
	if not knows("dekovil"):
		return "Önce okuma odasında Dekovil araştırılmalı"
	if b.spur:
		return "Buraya zaten yan hat var"
	var line := spur_line(b)
	if line.size() < 2 or (line.size() - 1) * ROAD_STEP > SPUR_MAX:
		return "Ana hatta çok uzak (en çok %d m)" % int(SPUR_MAX)
	var cost := spur_cost(b)
	if not pay(cost, b.global_position):
		return "Yan hat için %s gerek" % BuildingDefs.cost_text_of(cost)
	b.spur = true
	_rail_mesh(line, SPUR_GAUGE)
	message.emit("%s yan hatta bağlandı: tren yükünü oradan doğrudan alır." % b.display_name(), "good")
	return ""


## The town announced: settlers off the train, as many as it brings and there are beds for, in
## couples where they can be, stepping down one by one.
func _settlers_off(st: Building) -> void:
	if not announced:
		return
	var free := beds() - villagers.filter(func(o: Villager) -> bool: return not o.dead).size()
	var n := mini(settlers_due(), free)
	if n <= 0:
		message.emit("Trende göçmenler var ama kasabada boş yatak yok: ev kurun.", "info")
		return
	var tr := train
	var sd := Vector3.ZERO
	if is_instance_valid(tr):
		sd = st.global_position - tr.door(Vector3.ZERO)
		sd.y = 0.0
		sd = sd.normalized()
	var fam := ""
	for k in n:
		get_tree().create_timer(0.8 + k * 0.7, false).timeout.connect(func() -> void:
			var at := tr.door(sd) if is_instance_valid(tr) else st.door()
			at.y = ground_at(at)
			var v := spawn_villager(at, false, fam if k % 2 == 1 else "", k % 2)
			fam = v.family
			v.give([{"t": "go", "to": st.door() + Vector3(randf_range(-3, 3), 0, randf_range(1, 4))}], "Trenden indi")
			_house_people())
	message.emit("Trenden %d göçmen iniyor: ana karadan yeni bir hayat için geldiler." % n, "good")


## The line dressed for its years: telegraph poles along it, the water tower and the semaphore by
## the station (EraDressing; laid out the same from the rail and the station on a loaded game).
func dress_line() -> void:
	var era := EraDressing.new()
	add_child(era)
	era.build(self, rail, depot())


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
			store.add_goods(k, roundi(int(START_STOCK[k]) * supplies * _crowd()))
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
func _rail_mesh(line: PackedVector3Array, gauge := 1.0) -> void:
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
		var l := Vector3(c.x, g, c.z) - side * 1.6 * gauge + Vector3.UP * 0.02
		var rr := Vector3(c.x, g, c.z) + side * 1.6 * gauge + Vector3.UP * 0.02
		l.y = (g - 0.1) if up else nav.height(l.x, l.z) + 0.03
		rr.y = (g - 0.1) if up else nav.height(rr.x, rr.z) + 0.03
		var top := Vector3(c.x, g + 0.14, c.z)
		var rl := [top - side * 0.76 * gauge + Vector3.UP * 0.18, top + side * 0.76 * gauge + Vector3.UP * 0.18]
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
	sl.size = Vector3(2.5 * gauge, 0.14, 0.24)
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
	var many := _crowd() # (more on the train, more brought with them)
	_cargo = {"yiyecek": roundi(int(START_STOCK.yiyecek) * supplies * many), "odun": roundi(int(START_STOCK.odun) * supplies * many), "tas": roundi(int(START_STOCK.tas) * supplies * many)}
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
## What the settlers bring, by how many they are: six bring the stock as it stands, each more a
## sixth more (each fewer a sixth less).
func _crowd() -> float:
	return maxf(float(start_people) / 6.0, 0.5)


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
		v.origin = str(data.get("origin", ""))
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
	var day_s := maxf(weather.day_length_minutes * 60.0, 60.0)
	if v.team == 0 and not loading:
		if cemetery == null:
			cemetery = Cemetery.new()
			cemetery.village = self
			add_child(cemetery)
		cemetery.call_deferred("bury", v)
	if v.team == 0:
		for o in villagers:
			if o.family == v.family:
				o.think("grief", "%s öldü: yasta" % v.display_name.split(" ")[0], -25.0, day_s * 2.0)
			else:
				o.think("loss", "Kasabadan biri öldü", -5.0, day_s * 0.6)
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
	if not kind in BuildingDefs.YARDS and not BuildingDefs.DEFS[kind].role in ["farm", "light"]:
		# (the ground round it trodden bare by the building of it and the coming and going, fading into the grass)
		nav.set_yard(b.global_transform, (BuildingDefs.DEFS[kind].size as Vector2) + Vector2(3.0, 3.0), true, 3.5)
	b.finished.connect(_on_finished)
	b.ruined.connect(_on_ruined)
	buildings.append(b)
	b.begin()
	return b


## How far round a building of each sort the woods are cleared (m past its walls), the trees cut
## there leaving their stumps: a settlement is a clearing, not houses stood in the forest.
const CLEARING := {"house": 7.0, "store": 8.0, "square": 6.0, "bell": 5.0, "well": 4.0, "work": 5.0, 
	"carts": 6.0, "research": 5.0, "smith": 5.0, "barracks": 7.0, "tower": 4.0, "jail": 5.0, "healer": 5.0}


func _clear_ground(kind: String, pos: Vector3, yaw: float) -> void:
	var def := BuildingDefs.def(kind)
	var sz: Vector2 = def.size
	var inv := Basis(Vector3.UP, yaw).inverse()
	var ring := float(CLEARING.get(str(def.role), 0.0))
	var reach := sz.length() * 0.5 + 3.0 + ring
	for i in _props_in(pos, reach):
		var info := props.prop_info(i)
		if str(info.kind) == "cliff":
			continue
		var l := inv * (Vector3(info.origin.x, 0, info.origin.z) - Vector3(pos.x, 0, pos.z))
		var dx := absf(l.x) - sz.x * 0.5
		var dz := absf(l.z) - sz.y * 0.5
		if dx <= 1.5 and dz <= 2.5: # (where it stands: gone, root and all)
			props.cut_tree(i)
			reserved.erase(i)
		elif ring > 0.0 and maxf(dx, dz) <= ring:
			# The clearing round it: felled to a stump (now and then one left standing for its shade),
			# the undergrowth grubbed out.
			var o: Vector3 = info.origin
			var keep := fposmod(sin(o.x * 12.9898 + o.z * 78.233) * 43758.5453, 1.0) < 0.12
			if str(info.kind) == "tree":
				if keep:
					continue
				var r := float(props.tree_info(i).radius)
				props.cut_tree(i)
				reserved.erase(i)
				cut_marks.erase(i)
				call("add_stump", Vector3(o.x, nav.height(o.x, o.z) + 0.2, o.z), r * 1.15, i) # (village_work.gd)
			elif str(info.kind) in ["bush", "fern", "log", "stump"]:
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


# --- Stake pits (TUZAK) ----------------------------------------------------------------------------

const TRAP_COST := 2 ## odun a pit
const TRAP_GAP := 2.5 ## m between pits laid in a box


## Pits dug and staked across `area` (a pit every TRAP_GAP), or at its middle if it's a click; a
## sprung one there set again. Each costs TRAP_COST odun from the stores. How many were set.
func lay_traps(area: Rect2) -> int:
	var spots: Array[Vector3] = []
	if area.size.x < 1.5 and area.size.y < 1.5:
		spots.append(Vector3(area.get_center().x, 0, area.get_center().y))
	else:
		var x := area.position.x + TRAP_GAP * 0.5
		while x < area.end.x:
			var z := area.position.y + TRAP_GAP * 0.5
			while z < area.end.y:
				spots.append(Vector3(x, 0, z))
				z += TRAP_GAP
			x += TRAP_GAP
	var n := 0
	for p in spots:
		if int(stock.get("odun", 0)) < TRAP_COST:
			break
		var near: Dictionary = {}
		for t: Dictionary in traps:
			if Vector2(t.at.x - p.x, t.at.z - p.z).length() < TRAP_GAP * 0.6:
				near = t
				break
		if not near.is_empty() and near.armed:
			continue
		if near.is_empty() and (not nav.is_open(p) or nav.on_road(p)):
			continue
		var left := TRAP_COST
		while left > 0:
			var s := store_with("odun", p)
			if s == null:
				break
			left -= s.take_goods("odun", left)
		if near.is_empty():
			p.y = nav.height(p.x, p.z)
			near = {"at": p, "armed": true, "node": null}
			traps.append(near)
		near.armed = true
		_show_trap(near)
		n += 1
	return n


## A pit as it looks: a patch of turned earth with sharpened stakes in it (set), or the stakes
## broken and askew (sprung).
func _show_trap(t: Dictionary) -> void:
	if is_instance_valid(t.node):
		(t.node as Node).queue_free()
	var n := Node3D.new()
	add_child(n)
	n.position = t.at
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color(0.24, 0.18, 0.12)
	var pit := CylinderMesh.new()
	pit.top_radius = 0.75
	pit.bottom_radius = 0.75
	pit.height = 0.04
	var mi := MeshInstance3D.new()
	mi.mesh = pit
	mi.material_override = earth
	mi.position.y = 0.02
	n.add_child(mi)
	var wood := Building.material("dark")
	for k in 7:
		var a := k * TAU / 7.0 + 0.3
		var r := 0.15 + (k % 3) * 0.2
		var stake := CylinderMesh.new()
		stake.top_radius = 0.0
		stake.bottom_radius = 0.04
		stake.height = 0.45 if t.armed else 0.25
		stake.radial_segments = 5
		var s := MeshInstance3D.new()
		s.mesh = stake
		s.material_override = wood
		s.position = Vector3(cos(a) * r, 0.2 if t.armed else 0.08, sin(a) * r)
		s.rotation = Vector3(0.15 if t.armed else 1.1, a, 0.0) # (sprung: knocked flat)
		n.add_child(s)
	t.node = n


## Land mines buried across `area` (one every MINE_GAP), or one at a click. Each takes MINE_COST
## from the stores (iron for the case, coal for the powder). How many were laid.
const MINE_COST := {"demir": 1, "komur": 1}
const MINE_GAP := 5.0


## Where mines (or pits, `gap` apart) would go across `area` (one at a click), each [spot, why not]
## ("" if it can): not in water or on a cliff, not under a building, not on top of another. The woods
## are fine.
func lay_spots(area: Rect2, gap: float, kind: String) -> Array:
	var spots: Array[Vector3] = []
	if area.size.x < 1.5 and area.size.y < 1.5:
		spots.append(Vector3(area.get_center().x, 0, area.get_center().y))
	else:
		var x := area.position.x + gap * 0.5
		while x < area.end.x:
			var z := area.position.y + gap * 0.5
			while z < area.end.y:
				spots.append(Vector3(x, 0, z))
				z += gap
			x += gap
	var out: Array = []
	for p in spots:
		p.y = nav.height(p.x, p.z)
		var why := ""
		var k := nav.shut_kind(p)
		if k == 1:
			why = "su ya da yar"
		elif k == 2:
			why = "bina var"
		elif p.y < terrain.lake_level + 0.2:
			why = "su"
		elif kind == "tuzak" and nav.on_road(p):
			why = "yol"
		elif (mines if kind == "mayin" else traps).any(func(m: Dictionary) -> bool: return Vector2(m.at.x - p.x, m.at.z - p.z).length() < gap * 0.6 and (kind == "mayin" or m.armed)):
			why = "zaten var"
		out.append([p, why])
	return out


func lay_mines(area: Rect2) -> int:
	if not knows("patlayici"):
		message.emit("Önce okuma odasında Patlayıcılar araştırılmalı", "info")
		return 0
	var n := 0
	var short := false
	for e: Array in lay_spots(area, MINE_GAP, "mayin"):
		if str(e[1]) != "":
			continue
		var p: Vector3 = e[0]
		if not pay(MINE_COST, p):
			short = true
			break
		var m := {"at": p, "node": null}
		_show_mine(m)
		mines.append(m)
		n += 1
	if short:
		message.emit("Demir ya da kömür bitti: %d mayın gömülebildi (mayın başı %s)." % [n, BuildingDefs.cost_text_of(MINE_COST)], "info")
	return n


## A mine as it looks: a little mound of turned earth, a stick marking it (for the town's own).
func _show_mine(m: Dictionary) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = m.at
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color(0.22, 0.17, 0.11)
	var mound := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.12
	sm.radial_segments = 8
	sm.rings = 3
	mound.mesh = sm
	mound.material_override = earth
	node.add_child(mound)
	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.015
	cm.height = 0.6
	stick.mesh = cm
	stick.material_override = Building.material("wood")
	stick.position = Vector3(0.45, 0.3, 0)
	node.add_child(stick)
	var rag := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.01, 0.1, 0.16)
	rag.mesh = rm
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.7, 0.12, 0.08)
	rag.material_override = red
	rag.position = Vector3(0.45, 0.55, 0.08)
	node.add_child(rag)
	m.node = node


## A mine under `p` (within `r` m): it goes off. Whether one did.
func mine_under(p: Vector3, r: float) -> bool:
	for m: Dictionary in mines:
		if Vector2(m.at.x - p.x, m.at.z - p.z).length() < r:
			_blow(m)
			return true
	return false


## The blast: a flash and a crash, earth thrown up and a crater left, anyone close cut down
## (the nearer the worse), the ground scorched.
func _blow(m: Dictionary) -> void:
	mines.erase(m)
	if is_instance_valid(m.node):
		(m.node as Node).queue_free()
	var at: Vector3 = m.at
	raids._flash(at + Vector3.UP * 0.5, "war/shell")
	raids._flash(at + Vector3.UP * 1.2, "")
	for k in 8:
		raids._impact(at + Vector3(randf_range(-1.8, 1.8), 0.05, randf_range(-1.8, 1.8)))
	terrain.dig_crater(at, 1.4, 0.5)
	terrain.commit_digs()
	nav.scorch(at, 2.5, 1.0)
	var all: Array[Villager] = []
	all.append_array(villagers)
	all.append_array(raids.raiders)
	all.append_array(raids.camp_men)
	for v in all:
		if is_instance_valid(v) and not v.dead:
			var d := v.position.distance_to(at)
			if d < 4.5:
				v.hurt(70.0 * (1.0 - d / 4.5) + 10.0)


## A trench marked from `a` to `b`, in 3 m lengths for the free hands to dig. How many lengths.
func mark_trench(a: Vector2, b: Vector2) -> int:
	var len := a.distance_to(b)
	if len < 2.0:
		return 0
	var n := maxi(1, int(len / 3.0))
	for k in n:
		var p0 := a.lerp(b, float(k) / n)
		var p1 := a.lerp(b, float(k + 1) / n)
		trenches.append({"a": p0, "b": p1, "done": 0.0, "node": null})
		_show_trench(trenches[-1])
	return n


## A length marked out (pegs and a string) or, dug, the trench itself in the ground.
func _show_trench(t: Dictionary) -> void:
	if is_instance_valid(t.node):
		(t.node as Node).queue_free()
	t.node = null
	if float(t.done) >= 1.0:
		return
	var node := Node3D.new()
	add_child(node)
	var a3 := Vector3(t.a.x, 0, t.a.y)
	var b3 := Vector3(t.b.x, 0, t.b.y)
	a3.y = nav.height(a3.x, a3.z)
	b3.y = nav.height(b3.x, b3.z)
	var line := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.02, 0.02, a3.distance_to(b3))
	line.mesh = lm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.8, 0.6)
	line.material_override = m
	node.add_child(line)
	line.global_position = (a3 + b3) * 0.5 + Vector3.UP * 0.25
	line.look_at(b3 + Vector3.UP * 0.25, Vector3.UP)
	t.node = node


## The next length to dig for a free pair of hands, nearest first.
func trench_to_dig(p: Vector3) -> Dictionary:
	var best := {}
	var bd := 120.0
	for t: Dictionary in trenches:
		if float(t.done) >= 1.0 or t.get("digger") != null and is_instance_valid(t.get("digger")):
			continue
		var c := Vector3((t.a.x + t.b.x) * 0.5, p.y, (t.a.y + t.b.y) * 0.5)
		var d := c.distance_to(p)
		if d < bd:
			bd = d
			best = t
	return best


## A length dug a stint further; finished, the ground's cut down into it.
func dig_on(t: Dictionary, by: float) -> void:
	var was := float(t.done)
	t.done = minf(was + by, 1.0)
	# the ground going down a stint at a time, the spoil banked on the side away from the town
	terrain.dig_trench_part(t.a, t.b, 1.3, TRENCH_DEPTH * (float(t.done) - was), trench_bank(t))
	terrain.commit_digs()
	if float(t.done) >= 1.0:
		_show_trench(t)


const TRENCH_DEPTH := 0.9


## Which side of a trench its spoil's banked on: away from the town (the bank faces the enemy, the
## town's side left open to come and go by).
func trench_bank(t: Dictionary) -> Vector2:
	var across := Vector2(t.b.y - t.a.y, -(t.b.x - t.a.x)).normalized()
	var st: Array = stores()
	if not st.is_empty():
		var home: Vector3 = (st[0] as Node3D).global_position
		if across.dot(Vector2(home.x, home.z) - (t.a + t.b) * 0.5) > 0.0:
			across = -across
	return across


## A place for a militiaman in a dug trench, the nearest to `p` with room (two to a length).
func trench_post(p: Vector3, v: Villager) -> Vector3:
	var best := Vector3.INF
	var bd := 90.0
	for t: Dictionary in trenches:
		if float(t.done) < 1.0:
			continue
		var held := 0
		var c: Vector2 = (t.a + t.b) * 0.5
		for o in villagers:
			if o != v and o.armed and Vector2(o.position.x, o.position.z).distance_to(c) < 2.0:
				held += 1
		if held >= 2:
			continue
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), t.a, t.b)
		var d := q.distance_to(Vector2(p.x, p.z))
		if d < bd:
			bd = d
			best = Vector3(q.x, 0, q.y)
	if best != Vector3.INF:
		best.y = nav.height(best.x, best.z)
	return best


## Down in a dug trench at `p`: cover.
func in_trench(p: Vector3) -> bool:
	for t: Dictionary in trenches:
		if float(t.done) >= 1.0:
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), t.a, t.b)
			if q.distance_to(Vector2(p.x, p.z)) < 0.9:
				return true
	return false


## An outlaw at `p`: a set pit it's stepped into springs on it (hurt, and slowed for good: it limps).
func spring_trap(r: Villager) -> void:
	if not mines.is_empty() and mine_under(r.position, 0.9):
		message.emit("Bir düşman mayına bastı!", "good")
		return
	for t: Dictionary in traps:
		if not t.armed:
			continue
		if Vector2(t.at.x - r.position.x, t.at.z - r.position.z).length() < 0.8:
			t.armed = false
			_show_trap(t)
			r.speed_mul = minf(r.speed_mul, 0.6)
			r.hurt(30.0)
			message.emit("Bir firari kazık tuzağına düştü!", "good")
			return


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
	_unplace(b)
	b.demolish()
	message.emit("%s yıkıldı" % b.display_name(), "info")


## `b` taken off the ground: its people let go, its yard and footprint cleared (not yet gone).
func _unplace(b: Building) -> void:
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
	if b.has_meta("litter") and is_instance_valid(b.get_meta("litter")):
		(b.get_meta("litter") as Node).queue_free()


## Workshop `b` set to make `what` (BuildingDefs.WORKSHOP): fitted out anew where it stands (its
## yard and gear those of the new work), its pile and workers kept. The new one, or null with why
## not in `why`.
func refit(b: Building, what: String, why: Array) -> Building:
	var w: Dictionary = BuildingDefs.WORKSHOP[what]
	var needs := str(w.get("needs", ""))
	if not knows(needs):
		why.append("Önce okuma odasında %s araştırılmalı" % BuildingDefs.TECHS[needs].name)
		return null
	var kind := str(w.kind)
	var mode := str(w.get("mode", ""))
	if b.kind == kind:
		if kind != "camur":
			b.mode = mode
		return b
	var pos := b.global_position
	var yaw := b.global_basis.get_euler().y
	if kind == "camur" and not mud_near(pos):
		why.append("Yakında çamur yok: çamur ıslak zeminde, kıyıda olur")
		return null
	if b.state == "site":
		# (not built yet: the site's laid out again for the other, what was brought for it back in store)
		for r: String in b.delivered:
			add_anywhere(r, int(b.delivered[r]), pos)
		_unplace(b)
		b.state = "gone"
		b.queue_free()
		var ns := place(kind, pos, yaw)
		ns.mode = mode
		return ns
	var crew := b.workers.duplicate()
	var wanted := b.wanted
	var area := b.work_area
	var pile := b.goods.duplicate()
	b.goods.clear()
	_unplace(b)
	b.state = "gone"
	b.queue_free()
	loading = true # (no "done" said for it, no more than for a loaded one)
	var nb := place(kind, pos, yaw)
	nb.complete_now()
	loading = false
	add_litter(nb)
	nb.mode = mode
	nb.wanted = wanted
	nb.work_area = area
	for r: String in pile:
		nb.add_goods(r, int(pile[r]))
	for v: Villager in crew:
		if is_instance_valid(v) and not v.dead:
			v.abort()
			call("employ", v, nb) # (village_work.gd)
	return nb


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
	if b.repaired:
		b.freshen()
	if b.kind == "silahlik" and not b.has_meta("stocked"):
		b.set_meta("stocked", true)
		b.arms = 2
		b.ammo = 40
		message.emit("Silahlık hazır: kasabanın eski iki Mosin tüfeği ve 40 fişek rafta. Kartından tüfekçi ya da okçu yetiştir.", "good")
	if b.def.role == "house":
		_house_people()
		if not _yard_of(b):
			add_yard(b)
	add_litter(b)
	if b.def.role == "light" and not b.repaired:
		b.add_goods("odun", 2) # (it's put up with its first kindling)


func _on_ruined(b: Building) -> void:
	message.emit("%s harabeye döndü! Seçip Onar ya da Yık." % b.display_name(), "bad")
	if b.def.role == "store" and b.goods_total() > 0:
		message.emit("Ambardakiler enkazın altında kaldı; onarılınca geri gelir.", "bad")
	_let_go(b)


## The things lying about round a finished building (TownLitter), once.
func add_litter(b: Building) -> void:
	if b.has_meta("litter") or not TownLitter.KINDS.has(str(b.def.role)):
		return
	var t := TownLitter.new()
	t.building = b
	t.village = self
	b.set_meta("litter", t)
	add_child(t)


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


## Puts `n` of `r` in the store nearest `p` with room (the nearest at all, if they're all full;
## lost if there's none).
func add_anywhere(r: String, n: int, p: Vector3) -> void:
	if n <= 0:
		return
	var s := store_room(p)
	if s == null:
		s = _nearest(stores(), p)
	if s:
		s.add_goods(r, n)


## The store nearest `p` with room left, or null (none, or all full).
func store_room(p: Vector3) -> Building:
	var best: Building = null
	var bd := INF
	for b in stores():
		if b.room() <= 0:
			continue
		var d := b.global_position.distance_squared_to(p)
		if d < bd:
			bd = d
			best = b
	return best


## What all the stores hold, and how much they could: [held, room for].
func store_fill() -> Vector2i:
	var held := 0
	var cap := 0
	for b in stores():
		held += b.goods_total()
		cap += b.holds()
	return Vector2i(held, cap)


## The workplaces asked for workers that have none (nobody free to send).
func unmanned() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role in ["work", "farm", "research", "smith", "healer", "carts"] and b.wanted > 0 and b.workers.is_empty():
			out.append(b)
	return out


## The workplaces whose piles are full (their work stopped till someone carries it off).
func full_yards() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role in ["work", "farm"] and b.room() <= 0:
			out.append(b)
	return out


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
		if b.state == "done" and b.def.role == "carts" and not b.workers.is_empty():
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
