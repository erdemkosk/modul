extends "res://scripts/village_life.gd"
## The defence: the armoury and its rack, raising and arming the militia, posts and cover, the
## night watch's shifts, the bowyer, the wounded carried in, the outlaws' dropped rifles.

## In a raid: a guard goes for the nearest bandit, the archer climbs its tower, anyone else near one
## runs and hides. False if the raid asks nothing of it just now.
func _plan_raid(v: Villager) -> bool:
	# The militia: to the armoury for a rifle, then to a post to hold.
	if v.militia and not v.is_child:
		if v.armed:
			if v.plan.is_empty() or v.idle:
				v.abort()
				hold_at(v, default_post(v))
			return true
		var a := armory_for(v)
		if a:
			if v.job != "Silahlığa koşuyor":
				v.abort()
				arm(v, a)
			return true
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
	if v.has_trait("brave") and not v.is_child:
		# (it won't run: it goes on working, and goes for any outlaw who comes close, bare-handed)
		var close := raids.nearest_raider(v.position, 18.0)
		if close == null:
			return false
		if v.plan.is_empty() or str(v.plan[0].t) != "fight":
			v.abort()
			v.give([{"t": "fight", "foe": close, "give_up": 30.0}], "Haydutla boğuşuyor")
		return true
	var near := raids.nearest_raider(v.position, 600.0 if not bells().is_empty() else (90.0 if v.has_trait("coward") else 35.0))
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


# --- The defence -----------------------------------------------------------------------------------


func armories() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role == "armory":
			out.append(b)
	return out


## The nearest armoury with a weapon for `v` (its own kind, or any for one marked by hand).
func armory_for(v: Villager) -> Building:
	var with: Array[Building] = []
	for a in armories():
		if _weapon_at(a, v.weapon) != "":
			with.append(a)
	return _nearest(with, v.position)


## What `a` can hand out for a militiaman trained to `kind` ("" either): "rifle", "bow" or "".
func _weapon_at(a: Building, kind: String) -> String:
	if kind in ["", "rifle"] and a.arms > 0:
		return "rifle"
	if kind in ["", "bow"] and a.bows > 0 and a.arrows > 0:
		return "bow"
	return ""


## To the armoury for a rifle and its cartridges, then (`then`) to hold a post.
func arm(v: Villager, a: Building, then := true) -> void:
	v.give([{"t": "go", "to": a.door()},
		{"t": "work", "time": 1.2, "anim": "gather", "face": a.global_position},
		{"t": "do", "f": func() -> bool:
			if not is_instance_valid(a):
				return false
			var kind := _weapon_at(a, v.weapon)
			if kind == "":
				return false
			if kind == "rifle":
				a.arms -= 1
				var n := mini(10, a.ammo)
				a.ammo -= n
				v.ammo = n
				v.ranged = 42.0
				v.attack = 26.0
			else:
				a.bows -= 1
				var n := mini(20, a.arrows)
				a.arrows -= n
				v.ammo = n
				v.ranged = 26.0
				v.attack = 17.0
			v.held = kind
			v.armed = true
			v.fighter = true
			v.arm_with(kind)
			if v.drafted:
				hold_at(v, cover_near(v.position))
			elif then:
				hold_at(v, default_post(v))
			return true}], "Silahlığa koşuyor", a)


## Off to `post` and holding it: shooting what it can see from there.
func hold_at(v: Villager, post: Vector3) -> void:
	var raids_from: Vector3 = raids.origin() if raids else post + Vector3.FORWARD
	# At a palisade: up onto its walkway, shooting over the points (in cover, and seeing further).
	for w in walls:
		if not is_instance_valid(w):
			continue
		var n := w.nearest(post)
		if not n.is_empty() and float(n.dist) < 4.0:
			var spot := w.walk_spot(post)
			if not spot.is_empty():
				v.give([{"t": "go", "to": spot.down}, {"t": "do", "f": func() -> bool:
					v.climb((spot.at as Vector3).y)
					v.in_cover = true
					return true}, {"t": "work", "time": 0.9, "anim": "climb"},
					{"t": "hold", "face": raids_from}], "Surda nöbette", null)
				return
	v.give([{"t": "go", "to": post}, {"t": "do", "f": func() -> bool:
		v.in_cover = is_cover(v.position)
		return true}, {"t": "hold", "face": raids_from}], "Mevzide", null)


