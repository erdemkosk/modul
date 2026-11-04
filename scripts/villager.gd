class_name Villager
extends Node3D
## One of the village's people: walks the Nav grid (wearing the ground as it goes), carries what it's
## given to carry, works where it's sent. What it does is a plan, a list of steps the Village gives it:
##   {t: "go", to: Vector3}                       walk there
##   {t: "work", time, anim, face, tick?, done?}  work on the spot (`tick` says when to stop, else `time`)
##   {t: "do", f: Callable}                       do something at once; false calls the plan off
##   {t: "fight", foe: Villager, give_up?}         run it down and strike till one of them falls
##   {t: "step", to: Vector3}                     a few steps straight there (in through a door)
## Any step may carry a `job`: what it's doing, said from when that step's under way.
## An emptied plan and the village gives it the next one. Called off (`abort`), what it carried for a
## building site goes back into the store and what it had set aside (a tree) is let go.
##
## Raiders are these too (`team` 1, Raids gives them their plans): the same walk, the same blows.
## Struck, a fighter turns on whoever struck it; at no hit points it falls and lies a while.
##
## A carter pushes a handcart (`has_cart`): it carries three times what a back does, and is quick on
## a trodden path, but it wears the ground three times as hard, and on soft or rain-soaked ground
## it's slow and now and then sinks in and has to be heaved out.
## A drover leads an ox and its two-wheeled cart (`vehicle` "ox"): thirty to a load, slow and
## steady, the ruts it leaves deepest of all; mud stops it more often and for longer.

signal died(v: Villager)

const LANTERN_REACH := 7.0

const TUNICS := [Color(0.42, 0.24, 0.16), Color(0.3, 0.33, 0.22), Color(0.5, 0.42, 0.28), Color(0.26, 0.3, 0.38),
	Color(0.55, 0.3, 0.2), Color(0.38, 0.36, 0.33), Color(0.46, 0.19, 0.14)]
const SKIN := [Color(0.86, 0.67, 0.53), Color(0.74, 0.55, 0.42), Color(0.62, 0.45, 0.33)]

var village: Node
var nav: Nav
var plan: Array = []
var job := "Boşta"
var idle := false ## its plan is only standing about: anything else may have it
var workplace: Building
var home: Building
var sleeping := false
var carry_res := ""
var carry_n := 0
var owed := {} ## {site, res, n}: taken from the store for a building site, not yet delivered
var target: Node ## the building its plan is for
var team := 0 ## 0 the village's, 1 a raider
var hp := 50.0
var max_hp := 50.0
var attack := 9.0
var dead := false
var fighter := false ## turns on whoever strikes it (a guard, a raider), rather than running
var inside: Building ## the building it's in (asleep, hiding)
var hiding := false
var perched: Building ## the tower it's up on
var tunic_color := Color(0, 0, 0, 0) ## (unset: one of TUNICS)
var display_name := "Kasabalı"
var meal_key := "" ## the last meal it had ("<day>-<o|a>")
var is_child := false
var born_day := 0
var _hit_t := 0.0 ## s to the next blow's sound
var _sit := 0.0 ## 0 standing .. 1 sat on the ground
var _hip_y := 0.78
var ranged := 0.0 ## a rifle's reach (0: hand to hand)
var speed_mul := 1.0
var has_cart := false ## pushing or leading a cart of any kind
var vehicle := "" ## "", "hand", "ox"

var _path := PackedVector3Array()
var _path_i := 0
var _elapsed := 0.0
var _anim := ""
var _phase := 0.0
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _elbows: Array[Node3D] = [] ## the forearms' pivots (on a model built in two at the elbow)
var _knees: Array[Node3D] = [] ## the shins' pivots
var _torso: Node3D
var _load: Node3D
var _wire_t := 0.0 ## s at the wire in front of it
var _yaw := 0.0
var _weapon: Node3D
var _attack_t := 0.0
var _chase_at := Vector3.INF
var _tunic: StandardMaterial3D
var _cart: Node3D
var _wheels: Array[Node3D] = []
var _stuck := 0.0 ## seconds left heaving the cart out of the mud
var _bed: Node3D ## where a load sits
var _wheel_r := 0.36
var _ox_legs: Array[Node3D] = []
var _ox_head: Node3D
var _lantern: Node3D
var _tool: Node3D
var _tool_kind := ""
var _body: Townsfolk ## the rigged townsman (null: the old jointed figure)
var look_seed := 0 ## what its body was dressed from (Portraits builds it again from this)
var look_kind := "man"
var uniform := "" ## a side's soldier: "merkez", "kordal" (by tunic_color); "" its own clothes
var seat := -1.0 ## sat down at what it's doing: the seat's height over the ground (-1 on its feet)
var _run := 1.0 ## (a child at play runs)
var _talk_turn := -1 ## the turn of the talk it last spoke in
var _talk_look := Vector3.INF ## (in a talk: whoever's speaking, to look at)
var _saw_foe := false ## (it has called out the band coming)
# --- the defence
var militia := false ## takes a rifle from the armoury when the alarm goes
var drafted := false ## under the player's orders (skipped by Village._assign)
var armed := false ## has an armoury weapon in hand
var weapon := "" ## what it's trained to: "rifle", "bow" ("" marked by hand: whatever's on the rack)
var held := "" ## what it took from the rack this time
var ammo := 0 ## cartridges on it
var lantern_mode := "" ## "": lit at night, "off": kept dark
var revealed := 0.0 ## s it can be seen anywhere (the flash of its own shot)
var in_cover := false ## behind a wall or a fence: half as easy to hit
var focus: Villager ## (drafted) the one it's told to shoot
var down := false ## shot and lying wounded: bleeding out unless carried in
var bleed := 0.0 ## s left
var carried_by: Villager
var recovering := false ## abed till it's mended
var role := "" ## an outlaw's: "shooter", "torch", "looter"
# --- who it is
## What the town's work asks of hands and eyes, and the name each goes by.
const SKILLS := {"odun": "Odunculuk", "insa": "İnşaat", "tas": "Taşçılık", "tarim": "Tarım", "toplama": "Toplayıcılık",
	"tasima": "Taşıma", "zanaat": "Zanaat", "nisan": "Nişancılık", "okcu": "Okçuluk", "bilgi": "Okuryazarlık", "ikna": "İkna"}
var skills := {} ## skill -> 0..10, growing as it's done
var prio := {} ## skill -> 0 never, 1 as needed, 2 first
var keen: Array[String] = [] ## the work it's keen on (one or two): learnt twice as fast
var origin := "" ## where it came from, before the valley (ORIGINS): a knack it brought with it
var traits: Array[String] = [] ## who it is (TRAITS): none, one or two, each for better and for worse
var scars: Array[String] = [] ## what a bad wound left it with for good (SCARS)
var bleeding := false ## wounded and on its feet, losing blood till it's bound up (a healer)
var wounds: Array[Dictionary] = [] ## where it's hurt just now: {part (PARTS), how (WOUND_KINDS)}, gone when it's mended
var treated := false ## its wound seen to by a healer: mends quicker, seldom leaves a scar
var wounded_badly := false ## it went down: its mending may leave a scar

## Who they were before they came to the valley, out of the war and the turmoil: each brings a
## knack with it (`skill`, that much better to begin with).
const ORIGINS := {
	"esir": {"name": "Savaş esiri", "desc": "Kamptan çıkmış eski bir esir; esirken demiryolu inşaatında çalıştı.", "skill": "insa", "by": 2.0},
	"surgun": {"name": "Sürgün", "desc": "Okumuş biri, siyasi sürgün; kitapla, kalemle arası iyi.", "skill": "bilgi", "by": 3.0},
	"demiryolcu": {"name": "Demiryolcu", "desc": "Hatta, istasyonlarda yük taşıdı.", "skill": "tasima", "by": 2.0},
	"asker": {"name": "Terhis asker", "desc": "Cepheden döndü; tüfeği iyi tanır.", "skill": "nisan", "by": 2.0},
	"koylu": {"name": "Köylü", "desc": "Toprağı bilir, kaçarken tarlasını bıraktı.", "skill": "tarim", "by": 2.0},
	"makinist": {"name": "Makinist", "desc": "Fabrikada, atölyede makine başında çalıştı.", "skill": "zanaat", "by": 2.0},
	"felcer": {"name": "Felçer", "desc": "Sahra hastanesinde sağlık eriydi; otu, sargıyı bilir.", "skill": "toplama", "by": 2.0},
	"papaz": {"name": "Köy papazı", "desc": "Bir köyün papazıydı; insanlarla konuşmayı, öfkeyi yatıştırmayı bilir.", "skill": "ikna", "by": 4.0},
	"tuccar": {"name": "Seyyar tüccar", "desc": "Panayır panayır dolaştı; pazarlıkta, dil dökmede üstüne yoktur.", "skill": "ikna", "by": 3.0},
	"oduncu": {"name": "Ormancı", "desc": "Kordal taygasında büyüdü; baltayı herkesten iyi tutar.", "skill": "odun", "by": 2.0},
}


## Where it came from: one at random, its knack added.
func roll_origin(rng: RandomNumberGenerator) -> void:
	var keys := ORIGINS.keys()
	origin = keys[rng.randi() % keys.size()]
	var o: Dictionary = ORIGINS[origin]
	skills[o.skill] = minf(skill(o.skill) + float(o.by), 10.0)


## Where a blow lands, and how often (the body's the biggest mark, the head the smallest).
const PARTS := {"bas": ["baş", 1], "govde": ["gövde", 4], "sol_kol": ["sol kol", 2], "sag_kol": ["sağ kol", 2], "sol_bacak": ["sol bacak", 2], "sag_bacak": ["sağ bacak", 2]}
## What a wound is, worst last.
const WOUND_KINDS := ["sıyrık", "kesik", "derin kesik", "kurşun yarası"]


## A wound where the blow landed (`dmg` hard, from `by`): the worse kept if it's struck there again.
func _wound(dmg: float, by: Villager) -> void:
	var can: Array[String] = []
	for p: String in PARTS:
		if not (p == "sol_kol" and "tek_kol" in scars) and not (p == "sol_bacak" and "tek_bacak" in scars): # (not where a limb's gone)
			can.append(p)
	var total := 0
	for p in can:
		total += int(PARTS[p][1])
	var roll := randi() % total
	var part := "govde"
	for p in can:
		roll -= int(PARTS[p][1])
		if roll < 0:
			part = p
			break
	var how := "sıyrık"
	if dmg >= 10.0:
		how = "kurşun yarası" if by and is_instance_valid(by) and by.held == "rifle" else ("derin kesik" if dmg >= 20.0 else "kesik")
	for w: Dictionary in wounds:
		if w.part == part:
			if WOUND_KINDS.find(how) > WOUND_KINDS.find(str(w.how)):
				w.how = how
			return
	wounds.append({"part": part, "how": how})


## Its wounds in a word each ("sağ bacak: kurşun yarası, gövde: sıyrık").
func wounds_text() -> String:
	var out: Array[String] = []
	for w: Dictionary in wounds:
		out.append("%s: %s" % [PARTS[w.part][0], w.how])
	return ", ".join(out)


## What a bad wound can leave, for good: like a trait, but only the worse.
const SCARS := {
	"topal": {"name": "Topal", "minus": "%25 yavaş yürür", "walk": 0.75},
	"eli_sakat": {"name": "Eli sakat", "minus": "%15 yavaş çalışır, nişanı kötü", "work": 0.85, "aim": 0.8},
	"yuzu_yarali": {"name": "Yüzü yaralı", "minus": "yarası iz bıraktı", },
	"tek_kol": {"name": "Tek kollu", "minus": "sol kolu omuzdan yok: %35 yavaş çalışır, yarı yük taşır, tüfek kullanamaz", "work": 0.65, "carry": 0.5, "aim": 0.5, "no_rifle": true},
	"tek_bacak": {"name": "Tek bacaklı", "minus": "sol bacağı dizden aşağı yok: koltuk değneğiyle, %45 yavaş yürür", "walk": 0.55, "work": 0.9},
}

## What it can be, each as good as it's bad, by how it changes: its work's pace, how quick it
## learns, what it carries, its walk, its hit points, what it eats, its aim; and the cold, the raids.
const TRAITS := {
	"caliskan": {"name": "Çalışkan", "plus": "iş hızı +%20", "minus": "%30 daha çok yer", "work": 1.2, "eat": 1.3},
	"tembel": {"name": "Tembel", "plus": "%30 daha az yer", "minus": "iş hızı −%20", "work": 0.8, "eat": 0.7},
	"pehlivan": {"name": "Pehlivan", "plus": "1,5 kat taşır, can +30", "minus": "%30 yavaş öğrenir", "carry": 1.5, "hp": 30, "learn": 0.7},
	"zeki": {"name": "Zeki", "plus": "%50 hızlı öğrenir", "minus": "narin: can −20", "learn": 1.5, "hp": -20},
	"cevik": {"name": "Çevik", "plus": "%20 hızlı yürür", "minus": "can −10", "walk": 1.2, "hp": -10},
	"sibir": {"name": "Kordallı", "plus": "soğuk evde üşümez", "minus": "%15 daha çok yer", "cold": true, "eat": 1.15},
	"gozukara": {"name": "Gözü kara", "plus": "nişan +%20, baskında kaçmaz", "minus": "firari yakına gelirse eli boş da dalar", "aim": 1.2, "brave": true},
	"korkak": {"name": "Korkak", "plus": "iş hızı +%10 (dikkatli)", "minus": "milis olmaz, baskında hemen saklanır", "work": 1.1, "coward": true},
	"obur": {"name": "Obur", "plus": "sağlam: can +20", "minus": "%50 daha çok yer", "hp": 20, "eat": 1.5},
	"kanaatkar": {"name": "Kanaatkâr", "plus": "%40 daha az yer", "minus": "zayıf: can −15", "eat": 0.6, "hp": -15},
}
## How it's feeling (0..100): 50 and what it's been thinking lately, each thought for a while.
var thoughts: Array = [] ## {id, text, value, left (s)}
var low_for := 0.0 ## s its spirits have been at breaking point
var leaving := false ## (gone for good: on its way out of the valley)
var held_in: Building ## (an outlaw) the jail it's held in
var held_mode := "" ## (a prisoner) "": kept, "kazan": being won over, "calistir": put to work
var won := 0 ## (a prisoner being won over) mornings of it
var sulk_cd := 0.0 ## s before it can go off on its own again
var _trap_t := 0.0
var mood: float:
	get:
		var m := 50.0
		for t: Dictionary in thoughts:
			m += float(t.value)
		return clampf(m, 0.0, 100.0)

