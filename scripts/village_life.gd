extends "res://scripts/village_base.gd"
## Home and town life: meals, hearths and firewood's warmth, newcomers, the evenings on the square
## and the bell, sleeping (at home or rough by the camp fire), idle hours and chores, children at
## play, fires and lightning.

var _rung := {} ## "<day>-<hour>" -> true: the bell's rung for it
var _life: LifeScenes ## the scenes of the daily round (the chains, the dance, the yoke...): life()


## The daily round's scenes (made the first time).
func life() -> LifeScenes:
	if _life == null:
		_life = LifeScenes.new(self)
	return _life


func squares() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role == "square":
			out.append(b)
	return out


func bells() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role in ["bell", "square"]:
			out.append(b)
	return out


## Rings every bell (`times` strokes): the square's.
func ring_bells(times := 3, gap := 1.6) -> void:
	for b in bells():
		b.ring(times, gap)


## The evening: the square's fire lit (it burns the wood brought for it), the bell for the end of work.
func _evenings() -> void:
	var h := weather.hour
	var evening := h >= 18.3 and h < 23.0
	for b in squares():
		var want := evening and int(b.goods.get("odun", 0)) > 0
		if want and not b.lit:
			b.take_goods("odun", 1)
		b.set_fire(evening and (b.lit or want))
	for hour in [6, 19]:
		var key := "%d-%d" % [day, hour]
		if h >= float(hour) and h < float(hour) + 0.5 and not _rung.has(key):
			_rung[key] = true
			ring_bells(3 if hour == 6 else 5)
	life().tick()


func _eat(dt: float) -> void:
	if villagers.is_empty() or arriving:
		return # (none eaten off the train till its load's in the station)
	_eat_t += dt
	var mouths := 0.0 # (each by its traits: a glutton eats half again, a frugal one less)
	for v in villagers:
		mouths += v.trait_mul("eat")
	mouths += int(call("prisoner_count")) * 0.8 # (those held eat too, a little less: village_defense.gd)
	var every := EAT_EVERY / maxf(mouths + oxen(), 0.1)
	while _eat_t >= every:
		_eat_t -= every
		var s := store_with("yiyecek", Vector3.ZERO)
		if s:
			s.take_goods("yiyecek", 1)
	var hungry := int(stock.yiyecek) <= 0
	if hungry:
		for v in villagers:
			v.think("hungry", "Aç", -18.0, 60.0)
	if hungry and not _hungry:
		message.emit("Yiyecek bitti! Köylüler aç, yavaş çalışıyorlar.", "bad")
	_hungry = hungry
	work_rate = 0.6 if hungry else 1.0


func _arrive(dt: float) -> void:
	_arrive_t += dt
	if _arrive_t < ARRIVE_EVERY:
		return
	_arrive_t = 0.0
	if announced or beds() <= villagers.size() or int(stock.yiyecek) < 8:
		return # (once the town's announced, the settlers come by train)
	var home := _nearest(stores(), Vector3.ZERO) if stores().size() > 0 else null
	if home == null:
		return
	for k in 20:
		var a := randf() * TAU
		var p := home.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(60.0, 90.0)
		if nav.is_open(p):
			var v := spawn_villager(p, villagers.size() >= 4 and randf() < 0.3)
			var d := home.door()
			v.give([{"t": "go", "to": d + Vector3(randf_range(-3, 3), 0, randf_range(1, 4))}], "Köye geliyor")
			_house_people()
			message.emit("Köye yeni biri geldi (%d kişi)" % villagers.size(), "good")
			return


# --- Hearths ------------------------------------------------------------------------------------


func needs_fire() -> bool:
	return weather.is_night() or weather.temperature < COLD_BELOW


func _hearths(t: float) -> void:
	var want := needs_fire()
	var dry := 1.0 - clampf(weather.wetness + Weather.rain_now, 0.0, 1.0)
	var wind := Weather.wind_now.length()
	var night := weather.is_night() or weather.hour > 19.5 or weather.hour < 5.5
	for b in buildings:
		if b.def.role == "light" and b.state == "done":
			if night:
				b.heat_acc += t / (LOG_EVERY * 3.0)
				while b.heat_acc >= 1.0:
					b.heat_acc -= 1.0
					b.take_goods("odun", 1)
				b.set_lit(int(b.goods.get("odun", 0)) > 0)
				if b.lit and randf() < t * 0.0005 * (0.2 + dry) * (wind / 6.0):
					for o in buildings:
						if o != b and o.global_position.distance_to(b.global_position) < 4.0 + o.radius and o.ignite():
							message.emit("Fenerden sıçrayan kıvılcım %s binasını tutuşturdu!" % o.display_name(), "bad")
							break
			else:
				b.set_lit(false)
			continue
		if b.def.role == "tower" and b.state == "done":
			var up := false
			for w in b.workers:
				if is_instance_valid(w) and (w as Villager).perched == b:
					up = true
			b.set_watch_light(night and up)
			b.set_torches(night) # (its own torches, burning all night, watched or not)
			continue
		if b.def.role == "barracks" and b.state == "done":
			var manned := not b.workers.is_empty()
			b.set_watch_light(night and manned)
			b.set_lit(night and manned)
			continue
		if b.def.role != "house" or b.state != "done":
			continue
		var lived := not b.residents.is_empty()
		b.set_lit(night and lived and b.warm)
		b.show_fuel()
		b.show_laundry(lived and not night and Weather.rain_now < 0.1 and weather.snow_intensity < 0.1 and weather.temperature > 2.0)
		if not want or not lived:
			b.warm = true
			# Warm enough without it, the stove's still lit for the cooking: morning, noon and evening.
			var h := weather.hour
			b.set_hearth(lived and ((h > 5.8 and h < 8.3) or (h > 11.3 and h < 13.0) or (h > 17.3 and h < 20.5)))
			continue
		b.heat_acc += t / LOG_EVERY * (1.0 + clampf(-weather.temperature / 12.0, 0.0, 1.0)) * b.fuel_mul() # (bitter cold: up to twice the wood; plaster and a stove save it)
		while b.heat_acc >= 1.0:
			b.heat_acc -= 1.0
			# (the coal on the fire first; a fresh one lasts COAL_LASTS firewood; then the wood)
			if b.coal_burn > 0:
				b.coal_burn -= 1
			elif b.take_goods("komur", 1) == 1:
				b.coal_burn = COAL_LASTS - 1
			elif b.take_goods("odun", 1) == 0:
				b.warm = false
		if house_fuel(b) > 0:
			b.warm = true
		b.set_hearth(b.warm)
		if not b.warm and weather.is_night():
			b.cold_night = true
		# A spark onto the roof.
		if b.warm and randf() < t * 0.0006 * (0.2 + dry) * (1.0 + wind / 6.0):
			if b.ignite():
				message.emit("Ocaktan sıçrayan kıvılcım %s damını tutuşturdu!" % b.display_name(), "bad")


