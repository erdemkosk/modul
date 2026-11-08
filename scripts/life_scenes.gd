class_name LifeScenes
extends RefCounted
## The town's daily round as scenes with more than one in them, or tied to the hour, the season and
## what's going on (the moves themselves: LifePoses):
##   water        the houses short of a well (Building.water_far): one of the household fetches it
##                twice a day on the yoke, from the nearest well or the river
##   snow         after snow, each house's doorstep shovelled clear once a day; boots stamped and
##                the coat brushed at the door coming in (the line's shovellers: village_work)
##   the train    the folk about wave as it comes in and goes; at a stand a chain forms from the
##                wagon (one climbed up into it) to the pile, crates and sacks passed hand to hand
##                (the first train's load goes into the pile that way, for real); settlers stepping
##                down are met, embraced or shaken by the hand
##   fire         three or more at the same fire with the well near enough: a bucket chain from the
##                well to the flames instead of each running with a pail
##   the house    the pot stirred on a yard fire before a meal, linen scrubbed at the river and hung
##                on the line, the doorstep swept of a morning
##   the evening  a round dance beside the square's fire, a garmon or a balalaika, clapping
##   the children snowball fights and the sled in the winter, the hens chased in the summer
## Kept on the village (village_life.gd); `tick` every couple of seconds, the rest asked for when a
## plan's being made.

var village ## (the Village: untyped, it's the whole of it)
var _brigades := {} ## fire (Building) -> its chain
var _unload := {} ## the chain at the wagon, while there's one
var _unload_stop := -1.0 ## (the train's stand it was made for, by when it leaves: one chain a stop)
var _pile_at := -999.0
var _pile_props: Array[Node3D] = [] ## (what the chain has stacked by the station, cleared when the train's gone)
var _train_was := ""
var _waved := {} ## villager id -> clock it last waved
var _met := {} ## villager id -> true (a settler met off the train)
var _rings := {} ## square -> its dance
var _snow_day := {} ## house -> the day its step was cleared
var _water := {} ## house -> "<day>-<half>" it last had its water fetched
var _said := {}


func _init(v: Variant) -> void:
	village = v


func tick() -> void:
	_fire_chains()
	_train_scenes()
	_prune_rings()


# --- chains: hand to hand ----------------------------------------------------------------------

## A chain of `folk` from `a` (the source, on their left) to `b` (on their right), side-on to the
## line, `item` going down it (LifePoses._pass). `opts`: start ("pick": taken up low), end ("put"
## on a pile, "throw" at a fire), job, target, levels (each one's feet over the ground: up in a
## wagon), on_item (called as each piece reaches the end: false, it's done), alive (false: it
## breaks up), first (steps for the first before its place: climbing up), after (for each: steps
## once it breaks up, by its place in the line).
func make_chain(folk: Array, a: Vector3, b: Vector3, item: String, opts: Dictionary) -> Dictionary:
	var n := folk.size()
	var d := b - a
	d.y = 0.0
	var len := d.length()
	d = d / maxf(len, 0.01)
	var face := Vector3.UP.cross(d) # (the body faces -z; its right, +x, is down the line)
	var chain := {"n": n, "t0": 0.0, "item": item, "start": opts.get("start", ""), "end": opts.get("end", ""),
		"folk": folk, "ready": false, "count": 0, "alive": true, "born": float(village.clock),
		"levels": opts.get("levels", []), "on_item": opts.get("on_item", Callable()), "alive_f": opts.get("alive", Callable())}
	var spots: Array = opts.get("spots", [])
	var faces: Array = opts.get("faces", [])
	for i in n:
		var v: Villager = folk[i]
		var p := a + d * (len * float(i) / float(maxi(n - 1, 1)))
		if i < spots.size():
			p = spots[i]
		else:
			p.y = village.ground_at(p)
		var f: Vector3 = faces[i] if i < faces.size() else face
		v.abort()
		v.set_carry("", 0)
		var steps: Array = []
		if i == 0 and opts.has("first"):
			steps.append_array(opts.first)
		else:
			steps.append({"t": "go", "to": p})
			steps.append({"t": "step", "to": p})
		var ci := i
		steps.append({"t": "work", "anim": "pass", "face": p + f * 3.0, "life": {"chain": chain, "i": ci},
			"tick": func(_dt: float) -> bool: return _chain_tick(chain, v, ci)})
		var after: Array = opts.get("after", [])
		if i < after.size():
			steps.append_array(after[i])
		v.give(steps, str(opts.get("job", "Zincirde")), opts.get("target", null))
	return chain