const BUILD_PACE := 1.5625
const BREAK := 15.0 ## spirits this low: it can't go on ## building, mending, a house made better: a quarter quicker than other work
const TRAIT_CLASH := [["caliskan", "tembel"], ["obur", "kanaatkar"], ["gozukara", "korkak"], ["obur", "tembel"]]
var family := "" ## the surname's stem ("Ivanov"): a family shares a house
var female := false


## Two things it's good at, one it's poor at, the rest middling (a child: nothing yet); keen on
## one or two, whatever it's good at.
func roll_skills(rng: RandomNumberGenerator) -> void:
	var keys := SKILLS.keys()
	for k: String in keys:
		skills[k] = 0.0 if is_child else rng.randf_range(1.0, 3.5)
		prio[k] = 1
	roll_keen(rng)
	roll_traits(rng)
	apply_traits()
	if is_child:
		return
	keys.shuffle()
	skills[keys[0]] = rng.randf_range(5.5, 7.5)
	skills[keys[1]] = rng.randf_range(4.0, 6.0)
	roll_origin(rng)
	skills[keys[keys.size() - 1]] = rng.randf_range(0.0, 0.8)


## A settler to choose on the title screen (TitleMenu): a name, `family` (a new one if ""), what
## they're good at and keen on, their traits and their face's seed, as spawn_villager takes them.
static func candidate(rng: RandomNumberGenerator, female: bool, family: String) -> Dictionary:
	var base := preload("res://scripts/village_base.gd")
	var v := Villager.new()
	v.female = female
	v.roll_skills(rng)
	var fam := family if family != "" else str(base.SURNAMES[rng.randi() % base.SURNAMES.size()])
	var first: String = base.NAMES[(12 + rng.randi() % 12) if female else rng.randi() % 12]
	var out := {"name": "%s %s%s" % [first, fam, "a" if female else ""], "family": fam, "female": female,
		"skills": v.skills.duplicate(), "keen": v.keen.duplicate(), "traits": v.traits.duplicate(), "origin": v.origin, "look_seed": (rng.randi() % 2147483646) + 1}
	v.free()
	return out


## A thought `id` (one of a kind at a time: a new one takes its place) worth `value` to its
## spirits, said as `text`, for `secs` s.
func think(id: String, text: String, value: float, secs: float) -> void:
	for t: Dictionary in thoughts:
		if t.id == id:
			t.text = text
			t.value = value
			t.left = maxf(float(t.left), secs)
			return
	thoughts.append({"id": id, "text": text, "value": value, "left": secs})


## The thoughts worn off with `dt` s.
func _fade_thoughts(dt: float) -> void:
	for i in range(thoughts.size() - 1, -1, -1):
		thoughts[i].left = float(thoughts[i].left) - dt
		if float(thoughts[i].left) <= 0.0:
			thoughts.remove_at(i)


## Its spirits in a word, and their colour.
func mood_word() -> String:
	var m := mood
	return "keyifli" if m >= 75.0 else ("iyi" if m >= 55.0 else ("idare eder" if m >= 40.0 else ("morali bozuk" if m >= 20.0 else "çökmüş")))


## Its spirits' say in its pace and learning: in good heart a tenth quicker, low a sixth slower,
## broken a third.
func mood_mul() -> float:
	var m := mood
	return 1.1 if m >= 70.0 else (1.0 if m >= 35.0 else (0.85 if m >= 18.0 else 0.67))


## None, one or (now and then) two traits, never two that clash.
func roll_traits(rng: RandomNumberGenerator) -> void:
	traits.clear()
	var n := 0 if rng.randf() < 0.2 else (2 if rng.randf() < 0.35 else 1)
	var keys := TRAITS.keys()
	var tries := 0
	while traits.size() < n and tries < 20:
		tries += 1
		var t: String = keys[rng.randi() % keys.size()]
		if t in traits or TRAIT_CLASH.any(func(c: Array) -> bool: return t in c and traits.any(func(o: String) -> bool: return o in c)):
			continue
		traits.append(t)


## Its traits' and scars' say in `what` ("work", "learn", "carry", "walk", "eat", "aim"): their
## factors multiplied.
func trait_mul(what: String) -> float:
	var f := 1.0
	for t in traits:
		f *= float(TRAITS[t].get(what, 1.0))
	for t in scars:
		f *= float(SCARS[t].get(what, 1.0))
	return f


## Whether any of its traits (or scars) has `what` ("cold", "brave", "coward", "no_rifle").
func has_trait(what: String) -> bool:
	return traits.any(func(t: String) -> bool: return bool(TRAITS[t].get(what, false))) \
		or scars.any(func(t: String) -> bool: return bool(SCARS[t].get(what, false)))


var _crutch: Node3D


## What it's lost shown on its body: a lost arm gone from the shoulder (the left: the right hand
## holds the tools), a lost leg gone from the knee and a crutch under its arm.
func show_scars() -> void:
	if not _body or not _body.pose:
		return
	_body.pose.lost.clear()
	if "tek_kol" in scars:
		_body.pose.lost.append("LeftUpperArm")
	if "tek_bacak" in scars:
		_body.pose.lost.append("LeftLowerLeg")
		if _crutch == null:
			_crutch = Node3D.new()
			add_child(_crutch)
			var wood := Building.material("wood")
			for part: Array in [[Vector3(0.05, 1.2, 0.05), Vector3(0, 0.6, 0)], [Vector3(0.22, 0.05, 0.08), Vector3(0, 1.22, 0)], [Vector3(0.14, 0.04, 0.05), Vector3(0, 0.75, 0)]]:
				var m := BoxMesh.new()
				m.size = part[0]
				var mi := MeshInstance3D.new()
				mi.mesh = m
				mi.material_override = wood
				mi.position = part[1]
				_crutch.add_child(mi)
			_crutch.position = Vector3(-0.32, 0.0, -0.05)
			_crutch.rotation.z = 0.12


## Struck hard enough to lose an arm or a leg there and then (`dmg` from a heavy blow or a shot): it
## goes down with it.
func _maim() -> void:
	var can: Array[String] = []
	for s in ["tek_kol", "tek_bacak"]:
		if not s in scars:
			can.append(s)
	if can.is_empty():
		return
	var s: String = can[randi() % can.size()]
	scars.append(s)
	apply_traits()
	show_scars()
	think("scar", "%s" % ("Kolunu yitirdi" if s == "tek_kol" else "Bacağını yitirdi"), -15.0, maxf(village.weather.day_length_minutes * 60.0, 60.0) * 3.0)
	village.message.emit("%s ağır yaralandı: %s!" % [display_name, "kolu koptu" if s == "tek_kol" else "bacağı koptu"], "bad")


## Mended from a bad wound: whether it's left anything, more likely if nobody saw to it; the worst
## (an arm or a leg lost) only then.
func _roll_scar() -> void:
	var chance := 0.08 if treated else 0.45
	treated = false
	wounded_badly = false
	if randf() >= chance:
		return
	var pick: Array[String] = ["topal", "eli_sakat", "yuzu_yarali"]
	if chance > 0.2:
		pick += ["topal", "eli_sakat", "tek_kol", "tek_bacak"]
	var s: String = pick[randi() % pick.size()]
	if s in scars:
		return
	scars.append(s)
	apply_traits()
	show_scars()
	think("scar", "Kalıcı izi kaldı: %s" % SCARS[s].name, -8.0, maxf(village.weather.day_length_minutes * 60.0, 60.0) * 2.0)
	village.message.emit("%s iyileşti ama yarası iz bıraktı: %s." % [display_name, str(SCARS[s].name).to_lower()], "bad")


## Its traits put on its body: its hit points, its walk.
func apply_traits() -> void:
	var add := 0
	for t in traits:
		add += int(TRAITS[t].get("hp", 0))
	max_hp = maxf(20.0, 50.0 + add)
	hp = minf(hp, max_hp) if hp > 0.0 and hp < max_hp and (bleeding or recovering) else max_hp
	speed_mul = trait_mul("walk")


## One kind of work it's keen on, now and then two.
func roll_keen(rng: RandomNumberGenerator) -> void:
	var keys := SKILLS.keys()
	keen.clear()
	for i in (2 if rng.randf() < 0.4 else 1):
		var k: String = keys[rng.randi() % keys.size()]
		if not k in keen:
			keen.append(k)


func skill(k: String) -> float:
	return float(skills.get(k, 2.0))


## How quick at `k` it is: 0.7 at nothing, 1 at middling (5), 1.3 at the best (10).
func knack(k: String) -> float:
	return (0.7 + skill(k) * 0.06 if k != "" else 1.0) * trait_mul("work") * mood_mul() * (BUILD_PACE if k == "insa" else 1.0)


## Better at `k` for `secs` s of doing it (slower the better it already is).
func learn(k: String, secs: float) -> void:
	if k == "" or is_child:
		return
	skills[k] = minf(skill(k) + secs * 0.004 * (2.0 if k in keen else 1.0) * trait_mul("learn") * mood_mul() * (1.0 - skill(k) / 12.0), 10.0)
	if k in keen and not is_child:
		think("keen", "Sevdiği işi yaptı (%s)" % SKILLS[k], 6.0, 240.0)
	elif skill(k) < 1.5 and workplace and Villager.skill_of(workplace) == k:
		think("unfit", "Beceremediği işe verildi", -5.0, 120.0)


## What its work just now draws on.
func work_skill() -> String:
	var j := str(job)
	if j.begins_with("İnşa") or j.begins_with("Sur") or j.begins_with("Onarıyor") or j.begins_with("Büyütüyor"):
		return "insa"
	if j.begins_with("Taşıyor") or j.begins_with("Yakacak") or j.begins_with("Trenden yük"):
		return "tasima"
	if workplace:
		return Villager.skill_of(workplace)
	return ""


static func skill_of(b: Building) -> String:
	match b.kind:
		"oduncu":
			return "odun"
		"tasci", "camur":
			return "tas"
		"okuma":
			return "bilgi"
		"demirci":
			return "zanaat"
		"sifaci":
			return "toplama"
		"tarla":
			return "tarim"
		"toplayici":
			return "toplama"
		"arabaci":
			return "tasima"
		"silahlik", "kule":
			return "nisan"
	return ""


## Its aim with what it holds (a rifle: nişancılık, a bow: okçuluk).
func aim() -> float:
	if team != 0:
		return 1.0
	return (0.75 + skill("okcu" if held == "bow" else "nisan") * 0.05) * trait_mul("aim")
var _speed_now := 0.0 ## m/s over the ground this frame
var _rifle := false

## The tool in the right hand for each kind of work.
const TOOLS := {"mow": "scythe", "eat": "bowl", "chop": "axe", "limb": "axe", "mine": "pick", "build": "hammer", "reap": "sickle", "hoe": "hoe", "dig": "spade", "saw": "saw", "chisel": "mallet",
	"fish": "rod", "pipe": "pipe", "whittle": "knife", "drink": "cup"}


## Room kept between folk: no one walks through another. Everyone on their feet out in the open is
## in a coarse grid rebuilt once a frame, and each is eased off whoever it's pressed up against
## (the one standing at its work less than the one walking).
static var _all: Array[Villager] = []
static var _grid := {}
static var _grid_frame := -1
const ROOM := 0.62 ## m between two, at least
var _pressed := 0.0 ## s it has been pressed up against someone while trying to walk on
var _let_by := 0.0 ## s left that it slips past the others (a jam it couldn't step out of)
## One standing isn't slid over the ground: how far it's been shouldered is gathered up, and once
## it's worth a step it takes one, that way, the feet going (Townsfolk.side_step).
var _nudge := Vector2.ZERO
var _step_v := Vector2.ZERO ## m/s of the step it's taking
var _stepping := 0.0 ## s left of it


func _enter_tree() -> void:
	if not self in _all:
		_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)


func _keeps_room() -> bool:
	return not dead and not down and not sleeping and inside == null and carried_by == null and not has_cart and visible and is_inside_tree()


## A step aside under way, or one begun once it's been shouldered far enough (a few centimetres
## and it just stands; more and it moves its feet).
func _step_aside(dt: float, walking: bool) -> void:
	if walking or seat >= 0.0:
		_nudge = Vector2.ZERO
		_stepping = 0.0
		return
	if _stepping > 0.0:
		_stepping -= dt
		var to := position + Vector3(_step_v.x, 0, _step_v.y) * dt
		if nav.is_open(to) or not nav.is_open(position):
			position.x = to.x
			position.z = to.z
			position.y = village.ground_at(position) if village.has_method("ground_at") else nav.height(position.x, position.z)
		return
	if _nudge.length() > 0.07:
		_stepping = clampf(_nudge.length() / 0.6, 0.35, 0.7) # (a step at an easy pace)
		_step_v = _nudge / _stepping
		_nudge = Vector2.ZERO


