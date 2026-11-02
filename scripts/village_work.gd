extends "res://scripts/village_defense.gd"
## Work: who's put where, hauling, building sites piece by piece, the workplaces' rounds (felling,
## bucking, the quarry, the fields, the carts, the forester's saplings).

## Firewood to a house running low, or kindling to a lamp, from the store. False if none needs it
## or there's none.
## A lamp burns a log of kindling in LOG_EVERY * 3 s: a night (19:30 to 05:30, 1000 s at the usual
## pace) takes six or seven. It's filled for the whole night from the afternoon on.
const LAMP_NIGHT := 7


## Firewood to a house (or kindling to a lamp, or wood to the square's fire) that's short, from the
## store. `lamps_only`: just the lamps (a worker's errand at dusk, the watch's round at night).
func _plan_firewood(v: Villager, lamps_only := false) -> bool:
	var evening := weather.hour >= 15.0 or weather.is_night()
	if not needs_fire() and not evening:
		return false
	var best: Building = null
	var bd := INF
	for b in buildings:
		if b.state != "done" or (is_instance_valid(b.pile_claim) and b.pile_claim != v):
			continue
		if b.def.role == "house":
			if lamps_only or b.residents.is_empty() or int(b.goods.get("odun", 0)) >= 3:
				continue
		elif b.def.role == "light":
			if int(b.goods.get("odun", 0)) >= (LAMP_NIGHT if evening else 2):
				continue
		elif b.def.role == "square":
			if lamps_only:
				continue
			if int(b.goods.get("odun", 0)) >= 3:
				continue
		else:
			continue
		var d := b.global_position.distance_squared_to(v.position)
		if d < bd:
			bd = d
			best = b
	if best == null:
		return false
	var store := store_with("odun", best.global_position)
	if store == null:
		return false
	if v.idle:
		v.abort()
	var house := best
	house.pile_claim = v
	var want := 8 if house.def.role == "house" else (LAMP_NIGHT - int(house.goods.get("odun", 0)) if house.def.role == "light" else 3)
	var n := store.take_goods("odun", mini(v.capacity("odun"), maxi(want, 1)))
	v.owed = {"res": "odun", "n": n, "store": store}
	var into: Array = _go_in(house, v) if house.def.role == "house" else [{"t": "go", "to": house.door()}]
	var back: Array = _go_out(house, v) if house.def.role == "house" else []
	v.give(_go_in(store, v) + [
		{"t": "do", "f": func() -> bool:
			v.set_carry("odun", n)
			return true}] + _go_out(store, v) + into + [
		{"t": "do", "f": func() -> bool:
			house.pile_claim = null
			v.owed = {}
			v.set_carry("", 0)
			if not is_instance_valid(house) or house.state != "done":
				add_anywhere("odun", n, v.position)
				return true
			house.add_goods("odun", n)
			return true}] + back,
		("Yakacak taşıyor: %s" % house.display_name()) if house.def.role == "house" else "Fenere çıra götürüyor", house)
	return true


# --- Fire --------------------------------------------------------------------------------------------


## Workplaces take free villagers up to what's asked, and give back the ones over it.
func _staff() -> void:
	for b in buildings:
		if not b.def.role in ["work", "barracks", "tower", "carts", "oxen", "farm", "forest", "bowyer", "builders"]:
			continue
		if b.state != "done":
			continue
		while b.workers.size() > b.wanted:
			var v: Villager = b.workers.pop_back()
			_unstaff(v)
			v.abort()
		while b.workers.size() < b.wanted:
			var pick: Villager = null
			var bd := -INF
			var sk := Villager.skill_of(b)
			for v in villagers:
				if v.workplace == null and (v.plan.is_empty() or v.idle) and not v.sleeping and not v.is_child:
					var pr := int(v.prio.get(sk, 1))
					if sk != "" and pr == 0:
						continue
					var score := pr * 100.0 + v.skill(sk) * 8.0 - sqrt(v.position.distance_to(b.global_position))
					if score > bd:
						bd = score
						pick = v
			if pick == null:
				break
			if pick.idle:
				pick.abort()
			employ(pick, b)


## `v` to work at `b`, with what the work takes in hand.
func employ(v: Villager, b: Building) -> void:
	var pick := v
	pick.workplace = b
	b.workers.append(pick)
	match str(b.def.role):
		"barracks":
			pick.fighter = true
			pick.max_hp = 110.0
			pick.hp = 110.0
			pick.attack = 30.0
			pick.ranged = 32.0
			pick.arm_with("rifle")
		"tower":
			pick.arm_with("rifle")
		"carts":
			pick.give_cart(true)
		"oxen":
			pick.give_ox(true)


## `v` put to work at `b` by hand (the player's choice). Why not, if it can't be ("" if done).
func assign(v: Villager, b: Building) -> String:
	if v.is_child:
		return "%s daha çocuk" % v.display_name
	if not b.def.role in ["work", "farm", "forest", "carts", "oxen", "barracks", "tower", "bowyer", "builders"]:
		return "%s bir işyeri değil" % b.display_name()
	if b.state != "done":
		return "%s henüz bitmedi" % b.display_name()
	if v.workplace == b:
		return "%s zaten burada çalışıyor" % v.display_name
	if b.workers.size() >= int(b.def.slots):
		return "%s dolu (%d kişi)" % [b.display_name(), int(b.def.slots)]
	if is_instance_valid(v.workplace):
		v.workplace.workers.erase(v)
		v.workplace.wanted = maxi(0, v.workplace.wanted - 1)
	_unstaff(v)
	v.abort()
	b.wanted = maxi(b.wanted, b.workers.size() + 1)
	employ(v, b)
	return ""