## A member's frame in the chain: waiting for the rest to take their places, then (the last one)
## counting each piece in as it arrives. False: it's over (for it, and so for all).
func _chain_tick(chain: Dictionary, v: Villager, i: int) -> bool:
	if not bool(chain.alive):
		return false
	var f: Callable = chain.alive_f
	if f.is_valid() and not bool(f.call()):
		chain.alive = false
		chain.why = "over"
		return false
	var all_there := true
	for o: Variant in chain.folk:
		if not is_instance_valid(o) or (o as Villager).dead or (o as Villager).down:
			chain.alive = false
			chain.why = "gone"
			return false
		var w := o as Villager
		var at_post := not w.plan.is_empty() and str(w.plan[0].get("anim", "")) == "pass" and is_same((w.plan[0].get("life", {}) as Dictionary).get("chain"), chain)
		if not at_post:
			if bool(chain.ready):
				chain.alive = false # (one of them called off: it falls apart)
				chain.why = "left: %s %s" % [w.job, str(w.plan[0]) if not w.plan.is_empty() else "-"]
				return false
			all_there = false
	if not bool(chain.ready):
		if all_there:
			chain.ready = true
			chain.t0 = float(village.clock)
		elif float(village.clock) - float(chain.born) > 60.0:
			chain.alive = false
			chain.why = "never ready"
			return false
		return true
	if i == int(chain.n) - 1:
		var n := int(chain.n)
		var got := floori((float(village.clock) - float(chain.t0)) / LifePoses.PASS_T - (n - 1) * LifePoses.PASS_HOLD - 0.56) + 1
		while int(chain.count) < got:
			chain.count = int(chain.count) + 1
			var on: Callable = chain.on_item
			if on.is_valid() and not bool(on.call()):
				chain.alive = false
				chain.why = "done"
				return false
	var _v := v
	return true


# --- fire ----------------------------------------------------------------------------------------

## Three or more running pails to the same fire, and the well close enough for a chain of them: a
## bucket chain instead, from the well's lip to the flames, the last one flinging each pail on.
func _fire_chains() -> void:
	for fire: Variant in _brigades.keys():
		if not is_instance_valid(fire) or not bool(_brigades[fire].alive):
			_brigades.erase(fire)
	var wells: Array[Building] = village._wells()
	if wells.is_empty():
		return
	for fire: Building in village.buildings:
		if not fire.is_burning() or fire.state == "gone" or _brigades.has(fire):
			continue
		var folk: Array[Villager] = []
		for v: Villager in village.villagers:
			if not v.dead and not v.down and v.target == fire and v.job == "Yangın söndürüyor":
				folk.append(v)
		if folk.size() < 3:
			continue
		var well: Building = village._nearest(wells, fire.global_position)
		var a: Vector3 = well.door()
		var b: Vector3 = village._spot_by(fire, a)
		var len := Vector2(b.x - a.x, b.z - a.z).length()
		var n := clampi(ceili(len / 1.3) + 1, 3, folk.size())
		if len / float(n - 1) > 1.45:
			continue # (not enough of them to reach hand to hand: they run with the pails)
		var mid := a.lerp(b, 0.5)
		folk.sort_custom(func(p: Villager, q: Villager) -> bool: return p.position.distance_squared_to(mid) < q.position.distance_squared_to(mid))
		var crew := folk.slice(0, n)
		var f := fire
		var lit := [float(village.clock)]
		_brigades[fire] = make_chain(crew, a, b, "pail", {"start": "pick", "end": "throw", "job": "Yangında kova zinciri", "target": fire,
			"on_item": func() -> bool:
				if not is_instance_valid(f):
					return false
				if f.is_burning() and randf() < 0.6:
					f.douse()
				return true,
			"alive": func() -> bool:
				# (kept at it a little after the last flame's out: it flares up again as often as not)
				if is_instance_valid(f) and f.is_burning():
					lit[0] = float(village.clock)
				return is_instance_valid(f) and f.state != "gone" and float(village.clock) - lit[0] < 8.0})
		village.message.emit("%s için kuyudan kova zinciri kuruldu" % fire.display_name(), "info")


# --- the train ---------------------------------------------------------------------------------

func _train_scenes() -> void:
	var tr: Variant = village.train
	if not is_instance_valid(tr):
		_train_was = ""
		_clear_pile()
		return
	var state := "standing" if tr.is_standing() else "moving"
	if state != _train_was:
		_wave_at(tr, 45.0 if state == "standing" else 70.0) # (in, or off again)
		_train_was = state
	elif state == "moving":
		_wave_at(tr, 60.0)
	if state != "standing":
		if not _unload.is_empty():
			_unload.alive = false
			_unload = {}
		if not _pile_props.is_empty() and float(village.clock) - _pile_at > 90.0:
			_clear_pile()
	else:
		_unload_chain(tr)
	_welcome()


## The folk about near where the train is (and not busy at anything) stop and wave at it.
func _wave_at(tr: Variant, reach: float) -> void:
	var at: Vector3 = tr.engine_at()
	var now := float(village.clock)
	for v: Villager in village.villagers:
		if v.dead or v.sleeping or v.team != 0 or not v.visible or v.drafted:
			continue
		if not (v.plan.is_empty() or v.idle) or v.job.begins_with("Trenden") or v.job == "Kovalamaca oynuyor":
			continue
		if v.position.distance_to(at) > reach or now - float(_waved.get(v.get_instance_id(), -999.0)) < 50.0:
			continue
		_waved[v.get_instance_id()] = now
		v.abort()
		v.give([{"t": "work", "time": randf_range(3.5, 6.0), "anim": "wave", "face": at}], "Trene el sallıyor", null, true)