func _make_room(dt: float, walking: bool) -> void:
	if seat >= 0.0:
		return # (sat down: the others go round it)
	if _let_by > 0.0:
		_let_by -= dt
		return
	var f := Engine.get_process_frames()
	if f != _grid_frame:
		_grid_frame = f
		_grid.clear()
		for o in _all:
			if is_instance_valid(o) and o._keeps_room():
				var c := Vector2i(floori(o.position.x), floori(o.position.z))
				if _grid.has(c):
					(_grid[c] as Array).append(o)
				else:
					_grid[c] = [o]
	var me := Vector2i(floori(position.x), floori(position.z))
	var push := Vector2.ZERO
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var list: Variant = _grid.get(me + Vector2i(dx, dz))
			if list == null:
				continue
			for o: Villager in list:
				if o == self:
					continue
				var d := Vector2(position.x - o.position.x, position.z - o.position.z)
				var len := d.length()
				if len >= ROOM:
					continue
				if len < 0.01: # (right on top of each other: apart some way, the same way each time)
					d = Vector2(cos(get_instance_id() % 628 * 0.01), sin(get_instance_id() % 628 * 0.01))
					len = 0.01
				push += d / len * (ROOM - len)
				if walking:
					# two meeting: each steps to its own side of the other (the two going round,
					# not leaning into each other face to face for ever)
					push += Vector2(-d.y, d.x) / len * (ROOM - len) * 1.4
	if push == Vector2.ZERO:
		_pressed = 0.0
		return
	if walking:
		_pressed += dt
		if _pressed > 1.5: # (still jammed: let it slip by for a moment)
			_pressed = 0.0
			_let_by = 1.2
			return
	var by := push * minf(dt * (6.0 if walking else 2.5), 0.5)
	if not walking:
		_nudge += by # (stepped, not slid: _step_aside)
		return
	var to := position + Vector3(by.x, 0, by.y)
	if not nav.is_open(to) and nav.is_open(position) and walking:
		_pressed += dt * 2.0 # (a wall behind it: the jam ends sooner)
	if nav.is_open(to) or not nav.is_open(position):
		position.x = to.x
		position.z = to.z
		position.y = village.ground_at(position) if village.has_method("ground_at") else nav.height(position.x, position.z)


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_look()
	if is_child:
		scale = Vector3.ONE * 0.62


## Grown up: full size, and fit to work.
func grow_up() -> void:
	is_child = false
	scale = Vector3.ONE


## The townsfolk as built in Blender (tools/blender/build_villagers.py): a body and four limbs.
const FOLK := ["man_cap", "man_hat", "man_fur", "woman_scarf", "woman_shawl", "man_cap", "man_hat", "woman_scarf"]
static var _folk := {} ## variant -> {Torso, ArmL, ArmR, LegL, LegR: [mesh, position]}


static func _parts(variant: String) -> Dictionary:
	if _folk.has(variant):
		return _folk[variant]
	var path := "res://assets/villagers/%s.glb" % variant
	var out := {}
	if ResourceLoader.exists(path):
		var root := (load(path) as PackedScene).instantiate()
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			out[String(mi.name)] = [mi.mesh, mi.position]
		root.free()
	_folk[variant] = out
	return out


func _build_look() -> void:
	if Townsfolk.available():
		var rng := RandomNumberGenerator.new()
		if look_seed == 0: # (else it was chosen: a settler picked on the title screen keeps their face)
			rng.randomize()
			look_seed = rng.seed if rng.seed != 0 else 1
		rng.seed = look_seed
		# a side's soldier (the relief, a convoy's, a band of them) in that side's uniform
		if tunic_color.is_equal_approx(Color(0.36, 0.38, 0.27)):
			uniform = "merkez"
		elif tunic_color.is_equal_approx(Color(0.3, 0.1, 0.08)):
			uniform = "kordal"
		look_kind = uniform if uniform != "" else ("outlaw" if team == 1 else ("child" if is_child else ("woman" if female else "man")))
		_body = Townsfolk.new()
		add_child(_body)
		_body.build(look_kind, rng)
		_tunic = _body.coat_material
		_body.pose.ground = func(at: Vector3) -> float: return nav.height(at.x, at.z) if nav else at.y
		return
	var parts := _parts("outlaw" if team == 1 else FOLK[randi() % FOLK.size()])
	if parts.has("Torso") and parts.has("ArmL"):
		_build_model(parts)
		return
	var tunic := StandardMaterial3D.new()
	tunic.albedo_color = TUNICS[randi() % TUNICS.size()] if tunic_color.a == 0.0 else tunic_color
	tunic.roughness = 0.95
	_tunic = tunic
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN[randi() % SKIN.size()]
	skin.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.17, 0.13, 0.1)
	dark.roughness = 0.95
	_torso = Node3D.new()
	add_child(_torso)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.21
	cap.height = 0.95
	cap.radial_segments = 10
	cap.rings = 3
	body.mesh = cap
	body.material_override = tunic
	body.position = Vector3(0, 1.17, 0)
	_torso.add_child(body)
	var skirt := MeshInstance3D.new()
	var sk := CylinderMesh.new()
	sk.top_radius = 0.2
	sk.bottom_radius = 0.27
	sk.height = 0.35
	sk.radial_segments = 10
	skirt.mesh = sk
	skirt.material_override = tunic
	skirt.position = Vector3(0, 0.82, 0)
	_torso.add_child(skirt)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.13
	hs.height = 0.27
	hs.radial_segments = 10
	hs.rings = 6
	head.mesh = hs
	head.material_override = skin
	head.position = Vector3(0, 1.74, 0)
	_torso.add_child(head)
	var hat := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	if randf() < 0.5:
		hm.top_radius = 0.02
		hm.bottom_radius = 0.16
		hm.height = 0.18
	else:
		hm.top_radius = 0.13
		hm.bottom_radius = 0.15
		hm.height = 0.1
	hm.radial_segments = 8
	hat.mesh = hm
	hat.material_override = dark if randf() < 0.6 else tunic
	hat.position = Vector3(0, 1.88, 0)
	_torso.add_child(hat)
	for s in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(s * 0.1, 0.78, 0)
		add_child(hip)
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.12, 0.76, 0.14)
		leg.mesh = lm
		leg.material_override = dark
		leg.position = Vector3(0, -0.38, 0)
		hip.add_child(leg)
		_legs.append(hip)
		_hip_y = hip.position.y
		var sh := Node3D.new()
		sh.position = Vector3(s * 0.28, 1.47, 0)
		_torso.add_child(sh)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.1, 0.62, 0.11)
		arm.mesh = am
		arm.material_override = tunic
		arm.position = Vector3(0, -0.3, 0)
		sh.add_child(arm)
		_arms.append(sh)


## The model's body and limbs, turned to face -Z (it was built facing +Z), each limb on a pivot
## at its shoulder or hip for _animate to swing.
func _build_model(parts: Dictionary) -> void:
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.roughness = 0.9
	look.albedo_color = Color(randf_range(0.86, 1.08), randf_range(0.86, 1.08), randf_range(0.86, 1.08)) # (no two dyed quite alike)
	_tunic = look
	var turn := Basis(Vector3.UP, PI)
	_torso = Node3D.new()
	add_child(_torso)
	_torso.add_child(_part_mesh(parts.Torso[0], look, turn))
	for name: String in ["LegL", "LegR"]:
		var hip := Node3D.new()
		hip.position = turn * (parts[name][1] as Vector3)
		add_child(hip)
		hip.add_child(_part_mesh(parts[name][0], look, turn))
		_legs.append(hip)
		_hip_y = hip.position.y
		if parts.has(name + "2"):
			_knees.append(_joint(hip, parts, name, look, turn))
	for name: String in ["ArmR", "ArmL"]: # (turned round, the model's left arm is on +x: the right hand, the one that holds things, goes second)
		var sh := Node3D.new()
		sh.position = turn * (parts[name][1] as Vector3)
		_torso.add_child(sh)
		sh.add_child(_part_mesh(parts[name][0], look, turn))
		_arms.append(sh)
		if parts.has(name + "2"):
			_elbows.append(_joint(sh, parts, name, look, turn))


## The lower half of a limb on its own pivot (the elbow, the knee), hung from the upper half's.
static func _joint(upper: Node3D, parts: Dictionary, name: String, look: Material, turn: Basis) -> Node3D:
	var j := Node3D.new()
	j.position = turn * ((parts[name + "2"][1] as Vector3) - (parts[name][1] as Vector3))
	upper.add_child(j)
	j.add_child(_part_mesh(parts[name + "2"][0], look, turn))
	return j


## What a hand holds hangs from: the forearm, or the whole arm on a model with no elbow.
func _hand(i: int) -> Node3D:
	if _body:
		return _body.hand(i)
	return _elbows[i] if i < _elbows.size() else _arms[i]


## How far down that is to the palm.
func _palm() -> float:
	if _body:
		return 0.0
	return -0.27 if not _elbows.is_empty() else -0.6


static func _part_mesh(mesh: Mesh, mat: Material, turn: Basis) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.basis = turn
	return mi


## What it holds, shown: a log over the shoulder, a stone in its arms, a basket, a bucket.
func set_carry(res: String, n: int) -> void:
	carry_res = res
	carry_n = n
	if _load:
		_load.queue_free()
		_load = null
	if res == "" or n <= 0:
		return
	if has_cart and _bed and res != "su":
		_load = _cart_load(res, n)
		_bed.add_child(_load)
		return
	_load = _hand_load(res, n)
	add_child(_load)


## What's carried in the arms or on the shoulder, as it's carried: logs roped together, stone in a
## wooden hod with a rope handle, a tied sack, a wicker basket, a stack of bricks, a hooped pail.
func _hand_load(res: String, n: int) -> Node3D:
	var at := Node3D.new()
	var rope := Building.material("thatch")
	match res:
		"odun":
			at.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, 0.25), Vector3(0.2, 1.5 if _body else 1.62, 0.0))
			var logs := clampi(1 + n / 7, 1, 4)
			var bark := Building.material("log")
			for k in logs:
				var a := k * TAU / maxf(logs, 1.0)
				_hand_cyl(at, 0.075 if logs > 1 else 0.11, 1.5, Vector3(cos(a), 0, sin(a)) * (0.08 if logs > 1 else 0.0), bark)
			for y: float in [-0.45, 0.45]:
				_hand_cyl(at, 0.15 if logs > 1 else 0.125, 0.04, Vector3(0, y, 0), rope)
		"tas", "komur", "demir":
			at.position = Vector3(0, 1.06, -0.33)
			var board := Building.material("plank")
			_mesh_box(at, Vector3(0.5, 0.03, 0.36), Vector3(0, -0.14, 0), board)
			for s: float in [-1.0, 1.0]:
				_mesh_box(at, Vector3(0.03, 0.28, 0.36), Vector3(s * 0.25, 0, 0), board)
				_mesh_box(at, Vector3(0.5, 0.28, 0.03), Vector3(0, 0, s * 0.18), board)
			var ink: Material = Building.rock_material(3) if res == "tas" else (Building.material("dark"))
			for k in clampi(n / 3, 2, 6):
				var mi := MeshInstance3D.new()
				mi.mesh = Building.rock(k)
				mi.material_override = ink
				mi.scale = Vector3.ONE * 0.2
				mi.position = Vector3(-0.14 + (k % 3) * 0.14, 0.1 + (k / 3) * 0.08, -0.07 + (k % 2) * 0.14)
				at.add_child(mi)
		"yiyecek":
			at.position = Vector3(0, 1.06, -0.33)
			Props.place(at, "sack", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * 0.72), Vector3(0.03, -0.14, 0)))
		"camur":
			at.position = Vector3(0, 1.04, -0.33)
			_basket(at, 0.25, 0.26, rope)
			var mud := StandardMaterial3D.new()
			mud.albedo_color = Color(0.24, 0.17, 0.11)
			_mesh_ball(at, Vector3(0.42, 0.14, 0.42), Vector3(0, 0.12, 0), mud)
		"ot":
			at.position = Vector3(0, 1.04, -0.33)
			_basket(at, 0.23, 0.22, rope)
			var herb := StandardMaterial3D.new()
			herb.albedo_color = Color(0.35, 0.5, 0.22)
			for k in 7:
				var a := k * 2.4
				_mesh_ball(at, Vector3(0.14, 0.18, 0.14), Vector3(cos(a) * 0.12, 0.17 + (k % 3) * 0.03, sin(a) * 0.12), herb)
		"kerpic":
			at.position = Vector3(0, 0.97, -0.33)
			var brick := StandardMaterial3D.new()
			brick.albedo_color = Color(0.66, 0.5, 0.36)
			for k in clampi(1 + n / 3, 1, 5):
				var turn := 0.02 * float(k % 3 - 1)
				_mesh_box(at, Vector3(0.48, 0.075, 0.24), Vector3(turn, 0.04 + k * 0.08, -turn), brick)
		"su":
			at.position = Vector3(0, 1.0, -0.32)
			var stave := Building.material("wood")
			_hand_cyl(at, 0.13, 0.26, Vector3.ZERO, stave)
			var water := StandardMaterial3D.new()
			water.albedo_color = Color(0.2, 0.3, 0.36)
			_hand_cyl(at, 0.115, 0.01, Vector3(0, 0.125, 0), water)
			for y: float in [-0.08, 0.08]:
				_hand_cyl(at, 0.137, 0.02, Vector3(0, y, 0), Building.material("dark"))
			_pole(at, Vector3(-0.13, 0.12, 0), Vector3(0, 0.3, 0), 0.008, Building.material("dark"))
			_pole(at, Vector3(0.13, 0.12, 0), Vector3(0, 0.3, 0), 0.008, Building.material("dark"))
		"yarali":
			pass
		_:
			at.position = Vector3(0, 1.06, -0.33)
			_mesh_box(at, Vector3(0.48, 0.28, 0.34), Vector3.ZERO, Building.material("plank"))
			for s: float in [-0.14, 0.14]:
				_mesh_box(at, Vector3(0.5, 0.03, 0.36), Vector3(0, s, 0), Building.material("dark"))
	return at