## Of a morning, now and then, a child born to a couple who've a house with room in it, while the
## store's got food to spare.
func _births() -> void:
	if int(stock.get("yiyecek", 0)) < 25:
		return
	for b in buildings:
		if b.state != "done" or b.def.role != "house" or b.residents.size() >= b.beds():
			continue
		var fams := {}
		for o in b.residents:
			if is_instance_valid(o) and not (o as Villager).is_child and not (o as Villager).dead:
				var fv := o as Villager
				fams[fv.family] = int(fams.get(fv.family, 0)) | (2 if fv.female else 1)
		for f: String in fams:
			if int(fams[f]) == 3 and randf() < 0.18:
				var kid := spawn_villager(b.door(), true, f)
				b.residents.append(kid)
				kid.home = b
				message.emit("%s ailesinin bir çocuğu oldu: %s" % [f, kid.display_name.split(" ")[0]], "good")
				return


## The bricks on the mud pits' racks drying `t` s: in the sun, slower in the rain, not at all under
## snow or in the frost.
func _dry_bricks(t: float) -> void:
	var rate := 1.0
	if Weather.snow_cover_now > 0.3 or weather.temperature < 0.0:
		rate = 0.0
	elif Weather.rain_now > 0.15:
		rate = 0.25
	elif weather.is_night():
		rate = 0.4
	for b in buildings:
		if not b.drying.is_empty() and b.state == "done":
			b.dry(t, rate)


## Left lying out, things spoil: logs bucked and never fetched rot where they lie after a few days;
## what's heaped in a workshop's yard and never carried in goes off by the day (food fast, herbs and
## bandages soon, wood slowly in the wet); stone, iron and coal keep. What went, said once a morning.
const ROT := {"yiyecek": 0.25, "ot": 0.2, "odun": 0.06, "kerpic": 0.0, "camur": 0.15}
const LOGS_ROT_DAYS := 3
const OPEN_ROT := 0.3 ## the heap by the rails: crated and sacked, it goes off this much slower (twice that in the wet)


func _rot_morning() -> void:
	var lost := {}
	for i in range(billets.size() - 1, -1, -1):
		var bl: Dictionary = billets[i]
		if bl.get("claimed") == null and day - int(bl.get("day", day)) >= LOGS_ROT_DAYS:
			if is_instance_valid(bl.node):
				(bl.node as Node).queue_free()
			billets.remove_at(i)
			lost["kütük"] = int(lost.get("kütük", 0)) + 1
	# burnt-out ruins left untouched two days are cleared away (ONAR in time saves one)
	var cleared := 0
	for b in buildings.duplicate():
		if b.state != "ruin" or b.is_burning():
			continue
		if not b.has_meta("ruin_day"):
			b.set_meta("ruin_day", day)
		elif day - int(b.get_meta("ruin_day")) >= 2:
			call("remove_building", b)
			cleared += 1
	if cleared > 0:
		message.emit("Yanık enkaz temizlendi (%d bina)." % cleared, "info")
	var wet := weather.wetness > 0.4 or Weather.rain_now > 0.2
	for b in buildings:
		var open: bool = b.def.get("open", false)
		if b.state != "done" or (b.def.role in ["store", "house"] and not open) or b.goods.is_empty():
			continue
		for r: String in b.goods.keys():
			var k := float(ROT.get(r, 0.0)) * (1.6 if wet and r == "odun" else 1.0)
			if open:
				k *= OPEN_ROT * (2.0 if wet else 1.0)
			if k <= 0.0:
				continue
			var n := int(b.goods[r])
			var gone := mini(n, maxi(1, int(round(n * k)))) if n > 0 else 0
			if gone > 0:
				b.take_goods(r, gone)
				lost[str(BuildingDefs.RES_NAMES.get(r, r)).to_lower()] = int(lost.get(str(BuildingDefs.RES_NAMES.get(r, r)).to_lower(), 0)) + gone
	if not lost.is_empty():
		var parts: Array[String] = []
		for k: String in lost:
			parts.append("%d %s" % [lost[k], k])
		message.emit("Dışarıda kalanlar çürüdü: %s (yığınlar depoya taşınmalı)." % ", ".join(parts), "info")
	# the heap by the rails, all carried off, cleared away
	for b in buildings.duplicate():
		if b.def.get("open", false) and b.state == "done" and b.goods_total() == 0 and not arriving and stores().size() > 1:
			_unplace(b)
			b.demolish()
			message.emit("Rayın yanındaki yük yığını boşaldı.", "info")


## The town as the season has it: icicles on the houses' eaves and fur hats on heads in the winter.
func dress_for_season() -> void:
	var cold := seasons != null and seasons.winter()
	# (the town's doing well: fed, in good heart, and a name up the line: the houses get their paint)
	var heart := 0.0
	for v in villagers:
		heart += v.mood
	heart /= maxf(villagers.size(), 1.0)
	var well := heart >= 55.0 and int(stock.get("yiyecek", 0)) >= 40 and day >= 6
	for b in buildings:
		if b.def.role == "house":
			b.set_icicles(cold)
			b.set_trim(well)
	for v in villagers:
		v.dress_warm(cold)


## A house its family's outgrown: if the stores can spare it, they add a room themselves.
func _rooms_morning() -> void:
	var cost: Dictionary = BuildingDefs.UPGRADES["oda"].cost
	for b in buildings:
		if b.def.role != "house" or b.state != "done" or b.level >= 2 or b.upgrading != "" or b.residents.size() < b.beds():
			continue
		if not b.residents.any(func(o: Villager) -> bool: return is_instance_valid(o) and o.is_child):
			continue
		var can := true
		for r: String in cost:
			if int(stock.get(r, 0)) < int(cost[r]) + 10: # (not the last of it)
				can = false
		if can and call("upgrade", b, "oda") == "":
			message.emit("%s dar geldi, aile büyüdü: arkasına oda ekleniyor." % b.display_name(), "good")
			return


func _morning() -> void:
	_births()
	call("_prison_morning") # (village_defense.gd)
	call("_armoury_morning")
	_train_morning()
	_news_morning()
	_armoured_morning()
	_convoy_morning()
	trade.morning()
	_rooms_morning()
	_rot_morning()
	for b in buildings:
		if b.state == "done":
			b.grow_old()
	dress_for_season()
	for y in yards:
		if is_instance_valid(y):
			y.grow()
	for v in villagers:
		if v.is_child and day - v.born_day >= 4:
			v.grow_up()
			message.emit("%s büyüdü, artık çalışabilir" % v.display_name, "good")
	var cold := 0
	# How the night was: warm or cold in a house (a stove, a back room, plaster to its credit), or out.
	var day_s := maxf(weather.day_length_minutes * 60.0, 60.0)
	for v in villagers:
		if v.dead or v.team != 0:
			continue
		var h := v.home
		if not is_instance_valid(h) or h.state != "done":
			v.think("night", "Açıkta, ateş başında yattı", -8.0, day_s)
		elif h.cold_night and not v.has_trait("cold"):
			v.think("night", "Soğuk evde üşüdü", -14.0, day_s)
		else:
			v.think("night", "Sıcak evde uyudu", 5.0, day_s)
			if h.stove:
				v.think("home", "Sobalı evde oturuyor", 6.0, day_s * 1.05)
			elif h.level >= 2:
				v.think("home", "Geniş bir evde oturuyor", 4.0, day_s * 1.05)
			elif h.plastered:
				v.think("home", "Sıvalı, sıcak bir evde oturuyor", 3.0, day_s * 1.05)
			if h.residents.size() >= h.beds() and h.beds() > 0:
				v.think("crowd", "Evi dolu, sıkışık", -3.0, day_s)
		if is_instance_valid(h) and h.state == "done" and h.water_far and not v.is_child:
			v.think("water", "Suyu her gün uzaktan kovayla taşıyor", -4.0, day_s)
	for b in buildings:
		if b.def.role == "house" and b.cold_night:
			b.cold_night = false
			for v in b.residents:
				if is_instance_valid(v) and not v.dead and not v.has_trait("cold"):
					v.hurt(18.0)
					cold += 1
	if cold > 0:
		message.emit("Gece %d kişi soğuk evde üşüdü. Evlere yakacak odun taşınmalı." % cold, "bad")


