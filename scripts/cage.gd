class_name Cage
extends Node
## KAFES: rounds in the cage (CageArena), one after another, like the robot fights on television.
## Each round lays its own floor (mud, ice, fire vents, spikes, fences) and sends its own rivals in
## from the blue corner; you start from the red one, and the crowd's on its feet as it goes.
##
##   before    you build what you'll fight with (B), and start when it's ready (it's fixed after that:
##             only the workshop's repairs, paid for, change it)
##   a round   3, 2, 1 and in; it's yours when every rival's in pieces, or has sat there unable to
##             move for COUNT_OUT seconds (counted out); at TIME it goes to the judges, who give it
##             to whoever's lost the smaller share of their machine
##   between   the damage stays: you're paid for the round (more for what you tore off them, quicker),
##             and in the workshop you buy back what you lost — the cab first, then the engines, what
##             it runs on, the battery, the guns, the rest — as far as the money goes
##   the end   your cab gone, you're out (or down the pit); win them all and you're the champion
##
## From the third round two house robots keep the hatched corners (CageArena.HOUSE_ZONES): they
## can't be hurt, and drive into anything that comes in. Some rounds have a pit, which opens at
## PIT_OPENS s (lights, a siren): what goes over it falls and is out. In the workshop you can also
## build (B): a new part costs its price, one taken off pays back half.

signal finished(won_all: bool)

const TIME := 150.0 ## s a round
const PIT_OPENS := 45.0 ## s into a round the pit (if it has one) opens
const REFUND := 0.5 ## of its price a part taken off in the workshop pays back
const COUNT_OUT := 8.0 ## s a rival can't move before it's counted out
const START_CREDITS := 300
const CREW := [2.2, 1.7, 1.3, 1.0] ## by round: how far the rivals' aim wanders (x a seasoned crew's)
const ROUNDS := [
	{"name": "ÇAMUR ÇUKURU", "rivals": [["skirmisher", ""]],
		"layout": {"zones": [[Rect2(-9, -9, 18, 18), "mud"]], "blocks": [Vector2(-14, 12), Vector2(14, -12)],
			"spinners": [Vector2(-13, 13)]}},
	{"name": "BUZ PİSTİ", "rivals": [["", ""]],
		"layout": {"zones": [[Rect2(-22, -7, 44, 14), "ice"]],
			"spikes": [Rect2(-13, -17, 9, 2.5), Rect2(4, 14.5, 9, 2.5)],
			"saws": [[Vector2(-10, 10), Vector2(10, 10)], [Vector2(-10, -10), Vector2(10, -10)]]}},
	{"name": "ATEŞ KAPANLARI", "rivals": [["", ""]], "house": true,
		"layout": {"zones": [[Rect2(-24, -24, 48, 48), "gravel"]],
			"vents": [Vector2(-9, -9), Vector2(9, 9), Vector2(-9, 9), Vector2(9, -9)],
			"drums": [Vector2(0, -16), Vector2(0.8, -16.4), Vector2(0, 16), Vector2(-0.8, 16.3)]}},
	{"name": "BATAKLIK", "rivals": [["", ""], ["skirmisher", ""]], "house": true,
		"layout": {"zones": [[Rect2(-24, -24, 14, 14), "bog"], [Rect2(10, 10, 14, 14), "bog"], [Rect2(-6, -6, 12, 12), "mud"]],
			"pit": Rect2(-3, 8, 6, 6),
			"fences": [[Vector2(-14, 0), Vector2(-5, 0)], [Vector2(5, 0), Vector2(14, 0)]]}},
	{"name": "DİKENLİ ÇİT", "rivals": [["", ""]], "house": true,
		"layout": {"zones": [[Rect2(-24, -24, 48, 48), "dirt"]], "spikes": [Rect2(-2, -12, 4, 24)],
			"fences": [[Vector2(-15, -9), Vector2(-15, 9)], [Vector2(15, -9), Vector2(15, 9)]],
			"blocks": [Vector2(-8, 16), Vector2(8, -16)], "pit": Rect2(6, 6, 6, 6),
			"spinners": [Vector2(-9, -9)]}},
	{"name": "FİNAL", "rivals": [["artillery", "ŞAMPİYON"], ["rammer", ""]], "house": true,
		"layout": {"zones": [[Rect2(-24, -24, 48, 48), "wet"], [Rect2(-6, -6, 12, 12), "mud"]],
			"vents": [Vector2(-15, 15), Vector2(15, -15)], "spikes": [Rect2(-20, -1.5, 7, 3), Rect2(13, -1.5, 7, 3)],
			"fences": [[Vector2(-4, -15), Vector2(4, -15)], [Vector2(-4, 15), Vector2(4, 15)]], "pit": Rect2(-3, -3, 6, 6),
			"spinners": [Vector2(-12, 0), Vector2(12, 0)], "saws": [[Vector2(-8, -20), Vector2(8, -20)]]}},
]
## What a part costs to put back (credits): its weight, and a fitting charge.
const PER_KG := 1.2
const FITTING := 30.0
const MISSING := 1.3 ## (a whole part again, not a patch)