## The boxcar's door, and where the chain goes from it (the side toward `toward`).
func _wagon(tr: Variant, toward: Vector3) -> Dictionary:
	var car: Node3D = tr._cars[3] if tr._cars.size() > 3 else tr._cars[tr._cars.size() - 1]
	var c := car.global_position
	var side := toward - c
	side.y = 0.0
	side = side.normalized() if side.length() > 0.1 else car.global_basis.x
	var foot := c + side * 1.9 # (on the ground by the door)
	foot.y = village.ground_at(foot)
	var floor := c + side * 0.75
	floor.y = c.y + 1.15
	return {"foot": foot, "floor": floor, "side": side}


## At a stand: a chain from the wagon to the pile. The first train: those carrying its load off
## one by one form it, if there are enough to reach (and the load goes into the pile by it); a
## later train: whoever's free nearby (the crates stacked by the station meanwhile).
func _unload_chain(tr: Variant) -> void:
	if not _unload.is_empty() and bool(_unload.alive):
		return
	if not _unload.is_empty():
		_unload = {}
		return # (it broke up: not again this stop)
	var first := bool(village.arriving)
	var dest: Building = village._pile if first else village.depot()
	if dest == null or not is_instance_valid(dest):
		return
	var stop := float(village.loading_until)
	if not first and (stop < 0.0 or is_equal_approx(stop, _unload_stop)):
		return
	if first and _unload_stop == -2.0:
		return
	var w := _wagon(tr, dest.global_position)
	var end: Vector3 = dest.drop_spot("yiyecek") if first else dest.door()
	var folk: Array[Villager] = []
	for v: Villager in village.villagers:
		if v.dead or v.down or v.sleeping or v.is_child or v.team != 0 or v.drafted:
			continue
		if first:
			if v.job == "Trenden yük indiriyor":
				folk.append(v)
		elif v.position.distance_to(w.foot) < 150.0 and (v.plan.is_empty() or v.idle \
				or (v.position.distance_to(w.foot) < 70.0 and v.workplace == null and v.carry_n == 0 and v.owed.is_empty() and not v.armed and v.target == null)):
			folk.append(v) # (the free hands about, and those near between loads)
	var len := Vector2(end.x - (w.foot as Vector3).x, end.z - (w.foot as Vector3).z).length()
	var n := mini(folk.size() + 0, 8)
	if n < (maxi(4, mini(int(village.start_people), 8)) if first else 3): # (the first: all of them down off it)
		return
	# one up in the wagon at its door, the rest from below it to the pile, 1.3 m apart
	var ground_n := n - 1
	var reach := (ground_n - 1) * 1.4
	var b: Vector3 = end if len <= reach + 0.6 else (w.foot as Vector3) + ((end - w.foot) as Vector3).normalized() * reach
	b.y = village.ground_at(b)
	folk.sort_custom(func(p: Villager, q: Villager) -> bool: return p.position.distance_squared_to(w.foot) < q.position.distance_squared_to(w.foot))
	var crew: Array = folk.slice(0, n)
	if first:
		for v: Villager in crew:
			if v.carry_n > 0:
				dest.add_goods(v.carry_res, v.carry_n) # (what it had in its arms: put on the pile)
			else:
				_refund(v)
	_unload_stop = stop if not first else -2.0
	var floor: Vector3 = w.floor
	var foot: Vector3 = w.foot
	var side: Vector3 = w.side
	var levels: Array = [floor.y - foot.y]
	for i in range(1, n):
		levels.append(0.0)
	# the one up in the wagon in its doorway, then the line from the foot of the door out to the pile
	var dir := (b - foot)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else side
	var spots: Array = [floor]
	var faces: Array = [Vector3.UP.cross(side)]
	for i in range(1, n):
		var p := foot.lerp(b, float(i - 1) / float(maxi(n - 2, 1)))
		p.y = village.ground_at(p)
		spots.append(p)
	var climber: Villager = crew[0]
	var first_steps: Array = [{"t": "go", "to": foot}, {"t": "work", "time": 1.0, "anim": "climb", "face": floor},
		{"t": "do", "f": func() -> bool:
			climber.position = floor
			return true}]
	var after: Array = [[{"t": "work", "time": 0.8, "anim": "climb", "face": foot}, {"t": "do", "f": func() -> bool:
		climber.position = Vector3(foot.x, village.ground_at(foot), foot.z)
		return true}]]
	var opts := {"start": "pick", "end": "put", "levels": levels, "first": first_steps, "after": after, "spots": spots, "faces": faces,
		"job": "Trenden yük indiriyor" if first else "Vagondan yük indiriyor (zincir)", "target": dest}
	if first:
		var pile := dest
		var short := b.distance_to(end) > 1.0 # (the line doesn't reach the pile: stacked at its end, the pile's all the same)
		var spot0 := b
		var count0 := [0]
		opts["on_item"] = func() -> bool:
			if short:
				count0[0] += 1
				_stack(spot0, dir, count0[0])
			return _first_load_item(pile)
		opts["alive"] = func() -> bool: return is_instance_valid(pile) and is_instance_valid(village.train) and village.train.is_standing()
	else:
		var spot := b
		var count := [0]
		opts["on_item"] = func() -> bool:
			count[0] += 1
			_stack(spot, dir, count[0])
			return count[0] < 16
		opts["alive"] = func() -> bool: return is_instance_valid(village.train) and village.train.is_standing() and float(village.loading_until) > float(village.clock)
	_pile_at = float(village.clock)
	_unload = make_chain(crew, foot, b, "mixed", opts)