## `v` taken off its work by hand: free to carry and build.
func free_from_work(v: Villager) -> void:
	if not is_instance_valid(v.workplace):
		return
	var b := v.workplace
	b.workers.erase(v)
	b.wanted = maxi(0, b.wanted - 1)
	_unstaff(v)
	v.abort()


func _site_needs_hands() -> bool:
	for b in buildings:
		if not b.under_work():
			continue
		if b.can_work():
			return true
		for r: String in b.cost:
			if b.missing(r) > 0 and int(stock.get(r, 0)) > 0:
				return true
	return false


## Carry what a site still lacks from the store. False if no site needs anything there's some of.
func _plan_haul(v: Villager) -> bool:
	var best: Building = null
	var best_r := ""
	var bd := INF
	var have := stock
	for b in buildings:
		if not b.under_work():
			continue
		for r: String in b.cost:
			if b.missing(r) > 0 and int(have.get(r, 0)) > 0:
				var d := b.global_position.distance_squared_to(v.position)
				if d < bd:
					bd = d
					best = b
					best_r = r
	if best == null:
		return false
	var store := store_with(best_r, best.global_position)
	if store == null:
		return false
	if v.idle:
		v.abort()
	var cap := v.capacity(best_r)
	var n := store.take_goods(best_r, mini(best.missing(best_r), cap))
	best.incoming[best_r] = int(best.incoming[best_r]) + n
	v.owed = {"site": best, "res": best_r, "n": n, "store": store}
	var site := best
	var r := best_r
	v.give(_go_in(store, v) + [
		{"t": "do", "f": func() -> bool:
			v.set_carry(r, n)
			return site.under_work()}] + _go_out(store, v) + [
		{"t": "go", "to": site.stack_at() if site.state == "site" else _spot_by(site, v.position)},
		{"t": "do", "f": func() -> bool:
			if not site.under_work():
				return false
			site.incoming[r] = int(site.incoming[r]) - n
			if site.state == "site":
				site.deliver(r, n) # (onto the stack at its corner)
				if r == "odun":
					Ambience.log_drop(v.position)
			else:
				site.delivered[r] = int(site.delivered[r]) + n
			v.owed = {}
			v.set_carry("", 0)
			return true},
	], "Taşıyor: %s" % site.display_name(), site)
	return true


## Build at a site whose stuff has come. False if there's none.
## A palisade's next stretch: the wood for it from the store (an odun for every Wall.WOOD_PER
## stakes), carried out, the stakes stood up and rammed in.
func _plan_wall(v: Villager) -> bool:
	# A gate beaten in, once they've gone: mended first (six odun of new planks).
	if raids == null or not raids.active:
		for w in walls:
			if not is_instance_valid(w):
				continue
			for g in w.gates:
				if is_instance_valid(g) and g.broken and not g.has_meta("mender"):
					var store := store_with("odun", g.global_position)
					if store == null or int(store.goods.get("odun", 0)) < 6:
						break
					if v.idle:
						v.abort()
					g.set_meta("mender", v)
					var gate := g
					v.give(_go_in(store, v) + [{"t": "do", "f": func() -> bool:
							if not is_instance_valid(store) or store.take_goods("odun", 6) < 6:
								gate.remove_meta("mender")
								return false
							v.set_carry("odun", 6)
							return true}] + _go_out(store, v) + [
						{"t": "go", "to": gate.global_position + gate.global_basis.z * 1.5},
						{"t": "work", "time": 8.0, "anim": "build", "face": gate.global_position},
						{"t": "do", "f": func() -> bool:
							v.set_carry("", 0)
							if is_instance_valid(gate):
								gate.mend()
								gate.remove_meta("mender")
							return true}], "Sur: kapıyı onarıyor", null)
					return true
	var best: Wall = null
	var bs := -1
	var bd := INF
	for w in walls:
		if not is_instance_valid(w):
			continue
		var s := w.next_stretch(v.position)
		if s < 0:
			continue
		var d := w.stretch_at(s).distance_squared_to(v.position)
		if d < bd:
			bd = d
			best = w
			bs = s
	if best == null:
		return false
	var w := best
	var s := bs
	var need := ceili(float(w.left_in(s)) / Wall.WOOD_PER)
	var store := store_with("odun", w.stretch_at(s))
	if store == null or int(store.goods.get("odun", 0)) < need:
		return false
	if v.idle:
		v.abort()
	w.claims[s] = v
	var at := w.stretch_at(s)
	# (stood on the town's side of it)
	var n := w.nearest(at)
	var side := (n.dir as Vector3).cross(Vector3.UP)
	if store and side.dot(store.global_position - at) < 0.0:
		side = -side
	var stand := at + side * 1.3
	stand.y = ground_at(stand)
	v.give(_go_in(store, v) + [{"t": "do", "f": func() -> bool:
			if not is_instance_valid(store) or store.take_goods("odun", need) < need:
				return false
			v.set_carry("odun", need)
			return true}] + _go_out(store, v) + [
		{"t": "go", "to": stand},
		{"t": "do", "f": func() -> bool:
			v.set_carry("", 0)
			return true},
		{"t": "work", "time": 6.0, "anim": "build", "face": at},
		{"t": "do", "f": func() -> bool:
			if is_instance_valid(w):
				w.raise(s)
			return true}], "Sur: kazık çakıyor", null)
	return true