var game: Node
var arena: CageArena
var state := "prep" ## prep, countdown, fight, won, workshop, lost, champion
var round := 0
var credits := START_CREDITS
var rivals: Array[Machine] = []
var houses: Array[Machine] = []
var time_left := TIME
var excite := 0.15
var full: Array = [] ## the design as you set out with it (what the workshop puts back)
var run_seed := 0 ## the run's: each round's rivals are Forge's from it (a new lot each run)
var _count_t := 0.0
var _still := {} ## Machine -> s it's been unable to move
var _hp_start := {} ## Machine -> its health when the round began
var _ui: CageUi
var _murmur: AudioStreamPlayer
var _roar: AudioStreamPlayer
var _shout: AudioStreamPlayer
var _bound: Array[Machine] = []
var _pit_called := false


func _ready() -> void:
	_ui = CageUi.new()
	_ui.cage = self
	add_child(_ui)
	_murmur = _loop("res://assets/audio/crowd/murmur_loop.wav", -14.0, 24.5)
	_roar = _loop("res://assets/audio/crowd/roar_loop.wav", -60.0, 12.0)
	_shout = AudioStreamPlayer.new()
	add_child(_shout)
	var b := game.get("builder") as Builder
	b.guard = _may_build
	b.price_note = func(id: String) -> String: return "%d kredi" % int(price(id)) if state == "workshop" else ""
	b.removed.connect(_on_removed)
	b.closed.connect(func() -> void:
		if state == "workshop":
			full = (game.get("machine") as Machine).to_data() + _missing_entries()
			_ui.show_workshop())
	_prep()


