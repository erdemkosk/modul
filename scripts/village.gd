class_name Village
extends "res://scripts/village_work.gd"
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

func _process(dt: float) -> void:
	clock += dt
	_drift_tick(dt)
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
		_camp_fires()
		_training()
		_dry_bricks(_heat_t)
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


## Off on its own a while, its spirits broken: sat at the edge of the woods, or walking about.
func _plan_sulk(v: Villager) -> void:
	v.abort()
	v.sulk_cd = randf_range(70.0, 120.0)
	var to := v.position
	for k in 12:
		var a := randf() * TAU
		var p := v.position + Vector3(cos(a), 0, sin(a)) * randf_range(18.0, 35.0)
		if nav.is_open(p):
			to = p
			break
	to.y = nav.height(to.x, to.z)
	var what: String = ["Morali çökmüş: kendi başına oturuyor", "Morali çökmüş: ağlıyor", "Morali çökmüş: amaçsızca dolaşıyor"][randi() % 3]
	v.give([{"t": "go", "to": to}, {"t": "work", "time": randf_range(30.0, 50.0), "anim": "sit" if not what.ends_with("dolaşıyor") else "look"}], what)


## It's had enough: it says so and walks off down the valley, and the town's one fewer (its family
## the worse for it).
func _leave(v: Villager) -> void:
	v.abort()
	v.leaving = true
	if is_instance_valid(v.workplace):
		v.workplace.workers.erase(v)
	v.workplace = null
	var away := (v.position - (stores()[0].global_position if not stores().is_empty() else Vector3.ZERO))
	away.y = 0.0
	var to := v.position + (away.normalized() if away.length() > 1.0 else Vector3.FORWARD) * 120.0
	to.y = nav.height(to.x, to.z)
	message.emit("%s artık dayanamadı: kasabayı terk ediyor" % v.display_name, "bad")
	for o in villagers:
		if o != v and o.family == v.family:
			o.think("left", "%s kasabayı terk etti" % v.display_name.split(" ")[0], -12.0, maxf(weather.day_length_minutes * 60.0, 60.0))
	v.give([{"t": "go", "to": to}, {"t": "do", "f": func() -> bool:
		villagers.erase(v)
		if is_instance_valid(v.home):
			v.home.residents.erase(v)
		v.home = null
		v.queue_free()
		return true}], "Kasabayı terk ediyor")


func _assign() -> void:
	var night := weather.is_night()
	var fires: Array[Building] = []
	for b in buildings:
		if b.is_burning() and b.state != "gone":
			fires.append(b)
	var raid := raids != null and raids.threat()
	_rescues()
	if not raid:
		_captures()
	var day_s := maxf(weather.day_length_minutes * 60.0, 60.0)
	for v in villagers:
		if v.dead or v.down or v.drafted or v.leaving:
			continue
		# Broken in spirit: now and then it downs tools and goes off on its own; a day of it, and it
		# leaves the valley.
		if v.mood < Villager.BREAK and not raid and not v.sleeping and not v.is_child:
			if v.low_for > day_s:
				_leave(v)
				continue
			if v.sulk_cd <= 0.0 and (v.plan.is_empty() or v.idle or (is_instance_valid(v.workplace) and v.target == v.workplace and v.carry_n == 0)):
				_plan_sulk(v)
				continue
		if v.sleeping:
			var cover := v.inside
			var unsafe := not is_instance_valid(cover) or cover.state != "done" or cover.is_burning()
			if v.recovering and v.hp < v.max_hp * 0.6 and not unsafe:
				continue # (abed with its wound)
			if raid and v.militia and not v.is_child and (v.armed or armory_for(v) != null):
				v.wake() # (the alarm: up and to the armoury)
				continue
			if unsafe or (v.hiding and not raid) or (not v.hiding and not night and not raid) or (not v.hiding and night and on_watch(v)):
				v.wake()
			continue
		if raid and _plan_raid(v):
			continue
		if not raid and v.armed and (v.plan.is_empty() or v.idle or str(v.plan[0].t) == "hold"):
			_plan_return_arms(v)
			continue
		if not raid and (v.plan.is_empty() or v.idle) and not v.is_child and _plan_loot(v):
			continue
		if not fires.is_empty() and (v.plan.is_empty() or v.idle) and _plan_fire(v, fires):
			continue
		# An urgent felling (ACİL KES): anyone whose woodcutting isn't set to never, between jobs, goes
		# for it before their own work (not the watch, not by night).
		# A healer gathering herbs drops them for a wound.
		if is_instance_valid(v.workplace) and v.workplace.def.role == "healer" and v.target == v.workplace and v.carry_n == 0 \
				and v.workplace.state == "done" and needs_healer():
			v.abort()
			_plan_work(v)
			continue
		# A worker at its workplace's round with nothing in hand drops it at once (what it carries, it
		# brings home first).
		var at_work: bool = is_instance_valid(v.workplace) and v.target == v.workplace and v.carry_n == 0 and not v.sleeping
		if not night and not v.is_child and int(v.prio.get("odun", 1)) > 0 and (v.plan.is_empty() or v.idle or at_work) \
				and not (v.workplace and v.workplace.def.role in ["barracks", "tower"]) and urgent_count() > 0:
			if v.idle or at_work:
				v.abort()
			if _plan_cut(v, true):
				continue
		if not v.plan.is_empty() and not (v.idle and v.workplace == null and _site_needs_hands()):
			continue
		var meal := _meal_key()
		if meal != "" and v.meal_key != meal and (v.plan.is_empty() or v.idle) and not raid:
			_plan_meal(v, meal)
			continue
		# Its own house out of fuel in the cold: fetched from the store on the way home, before the night.
		var home := v.home
		if is_instance_valid(home) and home.state == "done" and needs_fire() and house_fuel(home) <= 0 \
				and not is_instance_valid(home.pile_claim) and not raid and _fuel_trip(v, home):
			v.job = "Evine yakacak götürüyor"
			continue
		if night and not on_watch(v):
			# Work done for the day: home to bed, or with no house, to the camp fire.
			if is_instance_valid(v.home) and v.home.state == "done":
				_plan_home(v)
			else:
				_plan_bed(v)
			continue
		if v.workplace:
			# At dusk a lamp nobody's filled yet: a worker takes the kindling on the way (not the watch).
			if weather.hour > 16.5 and not night and not v.workplace.def.role in ["barracks", "tower"] and _plan_firewood(v, true):
				continue
			if v.workplace.state == "done":
				_plan_work(v)
			continue
		if v.is_child:
			if v.plan.is_empty():
				_plan_play(v)
			continue
		var haul_ok := int(v.prio.get("tasima", 1)) > 0
		var build_ok := int(v.prio.get("insa", 1)) > 0
		var cut_ok := int(v.prio.get("odun", 1)) > 0
		if (haul_ok and _plan_haul(v)) or (build_ok and _plan_build(v)) or _plan_firewood(v) or (build_ok and _plan_wall(v)) \
				or (cut_ok and _plan_cut(v)) or (haul_ok and _plan_logs(v)):
			continue
		if v.plan.is_empty():
			_plan_idle(v)