func _plan_build(v: Villager) -> bool:
	var best: Building = null
	var bd := INF
	for b in buildings:
		if not b.can_work():
			continue
		var n := 0
		for o in villagers:
			if o.target == b and o.job.begins_with("İnşa"):
				n += 1
		# (a site's full at six; the builders' own crew can always join, up to four more)
		var builder: bool = v.workplace != null and v.workplace.def.role == "builders"
		if n >= BUILDERS_PER_SITE + (4 if builder else 0):
			continue
		var d := b.global_position.distance_squared_to(v.position)
		if d < bd:
			bd = d
			best = b
	if best == null:
		return false
	if v.idle:
		v.abort()
	var site := best
	if site.state == "repair" and site.upgrading == "oda":
		# (the back room: from beside it, round the back of the house)
		var c := site.global_transform * Vector3(site.annex.get_center().x, 0, site.annex.get_center().y)
		var out := site.global_transform.basis * Vector3(randf_range(-2.4, 2.4), 0, -site.annex.size.y * 0.5 - 1.3)
		var at := c + out
		at.y = nav.height(at.x, at.z)
		v.give([
			{"t": "go", "to": at},
			{"t": "work", "anim": "build", "face": c, "tick": func(dt: float) -> bool: return site.add_work(dt)},
		], "Büyütüyor: %s" % site.display_name(), site)
		return true
	if site.state == "repair" and site.upgrading != "":
		v.give([
			{"t": "go", "to": _spot_by(site, v.position)},
			{"t": "work", "anim": "build", "face": site.global_position, "tick": func(dt: float) -> bool: return site.add_work(dt)},
		], "%s: %s" % ["Sıvıyor" if site.upgrading == "siva" else "Soba yapıyor", site.display_name()], site)
		return true
	if site.state == "repair":
		v.give([
			{"t": "go", "to": _spot_by(site, v.position)},
			{"t": "work", "anim": "build", "face": site.global_position, "tick": func(dt: float) -> bool: return site.add_work(dt)},
		], "Onarıyor: %s" % site.display_name(), site)
		return true
	# A piece off the stack, carried to its place (up the scaffold if it's high), set there.
	var i := site.claim(v)
	if i < 0:
		return false
	var piece = site.pieces[i]
	var spot := site.work_spot(i)
	var at: Vector3 = spot.at
	var level: float = spot.level
	# An armful: up to four more pieces going up beside it, at the same height, in the same trip.
	var batch: Array[int] = [i]
	while batch.size() < 5:
		var j := site.claim(v)
		if j < 0:
			break
		var sj := site.work_spot(j)
		if (sj.at as Vector3).distance_to(at) > 2.5 or float(sj.level) != level:
			site.unclaim_one(j)
			break
		batch.append(j)
	var looks := "tas" if piece.res == "tas" else "odun"
	var steps: Array = [
		{"t": "go", "to": site.stack_at()},
		{"t": "work", "time": 0.9, "anim": "gather", "face": site.global_transform * (site._stack_spot())},
		{"t": "do", "f": func() -> bool:
			v.set_carry(looks, 1)
			return site.state == "site"},
		{"t": "go", "to": at},
	]
	if level > 0.0:
		steps.append({"t": "do", "f": func() -> bool:
			v.climb(site.global_position.y + level)
			return true})
		steps.append({"t": "work", "time": 0.9, "anim": "climb"})
	for k in batch.size():
		var j: int = batch[k]
		steps.append({"t": "work", "time": randf_range(0.5, 0.85), "anim": "build", "face": site.work_spot(j).face})
		steps.append({"t": "do", "f": func() -> bool:
			if k == batch.size() - 1:
				v.set_carry("", 0)
			if is_instance_valid(site):
				site.place(j, v.global_position)
			return true})
	if level > 0.0:
		steps.append({"t": "do", "f": func() -> bool:
			v.climb(ground_at(v.position))
			return true})
		steps.append({"t": "work", "time": 0.8, "anim": "climb"})
	v.give(steps, "İnşa: %s (%s)" % [site.display_name(), site.stage_name().to_lower()], site)
	return true