## The open ground between two buildings' walls (their footprints, turned as they stand).
func _wall_gap(a: Building, b: Building) -> float:
	var best := INF
	for pair: Array in [[a, b], [b, a]]:
		var x: Building = pair[0]
		var y: Building = pair[1]
		var sz: Vector2 = y.def.size
		var inv := y.global_transform.affine_inverse()
		var xs: Vector2 = x.def.size
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(0, 0)]:
			var corner: Vector3 = x.global_transform * Vector3(c.x * xs.x * 0.5, 0, c.y * xs.y * 0.5)
			var l := inv * corner
			var dx := maxf(absf(l.x) - sz.x * 0.5, 0.0)
			var dz := maxf(absf(l.z) - sz.y * 0.5, 0.0)
			best = minf(best, Vector2(dx, dz).length())
	return best


func _fires(t: float) -> void:
	var wind := Weather.wind_now
	for b in buildings:
		if not b.is_burning():
			_burning.erase(b)
			continue
		if not _burning.has(b):
			_burning[b] = true
			message.emit("Yangın! %s yanıyor" % b.display_name(), "bad")
			if b.def.role == "store" and b.goods_total() > 0:
				message.emit("Ambar yanıyor: içindekiler kül oluyor!", "bad")
		var n := b.burning_count()
		if b.def.role in ["store", "work"]:
			for k: String in b.goods:
				var lost := int(ceil(float(b.goods[k]) * 0.0015 * mini(n, 8) * t))
				b.take_goods(k, lost)
		# to a neighbour only if it's close: wall to wall within a metre and a half, or a few metres more
		# straight downwind in a strong wind (sparks carried); never across open ground
		var wet := clampf(maxf(Weather.rain_now, maxf(Weather.snow_now * 1.3, Weather.snow_cover_now * 0.7)), 0.0, 1.0)
		for o in buildings:
			if o == b or o.state == "gone" or o.is_burning():
				continue
			var gap := _wall_gap(b, o)
			var dir := (o.global_position - b.global_position).normalized()
			var downwind := clampf(Vector2(wind.x, wind.z).dot(Vector2(dir.x, dir.z)) / 6.0, -0.5, 1.5)
			var reach := 1.5 + (2.5 * downwind if wind.length() > 6.0 and downwind > 0.3 else 0.0)
			if gap > reach:
				continue
			var chance := 0.0035 * mini(n, 8) * (1.0 + downwind) * clampf(1.0 - gap / maxf(reach, 0.1), 0.15, 1.0) * (1.0 - wet * 0.9) * t
			if randf() < chance and o.ignite():
				message.emit("Yangın %s binasına sıçradı!" % o.display_name(), "bad")


func _lightning() -> void:
	var f := weather.lightning_flash
	if f > 0.7 and _last_flash <= 0.7 and randf() < 0.3:
		var can: Array[Building] = []
		for b in buildings:
			if b.state == "done":
				can.append(b)
		if not can.is_empty():
			var b: Building = can[randi() % can.size()]
			if b.ignite():
				message.emit("Yıldırım düştü! %s tutuştu" % b.display_name(), "bad")
	_last_flash = f


# --- Giving out work ------------------------------------------------------------------------------


## To bed with no house of its own: a guard in its guardhouse's bunks, anyone else out by the camp
## fire beside the store.
func _plan_bed(v: Villager) -> void:
	if v.workplace and v.workplace.def.role == "barracks" and v.workplace.state == "done":
		var g := v.workplace
		v.give(_go_in(g) + [{"t": "do", "f": func() -> bool:
			if is_instance_valid(g) and g.state == "done" and not g.is_burning():
				v.sleep_in(g)
			return true}], "Eve gidiyor", g)
		return
	var store := _nearest(stores(), v.position)
	if store == null:
		return
	var fire := camp_fire(store)
	var k := _camp_sleepers(store)
	var a := k * 0.9 + 0.4
	var spot := fire + Vector3(cos(a), 0, sin(a)) * (2.4 + (k / 7) * 1.4)
	spot.y = ground_at(spot)
	v.give([{"t": "go", "to": spot}, {"t": "do", "f": func() -> bool:
		if is_instance_valid(store) and store.state == "done":
			v.sleep_rough(store, spot, fire)
		return true}], "Kampa gidiyor", store)


## The camp fire for those with no roof: out in front of the store, a little to the side.
func camp_fire(store: Building) -> Vector3:
	if _camp_at.has(store):
		return _camp_at[store]
	# (the first open ground round the store with room for the sleepers about it)
	var sz: Vector2 = store.def.size
	var best := store.global_transform * Vector3(sz.x * 0.5 + 5.0, 0, sz.y * 0.5 + 4.0)
	for r in [7.0, 10.0, 13.0, 17.0, 22.0]:
		var found := false
		for k in 12:
			var a := k * TAU / 12.0 + 0.6
			var p: Vector3 = store.global_position + Vector3(cos(a), 0, sin(a)) * (r + sz.length() * 0.5)
			var clear := true
			for q in 8:
				var e: Vector3 = p + Vector3(cos(q * TAU / 8.0), 0, sin(q * TAU / 8.0)) * 4.0
				if not nav.is_open(e) or not nav.is_open(p):
					clear = false
					break
			for b in buildings:
				if b.global_position.distance_to(p) < b.radius + 5.0:
					clear = false
			for y in yards:
				if is_instance_valid(y) and is_instance_valid(y.house) and y.house.global_position.distance_to(p) < 13.0:
					clear = false
			if clear:
				best = p
				found = true
				break
		if found:
			break
	best.y = ground_at(best)
	_camp_at[store] = best
	return best


var _camp_at := {} ## store -> where its camp fire is


func _camp_sleepers(store: Building) -> int:
	var n := 0
	for o in villagers:
		if o.sleeping and o.inside == store and o.get("_rough"):
			n += 1
		elif o.job == "Kampa gidiyor" and o.target == store:
			n += 1
	return n


var _camps := {} ## store -> the camp fire's nodes