## (the first train) a member taken off its round trip: what it was to carry goes back in the wagon.
func _refund(v: Villager) -> void:
	var cargo: Dictionary = village._cargo
	for r: String in ["yiyecek", "odun", "tas"]:
		if int(cargo.get(r, 0)) > 0:
			cargo[r] = int(cargo[r]) + v.capacity(r)
			return
	cargo["tas"] = int(cargo.get("tas", 0)) + v.capacity("tas")


## (the first train) a crate or sack at the end of the line: into the pile; the wagon empty, it's done.
func _first_load_item(pile: Building) -> bool:
	if not is_instance_valid(pile):
		return false
	var cargo: Dictionary = village._cargo
	for r: String in ["yiyecek", "odun", "tas"]:
		var left := int(cargo.get(r, 0))
		if left > 0:
			var n := mini(10, left)
			cargo[r] = left - n
			pile.add_goods(r, n)
			break
	for r: String in cargo:
		if int(cargo[r]) > 0:
			return true
	village._cargo_done(pile)
	return false


## A crate or a sack set down on the stack at the line's end (a later train's: cleared when it's gone).
func _stack(at: Vector3, dir: Vector3, k: int) -> void:
	var side := Vector3.UP.cross(dir)
	var col := (k - 1) % 4
	var row := ((k - 1) / 4) % 2
	var lay := (k - 1) / 8
	var p := at + dir * (0.5 + row * 0.45) + side * (float(col) - 1.5) * 0.46 + Vector3.UP * (0.15 + lay * 0.31)
	p.y += village.ground_at(p) - at.y if lay == 0 else 0.0
	var kind := "crate" if k % 3 != 0 else "sack"
	var n := LifeProps.make(kind)
	village.add_child(n)
	n.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP).rotated(Vector3.UP, randf_range(-0.12, 0.12)), p)
	_pile_props.append(n)


func _clear_pile() -> void:
	for n in _pile_props:
		if is_instance_valid(n):
			n.queue_free()
	_pile_props.clear()


## Settlers just down off a train (not the first: they came together) met by one of the town:
## an embrace, or a handshake, and a word.
func _welcome() -> void:
	if not bool(village.announced):
		return
	for v: Villager in village.villagers:
		if v.dead or v.job != "Trenden indi" or _met.has(v.get_instance_id()):
			continue
		_met[v.get_instance_id()] = true
		var best: Villager = null
		var bd := 140.0
		for o: Villager in village.villagers:
			if o == v or o.dead or o.sleeping or o.is_child or o.team != 0 or o.drafted or o.job == "Trenden indi" or _met.has(o.get_instance_id()):
				continue
			if not (o.plan.is_empty() or o.idle):
				continue
			var d := o.position.distance_to(v.position)
			if d < bd:
				bd = d
				best = o
		if best == null:
			continue
		var at: Vector3 = v.plan[0].to if not v.plan.is_empty() and v.plan[0].has("to") else v.position
		var greet := "embrace" if v.female or best.female or randf() < 0.4 else "handshake"
		meet(best, v, at, greet, "Yeni geleni karşılıyor", "Karşılanıyor", "welcome")


## Two meeting at `at`: each goes to its side of it, waits for the other, then the greeting
## ("embrace", "handshake"), then a word together (`where` for what's said).
func meet(a: Villager, b: Villager, at: Vector3, greet: String, job_a: String, job_b: String, where := "") -> void:
	var dir := b.position - a.position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var d := 0.64 if greet == "embrace" else 0.9
	var pa := at - dir * d * 0.5
	var pb := at + dir * d * 0.5
	pa.y = village.ground_at(pa)
	pb.y = village.ground_at(pb)
	if not village.nav.is_open(pa) or not village.nav.is_open(pb):
		return
	var talk := {"folk": [a, b], "t0": float(village.clock), "seed": randi() % 1000, "reach": 3.2, "where": where}
	var plans := [[a, pa, b, pb, job_a], [b, pb, a, pa, job_b]]
	for e: Array in plans:
		var me: Villager = e[0]
		var mine: Vector3 = e[1]
		var other: Villager = e[2]
		var theirs: Vector3 = e[3]
		var waited := [0.0]
		me.abort()
		me.give([{"t": "go", "to": mine}, {"t": "step", "to": mine},
			{"t": "work", "anim": "wave", "face": theirs, "tick": func(dt: float) -> bool:
				waited[0] += dt
				return waited[0] < 20.0 and is_instance_valid(other) and not other.dead and other.position.distance_to(theirs) > 0.3},
			{"t": "work", "time": 3.4 if greet == "embrace" else 2.4, "anim": greet, "face": theirs, "life": {"d": d}},
			{"t": "work", "time": randf_range(7.0, 11.0), "anim": "chat", "talk": talk, "face": theirs}], str(e[4]), null, true)