## A worker's next round: out to what its workplace works, and back to the store with it.
func _plan_work(v: Villager) -> void:
	var b := v.workplace
	if b.def.role == "tower":
		v.give([{"t": "go", "to": b.door()}, {"t": "do", "f": func() -> bool:
			v.perch_on(b)
			return true},
			{"t": "work", "anim": "aim", "tick": func(_dt: float) -> bool:
				return v.workplace == b and b.state == "done" and (not weather.is_night() or on_watch(v) or (raids and raids.threat()))},
			{"t": "do", "f": func() -> bool:
				v.get_down()
				return true}], "Gözcü kulesinde", b)
		return
	if b.def.role == "barracks":
		if weather.is_night():
			# A lamp running low on the round: kindling to it first (the watch keeps the lamps lit).
			if _plan_firewood(v, true):
				return
			# The round: from one lit house, lamp or store to another, a stop at each to look about.
			var stops: Array[Building] = []
			for o in buildings:
				if o.state == "done" and o.def.role in ["house", "store", "light", "square", "work", "farm"] and o.global_position.distance_to(b.global_position) < 180.0:
					stops.append(o)
			if not stops.is_empty():
				var o: Building = stops[randi() % stops.size()]
				var p := o.door() + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
				v.give([{"t": "go", "to": p}, {"t": "work", "time": randf_range(5.0, 9.0), "anim": "look"}], "Nöbette (devriye)", b, true)
				return
		var p := b.door() + Vector3(randf_range(-7, 7), 0, randf_range(1, 8))
		v.give([{"t": "go", "to": p}, {"t": "work", "time": randf_range(5.0, 12.0), "anim": "idle"}], "Nöbette", b, true)
		return
	if b.def.role in ["carts", "oxen"]:
		_plan_cart(v)
		return
	if b.def.role == "bowyer":
		_plan_bowyer(v, b)
		return
	if b.def.role == "builders":
		# The builders: the sites first (building, mending), then their materials; with none, planks
		# sawn at the bench.
		if _plan_build(v) or _plan_wall(v) or _plan_haul(v):
			b.idle_note = ""
			return
		b.idle_note = "Şantiye yok: tezgâhta bekliyor"
		v.give([{"t": "go", "to": b.station()}, {"t": "work", "time": randf_range(6.0, 10.0), "anim": "saw", "face": b.station_face()}], "İnşaatçı: tahta biçiyor", b, true)
		return
	if b.def.role == "farm":
		_plan_farm(v, b)
		return
	if b.def.role == "forest":
		_plan_forest(v, b)
		return
	var res := str(b.def.res)
	var store := _nearest(stores(), b.global_position)
	if store == null:
		b.idle_note = "Depo yok"
		_plan_idle(v)
		return
	# The pile's grown and nobody fetches it: a load of it to the store first.
	if not carters_about() and b.goods_total() >= 9:
		res = b.biggest_good()
		var n := b.take_goods(res, v.capacity(res))
		if n > 0:
			v.give([{"t": "go", "to": b.door()}, {"t": "step", "to": b.station()},
				{"t": "work", "time": 1.2, "anim": "gather", "face": b.global_transform * b.def.get("pile", Vector3.ZERO)},
				{"t": "do", "f": func() -> bool:
					v.set_carry(res, n)
					return true},
				{"t": "step", "to": b.door()}] + _go_in(store, v) + [
				{"t": "do", "f": func() -> bool:
					if is_instance_valid(store) and store.state == "done":
						store.add_goods(res, v.carry_n)
					else:
						add_anywhere(res, v.carry_n, v.position)
					v.set_carry("", 0)
					return true}] + _go_out(store, v), "%s: depoya taşıyor" % b.display_name(), b)
			return
	if b.kind == "camur":
		_plan_mud(v, b)
		return
	# Logs lying from a tree already down: one fetched and sawn.
	if res == "odun":
		var bl := _billet_for(b)
		if not bl.is_empty():
			bl.claimed = v
			var at: Vector3 = (bl.node as Node3D).global_position
			v.give([{"t": "go", "to": at + (b.global_position - at).normalized() * 0.9},
				{"t": "work", "time": 1.4, "anim": "gather", "face": at},
				{"t": "do", "f": func() -> bool:
					if is_instance_valid(bl.node):
						(bl.node as Node).queue_free()
					billets.erase(bl)
					v.set_carry("odun", BILLET_WOOD)
					Ambience.log_drop(v.position)
					return true}] + _work_at(b, v, res), "%s: tomruk taşıyor" % b.display_name(), b)
			return
	var kind: String = {"odun": "tree", "tas": "rock", "yiyecek": "bush"}[res]
	# (trees marked to be felled first: a little further than the camp would go for its own)
	var i := marked_tree(b.global_position, float(b.def.reach) * 1.6, b.work_area) if res == "odun" else -1
	if i < 0:
		i = find_prop(b.global_position, float(b.def.reach), kind, b.work_area)
	if i < 0:
		b.idle_note = {"odun": "Yakında ağaç kalmadı", "tas": "Yakında kaya kalmadı", "yiyecek": "Kışın çalılar yemiş vermez" if seasons and seasons.winter() else "Yakında yemiş kalmadı"}[res]
		_plan_idle(v)
		return
	b.idle_note = ""
	reserved[i] = v
	var info := props.prop_info(i)
	var o: Vector3 = info.origin
	var away := Vector3(v.position.x - o.x, 0, v.position.z - o.z)
	if away.length() < 0.1:
		away = Vector3.BACK
	var spot := o + away.normalized() * (float(info.radius) + 0.75)
	spot.y = nav.height(spot.x, spot.z)
	var steps: Array = [{"t": "go", "to": spot}]
	match res:
		"odun":
			# Felled, limbed where it lies, bucked into logs; the first log shouldered.
			var info2 := props.tree_info(i)
			var fall := Vector3(o.x - spot.x, 0, o.z - spot.z).normalized()
			var trunk_mid: Vector3 = o + fall * float(info2.height) * 0.45
			var side := fall.cross(Vector3.UP).normalized()
			var limb_at := trunk_mid + side * (float(info2.radius) + 0.8)
			limb_at.y = nav.height(limb_at.x, limb_at.z)
			steps.append({"t": "work", "time": 7.0, "anim": "chop", "face": o})
			steps.append({"t": "do", "f": func() -> bool:
				reserved.erase(i)
				if props.cut.has(i):
					return false
				fell_tree(i, fall)
				return true})
			steps.append({"t": "work", "time": 3.0, "anim": "idle", "face": trunk_mid}) # (watching it come down)
			steps.append({"t": "go", "to": limb_at})
			steps.append({"t": "work", "time": 4.0, "anim": "limb", "face": trunk_mid})
			steps.append({"t": "work", "time": 3.0, "anim": "saw", "face": trunk_mid})
			steps.append({"t": "do", "f": func() -> bool:
				_buck(i, o, fall, float(info2.height), float(info2.radius), b)
				var bl := _billet_for(b, v.position)
				if not bl.is_empty():
					if is_instance_valid(bl.node):
						(bl.node as Node).queue_free()
					billets.erase(bl)
				v.set_carry("odun", BILLET_WOOD)
				return true})
		"tas":
			steps.append({"t": "work", "time": 8.0, "anim": "mine", "face": o})
			steps.append({"t": "do", "f": func() -> bool:
				reserved.erase(i)
				if props.cut.has(i):
					return false
				var left := int(rock_left.get(i, 15)) - 3
				rock_left[i] = left
				if left <= 0:
					props.cut_tree(i)
				v.set_carry("tas", 3)
				return true})
		"yiyecek":
			steps.append({"t": "work", "time": 5.0, "anim": "gather", "face": o})
			steps.append({"t": "do", "f": func() -> bool:
				reserved.erase(i)
				bush_rest[i] = clock + 240.0
				v.set_carry("yiyecek", 3)
				return true})
	# What's gathered is brought to the yard and worked there: sawn, dressed, sorted; it's piled there.
	steps.append_array(_work_at(b, v, res))
	v.give(steps, "%s: %s" % [b.display_name(), {"odun": "ağaç kesiyor", "tas": "taş kırıyor", "yiyecek": "yemiş topluyor"}[res]], b)