func _hand_cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * 0.94
	c.height = h
	c.radial_segments = 9
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _mesh_ball(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 10
	m.rings = 6
	mi.mesh = m
	mi.material_override = mat
	mi.scale = size
	mi.position = pos
	parent.add_child(mi)


## A wicker basket: tapering, a thick rim, bands round it, a bow handle.
func _basket(parent: Node3D, r: float, h: float, wicker: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * 0.72
	c.height = h
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = wicker
	parent.add_child(mi)
	_hand_cyl(parent, r + 0.012, 0.03, Vector3(0, h * 0.5, 0), Building.material("wood"))
	_hand_cyl(parent, r * 0.86, 0.02, Vector3(0, -h * 0.12, 0), Building.material("wood"))
	_pole(parent, Vector3(-r, h * 0.5, 0), Vector3(0, h * 1.05, 0), 0.012, Building.material("wood"))
	_pole(parent, Vector3(r, h * 0.5, 0), Vector3(0, h * 1.05, 0), 0.012, Building.material("wood"))


## How much it carries of `res` in one go.
func capacity(res: String) -> int:
	match vehicle:
		"ox":
			return 30
		"hand":
			return 15
	return roundi({"odun": 20, "tas": 14, "yiyecek": 25, "camur": 12, "kerpic": 14}.get(res, 15) * trait_mul("carry"))


func _drop_vehicle() -> void:
	has_cart = false
	vehicle = ""
	if _cart:
		_cart.queue_free()
		_cart = null
	_bed = null
	_wheels.clear()
	_ox_legs.clear()
	_ox_head = null
	_wheel_r = 0.36


## The handcart, pushed in front (assets/props/hand_cart.glb).
func give_cart(on: bool) -> void:
	_drop_vehicle()
	if not on:
		return
	has_cart = true
	vehicle = "hand"
	_wheel_r = 0.42
	_cart = Node3D.new()
	_cart.position = Vector3(0, 0, -1.25)
	add_child(_cart)
	for mi in Props.place(_cart, "hand_cart"):
		if mi.get_meta("tag", "") == "wheel":
			_wheels.append(mi)
	_bed = Node3D.new()
	_cart.add_child(_bed)


## An ox and its cart, led from its left (assets/props/ox.glb, ox_cart.glb): the head and each leg
## hung from a pivot at their tops, to swing as it walks.
func give_ox(on: bool) -> void:
	_drop_vehicle()
	if not on:
		return
	has_cart = true
	vehicle = "ox"
	_wheel_r = 0.68
	_cart = Node3D.new()
	add_child(_cart)
	var coat := StandardMaterial3D.new()
	coat.vertex_color_use_as_albedo = true
	coat.albedo_color = [Color(0.5, 0.36, 0.25), Color(0.62, 0.52, 0.4), Color(0.34, 0.26, 0.2), Color(0.8, 0.74, 0.64)][randi() % 4]
	coat.roughness = 0.95
	var ox := Node3D.new()
	ox.position = Vector3(0.95, 0, -1.9)
	_cart.add_child(ox)
	_ox_head = Node3D.new()
	_ox_head.position = Vector3(0, 1.42, -1.2)
	ox.add_child(_ox_head)
	var hips := {}
	for mi in Props.place(ox, "ox", Transform3D.IDENTITY, coat):
		var tag: String = mi.get_meta("tag", "")
		var t := mi.transform
		if tag == "head":
			mi.reparent(_ox_head, false)
			mi.transform = _ox_head.transform.affine_inverse() * t
		elif tag == "leg":
			var key := Vector2i(signi(roundi(t.origin.x * 10.0)), signi(roundi(t.origin.z * 10.0 + 1.0)))
			if not hips.has(key):
				var hip := Node3D.new()
				hip.position = Vector3(t.origin.x, 1.0, t.origin.z)
				ox.add_child(hip)
				hips[key] = hip
				_ox_legs.append(hip)
			mi.reparent(hips[key], false)
			mi.transform = (hips[key] as Node3D).transform.affine_inverse() * t
	var cart := Node3D.new()
	cart.position = Vector3(0.95, 0, 1.0)
	_cart.add_child(cart)
	for mi in Props.place(cart, "ox_cart"):
		if mi.get_meta("tag", "") == "wheel":
			_wheels.append(mi)
	_bed = Node3D.new()
	_bed.position = Vector3(0, 0.4, 0)
	cart.add_child(_bed)


## A round stick from `a` to `b`.
func _pole(parent: Node3D, a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = thick
	c.bottom_radius = thick
	c.height = a.distance_to(b)
	c.radial_segments = 6
	mi.mesh = c
	mi.material_override = mat
	var up := (b - a).normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.BACK).normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)
	parent.add_child(mi)


func _mesh_box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)


func _cart_load(res: String, n: int) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, 0.62, 0)
	var big := vehicle == "ox"
	var k := mini(ceili(n / (3.0 if big else 2.0)), 10 if big else 8)
	if big:
		root.scale = Vector3(1.4, 1.2, 1.5)
	for i in k:
		var mi := MeshInstance3D.new()
		match res:
			"odun":
				var c := CylinderMesh.new()
				c.top_radius = 0.1
				c.bottom_radius = 0.11
				c.height = 1.3
				c.radial_segments = 7
				mi.mesh = c
				mi.material_override = Building.material("wood")
				mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3((i % 4) * 0.21 - 0.31, 0.11 + (i / 4) * 0.2, 0))
			"tas":
				var b := BoxMesh.new()
				b.size = Vector3(0.3, 0.22, 0.3)
				mi.mesh = b
				mi.material_override = Building.material("stone")
				mi.position = Vector3((i % 3) * 0.3 - 0.3, 0.11 + (i / 3) * 0.22, ((i / 3) % 2) * 0.3 - 0.15)
			_:
				var c := CylinderMesh.new()
				c.top_radius = 0.17
				c.bottom_radius = 0.13
				c.height = 0.25
				c.radial_segments = 8
				mi.mesh = c
				mi.material_override = Building.material("thatch")
				mi.position = Vector3((i % 2) * 0.38 - 0.19, 0.13 + (i / 4) * 0.25, ((i / 2) % 2) * 0.4 - 0.2)
		root.add_child(mi)
	return root


func give(new_plan: Array, what: String, for_node: Node = null, is_idle := false) -> void:
	if what == "Saklanıyor" and job != what and randf() < 0.3:
		call_out(["Saklanın!", "Herkes içeri!", "Çocukları alın!"])
	plan = new_plan
	job = what
	target = for_node
	idle = is_idle
	_path = PackedVector3Array()
	_elapsed = 0.0


## The plan's called off: what was owed goes back, what was set aside is let go.
func abort() -> void:
	plan.clear()
	_path = PackedVector3Array()
	_elapsed = 0.0
	if not owed.is_empty():
		village.give_back(owed)
		owed = {}
	set_carry("", 0)
	village.release(self)
	if perched:
		get_down()
	job = "Boşta"
	target = null
	idle = false
	_anim = ""


func sleep_in(h: Building, hide := false) -> void:
	if down:
		down = false
		recovering = true
		carried_by = null
		hp = maxf(hp, 5.0)
		if _body:
			_body.stand()
	sleeping = true
	hiding = hide
	inside = h
	visible = false


## Asleep out of doors (no roof of its own): curled up on its side in a blanket at `at`, its feet
## to the fire at `fire`.
var _blanket: Node3D
var _rough := false


func sleep_rough(cover: Building, at: Vector3, fire: Vector3) -> void:
	sleeping = true
	hiding = false
	inside = cover
	_rough = true
	if _lantern:
		_lantern.visible = false
	position = at
	_face(fire, 1.0)
	rotation.y = _yaw + PI * 0.5
	_blanket = MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(1.8, 0.1, 0.75)
	(_blanket as MeshInstance3D).mesh = m
	var wool := StandardMaterial3D.new()
	wool.albedo_color = [Color(0.36, 0.2, 0.15), Color(0.3, 0.3, 0.27), Color(0.42, 0.36, 0.24)][get_instance_id() % 3]
	wool.roughness = 1.0
	(_blanket as MeshInstance3D).material_override = wool
	_blanket.position = Vector3(-0.55, 0.05, 0)
	add_child(_blanket)
	if _body:
		_body.play("CrouchIdle", 0.08)
		_body.rotation = Vector3(0, 0, PI * 0.5)
		_body.position = Vector3(0.1, 0.28, 0)
	else:
		visible = false


func wake() -> void:
	if recovering and wounded_badly and team == 0:
		_roll_scar()
	recovering = false
	sleeping = false
	hiding = false
	visible = true
	job = "Boşta"
	if _rough:
		_rough = false
		inside = null
		if _blanket:
			_blanket.queue_free()
			_blanket = null
		if _body:
			_body.rotation = Vector3.ZERO
			_body.position = Vector3.ZERO
		return
	var from: Building = inside if is_instance_valid(inside) else (home if is_instance_valid(home) else null)
	inside = null
	if from:
		# Out the way it came in: the door opens, a few steps out.
		position = from.inside()
		var b := from
		give([{"t": "do", "f": func() -> bool:
			if is_instance_valid(b):
				b.open_door()
			return true}, {"t": "step", "to": b.door()}], "Dışarı çıkıyor")


## Up (or down) the scaffold to `y`, hand over hand.
func climb(y: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "position:y", y, 0.8).set_trans(Tween.TRANS_SINE)


## Up onto a tower's platform (an archer).
func perch_on(t: Building) -> void:
	perched = t
	position = t.global_transform * Vector3(0, 9.58, 0)


func get_down() -> void:
	if is_instance_valid(perched):
		position = perched.door()
	perched = null
	position.y = village.ground_at(position) if village.has_method("ground_at") else nav.height(position.x, position.z)


## What the body says of how it's doing, laid over its moves: the head turned to whoever it's talking
## with (or to anyone close by, now and then), a limp on a hurt or lost leg, a shiver in the cold
## without a fire, the back bent when it's low.
var _look_t := 0.0
var _look_at := Vector3.INF


func _body_mood(walking: bool) -> void:
	var pose: TownsfolkPose = _body.pose
	pose.walking = walking
	_look_t -= get_process_delta_time()
	if _look_t <= 0.0:
		_look_t = randf_range(1.5, 4.0)
		_look_at = Vector3.INF
		if not walking and team == 0 and not sleeping:
			var who: Villager = null
			var bd := 6.0 if _anim == "chat" else 4.0
			for o: Villager in village.villagers:
				if o != self and not o.dead and not o.sleeping:
					var d := o.position.distance_to(position)
					if d < bd:
						bd = d
						who = o
			if who and (_anim == "chat" or randf() < 0.5):
				_look_at = who.position + Vector3.UP * 1.55
	pose.look_at = _talk_look if _talk_look != Vector3.INF else _look_at
	var leg_hurt := "tek_bacak" in scars or wounds.any(func(w: Dictionary) -> bool: return str(w.part).ends_with("bacak"))
	pose.limp = move_toward(pose.limp, 1.0 if leg_hurt else (0.4 if hp < max_hp * 0.5 else 0.0), 0.02)
	var freezing: bool = village.weather.temperature < -2.0 and not sleeping and inside == null and not has_trait("sibir")
	pose.shiver = move_toward(pose.shiver, 1.0 if freezing and not walking else 0.0, 0.02)
	_body.cold = village.weather.temperature < 0.0
	pose.slump = move_toward(pose.slump, 1.0 if mood < 25.0 else 0.0, 0.01)


## In the winter, a fur hat (the women keep their kerchiefs) and a scarf; out of it, as before.
func dress_warm(on: bool) -> void:
	if _body and team == 0 and not is_child:
		_body.set_winter(on)