## The camp fires burn the night through while anyone's asleep by them; the army tents round them
## (canvas brought out of the war) stand while there's anyone in the town with no house.
func _camp_fires() -> void:
	var homeless := villagers.any(func(o: Villager) -> bool: return not o.dead and not o.is_child and not is_instance_valid(o.home))
	for s in stores():
		var n := 0
		for o in villagers:
			if o.sleeping and o.inside == s and o.get("_rough"):
				n += 1
		var on := n > 0
		if (on or homeless) and not _camps.has(s):
			var root := Node3D.new()
			add_child(root)
			root.global_position = camp_fire(s)
			var f := FireFx.flames()
			f.amount = 16
			(f.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.25, 0.15, 0.25)
			f.position = Vector3.UP * 0.3
			root.add_child(f)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.58, 0.26)
			l.light_energy = 2.4
			l.omni_range = 10.0
			l.light_volumetric_fog_energy = 0.2
			l.position = Vector3.UP * 0.9
			root.add_child(l)
			var ring := Building.material("stone")
			for k in 8:
				var st := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.14
				sm.height = 0.2
				st.mesh = sm
				st.material_override = ring
				st.position = Vector3(cos(k * TAU / 8.0), 0.05, sin(k * TAU / 8.0)) * 0.55
				root.add_child(st)
			_tents(root)
			_camps[s] = root
		if _camps.has(s):
			var root: Node3D = _camps[s]
			root.visible = on or homeless
			for c in root.get_children():
				if c is OmniLight3D:
					(c as OmniLight3D).visible = on
			for c in root.get_children():
				if c is GPUParticles3D:
					(c as GPUParticles3D).emitting = on


## Three wall tents round a camp fire (assets/props/tent.glb).
func _tents(root: Node3D) -> void:
	for k in 3:
		var a := 0.9 + k * TAU / 3.0
		var at := Vector3(cos(a), 0, sin(a)) * 4.6
		var clear := true
		for q in 6: # (only on open ground, clear of a house's corner)
			if not nav.is_open(root.global_position + at + Vector3(cos(q * TAU / 6.0), 0, sin(q * TAU / 6.0)) * 1.8):
				clear = false
		if not clear:
			continue
		var g := ground_at(root.global_position + at) - root.global_position.y
		Props.place(root, "tent", Transform3D(Basis(Vector3.UP, a), at + Vector3.UP * g))


func _plan_home(v: Villager) -> void:
	var h := v.home
	if v.idle:
		v.abort()
	v.give(life().at_door(_go_in(h), h) + [{"t": "do", "f": func() -> bool:
		if is_instance_valid(h) and h.state == "done" and not h.is_burning():
			v.sleep_in(h)
		return true}], "Eve gidiyor", h)


## Nothing to do: a while spent as people spend it, each in their own way (who they are, what
## they're good at, the season and the hour, what's near): of an evening round the fire on the
## square; by day a chore about the house, now and then a word with someone, a sit on the porch, a
## chopping block or a stump (a pipe, a bit of whittling, a knife put to the stone), the rod at the
## water in the warm months, hands warmed at a fire in the cold, a wash at the well of a morning, a
## prayer at the graves, a mother sat with her child, a look down the line for the train; or just a
## stretch, a look round, a stroll.
func _plan_idle(v: Villager) -> void:
	# Of an evening, round the fire on the square.
	var sq := _nearest(squares(), v.position)
	if sq and sq.lit and sq.global_position.distance_to(v.position) < 200.0 and randf() < 0.8:
		if randf() < 0.55 and life().plan_dance(v, sq):
			return
		_plan_square(v, sq)
		return
	# A house short of water: its water fetched on the yoke, twice a day.
	if life().plan_water(v):
		return
	var near: Building = v.workplace if v.workplace else _nearest(stores(), v.position)
	var at := near.door() if near else v.position
	var p := at + Vector3(randf_range(-6, 6), 0, randf_range(1.5, 7))
	# Someone else standing about near: now and then, go over and talk.
	if randf() < 0.3 and _plan_chat(v):
		return
	# By day, a chore about the house: splitting wood at the block, hanging the washing, hoeing the
	# garden; or a bucket fetched from the well.
	var h := weather.hour
	if not v.is_child and h > 6.5 and h < 19.0 and randf() < 0.5:
		if randf() < 0.55 and life().plan_chore(v):
			return
		var y := _yard_of(v.home) if is_instance_valid(v.home) else null
		if randf() < 0.15 and life().plan_water(v, true):
			return
		if y:
			var list := y.chores()
			if not list.is_empty():
				var c: Dictionary = list[randi() % list.size()]
				var step := {"t": "work", "time": float(c.time), "anim": c.anim, "face": c.face}
				var walk := {"t": "go", "to": c.at}
				if str(c.job) == "Çamaşır asıyor":
					step["anim"] = "hang" # (the basket on the hip to the line, the pieces pegged up)
					step["time"] = 24.0
					walk["life"] = "basket"
				if c.has("split"):
					var t := [0.0]
					step["tick"] = func(dt: float) -> bool:
						t[0] += dt
						if fmod(t[0], 1.37) < dt and is_instance_valid(y):
							y.split_one()
						return t[0] < float(c.time)
				v.give([walk, step], c.job, null, true)
				return
	if randf() < 0.75 and _pastime(v):
		return
	var roll := randf()
	var what: Array
	if roll < 0.2:
		what = [{"t": "go", "to": p}, {"t": "work", "time": 2.5, "anim": "stretch"}, {"t": "work", "time": randf_range(3.0, 6.0), "anim": "idle"}]
	elif roll < 0.6:
		what = [{"t": "go", "to": p}, {"t": "work", "time": randf_range(4.0, 8.0), "anim": "look"}]
	else:
		what = [{"t": "go", "to": p}, {"t": "work", "time": randf_range(2.0, 5.0), "anim": "idle"}, {"t": "go", "to": at + Vector3(randf_range(-8, 8), 0, randf_range(1.5, 9))}]
	v.give(what, "Boşta", null, true)


## Water for each house: a finished well within WELL_REACH, or the river within RIVER_REACH. Short
## of both, its people lose time every day walking for it (Villager.knack) and grumble.
func _water() -> void:
	var wells := _wells()
	for b in buildings:
		if b.def.role != "house" or b.state != "done":
			continue
		var w := _nearest(wells, b.global_position)
		b.water_m = w.global_position.distance_to(b.global_position) if w else INF
		if b._river_near < 0:
			b._river_near = 1 if _river_within(b.global_position, BuildingDefs.RIVER_REACH) else 0
		b.water_far = b.water_m > BuildingDefs.WELL_REACH and b._river_near == 0


## Whether there's open water (the river, the lake) within `r` m of `p`.
func _river_within(p: Vector3, r: float) -> bool:
	for ring in [0.35, 0.7, 1.0]:
		for k in 16:
			var a := k * TAU / 16.0
			var q := p + Vector3(cos(a), 0, sin(a)) * r * float(ring)
			if terrain.is_water(q.x, q.z):
				return true
	return false


## The houses short of water (Building.water_far).
func dry_houses() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.def.role == "house" and b.state == "done" and b.water_far:
			out.append(b)
	return out


func _wells() -> Array[Building]:
	var out: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role == "well":
			out.append(b)
	return out