## Where the militia go when nobody says: behind cover between the store and where the band came from.
func default_post(v: Villager) -> Vector3:
	var store := _nearest(stores(), v.position)
	var home := store.global_position if store else v.position
	var from: Vector3 = raids.origin() if raids and raids.active else home + Vector3(30, 0, 0)
	var dir := (from - home)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.RIGHT
	var side := dir.cross(Vector3.UP)
	# a palisade toward where they come from: a place on its walkway
	var far := home + dir * 60.0 + side * randf_range(-14.0, 14.0)
	var best := {}
	for w in walls:
		if not is_instance_valid(w):
			continue
		var n := w.nearest(far)
		if not n.is_empty() and w.built[int(n.k)] == 1 and (best.is_empty() or float(n.dist) < float(best.dist)):
			best = n
	if not best.is_empty():
		return best.at
	var p := home + dir * 14.0 + side * randf_range(-10.0, 10.0)
	return cover_near(p)


## A spot near `p` with a wall or a fence close at hand (or `p`).
func cover_near(p: Vector3, reach := 5.0) -> Vector3:
	for rr in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]:
		if rr > reach:
			break
		for k in 10:
			var a := k * TAU / 10.0
			var q: Vector3 = p + Vector3(cos(a), 0, sin(a)) * rr
			if nav.is_open(q) and is_cover(q):
				q.y = ground_at(q)
				return q
			if rr == 0.0:
				break
	p.y = ground_at(p)
	return p


func is_cover(p: Vector3) -> bool:
	for k in 8:
		var a := k * TAU / 8.0
		if not nav.is_open(p + Vector3(cos(a), 0, sin(a)) * 1.4):
			return true
	return false


## Militia to be trained: one at a time at each armoury, by day, if there's a weapon for it. The one
## picked takes it out to the target beside the armoury and practises (a bow takes much longer to
## learn than a rifle; the rifle burns a few cartridges), then puts it back on the rack: from then
## on that's its weapon when the alarm goes.
func _training() -> void:
	if weather.is_night():
		return
	for a in armories():
		if a.training.is_empty():
			continue
		var tr: Variant = a.get_meta("trainee") if a.has_meta("trainee") else null
		if tr != null and is_instance_valid(tr) and not (tr as Villager).dead and str((tr as Villager).job).begins_with("Talim"):
			continue
		var kind: String = a.training[0]
		if _weapon_at(a, kind) == "" or (kind == "rifle" and a.ammo < 3):
			continue
		var best: Villager = null
		var bd := INF
		for v in villagers:
			if v.dead or v.down or v.drafted or v.sleeping or v.is_child or v.weapon != "" or v.has_cart:
				continue
			if v.workplace and v.workplace.def.role in ["barracks", "tower"]:
				continue
			if not (v.plan.is_empty() or v.idle):
				continue
			var key := "nisan" if kind == "rifle" else "okcu"
			if int(v.prio.get(key, 1)) == 0:
				continue
			# (the best eye for it first, those put first for it before the rest)
			var d := v.position.distance_to(a.global_position) * (0.5 if v.workplace == null else 1.0) * 0.02 - v.skill(key) - int(v.prio.get(key, 1)) * 10.0
			if d < bd:
				bd = d
				best = v
		if best == null:
			continue
		var v := best
		a.set_meta("trainee", v)
		var board := a.global_transform * Vector3(5.1, 1.0, 0.0)
		var stand := a.global_transform * Vector3(5.1, 0.0, 14.0 if kind == "rifle" else 10.0)
		stand.y = ground_at(stand)
		var time := 35.0 if kind == "rifle" else 90.0
		var acc := [0.0]
		v.abort()
		v.give([{"t": "go", "to": a.door()},
			{"t": "work", "time": 1.0, "anim": "gather", "face": a.global_position},
			{"t": "do", "f": func() -> bool:
				v.arm_with(kind)
				return true},
			{"t": "go", "to": stand},
			{"t": "work", "anim": "aim", "face": board, "tick": func(dt: float) -> bool:
				acc[0] += dt
				var every := 6.0 if kind == "rifle" else 3.0
				if fmod(acc[0], every) < dt:
					if kind == "rifle" and is_instance_valid(a):
						a.ammo = maxi(a.ammo - 1, 0)
					raids.practice(v.muzzle(), board, kind)
				return acc[0] < time},
			{"t": "do", "f": func() -> bool:
				v.arm_with("")
				v.weapon = kind
				v.militia = true
				if is_instance_valid(a):
					if not a.training.is_empty():
						a.training.pop_front()
					a.remove_meta("trainee")
				message.emit("%s talimini bitirdi: artık %s milis." % [v.display_name, "tüfekçi" if kind == "rifle" else "okçu"], "good")
				return true}], "Talimde (%s)" % ("tüfek" if kind == "rifle" else "yay"), a)