## A weapon in its right hand: "spear", "axe", "torch", "bow".
func arm_with(kind: String) -> void:
	if _weapon:
		_weapon.queue_free()
	_weapon = Node3D.new()
	_rifle = kind == "rifle" and _body != null
	if _rifle:
		# Held as the rifle clips hold it: the grip in the right hand, the barrel out along -z.
		_body.weapon_mount().add_child(_weapon)
	else:
		_weapon.position = Vector3(0, _palm() + 0.02, -0.04)
		_hand(1).add_child(_weapon)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.13)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.35, 0.36, 0.38)
	iron.metallic = 0.6
	iron.roughness = 0.45
	match kind:
		"spear":
			_rod(Vector3(0, 0.25, 0), 0.03, 2.1, wood)
			var tip := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.0
			tm.bottom_radius = 0.06
			tm.height = 0.3
			tip.mesh = tm
			tip.material_override = iron
			tip.position = Vector3(0, 1.45, 0)
			_weapon.add_child(tip)
		"axe":
			_rod(Vector3(0, -0.1, 0), 0.03, 0.8, wood)
			var head := MeshInstance3D.new()
			var hm := BoxMesh.new()
			hm.size = Vector3(0.04, 0.2, 0.24)
			head.mesh = hm
			head.material_override = iron
			head.position = Vector3(0, -0.42, -0.1)
			_weapon.add_child(head)
		"torch":
			_rod(Vector3(0, -0.15, 0), 0.035, 0.7, wood)
			var fire := MeshInstance3D.new()
			var fm := SphereMesh.new()
			fm.radius = 0.11
			fm.height = 0.26
			fire.mesh = fm
			var glow := StandardMaterial3D.new()
			glow.albedo_color = Color(1.0, 0.6, 0.2)
			glow.emission_enabled = true
			glow.emission = Color(1.0, 0.5, 0.15)
			glow.emission_energy_multiplier = 4.0
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fire.material_override = glow
			fire.position = Vector3(0, -0.55, 0)
			_weapon.add_child(fire)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.55, 0.2)
			light.light_energy = 1.6
			light.omni_range = 7.0
			light.position = Vector3(0, -0.6, 0)
			_weapon.add_child(light)
		"bow":
			var limb := StandardMaterial3D.new()
			limb.albedo_color = Color(0.5, 0.33, 0.17)
			for k in 3:
				var seg := _rod(Vector3(0, -0.45 + k * 0.45, -0.08 * float(k == 1)), 0.018, 0.48, limb)
				seg.rotation.x = [0.28, 0.0, -0.28][k]
			var cord := StandardMaterial3D.new()
			cord.albedo_color = Color(0.85, 0.82, 0.72)
			_rod(Vector3(0, 0.0, 0.06), 0.004, 1.3, cord)
		"rifle":
			if _rifle:
				_rod(Vector3(0, 0.06, -0.55), 0.016, 0.8, iron).rotation.x = PI * 0.5
				_rod(Vector3(0, 0.03, -0.3), 0.03, 0.55, wood).rotation.x = PI * 0.5
				_rod(Vector3(0, -0.02, 0.2), 0.04, 0.35, wood).rotation.x = PI * 0.5 + 0.2
			else:
				_rod(Vector3(0, 0.1, 0), 0.025, 1.2, iron)
				_rod(Vector3(0, -0.35, 0.02), 0.04, 0.45, wood)