## The square's fire of an evening: sat round it on the ground (or stood close in the cold, warming
## their hands), talking among themselves by turns, a cup going round after supper, a pipe.
var _fire_talks := {} ## square -> the talk round its fire (Villager._talk)


func _plan_square(v: Villager, sq: Building) -> void:
	var fire := sq.global_position
	var talk: Dictionary = _fire_talks.get(sq, {})
	if talk.is_empty():
		talk = {"folk": [], "t0": clock, "seed": randi() % 1000, "reach": 7.5, "keep_face": true, "where": "fire"}
		_fire_talks[sq] = talk
	var folk: Array = talk.folk
	for i in range(folk.size() - 1, -1, -1):
		var o: Variant = folk[i]
		if not is_instance_valid(o) or (o as Villager).dead or not (o as Villager).job.begins_with("Ateş") and (o as Villager).job != "Meydanda, ateş başında":
			folk.remove_at(i)
	folk.append(v)
	var h := weather.hour
	var cold := weather.temperature < 3.0
	var anim := "sit"
	var seat := 0.0
	var r := randf_range(2.3, 3.0)
	var what := "Meydanda, ateş başında"
	var roll := randf()
	if roll < 0.28 and h >= 19.0 and not v.is_child:
		anim = "drink"
		what = "Ateş başında içiyor"
	elif roll < 0.5 and cold:
		anim = "warm"
		seat = -1.0
		r = randf_range(1.7, 2.1)
		what = "Ateşte ısınıyor"
	elif roll < 0.62 and _smokes(v):
		anim = "pipe"
		what = "Ateş başında pipo içiyor"
	var a := randf() * TAU
	var spot := fire + Vector3(cos(a), 0, sin(a)) * r
	spot.y = ground_at(spot)
	var work := {"t": "work", "time": randf_range(18.0, 34.0), "anim": anim, "face": fire + Vector3.UP, "talk": talk}
	if seat >= 0.0:
		work["seat"] = seat
	v.give([{"t": "go", "to": sq.door()}, {"t": "step", "to": spot}, work,
		{"t": "do", "f": func() -> bool:
			v.think("fire", "Akşam meydanda ateş başında oturdu", 10.0, maxf(weather.day_length_minutes * 60.0, 60.0))
			return true},
		{"t": "step", "to": sq.door()}], what, sq, true)


## Whether `v` is one for a pipe (some of the men, the same ones always).
static func _smokes(v: Villager) -> bool:
	return not v.is_child and not v.female and v.look_seed % 3 == 0


## A word with one or two others standing about near: they come together, two face to face a pace
## apart or three in a ring, and talk by turns (Villager._talk).
func _plan_chat(v: Villager) -> bool:
	var others: Array[Villager] = []
	for o in villagers:
		if o == v or o.dead or o.sleeping or o.team != 0 or o.is_child != v.is_child:
			continue
		if not (o.plan.is_empty() or (o.idle and o.job == "Boşta")):
			continue
		if o.position.distance_to(v.position) < 16.0:
			others.append(o)
	if others.is_empty():
		return false
	others.shuffle()
	var group: Array = [v, others[0]]
	if others.size() > 1 and randf() < 0.35:
		group.append(others[1])
	var mid := Vector3.ZERO
	for o: Villager in group:
		mid += o.position
	mid /= float(group.size())
	var r := 0.68 if group.size() == 2 else 0.85
	var a0 := randf() * TAU
	var talk := {"folk": group, "t0": clock, "seed": randi() % 1000, "reach": 3.2}
	var mood := LifeScenes.talk_mood(group)
	if mood != "":
		talk["mood"] = mood
		talk["where"] = mood
	var time := randf_range(12.0, 20.0)
	# two meeting: a handshake first now and then (the men), or kin an embrace
	if group.size() == 2 and mood == "" and randf() < 0.35:
		var a: Villager = group[0]
		var b: Villager = group[1]
		var kin := a.family != "" and a.family == b.family
		var greet := "embrace" if kin and randf() < 0.5 else ("handshake" if not a.female and not b.female else "")
		if greet != "":
			life().meet(a, b, mid, greet, "Sohbet ediyor", "Sohbet ediyor")
			return true
	for i in group.size():
		var o: Villager = group[i]
		var a := a0 + TAU * i / group.size()
		var spot := mid + Vector3(cos(a), 0, sin(a)) * r
		if not nav.is_open(spot):
			spot = mid
		spot.y = ground_at(spot)
		o.give([{"t": "go", "to": spot}, {"t": "step", "to": spot}, {"t": "work", "time": time, "anim": "chat", "talk": talk, "face": mid}], "Sohbet ediyor", null, true)
	return true


## One of the pastimes that suit `v` just now, tried in a weighted random order till one has a
## place for it. False if none has.
func _pastime(v: Villager) -> bool:
	var h := weather.hour
	var temp := weather.temperature
	var winter := seasons != null and seasons.winter()
	var wet := Weather.rain_now > 0.25 or weather.snow_intensity > 0.35
	var smoker := _smokes(v)
	var crafty := v.skill("zanaat") >= 4.0 or v.skill("insa") >= 5.0 or v.skill("odun") >= 6.0 or v.origin in ["makinist", "oduncu"]
	var opts: Array = [] ## [weight, Callable -> bool]
	opts.append([2.2 * (0.35 if temp < -6.0 or wet else 1.0), func() -> bool: return _plan_seat(v, smoker, crafty)])
	if not squares().is_empty() and not v.is_child and not wet and temp > -8.0:
		opts.append([4.5, func() -> bool: return _plan_bench(v, smoker)])
	if not v.is_child and not winter and temp > 3.0 and h > 5.0 and h < 20.5 and not wet:
		var w := 1.5 + (2.5 if v.skill("toplama") >= 4.0 else 0.0) + (1.5 if v.has_trait("tembel") or v.has_trait("kanaatkar") else 0.0) + (1.0 if v.origin == "koylu" else 0.0)
		opts.append([w, func() -> bool: return _plan_fish(v)])
	if temp < 4.0:
		opts.append([3.0, func() -> bool: return _plan_warm(v)])
	if smoker and not wet:
		opts.append([1.5, func() -> bool: return _plan_pipe(v)])
	if v.female:
		var kid := _child_of(v)
		if kid:
			opts.append([3.0, func() -> bool: return _plan_with_child(v, kid)])
	if temp > 4.0 and h > 5.5 and h < 11.0:
		opts.append([2.0, func() -> bool: return _plan_wash(v)])
	if cemetery != null and not cemetery.graves.is_empty() and not v.is_child:
		var mourning := v.thoughts.any(func(t: Dictionary) -> bool: return str(t.id) in ["grief", "loss", "funeral"])
		opts.append([0.5 + (3.0 if v.origin == "papaz" else 0.0) + (4.0 if mourning else 0.0), func() -> bool: return _plan_pray(v)])
	if rail.size() > 1:
		var due := next_train - day
		opts.append([0.5 + (1.2 if due <= 0 else 0.0) + (1.5 if v.origin == "demiryolcu" else 0.0), func() -> bool: return _plan_line(v)])
	while not opts.is_empty():
		var total := 0.0
		for o: Array in opts:
			total += float(o[0])
		var r := randf() * total
		var pick := 0
		for i in opts.size():
			r -= float(opts[i][0])
			if r <= 0.0:
				pick = i
				break
		var f: Callable = opts[pick][1]
		opts.remove_at(pick)
		if f.call():
			return true
	return false