## A basket of mud dug from the wettest ground in reach and brought back to the pit: piled there,
## or (making bricks) pressed into moulds at the table and laid out on the racks to dry.
func _plan_mud(v: Villager, b: Building) -> void:
	var at := _mud_spot(b)
	if at == Vector3.INF:
		b.idle_note = "Yakında çamur kalmadı"
		_plan_idle(v)
		return
	b.idle_note = ""
	var away := Vector3(v.position.x - at.x, 0, v.position.z - at.z)
	var spot := at + (away.normalized() if away.length() > 0.1 else Vector3.BACK) * 0.8
	spot.y = nav.height(spot.x, spot.z)
	var bricks := b.mode == "kerpic"
	var name := b.display_name()
	var steps: Array = [{"t": "go", "to": spot, "job": "%s: çamura gidiyor" % name}, {"t": "work", "time": 6.0, "anim": "dig", "face": at, "job": "%s: çamur kazıyor" % name},
		{"t": "do", "f": func() -> bool:
			terrain.churn(at, 0.5)
			v.set_carry("camur", 4)
			return true}]
	if bricks:
		# Into the pit and trodden with straw, pressed into the mould at the table and struck off level,
		# then the fresh bricks carried to the drying shelter and laid out on its straw.
		var at_pit := _yard_spot(b, Vector3(1.75, 0, -0.3))
		var pit := b.global_transform * Vector3(1.75, 0, -1.35)
		var at_rack := _yard_spot(b, Vector3(-1.2, 0, -0.25))
		var rack := b.global_transform * Vector3(-1.2, 0, -1.45)
		steps.append_array([{"t": "go", "to": at_pit, "job": "%s: çamuru getiriyor" % name},
			{"t": "work", "time": 4.0, "anim": "hoe", "face": pit, "job": "%s: çamuru samanla karıştırıyor" % name},
			{"t": "step", "to": b.station()},
			{"t": "work", "time": 3.0, "anim": "gather", "face": b.station_face(), "job": "%s: kalıba basıyor" % name},
			{"t": "work", "time": 2.0, "anim": "chisel", "face": b.station_face(), "job": "%s: kalıbı düzlüyor" % name},
			{"t": "do", "f": func() -> bool:
				v.set_carry("kerpic", v.carry_n) # (the mud, bricks now)
				return true},
			{"t": "go", "to": at_rack, "job": "%s: kerpiçleri rafa taşıyor" % name},
			{"t": "work", "time": 2.5, "anim": "gather", "face": rack, "job": "%s: kerpiçleri kurumaya diziyor" % name},
			{"t": "do", "f": func() -> bool:
				if is_instance_valid(b) and b.state == "done" and v.carry_n > 0:
					b.lay_to_dry(v.carry_n)
				v.set_carry("", 0)
				return true}])
	else:
		steps.append_array(_work_at(b, v, "camur"))
	v.give(steps, "%s: %s" % [name, "kerpiç yapıyor" if bricks else "çamur kazıyor"], b)


## A point of `b`'s yard (in its space) on the ground.
func _yard_spot(b: Building, local: Vector3) -> Vector3:
	var p := b.global_transform * local
	p.y = nav.height(p.x, p.z)
	return p


## The muddiest open ground a few tries find in `b`'s reach (INF: none muddy enough).
func _mud_spot(b: Building) -> Vector3:
	var best := Vector3.INF
	var top := 0.3
	for k in 28:
		var a := randf() * TAU
		var p := b.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(6.0, float(b.def.reach))
		var m := muddiness(p)
		if m > top and nav.is_open(p) and not terrain.is_water(p.x, p.z):
			top = m
			best = p
	if best != Vector3.INF:
		best.y = nav.height(best.x, best.z)
	return best


## A free hand to a tree marked to be felled (KES) that no camp's on: felled, limbed and bucked where
## it lies, and the first log carried to the nearest store (the rest lie for others to fetch).
func _plan_cut(v: Villager, urgent := false) -> bool:
	if cut_marks.is_empty():
		return false
	var i := marked_tree(v.position, 500.0 if urgent else 260.0, Rect2(), urgent)
	var store := _nearest(stores(), v.position)
	if i < 0 or store == null:
		return false
	reserved[i] = v
	var info := props.tree_info(i)
	var o: Vector3 = info.origin
	var away := Vector3(v.position.x - o.x, 0, v.position.z - o.z)
	if away.length() < 0.1:
		away = Vector3.BACK
	var spot := o + away.normalized() * (float(info.radius) + 0.75)
	spot.y = nav.height(spot.x, spot.z)
	var fall := Vector3(o.x - spot.x, 0, o.z - spot.z).normalized()
	var trunk_mid: Vector3 = o + fall * float(info.height) * 0.45
	var limb_at := trunk_mid + fall.cross(Vector3.UP).normalized() * (float(info.radius) + 0.8)
	limb_at.y = nav.height(limb_at.x, limb_at.z)
	var steps: Array = [{"t": "go", "to": spot, "job": "Acil kesime koşuyor" if urgent else "İşaretli ağaca gidiyor"},
		{"t": "work", "time": 8.0, "anim": "chop", "face": o, "job": "İşaretli ağacı kesiyor"},
		{"t": "do", "f": func() -> bool:
			reserved.erase(i)
			if props.cut.has(i):
				return false
			fell_tree(i, fall)
			return true},
		{"t": "work", "time": 3.0, "anim": "idle", "face": trunk_mid},
		{"t": "go", "to": limb_at, "job": "Dallarını budayıp tomruklara bölüyor"},
		{"t": "work", "time": 4.0, "anim": "limb", "face": trunk_mid},
		{"t": "work", "time": 4.0, "anim": "saw", "face": trunk_mid},
		{"t": "do", "f": func() -> bool:
			_buck(i, o, fall, float(info.height), float(info.radius), null)
			var bl := _billet_for(null, v.position)
			if not bl.is_empty():
				if is_instance_valid(bl.node):
					(bl.node as Node).queue_free()
				billets.erase(bl)
			v.set_carry("odun", BILLET_WOOD)
			return true}]
	steps.append({"t": "go", "to": store.door(), "job": "Tomruğu depoya taşıyor"})
	steps.append_array(_go_in(store, v) + [{"t": "do", "f": func() -> bool:
			if is_instance_valid(store) and store.state == "done":
				store.add_goods("odun", v.carry_n)
			else:
				add_anywhere("odun", v.carry_n, v.position)
			v.set_carry("", 0)
			return true}] + _go_out(store, v))
	v.give(steps, "İşaretli ağacı kesiyor")
	return true