# --- the house -----------------------------------------------------------------------------------

## Water fetched home on the yoke: a house short of it (Building.water_far) has it fetched twice a
## day by one of the household (`force`: any house, a trip now and then anyway). From the nearest
## well, or the river if that's nearer. True if `v` was sent.
func plan_water(v: Villager, force := false) -> bool:
	var h: Building = v.home
	if v.is_child or not is_instance_valid(h) or h.state != "done" or h.is_burning():
		return false
	var hour := float(village.weather.hour)
	if hour < 6.0 or hour > 19.0:
		return false
	var half := "%d-%d" % [int(village.day), 0 if hour < 12.5 else 1]
	if not force and (not h.water_far or str(_water.get(h, "")) == half):
		return false
	var src := Vector3.INF
	var face := Vector3.INF
	var well: Building = village._nearest(village._wells(), h.global_position)
	if well:
		src = well.door()
		face = well.global_position
	if village._shores.is_empty():
		village._find_shores()
	for e: Array in village._shores:
		var at: Vector3 = e[0]
		if at == Vector3.INF:
			continue
		if src == Vector3.INF or at.distance_to(h.global_position) < src.distance_to(h.global_position):
			src = at
			face = e[1]
	if src == Vector3.INF or src.distance_to(h.global_position) > 320.0:
		return false
	_water[h] = half
	var door := h.door()
	v.give([{"t": "go", "to": src},
		{"t": "work", "time": 4.5, "anim": "draw", "face": face},
		{"t": "go", "to": door, "life": "yoke"},
		{"t": "work", "time": 1.6, "anim": "set_down", "face": h.global_position, "life": {"what": "yoke"}}],
		"Omuz sırığıyla su taşıyor", null, true)
	return true


## A chore about the house for `v` just now, if one suits (the hour, the season, the weather): the
## doorstep shovelled after snow, the pot on the yard fire before a meal, the step swept of a
## morning, the washing scrubbed at the river. True if it was given one.
func plan_chore(v: Villager) -> bool:
	var h: Building = v.home
	if v.is_child or not is_instance_valid(h) or h.state != "done" or h.is_burning():
		return false
	var hour := float(village.weather.hour)
	var snow := Weather.snow_cover_now
	var wet := Weather.rain_now > 0.2 or float(village.weather.snow_intensity) > 0.4
	var temp := float(village.weather.temperature)
	var winter: bool = village.seasons != null and village.seasons.winter()
	var front := h.global_basis.z.normalized()
	var along := h.global_basis.x.normalized()
	var door := h.door()
	# the step dug out after snow: once a day a house, by whoever's about first
	if snow > 0.35 and hour > 7.0 and hour < 16.0 and int(_snow_day.get(h, -1)) != int(village.day):
		_snow_day[h] = int(village.day)
		var at := door + front * 0.6 + along * randf_range(-0.6, 0.6)
		if village.nav.is_open(at):
			at.y = village.ground_at(at)
			v.give([{"t": "go", "to": at}, {"t": "step", "to": at},
				{"t": "work", "time": randf_range(28.0, 40.0), "anim": "shovel", "face": at + along * 3.0}], "Kapının önündeki karı küreyor", null, true)
			return true
	if wet:
		return false
	# the pot on the fire in the yard before a meal (the women; inside in the cold)
	if v.female and temp > 4.0 and not winter and ((hour > 10.6 and hour < 12.0) or (hour > 16.6 and hour < 18.0)) and randf() < 0.6:
		for side: float in [1.0, -1.0]:
			var at := door + front * 1.8 + along * side * 2.6
			var pot := at - front * 0.72
			if village.nav.is_open(at) and village.nav.is_open(pot):
				at.y = village.ground_at(at)
				v.give([{"t": "go", "to": at}, {"t": "step", "to": at},
					{"t": "work", "time": randf_range(30.0, 45.0), "anim": "stir", "face": at - front * 3.0}], "Kazanda yemek pişiriyor", null, true)
				return true
	# the step swept of a morning
	if hour > 6.5 and hour < 10.5 and snow < 0.3 and randf() < 0.35:
		var at := door + front * 0.4
		if village.nav.is_open(at):
			at.y = village.ground_at(at)
			v.give([{"t": "go", "to": at}, {"t": "step", "to": at},
				{"t": "work", "time": randf_range(16.0, 26.0), "anim": "sweep", "face": at + front * 3.0}], "Kapı önünü süpürüyor", null, true)
			return true
	# the washing at the river (the women, the warm months, the forenoon)
	if v.female and not winter and temp > 7.0 and hour > 8.0 and hour < 15.0 and randf() < 0.35:
		if village._shores.is_empty():
			village._find_shores()
		var best: Array = []
		var bd := 160.0
		for e: Array in village._shores:
			var at: Vector3 = e[0]
			if at == Vector3.INF or village._seat_taken(at):
				continue
			var dd := at.distance_to(h.global_position)
			if dd < bd:
				bd = dd
				best = e
		if not best.is_empty():
			var at: Vector3 = best[0]
			village._hold_seat(at, v, "Nehirde çamaşır yıkıyor")
			v.give([{"t": "go", "to": at, "life": "basket"}, {"t": "step", "to": at},
				{"t": "work", "time": randf_range(40.0, 60.0), "anim": "scrub", "face": best[1]},
				{"t": "go", "to": door, "life": "basket"}], "Nehirde çamaşır yıkıyor", null, true)
			return true
	return false