## The bowyer: odun from the store, worked at the bench into a bow or a bundle of arrows, carried
## to the armoury: a bow, then arrows enough for the bows on the rack, then another bow.
func _plan_bowyer(v: Villager, b: Building) -> void:
	var a := _nearest(armories(), b.global_position)
	if a == null:
		b.idle_note = "Silahlık yok: yapılan yaylar konacak yer yok"
		_plan_idle(v)
		return
	var store := _nearest(stores(), b.global_position)
	if store == null or int(store.goods.get("odun", 0)) <= 0:
		b.idle_note = "Depoda odun yok"
		_plan_idle(v)
		return
	b.idle_note = ""
	# (a bow first, then arrows enough to use it, then the next bow)
	var bow := a.bows == 0 or (a.arrows >= 20 and a.arrows >= a.bows * 30)
	var need := 2 if bow else 1
	v.give([{"t": "go", "to": store.door()},
		{"t": "do", "f": func() -> bool:
			if not is_instance_valid(store) or store.take_goods("odun", need) < need:
				return false
			v.set_carry("odun", 1)
			return true},
		{"t": "go", "to": b.station()},
		{"t": "do", "f": func() -> bool:
			v.set_carry("", 0)
			return true},
		{"t": "work", "time": 30.0 if bow else 18.0, "anim": "chisel", "face": b.station_face()},
		{"t": "do", "f": func() -> bool:
			v.set_carry("tufek", 1)
			return true},
		{"t": "go", "to": a.door()},
		{"t": "do", "f": func() -> bool:
			v.set_carry("", 0)
			if is_instance_valid(a):
				if bow:
					a.bows += 1
				else:
					a.arrows += 12
			return true}], "Yayçı: %s yapıyor" % ("yay" if bow else "ok"), b)


## The raid over: the rifle and what's left of its cartridges back on the rack.
func _plan_return_arms(v: Villager) -> void:
	var a := _nearest(armories(), v.position)
	v.abort()
	var ground := ground_at(v.position)
	if v.position.y > ground + 0.5:
		v.climb(ground) # (down off the walkway)
	if a == null:
		_disarm(v)
		return
	v.give([{"t": "go", "to": a.door()}, {"t": "do", "f": func() -> bool:
		if is_instance_valid(a):
			if v.held == "bow":
				a.bows += 1
				a.arrows += v.ammo
			else:
				a.arms += 1
				a.ammo += v.ammo
		v.ammo = 0
		_disarm(v)
		return true}], "Tüfeği silahlığa koyuyor", a)


func _disarm(v: Villager) -> void:
	v.armed = false
	v.held = ""
	v.in_cover = false
	v.focus = null
	if v.workplace and v.workplace.def.role in ["barracks", "tower"]:
		return
	v.fighter = false
	v.ranged = 0.0
	v.attack = 9.0
	v.arm_with("")


## The wounded lying out: the nearest one free to come picks it up and carries it in to a bed.
# --- Prisoners -------------------------------------------------------------------------------------

## The jails with a cell free.
func _jails_free() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role == "jail" and b.prisoners.size() < int(b.def.cells):
			out.append(b)
	return out


## How many are held, all the jails together.
func prisoner_count() -> int:
	var n := 0
	for b in buildings:
		if b.def.role == "jail":
			n += b.prisoners.size()
	return n


## After a fight: an outlaw lying wounded carried to a jail with room by the nearest free hand.
func _captures() -> void:
	for o in downed_outlaws.duplicate():
		if not is_instance_valid(o) or o.dead or not o.down:
			downed_outlaws.erase(o)
			continue
		if is_instance_valid(o.carried_by) or (o.has_meta("taker") and is_instance_valid(o.get_meta("taker")) and (o.get_meta("taker") as Villager).job == "Haydudu hapse taşıyor"):
			continue
		var jails := _jails_free()
		if jails.is_empty():
			if not o.has_meta("said"):
				o.set_meta("said", true)
				message.emit("Yaralı bir haydut yerde: bir Hapishane olsaydı yakalanabilirdi.", "info")
			continue
		var to := _nearest(jails, o.position)
		var best: Villager = null
		var bd := 200.0
		for v in villagers:
			if v.dead or v.down or v.drafted or v.sleeping or v.is_child or v.has_cart or v.leaving or v.job == "Haydudu hapse taşıyor" or v.job == "Yaralıyı taşıyor":
				continue
			var d := v.position.distance_to(o.position)
			if d < bd:
				bd = d
				best = v
		if best == null:
			continue
		var v := best
		o.set_meta("taker", v)
		v.abort()
		v.give([{"t": "go", "to": o.position},
			{"t": "work", "time": 1.8, "anim": "gather", "face": o.position},
			{"t": "do", "f": func() -> bool:
				if not is_instance_valid(o) or o.dead or not o.down:
					return false
				o.carried_by = v
				v.set_carry("yarali", 1)
				return true},
			{"t": "go", "to": to.door()},
			{"t": "do", "f": func() -> bool:
				v.set_carry("", 0)
				if is_instance_valid(o) and not o.dead and o.down and is_instance_valid(to) and to.state == "done" and to.prisoners.size() < int(to.def.cells):
					imprison(o, to)
					message.emit("%s bir haydudu yakalayıp hapse kapattı." % v.display_name, "good")
				return true}], "Haydudu hapse taşıyor", o)