# --- seats ------------------------------------------------------------------------------------------

var _seats_held := {} ## Vector3i (the seat, to half a metre) -> [villager, job]: taken


## A seat near `v`: the edge of a house's porch (its own first), the chopping block in its yard, a
## stump near by. {at (where the feet go), face, h (the seat's height over the ground there),
## where} or {}.
func _seat_near(v: Villager) -> Dictionary:
	var found: Array[Dictionary] = []
	var own := v.home if is_instance_valid(v.home) and v.home.state == "done" else null
	for b in buildings:
		if b.state != "done" or b.kind != "ev" or b.is_burning() or b.global_position.distance_to(v.position) > 45.0:
			continue
		var sz: Vector2 = b.def.size
		for x: float in [-0.34, 0.34]:
			var l := Vector3(x * sz.x, 0, sz.y * 0.5 + 1.7 + 0.12)
			var at := b.global_transform * l
			at.y = nav.height(at.x, at.z)
			var hgt := b.global_position.y + 0.45 - at.y
			if hgt < 0.3 or hgt > 0.75 or not nav.is_open(at):
				continue
			found.append({"at": at, "face": b.global_transform * (l + Vector3(0, 0, 3.0)), "h": hgt, "where": "porch", "own": b == own})
	if own:
		var y := _yard_of(own)
		if y and y._block != Vector3.INF:
			var away := (own.door() - y._block)
			away.y = 0.0
			away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
			var at: Vector3 = y._block + away * 0.2
			at.y = nav.height(at.x, at.z)
			var hgt: float = y._block.y + 0.55 - at.y
			if hgt > 0.3 and hgt < 0.75:
				found.append({"at": at, "face": at + away * 3.0, "h": hgt, "where": "block", "own": true})
	for st in _stumps.get_children():
		var n := st as Node3D
		if n == null or n.position.distance_to(v.position) > 35.0:
			continue
		var a := randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var at := n.position + dir * 0.15
		at.y = nav.height(at.x, at.z)
		var hgt := n.position.y + 0.35 - at.y
		if hgt > 0.25 and hgt < 0.7 and nav.is_open(at + dir * 0.5):
			found.append({"at": at, "face": at + dir * 3.0, "h": hgt, "where": "stump", "own": false})
	found.shuffle()
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return bool(a.own) and not bool(b.own))
	for s: Dictionary in found:
		if not _seat_taken(s.at):
			return s
	return {}


func _seat_taken(at: Vector3) -> bool:
	var key := Vector3i(roundi(at.x * 2.0), 0, roundi(at.z * 2.0))
	if not _seats_held.has(key):
		return false
	var e: Array = _seats_held[key]
	var o: Variant = e[0]
	return is_instance_valid(o) and not (o as Villager).dead and (o as Villager).job == str(e[1]) and not (o as Villager).plan.is_empty()


func _hold_seat(at: Vector3, v: Villager, what: String) -> void:
	_seats_held[Vector3i(roundi(at.x * 2.0), 0, roundi(at.z * 2.0))] = [v, what]


const SQUARE_BENCH := 2.55 ## m from the square's middle to where someone sits on a bench


## An hour on a bench on the square, among the others there: talk, a pipe, and the better for it.
func _plan_bench(v: Villager, smoker: bool) -> bool:
	var sq := _nearest(squares(), v.position)
	if sq == null or sq.global_position.distance_to(v.position) > 130.0:
		return false
	var at := Vector3.INF
	var mid := Vector3.ZERO
	var picks: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
	picks.shuffle()
	for k in picks:
		var a := PI * 0.25 + (k / 3) * PI * 0.5
		var along := float(k % 3 - 1) * 0.8
		var l := Vector3(cos(a), 0, sin(a)) * SQUARE_BENCH + Vector3(-sin(a), 0, cos(a)) * along
		var w := sq.to_global(l)
		if not _seats_held.has(Vector3i(roundi(w.x * 2.0), 0, roundi(w.z * 2.0))):
			at = w
			mid = sq.global_position
			break
	if at == Vector3.INF:
		return false
	at.y = sq.global_position.y + 0.35
	var what := "Meydanda oturuyor"
	var anim := "sit"
	if smoker and randf() < 0.5:
		anim = "pipe"
		what = "Meydanda pipo içiyor"
	_hold_seat(at, v, what)
	var work := {"t": "work", "time": randf_range(30.0, 60.0), "anim": anim, "seat": 0.44, "face": mid}
	for o in villagers:
		if o == v or o.dead or o.plan.is_empty() or o.team != 0 or not (o.plan[0] as Dictionary).has("seat"):
			continue
		if o.position.distance_to(at) < 7.0 and str(o.plan[0].t) == "work":
			var talk: Dictionary = o.plan[0].get("talk", {})
			if talk.is_empty():
				talk = {"folk": [o], "t0": clock, "seed": randi() % 1000, "reach": 8.0, "keep_face": true, "where": "porch"}
				o.plan[0]["talk"] = talk
			(talk.folk as Array).append(v)
			work["talk"] = talk
			what = "Meydanda sohbet ediyor"
			break
	v.give([{"t": "go", "to": sq.door()}, {"t": "step", "to": at}, work,
		{"t": "do", "f": func() -> bool:
			v.think("square", "Meydanda oturup iki laf etti", 6.0, maxf(weather.day_length_minutes * 60.0, 60.0))
			return true},
		{"t": "step", "to": sq.door()}], what, sq, true)
	return true


## Sat at its ease: a rest, a pipe, or the knife out (whittling a peg, or a blade put to the stone).
func _plan_seat(v: Villager, smoker: bool, crafty: bool) -> bool:
	var s := _seat_near(v)
	if s.is_empty():
		return false
	var anim := "sit"
	var what: String = {"porch": "Sundurmada oturuyor", "block": "Kütüğe oturmuş dinleniyor", "stump": "Kütükte oturuyor"}[s.where]
	var r := randf()
	if smoker and r < 0.55:
		anim = "pipe"
		what = "Pipo içiyor"
	elif crafty and r < 0.6:
		anim = "whittle"
		what = "Tahta yontuyor" if randf() < 0.6 else "Bıçağını biliyor"
	_hold_seat(s.at, v, what)
	var work := {"t": "work", "time": randf_range(25.0, 45.0), "anim": anim, "seat": s.h, "face": s.face}
	# someone sat near by already: they get talking, each keeping to its seat
	for o in villagers:
		if o == v or o.dead or o.plan.is_empty() or o.team != 0 or not (o.plan[0] as Dictionary).has("seat"):
			continue
		if o.position.distance_to(s.at) < 5.5 and str(o.plan[0].t) == "work":
			var talk: Dictionary = o.plan[0].get("talk", {})
			if talk.is_empty():
				talk = {"folk": [o], "t0": clock, "seed": randi() % 1000, "reach": 6.0, "keep_face": true, "where": str(s.where)}
				o.plan[0]["talk"] = talk
			(talk.folk as Array).append(v)
			work["talk"] = talk
			break
	v.give([{"t": "go", "to": s.at}, {"t": "step", "to": s.at}, work], what, null, true)
	return true