## A free hand to a log lying from a marked tree (no camp's), carried to the nearest store.
func _plan_logs(v: Villager) -> bool:
	var bl := {}
	var bd := INF
	for x in billets:
		if x.camp != null or is_instance_valid(x.claimed) or not is_instance_valid(x.node):
			continue
		var d := (x.node as Node3D).global_position.distance_to(v.position)
		if d < bd and d < 200.0:
			bd = d
			bl = x
	if bl.is_empty():
		return false
	var store := _nearest(stores(), v.position)
	if store == null:
		return false
	bl.claimed = v
	var at: Vector3 = (bl.node as Node3D).global_position
	var steps: Array = [{"t": "go", "to": at + (v.position - at).normalized() * 0.9},
		{"t": "work", "time": 1.4, "anim": "gather", "face": at},
		{"t": "do", "f": func() -> bool:
			if is_instance_valid(bl.node):
				(bl.node as Node).queue_free()
			billets.erase(bl)
			v.set_carry("odun", BILLET_WOOD)
			Ambience.log_drop(v.position)
			return true},
		{"t": "go", "to": store.door()}]
	steps.append_array(_go_in(store, v) + [{"t": "do", "f": func() -> bool:
			if is_instance_valid(store) and store.state == "done":
				store.add_goods("odun", v.carry_n)
			else:
				add_anywhere("odun", v.carry_n, v.position)
			v.set_carry("", 0)
			return true}] + _go_out(store, v))
	v.give(steps, "Tomruk taşıyor")
	return true


## Back to the yard with what's carried, worked at its station (sawn on the trestles, dressed on
## the bench, sorted on the table), piled there, and out the front.
func _work_at(b: Building, v: Villager, res: String) -> Array:
	var how := str(b.def.get("work", "gather"))
	return [{"t": "go", "to": b.door()}, {"t": "step", "to": b.station()},
		{"t": "work", "time": {"saw": 5.0, "chisel": 5.0}.get(how, 2.5), "anim": how, "face": b.station_face()},
		{"t": "do", "f": func() -> bool:
			if v.carry_n > 0:
				if res == "odun":
					Ambience.log_drop(v.position)
				if is_instance_valid(b) and b.state == "done":
					b.add_goods(res, v.carry_n)
				else:
					add_anywhere(res, v.carry_n, v.position)
			v.set_carry("", 0)
			return true},
		{"t": "step", "to": b.door()}]


## The nearest log lying for camp `b` (or for no camp left standing) not already being fetched.
func _billet_for(b: Building, near := Vector3.INF) -> Dictionary:
	var at := b.global_position if near == Vector3.INF else near
	var best := {}
	var bd := INF
	for bl in billets:
		if is_instance_valid(bl.claimed) or not is_instance_valid(bl.node):
			continue
		if bl.camp != b and is_instance_valid(bl.camp) and (bl.camp as Building).state != "gone":
			continue
		var d := (bl.node as Node3D).global_position.distance_to(at)
		if d < bd:
			bd = d
			best = bl
	return best


## The fallen tree bucked where it lies: its crown and branches lopped off (left as slash that
## rots away), its trunk sawn into logs along where it fell, for its camp to fetch.
func _buck(i: int, base: Vector3, fall: Vector3, height: float, radius: float, camp: Building) -> void:
	for n: Node in get_children():
		if n.has_meta("felled") and int(n.get_meta("felled")) == i:
			n.queue_free()
	var count := clampi(int(height / 4.0), 2, 5)
	for k in count:
		var c := base + fall * (1.4 + k * 2.1)
		c.y = nav.height(c.x, c.z) + radius * 0.95
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius * 0.95
		cm.bottom_radius = radius
		cm.height = 1.9
		cm.radial_segments = 10
		mi.mesh = cm
		mi.material_override = Building.material("log")
		add_child(mi)
		mi.global_transform = Transform3D(Basis.looking_at(fall, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), c)
		billets.append({"node": mi, "camp": camp, "claimed": null})
	# the slash: a few branches where the crown came down, rotting away after a while
	var slash := StandardMaterial3D.new()
	slash.albedo_color = Color(0.2, 0.27, 0.13)
	for k in 6:
		var at := base + fall * (height * randf_range(0.6, 0.95)) + fall.cross(Vector3.UP) * randf_range(-1.5, 1.5)
		at.y = nav.height(at.x, at.z) + 0.15
		var br := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.02
		bm.bottom_radius = 0.05
		bm.height = randf_range(1.0, 2.0)
		bm.radial_segments = 5
		br.mesh = bm
		br.material_override = slash
		add_child(br)
		br.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5 + randf_range(-0.2, 0.2)), at)
		var tw := br.create_tween()
		tw.tween_interval(randf_range(60.0, 90.0))
		tw.tween_property(br, "position:y", at.y - 0.4, 8.0)
		tw.tween_callback(br.queue_free)