## `o` locked up in `jail`: who it is worked out (a name, its knacks and traits) for the card.
func imprison(o: Villager, jail: Building) -> void:
	downed_outlaws.erase(o)
	o.abort()
	o.sleep_in(jail, true)
	o.recovering = false
	o.held_in = jail
	o.held_mode = ""
	o.won = 0
	o.hp = o.max_hp
	if o.skills.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = randi()
		o.roll_skills(rng)
		o.family = _new_family()
		o.female = false
		o.display_name = full_name(o, NAMES[randi() % 12])
	o.job = "Hapiste"
	jail.prisoners.append(o)


## The jail's mornings: those held fed (or, the town hungry, trying their luck), those being won
## over a morning nearer, those put to work a day's stone and wood, the town uneasy at it.
func _prison_morning() -> void:
	var day_s := maxf(weather.day_length_minutes * 60.0, 60.0)
	var forced := 0
	for b in buildings:
		if b.def.role != "jail":
			continue
		for o in b.prisoners.duplicate():
			if not is_instance_valid(o):
				b.prisoners.erase(o)
				continue
			if _hungry and randf() < 0.35:
				message.emit("Aç kalan bir esir, %s, hapisten kaçtı!" % o.display_name.split(" ")[0], "bad")
				release(o, false)
				continue
			match o.held_mode:
				"kazan":
					if not _hungry:
						o.won += 1
					if o.won >= 3:
						recruit(o)
				"calistir":
					forced += 1
					add_anywhere("tas" if randf() < 0.5 else "odun", 4, b.global_position)
	if forced > 0:
		for v in villagers:
			v.think("forced", "Köyde zorla çalıştırılan var", -3.0, day_s)


## A prisoner won over: one of the town now (its family its own), out of the jail.
func recruit(o: Villager) -> void:
	if is_instance_valid(o.held_in):
		o.held_in.prisoners.erase(o)
		o.position = o.held_in.door()
	o.held_in = null
	o.held_mode = ""
	o.team = 0
	o.fighter = false
	o.ranged = 0.0
	o.role = ""
	o.attack = 9.0
	o.max_hp = 50.0
	o.apply_traits()
	for k: String in Villager.SKILLS:
		o.prio[k] = int(o.prio.get(k, 1))
	o.wake()
	o.arm_with("")
	if o.died.is_connected(raids._on_raider_down):
		o.died.disconnect(raids._on_raider_down)
	o.died.connect(_on_villager_died)
	villagers.append(o)
	o.think("free", "Hapisten çıktı, yeni bir hayat", 10.0, maxf(weather.day_length_minutes * 60.0, 60.0) * 2.0)
	_house_people()
	message.emit("%s artık kasabadan biri: hapisten çıkıp aramıza katıldı." % o.display_name, "good")


## A prisoner let go (or escaped, `freed` false): out of the jail and off into the woods. Let go,
## the outlaws are a day slower to come again.
func release(o: Villager, freed := true) -> void:
	var at := o.position
	if is_instance_valid(o.held_in):
		o.held_in.prisoners.erase(o)
		at = o.held_in.door()
	o.held_in = null
	o.position = at
	o.wake()
	o.leaving = true
	var away := at + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 140.0
	away.y = nav.height(away.x, away.z)
	o.give([{"t": "go", "to": away}, {"t": "do", "f": func() -> bool:
		o.queue_free()
		return true}], "Ormana gidiyor")
	if freed:
		if raids:
			raids.next_day += 1
		message.emit("%s serbest bırakıldı; haydutlar bunu unutmaz, bir süre gelmezler." % o.display_name.split(" ")[0], "info")