## Coming in out of the snow: the boots stamped and the coat brushed at the door (a step to put
## after the walk to it in `steps`, the plan in through the door).
func at_door(steps: Array, h: Building) -> Array:
	if Weather.snow_cover_now < 0.3 or steps.is_empty() or str(steps[0].get("t", "")) != "go" or not is_instance_valid(h):
		return steps
	var out := steps.duplicate()
	out.insert(1, {"t": "work", "time": 2.2, "anim": "stamp", "face": h.global_position})
	return out


# --- the evening: the dance ------------------------------------------------------------------------

## Of an evening with the square's fire lit: a round dance beside it on open ground, one playing the
## garmon (or the balalaika), the dancers hand in hand going round, stopping to stamp, the women
## spinning; others stood by clapping. `v` joins it if there's a part for it (true).
func plan_dance(v: Villager, sq: Building) -> bool:
	var hour := float(village.weather.hour)
	if hour < 19.0 or hour > 22.6 or Weather.rain_now > 0.25 or float(village.weather.snow_intensity) > 0.5:
		return false
	var ring: Dictionary = _rings.get(sq, {})
	if ring.is_empty():
		ring = _new_ring(sq)
		if ring.is_empty():
			return false
		_rings[sq] = ring
	var c: Vector3 = ring.center
	var dancers: Array = ring.dancers
	var player: Variant = ring.player
	var has_player: bool = player != null and is_instance_valid(player) and not (player as Villager).dead and _in_ring(player as Villager, ring)
	if not has_player and not v.is_child:
		ring.player = v
		var at: Vector3 = ring.player_at
		var inst := "garmon" if v.look_seed % 3 != 0 else "balalaika"
		v.give([{"t": "go", "to": at}, {"t": "step", "to": at},
			{"t": "work", "anim": inst, "face": c, "life": {"ring": ring}, "tick": func(_dt: float) -> bool: return _ring_alive(ring)}],
			"Meydanda garmon çalıyor" if inst == "garmon" else "Meydanda balalayka çalıyor", sq, true)
		return true
	if dancers.size() < 8 and (randf() < 0.75 or dancers.size() < 3):
		dancers.append(v)
		var life := {"ring": ring}
		var time := randf_range(50.0, 90.0)
		var start := c + Vector3(cos(randf() * TAU), 0, sin(randf() * TAU)) * 2.0
		start.y = village.ground_at(start)
		var spent := [0.0]
		v.give([{"t": "go", "to": start},
			{"t": "work", "anim": "dance", "face": c, "life": life, "tick": func(dt: float) -> bool:
				spent[0] += dt
				return spent[0] < time and _dance_tick(ring, v, life, dt)},
			{"t": "do", "f": func() -> bool:
				(ring.dancers as Array).erase(v)
				v.think("dance", "Akşam meydanda horon tepti", 10.0, maxf(float(village.weather.day_length_minutes) * 60.0, 60.0))
				return true}], "Meydanda halay çekiyor", sq, true)
		return true
	if randf() < 0.6:
		var a := randf() * TAU
		var at := c + Vector3(cos(a), 0, sin(a)) * (_radius(dancers.size()) + randf_range(1.4, 2.2))
		if not village.nav.is_open(at):
			return false
		at.y = village.ground_at(at)
		v.give([{"t": "go", "to": at}, {"t": "step", "to": at},
			{"t": "work", "time": randf_range(25.0, 45.0), "anim": "clap", "face": c}], "Oyunculara el çırpıyor", sq, true)
		return true
	return false


## Where by `sq` there's room for a dance (open ground off one of its sides), and the ring's state.
func _new_ring(sq: Building) -> Dictionary:
	var nav: Nav = village.nav
	for k in 16:
		var a := sq.global_rotation.y + (k % 8) * TAU / 8.0
		var dir := Vector3(sin(a), 0, cos(a))
		var c := sq.global_position + dir * (8.0 if k < 8 else 11.0)
		var ok := nav.is_open(c)
		var h0 := nav.height(c.x, c.z)
		for j in 8:
			var b := j * TAU / 8.0
			var q := c + Vector3(cos(b), 0, sin(b)) * 2.6
			# open and near enough flat (a ring of dancers on a slope is no dance)
			ok = ok and nav.is_open(q) and absf(nav.height(q.x, q.z) - h0) < 0.5
		if ok:
			c.y = village.ground_at(c)
			var pa := c - dir * 2.6 # (the player stood between the ring and the fire, facing the ring)
			pa.y = village.ground_at(pa)
			return {"center": c, "dancers": [], "player": null, "player_at": pa, "t0": -1.0, "part": "wait",
				"dir": 1.0, "speed": 0.55, "spin_u": -1.0, "theta": 0.0, "sq": sq}
	return {}