## A farmer's next stint: sow the field, hoe it while it grows, reap it when it's ripe and carry
## the sheaves home (or pile them by the field, with carters about).
func _plan_farm(v: Villager, b: Building) -> void:
	var c := b.crop
	if c == null or c.burning > 0.0:
		_plan_idle(v)
		return
	match c.stage:
		"wild":
			# The field opened first: the grass mown with the scythe and the ground turned, strip by strip.
			b.idle_note = "Tarla açılıyor: %%%d" % int(c.cleared * 100.0)
			v.give([{"t": "go", "to": c.spot()}, {"t": "work", "time": 5.0, "anim": "mow", "done": func() -> void:
				if is_instance_valid(c):
					c.clear(0.08)}], "Tarla: çimen biçiyor", b)
		"fallow", "sowing":
			b.idle_note = ""
			v.give([{"t": "go", "to": c.spot()}, {"t": "work", "time": 4.0, "anim": "sow", "done": func() -> void:
				if is_instance_valid(c):
					c.sow(0.1)}], "Tarla: ekiyor", b)
		"growing":
			b.idle_note = "Ekin büyüyor: %%%d" % int(c.growth * 100.0)
			v.give([{"t": "go", "to": c.spot()}, {"t": "work", "time": 6.0, "anim": "hoe", "done": func() -> void:
				if is_instance_valid(c):
					c.tend()}], "Tarla: çapalıyor", b, true)
		"ripe":
			b.idle_note = "Hasat: %d yiyecek kaldı" % c.left()
			var store := _nearest(stores(), b.global_position)
			var pile := store == null or (carters_about() and b.global_position.distance_to(store.global_position) > PILE_FROM)
			var drop_at: Building = b if pile else store
			v.give([
				{"t": "go", "to": c.spot()},
				{"t": "work", "time": 4.0, "anim": "reap"},
				{"t": "do", "f": func() -> bool:
					if not is_instance_valid(c):
						return false
					var n := c.reap(6)
					if n <= 0:
						return false
					v.set_carry("yiyecek", n)
					return true},
			] + (_go_in(drop_at, v) if drop_at != b else [{"t": "go", "to": drop_at.door() + Vector3(randf_range(-2, 2), 0, randf_range(0, 2))}]) + [
				{"t": "do", "f": func() -> bool:
					if v.carry_n > 0:
						if is_instance_valid(drop_at) and drop_at.state == "done":
							drop_at.add_goods(v.carry_res, v.carry_n)
						else:
							add_anywhere(v.carry_res, v.carry_n, v.position)
					v.set_carry("", 0)
					return true},
			] + (_go_out(drop_at, v) if drop_at != b else []), "Tarla: biçiyor", b)


## A carter's next run: a cartload to a building site, else the biggest pile to the store.
func _plan_cart(v: Villager) -> void:
	if _plan_haul(v) or _plan_firewood(v):
		return
	var best: Building = null
	var most := 3
	for b in buildings:
		if not b.def.role in ["work", "farm"] or b.state == "gone":
			continue
		if is_instance_valid(b.pile_claim) and b.pile_claim != v:
			continue
		var n := b.goods_total()
		if n > most:
			most = n
			best = b
	if best == null:
		_plan_idle(v)
		v.job = "Arabacı: bekliyor" if v.vehicle == "hand" else "Öküz arabası: bekliyor"
		return
	var store := _nearest(stores(), best.global_position)
	if store == null:
		_plan_idle(v)
		return
	best.pile_claim = v
	var from := best
	v.give([
		{"t": "go", "to": from.door() + Vector3(1.5, 0, 0.5)},
		{"t": "work", "time": 2.0, "anim": "gather", "face": from.global_position},
		{"t": "do", "f": func() -> bool:
			from.pile_claim = null
			var res := ""
			var top := 0
			for k: String in from.goods:
				if int(from.goods[k]) > top:
					top = int(from.goods[k])
					res = k
			if res == "":
				return false
			v.set_carry(res, from.take_goods(res, v.capacity(res)))
			return true},
		{"t": "go", "to": store.door() + Vector3(randf_range(-2, 2), 0, randf_range(0.5, 2))},
		{"t": "do", "f": func() -> bool:
			if v.carry_n > 0:
				if is_instance_valid(store) and store.state == "done":
					store.add_goods(v.carry_res, v.carry_n)
				else:
					add_anywhere(v.carry_res, v.carry_n, v.position)
			v.set_carry("", 0)
			return true},
	], "%s: %s yığınını taşıyor" % ["Arabacı" if v.vehicle == "hand" else "Öküz arabası", from.display_name()], from)