## A prisoner put back in a jail on a loaded game: an outlaw again, as it was.
func spawn_prisoner(d: Dictionary, jail: Building) -> void:
	var o := Villager.new()
	o.team = 1
	o.tunic_color = Color(0.17, 0.12, 0.11)
	o.village = self
	o.nav = nav
	o.look_seed = int(d.get("look", 0))
	o.display_name = str(d.name)
	o.family = str(d.get("family", ""))
	for k: String in d.get("skills", {}):
		o.skills[k] = float(d.skills[k])
	for t: String in d.get("traits", []):
		o.traits.append(t)
	for k: String in d.get("keen", []):
		o.keen.append(k)
	o.max_hp = 70.0
	o.hp = 70.0
	if raids:
		raids.add_child(o)
	else:
		add_child(o)
	o.position = jail.door()
	o.held_in = jail
	o.held_mode = str(d.get("mode", ""))
	o.won = int(d.get("won", 0))
	o.sleep_in(jail, true)
	o.job = "Hapiste"
	jail.prisoners.append(o)


func _rescues() -> void:
	for d in villagers:
		if not d.down or d.dead or is_instance_valid(d.carried_by):
			continue
		var r: Variant = d.get_meta("rescuer") if d.has_meta("rescuer") else null
		if r != null and is_instance_valid(r) and not (r as Villager).dead and not (r as Villager).down and (r as Villager).job == "Yaralıyı taşıyor":
			continue
		var best: Villager = null
		var bd := 140.0
		for v in villagers:
			if v == d or v.dead or v.down or v.drafted or v.sleeping or v.is_child or v.has_cart or v.job == "Yaralıyı taşıyor":
				continue
			if v.armed and raids and raids.active:
				continue # (it holds its post)
			var dist := v.position.distance_to(d.position)
			if dist < bd:
				bd = dist
				best = v
		if best == null:
			continue
		var v := best
		d.set_meta("rescuer", v)
		var shelters: Array[Building] = []
		for b in buildings:
			if b.state == "done" and b.def.role in ["house", "barracks", "store"] and not b.is_burning():
				shelters.append(b)
		var to := _nearest(shelters, d.position)
		if to == null:
			continue
		v.abort()
		v.give([{"t": "go", "to": d.position},
			{"t": "work", "time": 1.6, "anim": "gather", "face": d.position},
			{"t": "do", "f": func() -> bool:
				if not is_instance_valid(d) or d.dead or not d.down:
					return false
				d.carried_by = v
				v.set_carry("yarali", 1)
				return true}] + _go_in(to) + [{"t": "do", "f": func() -> bool:
				v.set_carry("", 0)
				if is_instance_valid(d) and not d.dead and d.down and is_instance_valid(to) and to.state == "done":
					d.sleep_in(to)
					message.emit("%s yaralıyı %s içine taşıdı." % [v.display_name, to.display_name()], "info")
				return true}] + _go_out(to), "Yaralıyı taşıyor", d)


## After a raid: a rifle the outlaws dropped, carried to the armoury.
func _plan_loot(v: Villager) -> bool:
	if raids == null or raids.loot.is_empty():
		return false
	var a := _nearest(armories(), v.position)
	if a == null:
		return false
	for l: Dictionary in raids.loot:
		if l.get("claimed", false):
			continue
		l["claimed"] = true
		var at: Vector3 = l.at
		v.give([{"t": "go", "to": at},
			{"t": "work", "time": 1.2, "anim": "gather", "face": at},
			{"t": "do", "f": func() -> bool:
				if is_instance_valid(l.node):
					(l.node as Node).queue_free()
				v.set_carry("tufek", 1)
				return true},
			{"t": "go", "to": a.door()},
			{"t": "do", "f": func() -> bool:
				v.set_carry("", 0)
				raids.loot.erase(l)
				if is_instance_valid(a):
					a.arms += 1
					a.ammo += int(l.ammo)
					message.emit("Haydudun tüfeği silahlığa kondu (+%d fişek). Rafta %d tüfek." % [int(l.ammo), a.arms], "good")
				return true}], "Düşen tüfeği topluyor", a)
		return true
	return false


## Keeping the watch tonight: a guard or a lookout whose turn it is. The guards of a post (the
## lookouts of a tower) split the night: the first half has the evening till two, the second from
## two till morning. One alone keeps the first half.
func on_watch(v: Villager) -> bool:
	var b := v.workplace
	if b == null or b.state != "done" or not b.def.role in ["barracks", "tower"]:
		return false
	var ws: Array = b.workers.filter(func(w: Variant) -> bool: return is_instance_valid(w) and not (w as Villager).dead)
	var i := ws.find(v)
	if i < 0:
		return false
	var first := weather.hour >= 12.0 or weather.hour < 2.0
	if ws.size() == 1:
		return first
	return (i % 2 == 0) == first