static func _radius(n: int) -> float:
	return maxf(float(n) * 1.25 / TAU, 0.75)


## Whether `v` is at (or on its way to) its part in `ring`.
func _in_ring(v: Villager, ring: Dictionary) -> bool:
	for st: Dictionary in v.plan:
		var life: Variant = st.get("life", null)
		if life is Dictionary and is_same((life as Dictionary).get("ring"), ring):
			return true
	return false


func _ring_alive(ring: Dictionary) -> bool:
	var hour := float(village.weather.hour)
	return hour >= 18.8 and hour < 23.0 and not bool(ring.get("over", false))


## A dancer's frame: where it is in the ring (going round it, the ring's part from the beat), and the
## hands of the ones either side to hold.
func _dance_tick(ring: Dictionary, v: Villager, life: Dictionary, dt: float) -> bool:
	if not _ring_alive(ring):
		return false
	var dancers: Array = ring.dancers
	var here: Array = []
	for o: Variant in dancers:
		if is_instance_valid(o) and not (o as Villager).dead and _in_ring(o as Villager, ring) and str((o as Villager).plan[0].get("anim", "")) == "dance":
			here.append(o)
	var n := here.size()
	var i := here.find(v)
	var c: Vector3 = ring.center
	var now := float(village.clock)
	if n >= 3 and float(ring.t0) < 0.0:
		ring.t0 = now
	if n < 2 or i < 0:
		ring.part = "wait"
		return true
	# the part of the dance from the beat: 10 s going round (one way, then back the other), 4 s
	# stamping (the women spinning once round in the middle of it)
	var t := now - float(ring.t0) if float(ring.t0) >= 0.0 else 0.0
	var cyc := int(t / 14.0)
	var u := fmod(t, 14.0)
	var r := _radius(n)
	var w := float(ring.speed) / r
	var dir := 1.0 if cyc % 2 == 0 else -1.0
	var theta := (w * 10.0 if cyc % 2 == 1 else 0.0) + dir * w * minf(u, 10.0)
	if float(ring.t0) < 0.0:
		ring.part = "wait"
		theta = 0.0
	else:
		ring.part = "round" if u < 10.0 else "stamp"
		ring.dir = dir
		ring.spin_u = clampf((u - 11.0) / 1.5, 0.0, 1.0) if u > 11.0 and u < 12.5 else -1.0
	var a := theta + TAU * float(i) / float(n)
	var want := c + Vector3(cos(a), 0, sin(a)) * r
	var d := Vector2(want.x - v.position.x, want.z - v.position.z)
	var step := maxf(1.6 * dt, 0.0)
	if d.length() <= step or d.length() > 6.0:
		v.position.x = want.x
		v.position.z = want.z
	else:
		v.position.x += d.x / d.length() * step
		v.position.z += d.y / d.length() * step
	v.position.y = village.ground_at(v.position)
	# hands: met halfway with each neighbour, a little in toward the middle
	if n >= 3:
		for side in 2:
			var j := (i + (1 if side == 0 else -1) + n) % n
			var aj := theta + TAU * float(j) / float(n)
			var pj := c + Vector3(cos(aj), 0, sin(aj)) * r
			var mid := (want + pj) * 0.5
			mid += (c - mid).normalized() * 0.1
			life["left_hand" if side == 0 else "right_hand"] = mid
	else:
		life.erase("left_hand")
		life.erase("right_hand")
	return true


func _prune_rings() -> void:
	# the music from the nearest ring with its player at it
	var playing := false
	for ring: Dictionary in _rings.values():
		var pl: Variant = ring.player
		if pl != null and is_instance_valid(pl) and not (pl as Villager).plan.is_empty():
			var a := str((pl as Villager).plan[0].get("anim", ""))
			if a in ["garmon", "balalaika"]:
				Ambience.music((pl as Villager).global_position + Vector3.UP, a)
				playing = true
				break
	if not playing:
		Ambience.music(Vector3.ZERO, "")
	for sq: Variant in _rings.keys():
		var ring: Dictionary = _rings[sq]
		if not is_instance_valid(sq) or not (sq as Building).lit or not _ring_alive(ring):
			ring.over = true
			_rings.erase(sq)
			continue
		var dancers: Array = ring.dancers
		for k in range(dancers.size() - 1, -1, -1):
			var o: Variant = dancers[k]
			if not is_instance_valid(o) or (o as Villager).dead or not _in_ring(o as Villager, ring):
				dancers.remove_at(k)


# --- the children --------------------------------------------------------------------------------

## A child's game for the season: snowballs with another, the sled down a slope near home (winter);
## the hens chased round the yard (summer). True if `v` was given one.
func plan_child(v: Villager, kids: Array[Villager]) -> bool:
	var winter: bool = village.seasons != null and village.seasons.winter()
	var snow := Weather.snow_cover_now
	if snow > 0.3:
		if not kids.is_empty() and randf() < 0.55:
			return _snowballs(v, kids[randi() % kids.size()])
		if randf() < 0.5 and _sled(v):
			return true
	elif not winter and randf() < 0.3:
		return _hens(v)
	return false