## The nearest standing prop of `kind` ("tree", "rock", "bush") within `reach` of `p` that no one's
## going for (a bush not resting), on ground a villager can get to.
func find_prop(p: Vector3, reach: float, kind: String, area := Rect2()) -> int:
	var best := -1
	var bd := INF
	var near := _props_in(p, reach)
	if area.has_area(): # (a drawn work area: what's in it, however far)
		var c := area.get_center()
		near = _props_in(Vector3(c.x, 0, c.y), area.size.length() * 0.5 + 1.0)
	for i in near:
		if reserved.has(i):
			continue
		if area.has_area() and not area.has_point(Vector2(props._xf[i].origin.x, props._xf[i].origin.z)):
			continue
		if str(props._models[props._kind[i]].kind) != kind:
			continue
		if kind == "bush" and (float(bush_rest.get(i, -1.0)) > clock or (seasons and seasons.winter())):
			continue
		var o: Vector3 = props._xf[i].origin
		if not nav.is_open(o + Vector3(1.2, 0, 0)) and not nav.is_open(o - Vector3(1.2, 0, 0)):
			continue
		if absf(terrain.height_at(o.x, o.z) - o.y) > 3.0:
			continue
		var d := Vector2(o.x - p.x, o.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


## The tree comes down away from the axe, hinged at its foot, and lies a while; a stump stays.
func fell_tree(i: int, away: Vector3) -> void:
	if cut_marks.has(i):
		cut_marks.erase(i)
		_show_marks()
	var info := props.tree_info(i)
	var mesh := props.felled_mesh(i)
	props.cut_tree(i)
	var o: Vector3 = info.origin
	Ambience.play("tree_crack", o + Vector3.UP * 2.0, 2.0)
	var land := o + Vector3(away.x, 0, away.z).normalized() * float(info.height) * 0.5
	get_tree().create_timer(2.5).timeout.connect(func() -> void: Ambience.play("tree_fall", land, 4.0))
	var pivot := Node3D.new()
	pivot.set_meta("felled", i)
	add_child(pivot)
	pivot.global_position = o + Vector3.UP * 0.4
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(info.basis, Vector3.DOWN * 0.4)
	pivot.add_child(mi)
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.RIGHT
	var axis := Vector3.UP.cross(away.normalized()).normalized()
	var tw := pivot.create_tween()
	tw.tween_property(pivot, "quaternion", Quaternion(axis, PI * 0.47), 2.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(pivot, "quaternion", Quaternion(axis, PI * 0.5), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(25.0)
	tw.tween_property(pivot, "position:y", pivot.position.y - 2.0, 5.0)
	tw.tween_callback(pivot.queue_free)
	add_stump(o + Vector3.UP * 0.2, float(info.radius) * 1.15, i)


func add_stump(at: Vector3, r: float, prop := -1) -> void:
	var stump := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * 1.2
	c.height = 0.7
	c.radial_segments = 9
	stump.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.22, 0.15)
	m.roughness = 0.95
	stump.material_override = m
	stump.position = at
	stump.set_meta("prop", prop)
	stump.set_meta("born", clock)
	_stumps.add_child(stump)


const STUMP_LIFE := 420.0 ## s (about half a day) a stump stands before it's rotted away

## A sapling on the stump of tree `i`; in SAPLING_TIME (or `left`) it's the tree again.
func plant(i: int, left := SAPLING_TIME) -> void:
	if saplings.has(i) or not props.cut.has(i):
		return
	# The very tree that stood there, small: the same kind, turned the same way, grown up into it.
	var info := props.tree_info(i)
	var n := Node3D.new()
	add_child(n)
	n.position = info.origin
	var young := MeshInstance3D.new()
	young.mesh = props.felled_mesh(i)
	young.basis = info.basis
	n.add_child(young)
	saplings[i] = {"node": n, "left": left}
	_grow_one(i, 0.0)


func _grow_one(i: int, dt: float) -> void:
	var s: Dictionary = saplings[i]
	s.left = float(s.left) - dt
	var k := 1.0 - clampf(float(s.left) / SAPLING_TIME, 0.0, 1.0)
	(s.node as Node3D).scale = Vector3.ONE * lerpf(0.06, 1.0, k * k * (3.0 - 2.0 * k)) # (slow at first, then shooting up)
	if float(s.left) <= 0.0:
		(s.node as Node3D).queue_free()
		saplings.erase(i)
		props.regrow(i)
		for st: Node in _stumps.get_children():
			if int(st.get_meta("prop", -1)) == i:
				st.queue_free()


var _rot_t := 0.0


func _grow_saplings(dt: float) -> void:
	for i: int in saplings.keys():
		_grow_one(i, dt)
	# Stumps rot down and are gone a while after the tree came down (one with a sapling on it stays
	# till the tree's up; a gone one is still there, unseen, for a forester to plant on).
	_rot_t += dt
	if _rot_t < 4.0:
		return
	_rot_t = 0.0
	for st: Node in _stumps.get_children():
		var s := st as Node3D
		if not s.visible or s.has_meta("rotting"):
			continue
		var i := int(s.get_meta("prop", -1))
		if saplings.has(i) or clock - float(s.get_meta("born", clock)) < STUMP_LIFE:
			continue
		s.set_meta("rotting", true)
		var tw := create_tween()
		tw.tween_property(s, "scale", Vector3(1.15, 0.02, 1.15), 6.0).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			s.visible = false
			s.scale = Vector3.ONE
			s.remove_meta("rotting"))


## A forester's next stint: a sapling on the nearest stump in reach without one.
func _plan_forest(v: Villager, b: Building) -> void:
	var best := -1
	var bd := float(b.def.reach)
	var at := Vector3.ZERO
	for st: Node3D in _stumps.get_children():
		var i := int(st.get_meta("prop", -1))
		if i < 0 or saplings.has(i) or reserved.has(i) or not props.cut.has(i):
			continue
		var d := st.position.distance_to(b.global_position)
		if d < bd:
			bd = d
			best = i
			at = st.position
	if best < 0:
		b.idle_note = "Yakında dikilecek kütük yok"
		_plan_idle(v)
		return
	b.idle_note = ""
	reserved[best] = v
	var i := best
	var spot := at + (v.position - at).normalized() * 1.0
	v.give([
		{"t": "go", "to": spot},
		{"t": "work", "time": 5.0, "anim": "dig", "face": at},
		{"t": "do", "f": func() -> bool:
			reserved.erase(i)
			plant(i)
			return true},
	], "Ormancı: fidan dikiyor", b)