## Sat on the bank with a rod: the lake's shore or the river's, whichever's nearer (and not too far).
var _shores: Array[Array] = [] ## [where the feet go, the water before it]


func _plan_fish(v: Villager) -> bool:
	if _shores.is_empty():
		_find_shores()
	var best: Array = []
	var bd := 170.0
	for e in _shores:
		var d := (e[0] as Vector3).distance_to(v.position)
		if d < bd and not _seat_taken(e[0]):
			bd = d
			best = e
	if best.is_empty():
		return false
	var at: Vector3 = best[0]
	var water: Vector3 = best[1]
	_hold_seat(at, v, "Balık tutuyor")
	v.give([{"t": "go", "to": at}, {"t": "step", "to": at},
		{"t": "work", "time": randf_range(45.0, 80.0), "anim": "fish", "seat": 0.0, "face": water},
		{"t": "do", "f": func() -> bool:
			if randf() < 0.45:
				v.think("fish", "Balık tuttu", 4.0, maxf(weather.day_length_minutes * 60.0, 60.0) * 0.5)
			return true}], "Balık tutuyor", null, true)
	return true


## Places on the bank to sit and fish from: round the lake, and down both sides of the river.
func _find_shores() -> void:
	_shores.append([Vector3.INF, Vector3.INF]) # (looked: none found still counts)
	var lake: Dictionary = terrain.meta.get("lake", {})
	if not lake.is_empty():
		var c := Vector2(float(lake.x), float(lake.z))
		for k in 32:
			var a := k * TAU / 32.0
			var dir := Vector2(cos(a), sin(a))
			var rad := Vector2(float(lake.rx), float(lake.rz))
			var last_water := Vector2.INF
			for q in range(6, 30):
				var f := q * 0.05
				var pt := c + dir * rad * f
				if terrain.is_water(pt.x, pt.y):
					last_water = pt
				elif last_water != Vector2.INF:
					_shore(Vector3(pt.x, 0, pt.y) + Vector3(dir.x, 0, dir.y) * 0.6, Vector3(last_water.x, 0, last_water.y))
					break
	var river: Dictionary = terrain.meta.get("river", {})
	var pts: Array = river.get("points", [])
	var hw := float(river.get("half_width", 9.0))
	for k in range(0, pts.size() - 1, 2):
		var a := Vector3(float(pts[k][0]), 0, float(pts[k][2]))
		var b := Vector3(float(pts[k + 1][0]), 0, float(pts[k + 1][2]))
		var along := (b - a).normalized()
		var side := Vector3(-along.z, 0, along.x)
		for sgn: float in [-1.0, 1.0]:
			for off: float in [hw - 1.5, hw, hw + 1.5, hw + 3.0]:
				var pt := a + side * sgn * off
				if not terrain.is_water(pt.x, pt.z) and terrain.is_water(pt.x - side.x * sgn * 2.5, pt.z - side.z * sgn * 2.5):
					_shore(pt, pt - side * sgn * 3.0)
					break


func _shore(at: Vector3, water: Vector3) -> void:
	if not nav.is_open(at):
		return
	at.y = nav.height(at.x, at.z)
	water.y = at.y
	_shores.append([at, water])


## Hands to a fire in the cold: the camp fire or the square's, if one's burning.
func _plan_warm(v: Villager) -> bool:
	var fires: Array[Vector3] = []
	for s: Building in _camps:
		if is_instance_valid(s) and (_camps[s] as Node3D).visible and _camp_sleepers(s) > 0:
			fires.append(camp_fire(s))
	for sq in squares():
		if sq.lit:
			fires.append(sq.global_position)
	var best := Vector3.INF
	for f in fires:
		if f.distance_to(v.position) < 120.0 and (best == Vector3.INF or f.distance_to(v.position) < best.distance_to(v.position)):
			best = f
	if best == Vector3.INF:
		return false
	var a := randf() * TAU
	var at := best + Vector3(cos(a), 0, sin(a)) * randf_range(1.6, 2.0)
	at.y = ground_at(at)
	v.give([{"t": "go", "to": at}, {"t": "work", "time": randf_range(15.0, 25.0), "anim": "warm", "face": best}], "Ateşte ısınıyor", null, true)
	return true


## A pipe by its own door (or the store's), stood looking out.
func _plan_pipe(v: Villager) -> bool:
	var b: Building = v.home if is_instance_valid(v.home) and v.home.state == "done" else _nearest(stores(), v.position)
	if b == null:
		return false
	var at := b.door() + b.global_basis.z * 1.4 + b.global_basis.x * randf_range(-1.5, 1.5)
	if not nav.is_open(at):
		return false
	at.y = ground_at(at)
	v.give([{"t": "go", "to": at}, {"t": "work", "time": randf_range(18.0, 30.0), "anim": "pipe", "face": at + b.global_basis.z * 4.0}], "Pipo içiyor", null, true)
	return true


## A child of hers about and at a loose end.
func _child_of(v: Villager) -> Villager:
	for o in villagers:
		if o.is_child and not o.dead and not o.sleeping and o.family == v.family and v.family != "" \
				and (o.plan.is_empty() or o.idle) and o.position.distance_to(v.position) < 40.0:
			return o
	return null


## A mother sat with her child beside her, on the porch or a stump.
func _plan_with_child(v: Villager, kid: Villager) -> bool:
	var s := _seat_near(v)
	if s.is_empty():
		return false
	var face: Vector3 = s.face
	var side := (face - (s.at as Vector3)).cross(Vector3.UP).normalized() * 0.62
	var kid_at: Vector3 = s.at + side
	kid_at.y = nav.height(kid_at.x, kid_at.z)
	if not nav.is_open(kid_at):
		kid_at = s.at - side
		kid_at.y = nav.height(kid_at.x, kid_at.z)
	var time := randf_range(25.0, 40.0)
	_hold_seat(s.at, v, "Çocuğuyla oturuyor")
	v.give([{"t": "go", "to": s.at}, {"t": "step", "to": s.at}, {"t": "work", "time": time, "anim": "sit", "seat": s.h, "face": face}], "Çocuğuyla oturuyor", null, true)
	kid.abort()
	kid.give([{"t": "go", "to": kid_at}, {"t": "step", "to": kid_at},
		{"t": "work", "time": time, "anim": "sit", "seat": float(s.h) + (kid_at.y - (s.at as Vector3).y) * -1.0, "face": face + side}], "Annesiyle oturuyor", null, true)
	return true


## A wash at the well of a morning: a bucket drawn, the water scooped up to the face.
func _plan_wash(v: Villager) -> bool:
	var well := _nearest(_wells(), v.position)
	if well == null or well.global_position.distance_to(v.position) > 120.0:
		return false
	var at := well.door()
	v.give([{"t": "go", "to": at}, {"t": "work", "time": 4.0, "anim": "draw", "face": well.global_position},
		{"t": "work", "time": randf_range(6.0, 9.0), "anim": "wash", "face": well.global_position}], "Kuyuda yıkanıyor", null, true)
	return true