func _snowballs(v: Villager, other: Villager) -> bool:
	var mid := v.position.lerp(other.position, 0.5)
	var dir := other.position - v.position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.RIGHT
	var gap := randf_range(5.0, 7.5)
	var pa := mid - dir * gap * 0.5
	var pb := mid + dir * gap * 0.5
	if not village.nav.is_open(pa) or not village.nav.is_open(pb):
		return false
	pa.y = village.ground_at(pa)
	pb.y = village.ground_at(pb)
	var time := randf_range(20.0, 32.0)
	for e: Array in [[v, pa, other, pb], [other, pb, v, pa]]:
		var me: Villager = e[0]
		var mine: Vector3 = e[1]
		var foe: Villager = e[2]
		var theirs: Vector3 = e[3]
		var life := {"at": theirs + Vector3.UP * 0.9, "who": foe}
		me.abort()
		me.give([{"t": "go", "to": mine, "run": true}, {"t": "step", "to": mine},
			{"t": "work", "time": time, "anim": "snowball", "face": theirs, "life": life, "tick": func(_dt: float) -> bool:
				if is_instance_valid(foe) and not foe.dead:
					life["at"] = foe.position + Vector3(randf_range(-0.4, 0.4), 0.9, randf_range(-0.4, 0.4))
				return true}], "Kartopu oynuyor", null, true)
	return true


## A slope near home to sled down: its top and its foot (the foot 2 m or more lower, open between).
func _sled(v: Villager) -> bool:
	var home: Variant = v.home
	var at: Vector3 = (home as Building).door() if is_instance_valid(home) else v.position
	var nav: Nav = village.nav
	var best := []
	var bd := 1.8
	for k in 12:
		var a := k * TAU / 12.0
		var dir := Vector3(cos(a), 0, sin(a))
		for r: float in [8.0, 14.0, 20.0]:
			var top := at + dir * r
			var foot := top + dir * 18.0
			if not nav.is_open(top) or not nav.is_open(foot):
				continue
			var drop := nav.height(top.x, top.z) - nav.height(foot.x, foot.z)
			var clear := true
			for j in range(1, 4):
				clear = clear and nav.is_open(top.lerp(foot, j / 4.0))
			if clear and drop > bd:
				bd = drop
				best = [top, foot]
	if best.is_empty():
		return false
	var top: Vector3 = best[0]
	var foot: Vector3 = best[1]
	top.y = village.ground_at(top)
	foot.y = village.ground_at(foot)
	var steps: Array = [{"t": "go", "to": foot, "run": true}]
	for run in 3:
		steps.append({"t": "go", "to": top, "life": "sled_pull"})
		steps.append({"t": "work", "time": 1.0, "anim": "sled_ride", "face": foot})
		var s := [0.0]
		steps.append({"t": "work", "anim": "sled_ride", "face": foot, "tick": func(dt: float) -> bool:
			# down the slope: quicker as it goes, the steeper the quicker
			s[0] = minf(s[0] + dt * (0.03 + s[0] * 0.05), 1.0)
			var p := top.lerp(foot, smoothstep(0.0, 1.0, s[0]))
			v.position = Vector3(p.x, village.ground_at(p), p.z)
			return s[0] < 1.0})
	v.give(steps, "Kızakla kayıyor", null, true)
	return true


func _hens(v: Villager) -> bool:
	var main: Node = village.get_tree().current_scene
	var critters: Variant = main.get("critters") if main else null
	if critters == null or not is_instance_valid(critters):
		return false
	var flock: Array = []
	var hens: Dictionary = critters._hens
	for house: Variant in hens:
		if is_instance_valid(house) and (house as Building).global_position.distance_to(v.position) < 40.0:
			flock = hens[house]
			break
	if flock.is_empty():
		return false
	var steps: Array = []
	for k in 3:
		var hen: Node3D = flock[randi() % flock.size()]
		if not is_instance_valid(hen) or not hen.visible:
			continue
		var p := hen.global_position
		steps.append({"t": "go", "to": p, "run": true, "life": "hen"})
		steps.append({"t": "work", "time": 1.2, "anim": "grab", "face": p + (p - v.position).normalized()})
	if steps.is_empty():
		return false
	v.give(steps, "Tavuk kovalıyor", null, true)
	return true


# --- talk ----------------------------------------------------------------------------------------

## How a word between `group` goes: an argument if two of them can't abide each other (their ways
## clash), or one's in a black mood; else a friendly one.
static func talk_mood(group: Array) -> String:
	for i in group.size():
		var a: Villager = group[i]
		if a.mood < 28.0 and randf() < 0.5:
			return "argue"
		for j in range(i + 1, group.size()):
			var b: Villager = group[j]
			for pair: Array in Villager.TRAIT_CLASH:
				if (a.has_trait(pair[0]) and b.has_trait(pair[1])) or (a.has_trait(pair[1]) and b.has_trait(pair[0])):
					if randf() < 0.6:
						return "argue"
	return "argue" if randf() < 0.06 else ""