func _rod(at: Vector3, r: float, length: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = length
	m.radial_segments = 6
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	_weapon.add_child(mi)
	return mi


## Lying wounded: bleeding out where it fell, or carried on someone's shoulders.
func _downed(dt: float) -> void:
	if is_instance_valid(carried_by) and not carried_by.dead and not carried_by.down and carried_by.carry_res == "yarali":
		# a child carried in the arms; a grown body dragged by the arms along the ground behind,
		# on its back, the heels trailing
		if is_child:
			position = carried_by.position + carried_by.global_basis * Vector3(0.0, 1.0, -0.35)
			rotation.y = carried_by.rotation.y + PI * 0.5
		else:
			var behind: Vector3 = carried_by.position + carried_by.global_basis.z * 2.05 # (the body's laid out from its feet)
			behind.y = village.ground_at(behind)
			position = behind
			rotation.y = carried_by.rotation.y
		return
	if carried_by != null:
		carried_by = null # (put down, or the one carrying it fell)
		position.y = village.ground_at(position)
	bleed -= dt
	if bleed <= 0.0:
		die()


func _go_down() -> void:
	abort()
	down = true
	bleeding = false
	wounded_badly = true
	treated = false
	hp = 1.0
	bleed = 120.0
	job = "Yaralı, yerde"
	drafted = false
	if team == 0:
		# whoever's nearest on their feet calls it out
		var near: Villager = null
		var bd := 20.0
		for o: Villager in village.villagers:
			if o != self and not o.dead and not o.down and o.visible and not o.is_child:
				var d := o.position.distance_to(position)
				if d < bd:
					bd = d
					near = o
		if near:
			near.call_out(["Yaralı var!", "%s vuruldu!" % display_name.split(" ")[0], "Sedye! Yaralı var!", "Vurdular, yardım edin!"])
	if _lantern:
		_lantern.visible = false
	_hold("")
	if _body:
		_body.lie()


## A blow (an arrow) of `dmg` from `by`.
func hurt(dmg: float, by: Villager = null) -> void:
	if dead:
		return
	if down:
		die() # (struck again where it lies)
		return
	hp -= dmg
	if team == 0 and dmg >= 12.0 and randf() < 0.07 and _body:
		_maim() # (a limb lost to the blow: down with it, where it'll bleed unless carried in)
		_go_down()
		return
	if team == 0 and dmg >= 5.0:
		_wound(dmg, by)
		think("hurt", "Yaralandı", -10.0, 600.0)
		if dmg >= 10.0 and hp > 0.0 and hp < max_hp * 0.6 and randf() < 0.6:
			bleeding = true # (on its feet but losing blood till someone binds it)
	if _tunic:
		var c := _tunic.albedo_color
		_tunic.albedo_color = Color(1.0, 0.3, 0.25)
		var tw := create_tween()
		tw.tween_interval(0.12)
		tw.tween_callback(func() -> void: _tunic.albedo_color = c)
	if hp <= 0.0:
		# One of the town shot or cut down mostly lies wounded, not dead: it can still be saved.
		if team == 0 and _body and randf() < 0.75:
			_go_down()
			return
		if team == 1 and _body and randf() < 0.6: # (an outlaw too: lying there to be taken, if there's a jail)
			_go_down()
			bleed = 200.0
			job = "Yaralı firari"
			if not self in village.downed_outlaws:
				village.downed_outlaws.append(self)
			return
		die()
		return
	if fighter and not armed and by and is_instance_valid(by) and not by.dead and (plan.is_empty() or str(plan[0].t) != "fight"):
		abort()
		give([{"t": "fight", "foe": by, "give_up": 40.0}], "Savaşıyor")


func die() -> void:
	if dead:
		return
	abort()
	dead = true
	hp = 0.0
	if perched:
		get_down()
	died.emit(self)
	var tw := create_tween()
	if _body:
		_body.die() # (the knees go, and it falls)
		tw.tween_interval(1.4)
	else:
		tw.tween_property(self, "rotation:x", -PI * 0.5, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(self, "position:y", position.y + 0.2, 0.45)
	# (the town's dead are buried; the band's lie where they fell a while, to be searched, then go)
	tw.tween_interval(30.0 if team == 0 else maxf(village.weather.day_length_minutes * 60.0 * 0.5, 90.0))
	tw.tween_property(self, "position:y", position.y - 1.0, 4.0)
	tw.tween_callback(queue_free)


func _process(dt: float) -> void:
	if dead:
		return
	if team == 1 and not down and (not village.traps.is_empty() or not village.mines.is_empty()):
		_trap_t -= dt
		if _trap_t <= 0.0:
			_trap_t = 0.15
			village.spring_trap(self)
	if team == 0:
		var g := dt * _rate()
		_fade_thoughts(g)
		sulk_cd -= g
		low_for = low_for + g if mood < BREAK else maxf(low_for - g * 2.0, 0.0)
	if revealed > 0.0:
		revealed -= dt
	if down:
		_downed(dt)
		return
	if bleeding and team == 0:
		hp -= dt * _rate() * 0.45 # (losing blood: down in two minutes or so, unless it's bound up)
		if hp <= 1.0:
			_go_down()
			return
	elif hp < max_hp:
		hp = minf(hp + dt * (0.35 if sleeping else 0.12) * (2.0 if treated else 1.0), max_hp) # (mending, quicker asleep, quicker seen to)
		if hp >= max_hp:
			wounds.clear() # (mended: what's left of it is a scar, if anything)
	if sleeping:
		return
	seat = -1.0
	_run = 1.0
	_talk_look = Vector3.INF
	if _keeps_room():
		var moving := not _path.is_empty() or (not plan.is_empty() and str(plan[0].t) in ["step", "circle"])
		_make_room(dt, moving)
		_step_aside(dt, moving)
	if Engine.get_process_frames() % 30 == get_instance_id() % 30:
		if _body and team == 0 and uniform == "":
			_body.set_militia(militia and not is_child)
		if _saw_foe and (village.raids == null or not village.raids.active):
			_saw_foe = false
	_lantern_check()
	if plan.is_empty():
		_anim = "idle"
		_animate(dt, false)
		return
	var step: Dictionary = plan[0]
	if step.has("job"):
		job = str(step.job)
	match str(step.t):
		"go":
			if _path.is_empty():
				_path = nav.path_for(self, position, step.to)
				_path_i = 0
			if _path.is_empty(): # (the way's still being found)
				_anim = "idle"
				_animate(dt, false)
			elif team == 0 and _path_i == 0 and _way_barred():
				# no way there but through the stakes or a barred gate: it doesn't set out at all,
				# it stays where it is and thinks again in a while
				abort()
				give([{"t": "work", "time": STAY_IN, "anim": "idle"}], "Kapılar kilitli, burada bekliyor", null, true)
			else:
				_run = 1.5 if bool(step.get("run", false)) else 1.0
				if _walk(dt):
					plan.pop_front()
					_path = PackedVector3Array()
		"work":
			_anim = str(step.get("anim", "build"))
			seat = float(step.seat) if step.has("seat") else (0.0 if _anim in ["sit", "eat"] else -1.0)
			var face_now: Vector3 = step.get("face", Vector3.INF)
			if step.has("talk"):
				var f := _talk(step)
				if f != Vector3.INF and not bool(step.talk.get("keep_face", false)):
					face_now = f
			_hold(TOOLS.get(_anim, ""))
			# The blows heard: an axe on wood, a pick and a chisel on stone, the hammer on a site.
			var period: float = BEATS.get(_anim, 0.0)
			if period > 0.0:
				_hit_t -= delta_safe(dt)
				if _hit_t <= 0.0:
					_hit_t = period
					var pitch: float = {"chop": 1.0, "limb": 1.2, "mine": 1.7, "chisel": 2.0, "build": 1.4}[_anim]
					Ambience.knock(global_position + Vector3.UP * 1.0 - global_basis.z * 0.6, pitch)
			if face_now != Vector3.INF:
				_face(face_now, dt)
			var sk := work_skill()
			var pace := knack(sk)
			learn(sk, dt)
			_elapsed += dt * pace
			var over := false
			if step.has("tick"):
				over = not bool((step.tick as Callable).call(dt * _rate() * pace))
			elif _elapsed * _rate() >= float(step.time):
				over = true
			if over:
				_elapsed = 0.0
				plan.pop_front()
				if step.has("done"):
					(step.done as Callable).call()
			_animate(dt, false)
		"do":
			plan.pop_front()
			var r: Variant = (step.f as Callable).call()
			if r is bool and not r:
				abort()
		"fight":
			_fight(step, dt)
		"hold":
			_hold_post(step, dt)
		"chase":
			_chase(step, dt)
		"flee":
			_flee(step, dt)
		"circle":
			_circle(step, dt)
		"step":
			var to: Vector3 = step.to
			var d := Vector2(to.x - position.x, to.z - position.z)
			var len := d.length()
			var move := 1.7 * dt
			_speed_now = 1.7
			if len <= move:
				position = to
				position.y = village.ground_at(position)
				plan.pop_front()
			else:
				position.x += d.x / len * move
				position.z += d.y / len * move
				position.y = village.ground_at(position)
				_face(to, dt)
			_anim = "walk"
			_hold("")
			_phase += dt * 5.0
			_animate(dt, true)
		_:
			plan.pop_front()


## A word with others (`talk`: {folk, t0, seed}, the one dictionary shared by all of them): those
## there turn to whoever's speaking and take turns at it, a few seconds each, the others hearing
## them out and nodding; now and then the one speaking says something aloud (FolkTalk, FolkLines).
## Waits for the other to come up. Where to face (INF: as the step says).
func _talk(step: Dictionary) -> Vector3:
	var talk: Dictionary = step.talk
	var reach := float(talk.get("reach", 3.2))
	var here: Array[Villager] = []
	for o: Variant in talk.folk:
		if not is_instance_valid(o):
			continue
		var w := o as Villager
		if w.dead or w.sleeping or w.plan.is_empty() or not is_same(w.plan[0].get("talk"), talk):
			continue
		if w == self or w.position.distance_to(position) < reach:
			here.append(w)
	if here.size() < 2:
		for o: Variant in talk.folk:
			if is_instance_valid(o) and o != self and not (o as Villager).dead:
				return (o as Villager).position # (looking out for the other, coming over)
		return Vector3.INF
	here.sort_custom(func(a: Villager, b: Villager) -> bool: return a.get_instance_id() < b.get_instance_id())
	var span := 3.6 + float(int(talk.seed) % 3) * 0.8
	var turn := int((float(village.clock) - float(talk.t0)) / span)
	var speaker: Villager = here[(turn * 7 + int(talk.seed)) % here.size()]
	if speaker == self:
		_anim = "chat"
		var mid := Vector3.ZERO
		var other: Villager = null
		for o in here:
			if o != self:
				mid += o.position
				other = o
		mid /= float(here.size() - 1)
		_talk_look = mid + Vector3.UP * 1.45
		if _talk_turn != turn:
			_talk_turn = turn
			if randf() < 0.4:
				FolkTalk.say(self, FolkLines.line(self, other, str(talk.get("where", ""))))
		return mid
	if _anim == "chat":
		_anim = "listen" # (hearing the other out; one sat at its pipe or its cup keeps at it)
	_talk_look = speaker.position + Vector3.UP * 1.45
	return speaker.position


## Called out in a fight or a fright: a short shout over its head (FolkTalk lets only a few through).
func call_out(lines: Array) -> void:
	if not lines.is_empty():
		FolkTalk.say(self, str(lines.pick_random()), true)


## Tag: after `who` (fleeing, `flee`) till it's caught, then the other's turn, once it's counted to
## three. `left` s of the game, about `center`.
func _chase(step: Dictionary, dt: float) -> void:
	step.left = float(step.left) - dt * _rate()
	var o: Variant = step.who
	if float(step.left) <= 0.0 or not is_instance_valid(o) or (o as Villager).plan.is_empty() or str((o as Villager).plan[0].t) != "flee":
		plan.pop_front()
		_path = PackedVector3Array()
		return
	var w := o as Villager
	if w.position.distance_to(position) < 0.9:
		var left := float(step.left)
		var c: Vector3 = step.center
		var what := job
		w.give([{"t": "work", "time": 1.6, "anim": "look", "face": position}, {"t": "chase", "who": self, "left": left, "center": c}], what, null, true)
		give([{"t": "flee", "from": w, "left": left + 1.6, "center": c}], what, null, true)
		return
	if _path.is_empty() or _path_i >= _path.size() or w.position.distance_to(_chase_at) > 1.5:
		_path = PackedVector3Array([w.position]) if _line_open(position, w.position) else nav.path_for(self, position, w.position)
		_path_i = 0
		_chase_at = w.position
	if _path.is_empty():
		_anim = "look"
		_face(w.position, dt)
		_animate(dt, false)
		return
	_run = 1.45
	_walk(dt)


## Tag, the one it's after: off out of reach when `from` comes close, never far from `center`.
func _flee(step: Dictionary, dt: float) -> void:
	step.left = float(step.left) - dt * _rate()
	var o: Variant = step.from
	if float(step.left) <= 0.0 or not is_instance_valid(o) or (o as Villager).dead:
		plan.pop_front()
		_path = PackedVector3Array()
		return
	var w := o as Villager
	var running := not _path.is_empty() and _path_i < _path.size()
	if not running and w.position.distance_to(position) < 5.0:
		var c: Vector3 = step.center
		var away := position - w.position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
		for k in 6:
			var p := position + away.rotated(Vector3.UP, randf_range(-1.0, 1.0)) * randf_range(3.0, 6.0)
			p = c + (p - c).limit_length(8.0)
			if nav.is_open(p) and _line_open(position, p):
				p.y = village.ground_at(p)
				_path = PackedVector3Array([p])
				_path_i = 0
				running = true
				break
	if running:
		_run = 1.4
		if _walk(dt):
			_path = PackedVector3Array()
		return
	_anim = "look"
	_face(w.position, dt)
	_animate(dt, false)


## Nothing in the way along the straight line from `a` to `b` (a short run at play).
func _line_open(a: Vector3, b: Vector3) -> bool:
	for k in range(1, 6):
		if not nav.is_open(a.lerp(b, k / 5.0)):
			return false
	return true


## A ring game: round `ring.center` at `ring.r` m, all of them together the same way (`ring.w`
## rad/s from `ring.t0`), each from its own place on the ring (`a0`).
func _circle(step: Dictionary, dt: float) -> void:
	step.left = float(step.left) - dt * _rate()
	if float(step.left) <= 0.0:
		plan.pop_front()
		return
	var ring: Dictionary = step.ring
	var c: Vector3 = ring.center
	var r := float(ring.r)
	var w := float(ring.w)
	var a := float(step.a0) + w * (float(village.clock) - float(ring.t0))
	var to := c + Vector3(cos(a), 0, sin(a)) * r
	var d := Vector2(to.x - position.x, to.z - position.z)
	var move := minf(d.length(), 3.0 * dt)
	if d.length() > 0.001:
		position.x += d.x / d.length() * move
		position.z += d.y / d.length() * move
	position.y = village.ground_at(position)
	var ahead := a + signf(w) * 0.35
	_face(c + Vector3(cos(ahead), 0, sin(ahead)) * r, dt)
	_speed_now = maxf(absf(w) * r * _rate(), move / maxf(dt, 0.001))
	_anim = "walk"
	_hold("")
	_phase += dt * _speed_now * 3.2
	_animate(dt, true)


## One of the town come up against a barred gate or the stakes with no way round: it stands and
## waits a little (a gate may be unbarred), then gives it up and finds something else to do.
const BARRED_WAIT := 6.0
const STAY_IN := 12.0 ## s before one shut in (or out) tries for somewhere again


## Whether its way crosses a standing wall or a barred gate anywhere along it.
func _way_barred() -> bool:
	if not village.has_method("barred_at"):
		return false
	for i in range(_path.size() - 1):
		if not village.barred_at(_path[i], _path[i + 1]).is_empty():
			return true
	return not _path.is_empty() and not village.barred_at(position, _path[0]).is_empty()


var _barred_t := 0.0
static var _barred_said := -999.0


func _barred(dt: float) -> bool:
	if not village.has_method("barred_at"):
		return false
	var bar: Dictionary = village.barred_at(position, _path[_path_i])
	if bar.is_empty():
		_barred_t = 0.0
		return false
	var at: Vector3 = (bar.gate as Node3D).global_position if bar.has("gate") else bar.at
	_face(at, dt)
	_anim = "idle"
	job = "Kapı kilitli, bekliyor" if bar.has("gate") else "Sur yolu kesiyor"
	_animate(dt, false)
	_barred_t += dt
	var now := Time.get_ticks_msec() * 0.001
	if now - _barred_said > 90.0:
		_barred_said = now
		village.message.emit("Kapı kilitli: %s geçemiyor" % display_name.split(" ")[0] if bar.has("gate") else "%s surdan geçemiyor: kapı gerek" % display_name.split(" ")[0], "bad")
	if _barred_t > BARRED_WAIT:
		_barred_t = 0.0
		abort.call_deferred()
	return true


## A stretch of its walk; true once it's there.
func _walk(dt: float) -> bool:
	in_cover = false
	if _path_i >= _path.size():
		return true
	if team == 1 and village.has_method("barrier_at"):
		var bar: Dictionary = village.barrier_at(position, _path[_path_i])
		if not bar.is_empty():
			# A shut gate or the stakes in the way: hacked at till it gives.
			var at: Vector3 = (bar.gate as Node3D).global_position if bar.has("gate") else bar.at
			_face(at, dt)
			_anim = "strike"
			_attack_t -= dt
			if _attack_t <= 0.0:
				_attack_t = randf_range(1.0, 1.4)
				if not _saw_foe:
					_saw_foe = true
					if randf() < 0.4:
						call_out(["Kırın şu kapıyı!", "Ambarı bulun!", "Yakın hepsini!"])
				if bar.has("gate"):
					(bar.gate as Gate).hit(attack)
				else:
					if role == "torch" and randf() < 0.35:
						(bar.wall as Wall).ignite(at) # (a torch to it as well: it takes, slowly)
					(bar.wall as Wall).hit(at, attack)
			job = "Suru kırıyor"
			_animate(dt, false)
			return false
	if team == 1:
		var wire: Building = village.wire_ahead(position, _path[_path_i])
		if wire:
			# Cut through by hand, torn on it the while, and shot at.
			_face(wire.global_position, dt)
			_anim = "strike"
			job = "Teli kesiyor"
			_wire_t += dt
			if floori(_wire_t / 1.5) > floori((_wire_t - dt) / 1.5):
				hurt(village.WIRE_TEAR)
			if _wire_t >= village.WIRE_CUT:
				_wire_t = 0.0
				village.cut_wire(wire)
			_animate(dt, false)
			return false
		_wire_t = 0.0
	if team == 0 and _barred(dt):
		return false
	var worn := nav.worn(position)
	var speed := 2.9 * (1.0 + 0.8 * worn * (1.0 - 0.75 * Weather.wet_now)) # (a trodden path: up to 80% quicker going)
	speed *= 0.82 if carry_n > 0 else 1.0
	# A trodden way in the wet is mud underfoot; deep snow is slow going everywhere; planks are neither.
	var planks := nav.on_road(position)
	if planks:
		speed = 2.9 * 1.5 * (0.82 if carry_n > 0 else 1.0)
	else:
		speed *= 1.0 - 0.35 * smoothstep(0.3, 0.9, Weather.wet_now) * worn - 0.3 * Weather.snow_cover_now
	var mud := 0.0
	if has_cart:
		# Quick on a hard path, slow off it; in the wet the path is mud, and soft ground is worse.
		speed = 3.0 * (1.0 + 1.2 * worn * (1.0 - 0.8 * Weather.wet_now))
		mud = 0.0 if planks else clampf(Weather.wet_now * (0.4 + worn * 0.6) + nav.terrain.soft_at(position.x, position.z).x * 1.5 + Weather.snow_cover_now * 0.5, 0.0, 1.0)
		speed *= 1.0 - 0.6 * mud
		if _stuck > 0.0:
			_stuck -= dt
			_anim = "push"
			_animate(dt, false)
			return false
		if vehicle == "ox":
			# Slow and steady, but heavy: the mud has it more often and for longer.
			speed = 1.9 * (1.0 + 0.55 * worn * (1.0 - 0.8 * Weather.wet_now)) * (1.0 - 0.45 * mud)
		if mud > 0.35 and randf() < dt * (0.1 if vehicle == "ox" else 0.06) * mud:
			_stuck = randf_range(5.0, 9.0) if vehicle == "ox" else randf_range(2.5, 5.0)
			job = job if job.ends_with("(çamura saplandı)") else job + " (çamura saplandı)"
	if carry_n > 0 and carry_res == "yarali":
		speed *= 0.5 # (a body dragged: slow going)
	speed *= _rate() * (1.1 if team == 1 else 1.0) * speed_mul * _run
	_speed_now = speed
	var left := speed * dt
	var moved := 0.0
	while left > 0.0 and _path_i < _path.size():
		var to := _path[_path_i]
		var d := Vector2(to.x - position.x, to.z - position.z)
		var len := d.length()
		if len <= left:
			position.x = to.x
			position.z = to.z
			left -= len
			moved += len
			_path_i += 1
		else:
			var step := d / len * left
			# a foe doesn't walk in through a wall: up against a building it stops there
			if team == 1 and nav.shut_kind(position + Vector3(step.x, 0, step.y)) == 2 and nav.shut_kind(position) != 2:
				_path_i = _path.size()
				break
			position.x += step.x
			position.z += step.y
			_face(to, dt)
			moved += left
			left = 0.0
	position.y = village.ground_at(position) if village.has_method("ground_at") else nav.height(position.x, position.z)
	if vehicle == "ox":
		# (the hooves and the wheels, a little to the right of the drover: a broad pair of ruts)
		nav.tread(global_transform * Vector3(0.95, 0, -1.7), dt, 2.0)
		nav.tread(global_transform * Vector3(0.95, 0, 1.0), dt, 4.0)
		nav.tread(position, dt, 1.0)
	else:
		nav.tread(position, dt, 3.0 if has_cart else (1.6 if carry_n > 0 else 1.0))
	for w in _wheels:
		w.rotation.x -= moved / _wheel_r
	for k in _ox_legs.size():
		_ox_legs[k].rotation.x = sin(_phase * 0.8 + (PI if k % 3 == 0 else 0.0)) * 0.4
	if _ox_head:
		_ox_head.rotation.x = sin(_phase * 0.8) * 0.06
	if _cart and vehicle == "hand":
		# (the bed follows the lie of the ground a little)
		var ahead := global_transform * Vector3(0, 0, -1.25)
		_cart.rotation.x = clampf(atan2(nav.height(ahead.x, ahead.z) - position.y, 1.25), -0.4, 0.4)
	if job.ends_with(" (çamura saplandı)") and _stuck <= 0.0:
		job = job.trim_suffix(" (çamura saplandı)")
	_anim = "walk"
	_hold("")
	_phase += dt * speed * 3.2
	_animate(dt, true)
	return _path_i >= _path.size()


## Out at night, one of the town's carries a lantern in its left hand.
func lantern_on() -> bool:
	return _lantern != null and _lantern.visible


func _lantern_check() -> void:
	if team != 0 or Engine.get_process_frames() % 20 != get_instance_id() % 20:
		return
	var want: bool = village.weather.is_night() and not perched and not down and lantern_mode != "off"
	if want and _lantern == null:
		_lantern = Node3D.new()
		_lantern.position = Vector3(0, _palm() - 0.02, -0.05)
		_hand(0).add_child(_lantern)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.2, 0.14)
		box.mesh = bm
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.75, 0.4)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.62, 0.25)
		glow.emission_energy_multiplier = 3.0
		box.material_override = glow
		_lantern.add_child(box)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.66, 0.32)
		l.omni_range = LANTERN_REACH
		l.light_energy = 0.9
		l.shadow_enabled = false
		_lantern.add_child(l)
	if _lantern:
		_lantern.visible = want