## Stood at one of the graves a while, head bowed.
func _plan_pray(v: Villager) -> bool:
	var i := randi() % cemetery.graves.size()
	var g: Vector3 = cemetery._slot(i)
	var at := g + Basis(Vector3.UP, cemetery._yaw) * Vector3(0, 0, -1.1)
	if g.distance_to(v.position) > 160.0 or not nav.is_open(at):
		return false
	at.y = ground_at(at)
	# knelt at it (or stood, the old and the stiff), crossing oneself as the Orthodox do
	var anim := "cross" if v.has_trait("tembel") or v.look_seed % 4 == 0 else "kneel_cross"
	v.give([{"t": "go", "to": at}, {"t": "step", "to": at}, {"t": "work", "time": randf_range(22.0, 34.0), "anim": anim, "face": g}], "Mezarlıkta dua ediyor", null, true)
	return true


## Stood a few metres off the line looking down it (waiting on the train if it's due).
func _plan_line(v: Villager) -> bool:
	var best := -1
	var bd := 90.0
	for k in range(0, rail.size(), 3):
		var d := rail[k].distance_to(v.position)
		if d < bd:
			bd = d
			best = k
	if best < 0:
		return false
	var p := rail[best]
	var along := (rail[mini(best + 1, rail.size() - 1)] - rail[maxi(best - 1, 0)])
	along.y = 0.0
	along = along.normalized() if along.length() > 0.01 else Vector3.RIGHT
	var side := Vector3(-along.z, 0, along.x)
	if (v.position - p).dot(side) < 0.0:
		side = -side
	var at := p + side * randf_range(4.5, 6.0)
	if not nav.is_open(at):
		return false
	at.y = ground_at(at)
	var due := next_train - day <= 0
	v.give([{"t": "go", "to": at}, {"t": "work", "time": randf_range(12.0, 22.0), "anim": "look", "face": p + along * randf_range(-15.0, 15.0)}],
		"Treni bekliyor" if due else "Demiryoluna bakıyor", null, true)
	return true


## A child at play: tag with another child (the one it's after till it's caught, then the other way
## about), a ring game round and round with two or more, or running about near home.
func _plan_play(v: Villager) -> void:
	var near: Building = v.home if is_instance_valid(v.home) else _nearest(stores(), v.position)
	var at := near.door() if near else v.position
	var kids: Array[Villager] = []
	for o in villagers:
		if o != v and o.is_child and not o.dead and not o.sleeping and (o.plan.is_empty() or (o.idle and o.job == "Oynuyor")) \
				and o.position.distance_to(v.position) < 25.0:
			kids.append(o)
	if life().plan_child(v, kids):
		return
	var mid := v.position.lerp(kids[0].position, 0.5) if not kids.is_empty() else v.position
	if not nav.is_open(mid):
		mid = v.position
	if kids.size() >= 2 and randf() < 0.45:
		var ring := {"center": mid, "r": 1.3 + kids.size() * 0.15, "w": 0.9 * (1.0 if randf() < 0.5 else -1.0), "t0": clock}
		var all: Array[Villager] = [v]
		all.append_array(kids.slice(0, 4))
		var time := randf_range(14.0, 22.0)
		for i in all.size():
			var k: Villager = all[i]
			var a0 := TAU * i / all.size()
			var start: Vector3 = mid + Vector3(cos(a0), 0, sin(a0)) * float(ring.r)
			start.y = ground_at(start)
			k.abort()
			k.give([{"t": "go", "to": start}, {"t": "circle", "ring": ring, "a0": a0, "left": time}], "Halka oyunu oynuyor", null, true)
		return
	if not kids.is_empty() and randf() < 0.7:
		var other := kids[randi() % kids.size()]
		var time := randf_range(18.0, 30.0)
		other.abort()
		other.give([{"t": "flee", "from": v, "left": time + 2.0, "center": mid}], "Kovalamaca oynuyor", null, true)
		v.give([{"t": "work", "time": 1.6, "anim": "look", "face": other.position}, {"t": "chase", "who": other, "left": time, "center": mid}], "Kovalamaca oynuyor", null, true)
		return
	var to := at + Vector3(randf_range(-7, 7), 0, randf_range(1, 8))
	v.give([{"t": "go", "to": to, "run": true}, {"t": "work", "time": randf_range(1.0, 3.0), "anim": "look"}], "Oynuyor", null, true)


## Lunch about noon, supper before dark: once each, at home if it's near (in through the door, a
## while inside), or else sat down where it is with a bowl.
func _meal_key() -> String:
	var h := weather.hour
	if h >= 12.0 and h < 13.2:
		return "%d-o" % day
	if h >= 18.0 and h < 19.2:
		return "%d-a" % day
	return ""


func _plan_meal(v: Villager, key: String) -> void:
	v.meal_key = key
	if v.idle:
		v.abort()
	var h := v.home
	if is_instance_valid(h) and h.state == "done" and not h.is_burning() and h.global_position.distance_to(v.position) < 120.0:
		v.give(life().at_door(_go_in(h), h) + [{"t": "do", "f": func() -> bool:
			v.visible = false
			return true}, {"t": "work", "time": randf_range(10.0, 15.0), "anim": "idle"}, {"t": "do", "f": func() -> bool:
			v.visible = true
			return true}] + _go_out(h), "Evde yemek yiyor", h)
	else:
		v.give([{"t": "work", "time": randf_range(10.0, 15.0), "anim": "eat"}], "Yemek yiyor", null)


func _plan_fire(v: Villager, fires: Array[Building]) -> bool:
	var fire: Building = null
	var fd := INF
	for b in fires:
		var d := b.global_position.distance_to(v.position)
		if d < fd and d < 220.0:
			fd = d
			fire = b
	if fire == null:
		return false
	var wells: Array[Building] = []
	for b in buildings:
		if b.state == "done" and b.def.role == "well":
			wells.append(b)
	var well := _nearest(wells, fire.global_position)
	if well == null or well.global_position.distance_to(fire.global_position) > 160.0:
		if not _no_well_said:
			_no_well_said = true
			message.emit("Yakında kuyu yok: yangın söndürülemiyor!", "bad")
		return false
	_no_well_said = false
	if v.idle or not v.plan.is_empty():
		v.abort()
	v.give([
		{"t": "go", "to": well.door()},
		{"t": "work", "time": 1.4, "anim": "draw", "face": well.global_position},
		{"t": "do", "f": func() -> bool:
			v.set_carry("su", 1)
			return is_instance_valid(fire) and fire.is_burning()},
		{"t": "go", "to": _spot_by(fire, v.position)},
		{"t": "work", "time": 1.1, "anim": "throw", "face": fire.global_position},
		{"t": "do", "f": func() -> bool:
			v.set_carry("", 0)
			if is_instance_valid(fire):
				fire.douse()
			return true},
	], "Yangın söndürüyor", fire)
	return true