func _loop(path: String, db: float, secs: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s := (load(path) as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(secs * 44100.0) - 1
	p.stream = s
	p.volume_db = db
	add_child(p)
	p.play()
	return p


func _shout_out(file: String, db := -4.0) -> void:
	_shout.stream = load("res://assets/audio/crowd/" + file)
	_shout.volume_db = db
	_shout.play()


# --- The flow -------------------------------------------------------------------------------------

func _prep() -> void:
	state = "prep"
	round = 0
	credits = START_CREDITS
	_place_player()
	arena.set_round(ROUNDS[0].layout)
	_ui.show_prep()


## You build before the first round for nothing, and in the workshop for credits.
func can_build() -> bool:
	return state in ["prep", "workshop"]


## A part going on: free before the first round; in the workshop, if you can pay its price.
func _may_build(id: String, _at: Vector3i, _rot: int) -> bool:
	if state != "workshop":
		return true
	var p := int(price(id))
	if credits < p:
		game.call("say", "Kredi yetmiyor: %s %d kredi" % [Parts.def(id).name, p])
		return false
	credits -= p
	return true


func _on_removed(id: String, _at: Vector3i, _rot: int) -> void:
	if state == "workshop":
		credits += int(price(id) * REFUND)


## The entries of the parts that are missing now (kept in `full` across a workshop build: still to buy back).
func _missing_entries() -> Array:
	var out := []
	for d: Dictionary in damage_list():
		if d.missing:
			out.append(d.entry)
	return out


func start_run() -> void:
	var m: Machine = game.get("machine")
	full = m.to_data()
	if run_seed == 0:
		run_seed = randi() | 1
	_begin_round(0)


func _begin_round(i: int) -> void:
	round = i
	var r: Dictionary = ROUNDS[i]
	var b := game.get("builder") as Builder
	if b.active:
		b.set_active(false)
	for e in rivals + houses:
		if is_instance_valid(e):
			e.queue_free()
	rivals.clear()
	houses.clear()
	_still.clear()
	if Combat.current:
		Combat.current.clear_debris()
	arena.set_round(r.layout)
	_place_player()
	var k := 0
	for rv: Array in r.rivals:
		var at := Vector3(CageArena.HALF - 5.0 - k * 6.0, 0.0, CageArena.HALF - 5.0 + k * 1.5)
		at.y = arena.terrain.height_at(at.x, at.z) + 1.5
		# built for this round from the run's seed: a style (the round's, or any), stronger each round
		var made := Forge.make(run_seed * 977 + i * 31 + k, maxi(i - k, 0), str(rv[0])) # (a second one a round weaker)
		var e: Machine = game.call("_spawn", made.data, Transform3D(Basis.looking_at(-at * Vector3(1, 0, 1), Vector3.UP), at), 1, true)
		e.label = str(rv[1]) if str(rv[1]) != "" else str(made.name)
		for d in e.get_children():
			if d is AiDriver:
				# green crews early on (their aim wanders), seasoned by the fourth round; slower to open fire too
				(d as AiDriver).clumsy = CREW[mini(i, CREW.size() - 1)]
				(d as AiDriver)._wake = 1.2 + maxf(2.0 - i, 0.0) * 0.8
		e.set_physics_process(false) # (held till the countdown's done)
		rivals.append(e)
		k += 1
	if r.get("house", false):
		for z: Rect2 in CageArena.HOUSE_ZONES:
			var at := Vector3(z.get_center().x, 0.0, z.get_center().y)
			at.y = arena.terrain.height_at(at.x, at.z) + 1.5
			var h: Machine = game.call("_spawn", Designs.house(), Transform3D(Basis.looking_at(-at * Vector3(1, 0, 1), Vector3.UP), at), 2, false)
			h.label = "MUHAFIZ"
			h.house = true
			h.invulnerable = true
			var d := HouseDriver.new()
			d.zone = z
			d.home = Vector3(at.x, 0.0, at.z)
			h.add_child(d)
			h.set_lights(true)
			h.set_physics_process(false)
			houses.append(h)
	_hp_start.clear()
	var me: Machine = game.get("machine")
	me.resupply(1.0) # (each round on full racks)
	_hp_start[me] = me.health()
	for e in rivals:
		_hp_start[e] = e.health()
	_bind()
	time_left = TIME
	_pit_called = false
	state = "countdown"
	_count_t = 3.5
	game.set("player_input", false)
	_ui.show_round(r.name, i + 1, ROUNDS.size())


## Your machine to the red corner, its nose to the middle.
func _place_player() -> void:
	var m: Machine = game.get("machine")
	if not is_instance_valid(m):
		return
	var at := Vector3(-CageArena.HALF + 4.5, 0.0, -CageArena.HALF + 4.5)
	at.y = arena.terrain.height_at(at.x, at.z) + 1.2
	m.linear_velocity = Vector3.ZERO
	m.angular_velocity = Vector3.ZERO
	m.global_transform = Transform3D(Basis.looking_at(-at * Vector3(1, 0, 1), Vector3.UP), at)
	m.set_down()
	var cam := game.get("cam") as OrbitCamera
	if cam:
		cam.yaw = (-at * Vector3(1, 0, 1)).normalized().signed_angle_to(Vector3.FORWARD, Vector3.DOWN)


## Every machine in the cage, listened to: hits work the crowd up.
func _bind() -> void:
	var all: Array[Machine] = rivals.duplicate()
	var me: Machine = game.get("machine")
	if is_instance_valid(me):
		all.append(me)
	for m in all:
		if m in _bound:
			continue
		_bound.append(m)
		m.damaged.connect(func(amount: float, _from: Vector3, _kind: String) -> void:
			excite = minf(excite + amount / 260.0, 1.0)
			if amount > 120.0 and not _shout.playing:
				_shout_out(["cheer_01.wav", "cheer_02.wav", "ooh.wav", "gasp.wav"][randi() % 4], -6.0))


func _process(dt: float) -> void:
	excite = move_toward(excite, 0.15 if state != "fight" else 0.25, dt * 0.12)
	arena.set_excite(excite)
	_roar.volume_db = linear_to_db(maxf((excite - 0.15) * 1.2, 0.0001)) - 6.0
	match state:
		"countdown":
			_count_t -= dt
			_ui.countdown(_count_t)
			if _count_t <= 0.0:
				state = "fight"
				game.set("player_input", true)
				for e in rivals + houses:
					if is_instance_valid(e):
						e.set_physics_process(true)
				excite = 0.8
				_shout_out("cheer_02.wav", -2.0)
		"fight":
			time_left -= dt
			if TIME - time_left >= PIT_OPENS and arena.pit.size.x > 0.0 and not arena.pit_open:
				arena.open_pit()
				if not _pit_called:
					_pit_called = true
					_shout_out("ooh.wav", -2.0)
					game.call("say", "ÇUKUR AÇILIYOR")
			_check(dt)
	_ui.tick(dt)


func _check(dt: float) -> void:
	var me: Machine = game.get("machine")
	if not is_instance_valid(me) or not me.alive:
		return
	if me.falling:
		_lost("ÇUKURA DÜŞTÜN")
		return
	# you on your back (or unable to move) as long as a rival would be counted out: you are
	var down := me.immobile() or me.global_basis.y.y < 0.3
	_still[me] = (float(_still.get(me, 0.0)) + dt) if down else 0.0
	if float(_still[me]) >= COUNT_OUT:
		_lost("TERS DÖNDÜN" if me.global_basis.y.y < 0.3 else "HAREKETSİZ KALDIN")
		return
	var standing := 0
	for e in rivals:
		if not is_instance_valid(e) or not e.alive or e.falling:
			continue
		var stuck := e.immobile() or e.global_basis.y.y < 0.3 or e.linear_velocity.length() < 0.05 and e.throttle != 0.0
		_still[e] = (float(_still.get(e, 0.0)) + dt) if stuck else 0.0
		if float(_still[e]) < COUNT_OUT:
			standing += 1
	if standing == 0:
		_round_over(true, "")
	elif time_left <= 0.0:
		# the judges: the smaller share lost wins it
		var mine := float(_hp_start.get(me, 1.0)) - me.health()
		var theirs := 0.0
		for e in rivals:
			var h := e.health() if is_instance_valid(e) and e.alive else 0.0
			theirs = maxf(theirs, float(_hp_start.get(e, 1.0)) - h) if is_instance_valid(e) else 1.0
		_round_over(mine <= theirs, "JÜRİ KARARI")


func _round_over(won: bool, how: String) -> void:
	game.set("player_input", false)
	var me: Machine = game.get("machine")
	if is_instance_valid(me):
		me.throttle = 0.0
		me.firing = false
	for e in rivals + houses:
		if is_instance_valid(e):
			e.set_physics_process(false)
	if not won:
		_lost("JÜRİ KARARI · TUR KAYBEDİLDİ")
		return
	state = "won"
	excite = 1.0
	_shout_out("applause.wav", -3.0)
	# paid: the round's purse, what you tore off them, the time left
	var torn := 0.0
	for e in rivals:
		var h := e.health() if is_instance_valid(e) and e.alive and not e.falling else 0.0
		torn += float(_hp_start.get(e, 1.0)) - h
	var pay := 300 + 100 * round + int(torn * 350.0) + int(maxf(time_left, 0.0) * 1.0)
	credits += pay
	_ui.show_won(how if how != "" else "KAZANDIN", pay)
	var last := round >= ROUNDS.size() - 1
	await get_tree().create_timer(3.0).timeout
	if state != "won":
		return
	if last:
		state = "champion"
		_ui.show_final(true, round + 1, credits)
		finished.emit(true)
	else:
		state = "workshop"
		_ui.show_workshop()


## Your cab's gone (or the judges went against you): out.
func on_player_died() -> void:
	_lost("KABİNİN PARÇALANDI")


func _lost(why: String) -> void:
	if state in ["lost", "champion"]:
		return
	state = "lost"
	excite = 1.0
	_shout_out("gasp.wav", -2.0)
	await get_tree().create_timer(2.0).timeout
	_ui.show_final(false, round, credits, why)
	finished.emit(false)


## The builder's opening over the workshop: the workshop's panel steps aside (it's back when the
## builder closes).
func on_build_open() -> void:
	if _ui.panel_up():
		_ui.hide_panel()


## A panel of its own is up (the start, the workshop, the end): the pointer's for that.
func panel_up() -> bool:
	return _ui.panel_up()


## Enter: start (before the first round) or on to the next round (in the workshop).
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not k or not k.pressed or k.echo or not k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		return
	if (game.get("builder") as Builder).active:
		return
	if state == "prep":
		_ui.close()
		start_run()
	elif state == "workshop":
		_ui.close()
		next_round()


func next_round() -> void:
	_begin_round(round + 1)


## A new run: a new machine from your saved design in the red corner, the money and the rounds anew.
func restart() -> void:
	for e in rivals + houses:
		if is_instance_valid(e):
			e.queue_free()
	rivals.clear()
	houses.clear()
	game.call("_respawn_quiet")
	_prep()


# --- The workshop ---------------------------------------------------------------------------------

static func price(id: String) -> float:
	return float(Parts.def(id).mass) * PER_KG + FITTING


static func _key(id: String, at: Vector3i, rot: int) -> String:
	return "%s@%d,%d,%d/%d" % [id, at.x, at.y, at.z, rot]


## What's wrong with your machine against how you set out: [{id, key, missing, frac, cost}], the most
## needed first (the cab, the engines, what it runs on, the battery, the guns, the rest).
func damage_list() -> Array:
	var m: Machine = game.get("machine")
	var have := {}
	for p: Dictionary in m.design:
		have[_key(p.id, p.at, p.rot)] = p
	var out := []
	for e: Array in full:
		var id := str(e[0])
		var key := _key(id, Vector3i(int(e[1]), int(e[2]), int(e[3])), int(e[4]))
		var p: Dictionary = have.get(key, {})
		var frac := 0.0 if p.is_empty() else clampf(float(p.hp) / Parts.hp_of(id), 0.0, 1.0)
		if frac >= 0.999:
			continue
		var cost := price(id) * (MISSING if p.is_empty() else (1.0 - frac))
		out.append({"id": id, "key": key, "entry": e, "missing": p.is_empty(), "frac": frac, "cost": ceili(cost)})
	var rank := {"cab": 0, "engine": 1, "wheel": 2, "track": 2, "battery": 3, "weapon": 4}
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(rank.get(str(Parts.def(a.id).kind), 5)) < int(rank.get(str(Parts.def(b.id).kind), 5)))
	return out


## Puts back what the money runs to, in the list's order (only the cab with `cab_only`).
func repair(cab_only := false) -> int:
	var m: Machine = game.get("machine")
	var fix := {} ## key -> hp it's brought back to
	var spent := 0
	for d: Dictionary in damage_list():
		if cab_only and d.id != "cab":
			continue
		var cost: int = d.cost
		if credits - spent >= cost:
			fix[d.key] = Parts.hp_of(d.id)
			spent += cost
		elif not d.missing and credits - spent > 0:
			# a patch, as far as it goes
			var part := float(credits - spent) / cost
			fix[d.key] = Parts.hp_of(d.id) * (float(d.frac) + (1.0 - float(d.frac)) * part)
			spent = credits
		if spent >= credits:
			break
	if spent == 0:
		return 0
	credits -= spent
	var have := {}
	for p: Dictionary in m.design:
		have[_key(p.id, p.at, p.rot)] = p
	var parts: Array = []
	for e: Array in full:
		var id := str(e[0])
		var at := Vector3i(int(e[1]), int(e[2]), int(e[3]))
		var key := _key(id, at, int(e[4]))
		if fix.has(key):
			parts.append({"id": id, "at": at, "rot": int(e[4]), "hp": float(fix[key])})
		elif have.has(key):
			parts.append(have[key])
	m.design = _connected(parts)
	m.rebuild()
	return spent


## Only the parts still reaching the cab through bolted faces (a wheel bought back onto a bed that
## isn't there stays off).
static func _connected(parts: Array) -> Array:
	var occ := {}
	var cab := -1
	for i in parts.size():
		var p: Dictionary = parts[i]
		if p.id == "cab":
			cab = i
		for c in Parts.cells_of(p.id, p.at, p.rot):
			occ[c] = i
	if cab < 0:
		return parts
	var seen := {cab: true}
	var queue: Array[int] = [cab]
	while not queue.is_empty():
		var i: int = queue.pop_back()
		var p: Dictionary = parts[i]
		if i != cab and not Machine._structural(p.id):
			continue
		for c in Parts.cells_of(p.id, p.at, p.rot):
			for n in Machine._NEIGHBOURS:
				var j: int = occ.get(c + n, -1)
				if j >= 0 and not seen.has(j):
					seen[j] = true
					queue.append(j)
	var out: Array = []
	for i in parts.size():
		if seen.has(i):
			out.append(parts[i])
	return out