## A tool in the right hand ("" puts it away): only while working, and never over a weapon.
func _hold(kind: String) -> void:
	if _weapon and _weapon.get_child_count() > 0:
		kind = ""
	if kind == _tool_kind:
		return
	_tool_kind = kind
	if _tool:
		_tool.queue_free()
		_tool = null
	if _tool_left:
		_tool_left.queue_free()
		_tool_left = null
	_rod_line = null
	if _body:
		_body.grip(null)
	if kind == "" or (_arms.size() < 2 and _body == null):
		return
	_tool = Node3D.new()
	_tool.position = Vector3(0, _palm(), -0.04)
	_hand(0 if kind == "bowl" else 1).add_child(_tool)
	var wood := Building.material("wood")
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.32, 0.33, 0.35)
	iron.metallic = 0.7
	iron.roughness = 0.4
	# The haft runs along the forearm and out past the fist, the head at its far end (-y, then
	# forward once the arm swings up).
	if kind == "bowl":
		var bw := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.09
		bm.bottom_radius = 0.05
		bm.height = 0.07
		bm.radial_segments = 10
		bw.mesh = bm
		bw.material_override = wood
		bw.position = Vector3(0, -0.06, -0.06)
		_tool.add_child(bw)
		return
	if kind in ["rod", "pipe", "knife", "cup"]:
		_small_thing(kind, wood, iron)
		return
	if kind == "scythe":
		# the snath, long and bent, held by its two grips; the blade out at its foot
		_tool_part(Vector3(0.035, 1.6, 0.035), Vector3(0, -0.55, -0.1), wood, Vector3(-0.15, 0, 0))
		_tool_part(Vector3(0.03, 0.03, 0.2), Vector3(0, -0.45, -0.2), wood)
		_tool_part(Vector3(0.012, 0.08, 0.75), Vector3(0.0, -1.32, -0.42), iron, Vector3(0, 0.25, 0))
		_second_hand(Vector3(0, -0.45, -0.28))
		return
	var haft: float = {"axe": 0.85, "pick": 0.85, "hammer": 0.38, "sickle": 0.18, "hoe": 1.3, "spade": 1.1, "saw": 0.16, "mallet": 0.3}[kind]
	_tool_part(Vector3(0.035, haft, 0.035), Vector3(0, -haft * 0.35, 0), wood)
	var tip := Vector3(0, -haft * 0.85, 0)
	match kind:
		"axe":
			_tool_part(Vector3(0.04, 0.16, 0.22), tip + Vector3(0, 0, -0.1), iron)
		"pick":
			_tool_part(Vector3(0.05, 0.05, 0.6), tip, iron)
		"hammer":
			_tool_part(Vector3(0.09, 0.09, 0.2), tip, iron)
		"sickle":
			for k in 4:
				var a := k * 0.45
				_tool_part(Vector3(0.02, 0.12, 0.03), tip + Vector3(0, -cos(a) * 0.12 - 0.05, -sin(a) * 0.14), iron, Vector3(a, 0, 0))
		"hoe":
			_tool_part(Vector3(0.18, 0.04, 0.16), tip + Vector3(0, 0, -0.08), iron)
		"spade":
			_tool_part(Vector3(0.2, 0.26, 0.03), tip + Vector3(0, -0.1, 0), iron)
		"saw":
			_tool_part(Vector3(0.012, 0.13, 0.8), tip + Vector3(0, -0.02, -0.4), iron)
			_tool_part(Vector3(0.03, 0.03, 0.8), tip + Vector3(0, 0.22, -0.4), wood)
		"mallet":
			_tool_part(Vector3(0.12, 0.12, 0.2), tip, wood)
	# A long haft's held in both hands: the left one further down it.
	var other: float = {"axe": 0.3, "pick": 0.36, "hoe": 0.5, "spade": 0.5}.get(kind, 0.0)
	if other > 0.0:
		_second_hand(Vector3(0, -other, 0))


## What's held at one's ease: a fishing rod (its line hanging from the tip), a pipe, a knife (and
## the stick it's whittling, in the other hand), a tin cup.
var _tool_left: Node3D
var _rod_line: Node3D


func _small_thing(kind: String, wood: Material, iron: Material) -> void:
	var dark := Building.material("dark")
	match kind:
		"rod":
			_tool_part(Vector3(0.022, 2.6, 0.022), Vector3(0, -1.2, 0), wood)
			_rod_line = Node3D.new()
			_rod_line.position = Vector3(0, -2.48, 0)
			_tool.add_child(_rod_line)
			var line := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.006, 1.7, 0.006)
			line.mesh = lm
			var lc := StandardMaterial3D.new()
			lc.albedo_color = Color(0.82, 0.8, 0.72)
			line.material_override = lc
			line.position = Vector3(0, -0.85, 0)
			_rod_line.add_child(line)
		"pipe":
			_tool_part(Vector3(0.014, 0.014, 0.15), Vector3(0, -0.02, -0.07), dark)
			_tool_part(Vector3(0.035, 0.05, 0.035), Vector3(0, 0.0, -0.15), wood)
		"knife":
			_tool_part(Vector3(0.02, 0.09, 0.025), Vector3(0, -0.02, 0), wood)
			_tool_part(Vector3(0.006, 0.1, 0.022), Vector3(0, -0.11, 0), iron)
			_tool_left = Node3D.new()
			_tool_left.position = Vector3(0, _palm(), -0.04)
			_hand(0).add_child(_tool_left)
			var stick := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.03, 0.26, 0.03)
			stick.mesh = sm
			stick.material_override = Building.material("log")
			stick.position = Vector3(0, -0.06, 0)
			_tool_left.add_child(stick)
		"cup":
			var cup := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.04
			cm.bottom_radius = 0.035
			cm.height = 0.09
			cm.radial_segments = 8
			cup.mesh = cm
			cup.material_override = iron
			cup.position = Vector3(0, -0.04, -0.05)
			_tool.add_child(cup)


## Where the left hand takes hold of the tool (Townsfolk.grip).
func _second_hand(at: Vector3) -> void:
	if _body == null or _tool == null:
		return
	var m := Node3D.new()
	m.position = at
	_tool.add_child(m)
	_body.grip(m)


func _tool_part(size: Vector3, at: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	_tool.add_child(mi)


static func delta_safe(dt: float) -> float:
	return minf(dt, 0.1)


func _rate() -> float:
	return village.work_rate if team == 0 else 1.0


## At its post: the foe it's told to shoot, or else the nearest it can see in reach; out of cartridges
## it only watches.
func _hold_post(step: Dictionary, dt: float) -> void:
	_path = PackedVector3Array()
	var raids: Raids = village.raids
	var foe: Villager = null
	if is_instance_valid(focus) and not focus.dead and focus.position.distance_to(position) <= ranged * 1.25 and raids.can_see(position, focus):
		foe = focus
	elif raids and ranged > 0.0:
		foe = raids.nearest_raider(position, ranged, true)
	if foe and (ammo > 0 or not armed):
		if not _saw_foe:
			_saw_foe = true
			if randf() < 0.6:
				call_out(["Geliyorlar!", "Siper alın!", "İşte oradalar!", "Başınızı eğin!"])
		_face(foe.position, dt * 3.0)
		_anim = "aim"
		_attack_t = _attack_t - dt if _aimed_at(foe.position) else maxf(_attack_t, 0.5) # (turned to it, the gun up, then the shot)
		if _attack_t <= 0.0:
			_attack_t = randf_range(2.2, 3.0)
			if armed:
				ammo -= 1
				if ammo == 0:
					call_out(["Fişeğim bitti!", "Fişek! Fişek verin!"])
			var d := foe.position.distance_to(position)
			if held == "bow":
				_attack_t = randf_range(1.4, 1.9) # (a bow's quicker than a bolt)
				raids.arrow(muzzle(), foe, attack * randf_range(0.8, 1.2), Raids.range_chance(self, d), self)
			else:
				raids.shoot(muzzle(), foe, attack * randf_range(0.8, 1.2), Raids.range_chance(self, d), self)
	else:
		_anim = "idle"
		if step.has("face"):
			_face(step.face, dt)
	if armed and ammo <= 0:
		job = "Oku bitti" if held == "bow" else "Fişeği bitti"
	_animate(dt, false)


## Where a shot leaves from: the rifle's muzzle, the bow in the hand (or about the shoulder).
func muzzle() -> Vector3:
	if _weapon and is_instance_valid(_weapon) and _weapon.get_child_count() > 0:
		if _rifle:
			return _weapon.global_transform * Vector3(0, 0.06, -0.96)
		return _weapon.global_position
	return global_position + Vector3.UP * 1.45


## Turned to `p` near enough to shoot at it.
func _aimed_at(p: Vector3) -> bool:
	var to := Vector2(p.x - position.x, p.z - position.z)
	var fwd := Vector2(-global_basis.z.x, -global_basis.z.z)
	if to.length() < 0.1 or fwd.length() < 0.1:
		return true
	return to.normalized().dot(fwd.normalized()) > 0.985


func _fight(step: Dictionary, dt: float) -> void:
	var foe: Variant = step.foe
	if not is_instance_valid(foe) or (foe as Villager).dead or (foe as Villager).down or (foe as Villager).sleeping or (foe as Villager).perched:
		plan.pop_front()
		_path = PackedVector3Array()
		return
	var f := foe as Villager
	var d := Vector2(f.position.x - position.x, f.position.z - position.z).length()
	if d > float(step.get("give_up", 60.0)):
		plan.pop_front()
		_path = PackedVector3Array()
		return
	if ranged > 0.0 and d <= ranged and village.raids and village.raids.can_see(position, f):
		# A rifle: stand, aim, fire.
		_path = PackedVector3Array()
		_face(f.position, dt * 3.0)
		_anim = "aim"
		_attack_t = _attack_t - dt if _aimed_at(f.position) else maxf(_attack_t, 0.5)
		if _attack_t <= 0.0:
			_attack_t = randf_range(2.0, 2.8)
			village.raids.shoot(muzzle(), f, attack * randf_range(0.8, 1.2), Raids.range_chance(self, d), self)
		_animate(dt, false)
		return
	if role == "shooter" or (armed and ranged > 0.0):
		plan.pop_front() # (a rifleman doesn't run in: out of sight or reach, it lets it go)
		_path = PackedVector3Array()
		return
	if d > 1.4:
		if _path.is_empty() or f.position.distance_to(_chase_at) > 2.5 or _path_i >= _path.size():
			var way := nav.path_for(self, position, f.position)
			if not way.is_empty():
				_path = way
				_path_i = 0
				_chase_at = f.position
		_walk(dt)
		return
	_path = PackedVector3Array()
	_face(f.position, dt * 3.0)
	_anim = "strike"
	_attack_t -= dt
	if _attack_t <= 0.0:
		_attack_t = randf_range(0.9, 1.3)
		if randf() < 0.7:
			f.hurt(attack * randf_range(0.7, 1.3), self)
	_animate(dt, false)


func _face(p: Vector3, dt: float) -> void:
	var d := Vector2(p.x - position.x, p.z - position.z)
	if d.length() < 0.05:
		return
	var want := atan2(-d.x, -d.y)
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-10.0 * dt))
	rotation.y = _yaw


## The blows' time (s), heard (Ambience.knock) and swung in time with it (_animate: the bite at the
## top of the beat).
const BEATS := {"chop": 1.37, "limb": 1.2, "mine": 1.57, "chisel": 0.45, "build": 0.9}
## A blow as it's dealt, keyed through its beat (0 the bite): the follow-through after it, the tool
## freed and lifted, drawn back slow with the weight going onto the back foot, held a moment at
## the top, then brought in hard (eased in: quickest at the end). [t, twist, arm_l, arm_r, el, er,
## lean, kn]; the last stretch, back to the bite, is the blow.
const SWINGS := {
	"chop": [[0.0, -0.55, -1.15, -1.15, 0.3, 0.22, 0.3, 0.34], [0.1, -0.8, -1.05, -1.05, 0.32, 0.25, 0.37, 0.4],
		[0.27, -0.2, -1.25, -1.25, 0.45, 0.4, 0.18, 0.22], [0.78, 0.95, -1.75, -1.75, 0.85, 0.85, 0.02, 0.12],
		[0.87, 1.03, -1.82, -1.82, 0.9, 0.88, -0.02, 0.12]],
	"mine": [[0.0, 0.0, -0.75, -0.75, 0.15, 0.15, 0.52, 0.42], [0.1, -0.03, -0.68, -0.68, 0.18, 0.18, 0.57, 0.46],
		[0.3, 0.05, -1.2, -1.2, 0.5, 0.5, 0.35, 0.3], [0.8, 0.12, -2.7, -2.7, 1.0, 1.0, -0.17, 0.1],
		[0.88, 0.14, -2.8, -2.8, 1.05, 1.05, -0.2, 0.1]],
	"build": [[0.0, -0.05, -0.6, -0.95, 0.8, 0.45, 0.18, 0.08], [0.12, -0.06, -0.6, -0.9, 0.8, 0.4, 0.2, 0.08],
		[0.66, 0.06, -0.6, -2.0, 0.8, 1.6, 0.08, 0.05], [0.8, 0.07, -0.6, -2.06, 0.8, 1.66, 0.06, 0.05]],
}


## The numbers for `kind`'s blow at `u` through its beat (SWINGS).
static func _swing(kind: String, u: float) -> Array:
	var keys: Array = SWINGS[kind]
	var n := keys.size()
	for i in n:
		var a: Array = keys[i]
		var last := i == n - 1
		var b: Array = keys[0] if last else keys[i + 1]
		var t1 := 1.0 if last else float(b[0])
		if u >= float(a[0]) and u < t1:
			var k := (u - float(a[0])) / maxf(t1 - float(a[0]), 0.001)
			k = k * k if last else smoothstep(0.0, 1.0, k) # (the blow quickens all the way in)
			var out := []
			for j in range(1, 8):
				out.append(lerpf(float(a[j]), float(b[j]), k))
			return out
	return (keys[0] as Array).slice(1)


func _animate(dt: float, walking: bool) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var leg := 0.0
	var arm_l := 0.0
	var arm_r := 0.0
	var bob := 0.0
	var lean := 0.0
	var twist := 0.0
	var el := 0.15 ## elbows bent (forearm forward and up as it grows)
	var er := 0.15
	var kn := 0.05 ## knees bent
	match _anim:
		"walk":
			leg = sin(_phase) * 0.55
			arm_l = -leg * 0.6
			arm_r = leg * 0.6
			bob = absf(sin(_phase)) * 0.05
			el = 0.35 + maxf(-arm_l, 0.0) * 0.4
			er = 0.35 + maxf(-arm_r, 0.0) * 0.4
		"chop", "mine":
			# Both hands on the haft: the axe drawn back slow over the right shoulder and swung in
			# flat at the trunk, the hips leading and the body going through after it; the pick
			# lifted overhead, the back arched, and brought down with the weight behind it, the
			# knees giving. In time with the blow heard (BEATS).
			var w := _swing(_anim, 1.0 - clampf(_hit_t / float(BEATS[_anim]), 0.0, 1.0))
			twist = w[0]
			arm_l = w[1]
			arm_r = w[2]
			el = w[3]
			er = w[4]
			lean = w[5]
			kn = w[6]
		"mow":
			# The scythe: a long flat sweep from right to left, the body turning from the hips into it,
			# the knees soft; then lifted round to the right again.
			var u := fmod(t + (get_instance_id() % 5) * 0.25, 1.7) / 1.7
			var sweep := smoothstep(0.0, 0.55, u)
			var back := smoothstep(0.6, 1.0, u)
			twist = 0.85 - sweep * 1.6 + back * 1.6
			arm_l = -0.75 + (1.0 - absf(sweep - back)) * 0.1
			arm_r = -0.55
			lean = 0.32
			el = 0.75
			er = 0.45
			kn = 0.35
		"reap":
			# Bent to the stalks, the sickle drawn round low.
			var s := sin(t * 5.0)
			arm_r = -0.7 + s * 0.3
			arm_l = -0.9
			twist = s * 0.5
			lean = 0.55
			el = 0.9
			er = 0.4
			kn = 0.5
		"hoe":
			# Raised high, brought down hard into the ground (body behind it), drawn back toward the feet.
			var u := fmod(t + (get_instance_id() % 7) * 0.2, 1.6) / 1.6
			var up := smoothstep(0.0, 0.5, u) * (1.0 - smoothstep(0.55, 0.66, u))
			var pull := smoothstep(0.68, 1.0, u)
			arm_r = -0.35 - up * 0.95 + pull * 0.15
			arm_l = arm_r
			lean = 0.38 - up * 0.18 + pull * 0.06
			er = 0.25 + up * 0.75 + pull * 0.3
			el = er
			kn = 0.3 + (1.0 - up) * 0.1
			twist = -0.2
		"dig":
			var s := sin(t * 3.0)
			arm_l = -0.8 + s * 0.4
			arm_r = arm_l
			lean = 0.35 + s * 0.2
			el = 0.6
			er = 0.6
			kn = 0.4
		"limb":
			# Down at the trunk, lopping the branches off it.
			var s := sin(t * 5.2)
			arm_l = -1.1 - s * 0.6
			arm_r = arm_l
			lean = 0.5
			twist = s * 0.3
			el = 0.5 + maxf(s, 0.0) * 0.5
			er = el
			kn = 0.45
		"saw":
			# Both hands on the saw, drawn back and forth across the log: the arms pumping at the elbow.
			var s := sin(t * 5.0)
			arm_l = -0.75 + s * 0.3
			arm_r = -0.85 + s * 0.35
			lean = 0.3 - s * 0.06
			el = 1.1 - s * 0.5
			er = 1.2 - s * 0.6
			kn = 0.25
		"chisel":
			# The chisel held to the block, the mallet coming down on it.
			var s := absf(sin(t * 7.0))
			arm_l = -0.7
			arm_r = -1.2 - s * 0.5
			lean = 0.35
			el = 0.8
			er = 0.5 + s * 1.0
		"sit":
			# the hands on the knees (on the ground, the forearms across them)
			var low := seat >= 0.0 and seat < 0.2
			arm_l = -0.85 if low else -0.55
			arm_r = -0.8 if low else -0.5
			lean = 0.2 if low else 0.12
			el = 0.65 if low else 0.8
			er = 0.6 if low else 0.75
		"fish":
			# the rod out over the water in both hands, now and then a twitch of the tip
			var jig := pow(maxf(sin(t * 0.9 + get_instance_id() % 7), 0.0), 12.0) * 0.3
			arm_r = -0.9 - jig
			er = 0.5 + jig
			arm_l = -0.75
			el = 0.8
			lean = 0.12
		"whittle":
			# the stick held up before the chest, the knife drawn away down it, stroke on stroke
			var cut := maxf(sin(t * 3.4 + get_instance_id() % 5), 0.0)
			arm_l = -0.7
			el = 1.2
			arm_r = -0.65 - cut * 0.25
			er = 1.15 - cut * 0.45
			lean = 0.3
			twist = -0.1
		"pipe", "drink":
			# the pipe (the cup) to the mouth every few seconds, held a moment, lowered; the other
			# hand at rest
			var u := fmod(t + (get_instance_id() % 7) * 0.9, 6.5 if _anim == "pipe" else 5.0)
			var up := smoothstep(0.0, 0.7, u) * (1.0 - smoothstep(2.0, 2.7, u))
			arm_r = -0.4 - up * 0.5
			er = 0.5 + up * 1.6
			arm_l = -0.5 if seat >= 0.0 else 0.05
			el = 0.8 if seat >= 0.0 else 0.2
			lean = 0.1 if seat >= 0.0 else 0.0
		"warm":
			# the hands held out to the fire, rubbed now and then
			var rub := sin(t * 5.5) * 0.12 * maxf(sin(t * 0.6 + get_instance_id() % 5), 0.0)
			arm_l = -1.0
			arm_r = -1.0
			el = 0.85 + rub
			er = 0.85 - rub
			lean = 0.22 if seat >= 0.0 else 0.15
			kn = 0.12
		"pray":
			arm_l = -0.42
			arm_r = -0.42
			el = 1.95 # (the hands together before the chest)
			er = 1.95
			lean = 0.05
		"wash":
			# bent to the bucket, the water scooped up to the face in both hands
			var u := fmod(t + (get_instance_id() % 5) * 0.4, 2.4) / 2.4
			var up := smoothstep(0.15, 0.45, u) * (1.0 - smoothstep(0.7, 0.95, u))
			arm_l = -0.95 - up * 0.45
			arm_r = arm_l
			el = 0.5 + up * 1.6
			er = el
			lean = 0.6 - up * 0.2
			kn = 0.25
		"eat":
			# Sat, the bowl in the left hand, the spoon going up to the mouth.
			var s := sin(t * 2.2)
			arm_l = -0.6
			arm_r = -0.6 - maxf(s, 0.0) * 0.5
			lean = 0.2
			el = 1.3 # (the bowl held up)
			er = 1.2 + maxf(s, 0.0) * 1.2 # (the spoon to the mouth)
		"stretch":
			var s := sin(t * 1.6)
			arm_l = -2.6 - s * 0.3
			arm_r = arm_l
			lean = -0.15
			el = 0.05
			er = 0.05
		"look":
			twist = sin(t * 0.7 + get_instance_id() % 5) * 0.7
			arm_l = 0.1
			arm_r = 0.1
		"chat":
			var s := sin(t * 2.8 + get_instance_id() % 7)
			arm_r = -0.5 + s * 0.45
			arm_l = -0.15
			twist = sin(t * 0.9) * 0.2
			er = 1.1 + s * 0.4 # (a hand going as it talks)
			el = 0.25
		"sow":
			# The seed taken from the bag on the left arm, then flung out in a wide fan as the body turns.
			var u := fmod(t + (get_instance_id() % 5) * 0.3, 1.3) / 1.3
			var cast := smoothstep(0.35, 0.6, u) * (1.0 - smoothstep(0.75, 1.0, u))
			arm_l = -0.65
			arm_r = -0.5 - cast * 0.9
			twist = 0.35 - cast * 0.8
			lean = 0.12
			el = 1.35 # (the seed bag held up against the chest)
			er = 1.3 - cast * 1.1
			kn = 0.1
		"gather", "draw":
			arm_l = -0.9 + sin(t * 3.0) * 0.3
			arm_r = -0.9 - sin(t * 3.0) * 0.3
			lean = 0.35
		"throw":
			var s := sin(t * 4.5)
			arm_l = -1.2 - s * 0.8
			arm_r = arm_l
			lean = -s * 0.1
		"strike":
			var s := sin(t * 6.0 + get_instance_id() % 7)
			arm_r = -1.0 - s * 1.2
			arm_l = -0.4
			lean = -s * 0.15
		"aim":
			arm_l = -1.5
			arm_r = -1.4 + sin(t * 2.0) * 0.1
		"torch":
			var s := sin(t * 3.0)
			arm_r = -1.3 - s * 0.4
			arm_l = -0.3
			lean = 0.2
		"climb":
			var s := sin(t * 6.0)
			arm_l = -2.4 - s * 0.4
			arm_r = -2.4 + s * 0.4
			el = 0.6 + s * 0.4
			er = 0.6 - s * 0.4
			kn = 0.5 + s * 0.4
		"aim":
			arm_l = -1.3
			arm_r = -1.2
			el = 0.5
			er = 1.7 # (the butt to the shoulder)
		"build":
			# the hammer drawn up and brought down on the nail, the other hand holding it
			var w := _swing("build", 1.0 - clampf(_hit_t / float(BEATS.build), 0.0, 1.0))
			twist = w[0]
			arm_l = w[1]
			arm_r = w[2]
			el = w[3]
			er = w[4]
			lean = w[5]
			kn = w[6]
		_:
			arm_l = sin(t * 1.3) * 0.04
			arm_r = -arm_l
	if _anim == "push":
		arm_l = -0.7 + sin(t * 5.0) * 0.15
		arm_r = arm_l
		lean = 0.45
	if _anim == "push":
		el = 0.5
		er = 0.5
		kn = 0.4
	if vehicle == "hand" and _anim == "walk":
		arm_l = -0.7
		arm_r = -0.7
		lean = 0.15
		el = 0.45
		er = 0.45
	elif vehicle == "ox" and _anim == "walk":
		arm_r = -0.9 # (a hand on the halter)
	elif carry_n > 0 and carry_res in ["tas", "yiyecek", "su", "camur", "kerpic"] and _anim == "walk":
		arm_l = -0.42
		arm_r = -0.42
		el = 1.25 # (the load gripped in both hands, against the chest)
		er = 1.25
	elif carry_n > 0 and carry_res == "yarali" and _anim == "walk":
		arm_l = 0.55 # (both hands back, gripping the wrists, leaning into the pull)
		arm_r = 0.55
		el = 0.2
		er = 0.2
		lean = 0.35
		kn = 0.2
	elif carry_n > 0 and carry_res == "odun" and _anim == "walk":
		arm_r = -2.6
		er = 1.8 # (the hand over on the log)
	if _load and not has_cart:
		_load.visible = _anim in ["walk", "idle", "look"] # (down out of the way as they stoop to it)
	if _body:
		if _lantern and _lantern.visible:
			_lantern.global_basis = Basis.IDENTITY # (it hangs from the hand, upright)
		if _rod_line:
			_rod_line.global_basis = Basis.IDENTITY # (the line hangs straight down from the tip)
		_body.pose.seat = seat
		# the feet set on the slope, close to the view, on the land itself (not a floor or a porch)
		var cam := get_viewport().get_camera_3d()
		var near := cam != null and cam.global_position.distance_squared_to(global_position) < 4900.0
		_body.pose.plant = 1.0 if near and seat < 0.0 and perched == null and absf(position.y - nav.height(position.x, position.z)) < 0.06 else 0.0
		if _stepping > 0.0 and not walking:
			var l := global_basis.orthonormalized().inverse() * Vector3(_step_v.x, 0, _step_v.y)
			if absf(l.x) > absf(l.z):
				_body.side_step = "WalkRight" if l.x > 0.0 else "WalkLeft"
			else:
				_body.side_step = "WalkBack" if l.z > 0.0 else "Walk"
			_body.side_pace = _step_v.length() / Townsfolk.WALK_SPEED * 1.3
		else:
			_body.side_step = ""
		_body_mood(walking)
		_body.drive(_anim, walking, _speed_now, _rate(), carry_res if carry_n > 0 else "", vehicle, _rifle,
			{"arm_l": arm_l, "arm_r": arm_r, "el": el, "er": er, "lean": lean, "twist": twist, "kn": kn})
		return
	var k := 1.0 - exp(-14.0 * dt)
	# Sitting: down on the ground, the knees up a little.
	_sit = move_toward(_sit, 1.0 if _anim in ["sit", "eat"] else 0.0, dt * 2.5)
	var drop := (0.4 if not _knees.is_empty() else 0.52) * _sit
	for hip in _legs:
		hip.position.y = _hip_y - drop
	var thigh := 1.25 if not _knees.is_empty() else 1.45
	_legs[0].rotation.x = lerpf(_legs[0].rotation.x, (leg if walking else 0.0) + thigh * _sit, k)
	_legs[1].rotation.x = lerpf(_legs[1].rotation.x, (-leg if walking else 0.0) + thigh * _sit, k)
	if _knees.size() == 2:
		# A knee bends as its leg swings through, and when sitting, bending over, working low.
		var swing_l := maxf(sin(_phase + 1.3), 0.0) * 0.95 if walking else 0.0
		var swing_r := maxf(sin(_phase + 1.3 + PI), 0.0) * 0.95 if walking else 0.0
		_knees[0].rotation.x = lerpf(_knees[0].rotation.x, -(kn + swing_l + 0.5 * _sit), k)
		_knees[1].rotation.x = lerpf(_knees[1].rotation.x, -(kn + swing_r + 0.5 * _sit), k)
	if _elbows.size() == 2:
		_elbows[0].rotation.x = lerpf(_elbows[0].rotation.x, el, k)
		_elbows[1].rotation.x = lerpf(_elbows[1].rotation.x, er, k)
	# (the numbers above raise an arm forward and lean forward as they grow; the model faces -z)
	_arms[0].rotation.x = lerpf(_arms[0].rotation.x, -arm_l, k)
	_arms[1].rotation.x = lerpf(_arms[1].rotation.x, -arm_r, k)
	_torso.position.y = bob - drop
	_torso.rotation.x = lerpf(_torso.rotation.x, -lean, k)
	_torso.rotation.y = lerpf(_torso.rotation.y, twist, k)
