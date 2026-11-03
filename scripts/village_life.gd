extends "res://scripts/village_base.gd"
## Home and town life: meals, hearths and firewood's warmth, newcomers, the evenings on the square
## and the bell, sleeping (at home or rough by the camp fire), idle hours and chores, children at
## play, fires and lightning.

var _rung := {} ## "<day>-<hour>" -> true: the bell's rung for it


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


func _morning() -> void:
	_births()
	call("_prison_morning") # (village_defense.gd)
	call("_armoury_morning")
	_train_morning()
	_news_morning()
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
	for b in buildings:
		if b.def.role == "house" and b.cold_night:
			b.cold_night = false
			for v in b.residents:
				if is_instance_valid(v) and not v.dead and not v.has_trait("cold"):
					v.hurt(18.0)
					cold += 1
	if cold > 0:
		message.emit("Gece %d kişi soğuk evde üşüdü. Evlere yakacak odun taşınmalı." % cold, "bad")


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
		for o in buildings:
			if o == b or o.state == "gone" or o.is_burning():
				continue
			var gap := b.global_position.distance_to(o.global_position) - b.radius - o.radius
			if gap > 5.0:
				continue
			var dir := (o.global_position - b.global_position).normalized()
			var downwind := clampf(Vector2(wind.x, wind.z).dot(Vector2(dir.x, dir.z)) / 6.0, -0.5, 1.5)
			var chance := 0.0035 * mini(n, 8) * (1.0 + downwind) * clampf(1.0 - gap / 5.0, 0.15, 1.0) * (1.0 - Weather.rain_now * 0.7) * t
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


## Three army bell tents round a camp fire: khaki canvas on a centre pole, guyed out, flaps open.
func _tents(root: Node3D) -> void:
	var canvas := StandardMaterial3D.new()
	canvas.albedo_color = Color(0.47, 0.45, 0.33)
	canvas.roughness = 1.0
	canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pole := Building.material("wood")
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
		var cone := CylinderMesh.new()
		cone.top_radius = 0.06
		cone.bottom_radius = 1.6
		cone.height = 2.3
		cone.radial_segments = 10
		cone.cap_bottom = false
		var t := MeshInstance3D.new()
		t.mesh = cone
		t.material_override = canvas
		t.position = at + Vector3.UP * (g + 1.15)
		t.rotation.y = a
		root.add_child(t)
		var wall := CylinderMesh.new() # (the short wall round its foot)
		wall.top_radius = 1.6
		wall.bottom_radius = 1.62
		wall.height = 0.4
		wall.radial_segments = 10
		wall.cap_top = false
		wall.cap_bottom = false
		var w := MeshInstance3D.new()
		w.mesh = wall
		w.material_override = canvas
		w.position = at + Vector3.UP * (g + 0.2)
		root.add_child(w)
		var p := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.035
		pm.bottom_radius = 0.035
		pm.height = 2.7
		p.mesh = pm
		p.material_override = pole
		p.position = at + Vector3.UP * (g + 1.35)
		root.add_child(p)
		for q in 4: # (guy ropes out to pegs)
			var ga := a + q * TAU / 4.0 + 0.4
			var from := at + Vector3(cos(ga), 0, sin(ga)) * 1.5 + Vector3.UP * (g + 0.45)
			var to := at + Vector3(cos(ga), 0, sin(ga)) * 2.4 + Vector3.UP * g
			var rope := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.015, 0.015, from.distance_to(to))
			rope.mesh = rm
			rope.material_override = pole
			root.add_child(rope)
			rope.position = (from + to) * 0.5
			rope.look_at(root.global_position + to, Vector3.UP)


func _plan_home(v: Villager) -> void:
	var h := v.home
	if v.idle:
		v.abort()
	v.give(_go_in(h) + [{"t": "do", "f": func() -> bool:
		if is_instance_valid(h) and h.state == "done" and not h.is_burning():
			v.sleep_in(h)
		return true}], "Eve gidiyor", h)


## Nothing to do: a while spent as people spend it. A word with someone else standing about, a sit
## on the ground, a stretch, a look round, a stroll.
func _plan_idle(v: Villager) -> void:
	# Of an evening, round the fire on the square.
	var sq := _nearest(squares(), v.position)
	if sq and sq.lit and sq.global_position.distance_to(v.position) < 200.0 and randf() < 0.8:
		var a := randf() * TAU
		var seat := sq.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.2, 3.2)
		seat.y = ground_at(seat)
		v.give([{"t": "go", "to": sq.door()}, {"t": "step", "to": seat},
			{"t": "work", "time": randf_range(15.0, 30.0), "anim": "sit" if randf() < 0.6 else "chat", "face": sq.global_position + Vector3.UP},
			{"t": "do", "f": func() -> bool:
				v.think("fire", "Akşam meydanda ateş başında oturdu", 10.0, maxf(weather.day_length_minutes * 60.0, 60.0))
				return true},
			{"t": "step", "to": sq.door()}], "Meydanda, ateş başında", sq, true)
		return
	var near: Building = v.workplace if v.workplace else _nearest(stores(), v.position)
	var at := near.door() if near else v.position
	var p := at + Vector3(randf_range(-6, 6), 0, randf_range(1.5, 7))
	# Someone else standing about near: go over and talk.
	for o in villagers:
		if o == v or o.dead or o.sleeping or not o.idle or o.job == "Sohbet ediyor":
			continue
		if o.position.distance_to(v.position) < 14.0 and randf() < 0.6:
			var meet := (v.position + o.position) * 0.5
			var dir := (o.position - v.position)
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.1 else Vector3.RIGHT
			var talk := randf_range(7.0, 13.0)
			v.give([{"t": "go", "to": meet - dir * 0.6}, {"t": "work", "time": talk, "anim": "chat", "face": meet + dir}], "Sohbet ediyor", null, true)
			o.give([{"t": "go", "to": meet + dir * 0.6}, {"t": "work", "time": talk, "anim": "chat", "face": meet - dir}], "Sohbet ediyor", null, true)
			return
	# By day, a chore about the house: splitting wood at the block, hanging the washing, hoeing the
	# garden; or a bucket fetched from the well.
	var h := weather.hour
	if not v.is_child and h > 7.0 and h < 19.0 and randf() < 0.6:
		var y := _yard_of(v.home) if is_instance_valid(v.home) else null
		var wells: Array[Building] = []
		for b in buildings:
			if b.state == "done" and b.def.role == "well":
				wells.append(b)
		var well := _nearest(wells, v.position)
		if well and randf() < 0.2:
			v.give([{"t": "go", "to": well.door()},
				{"t": "work", "time": 5.0, "anim": "draw", "face": well.global_position},
				{"t": "do", "f": func() -> bool:
					v.set_carry("su", 1)
					return true},
				{"t": "go", "to": v.home.door() if is_instance_valid(v.home) else v.position + Vector3(4, 0, 4)},
				{"t": "do", "f": func() -> bool:
					v.set_carry("", 0)
					return true}], "Kuyudan su taşıyor", null, true)
			return
		if y:
			var list := y.chores()
			if not list.is_empty():
				var c: Dictionary = list[randi() % list.size()]
				var step := {"t": "work", "time": float(c.time), "anim": c.anim, "face": c.face}
				if c.has("split"):
					var t := [0.0]
					step["tick"] = func(dt: float) -> bool:
						t[0] += dt
						if fmod(t[0], 1.37) < dt and is_instance_valid(y):
							y.split_one()
						return t[0] < float(c.time)
				v.give([{"t": "go", "to": c.at}, step], c.job, null, true)
				return
	var roll := randf()
	var what: Array
	if roll < 0.35:
		what = [{"t": "go", "to": p}, {"t": "work", "time": randf_range(8.0, 15.0), "anim": "sit"}]
	elif roll < 0.5:
		what = [{"t": "go", "to": p}, {"t": "work", "time": 2.5, "anim": "stretch"}, {"t": "work", "time": randf_range(3.0, 6.0), "anim": "idle"}]
	elif roll < 0.75:
		what = [{"t": "go", "to": p}, {"t": "work", "time": randf_range(4.0, 8.0), "anim": "look"}]
	else:
		what = [{"t": "go", "to": p}, {"t": "work", "time": randf_range(2.0, 5.0), "anim": "idle"}, {"t": "go", "to": at + Vector3(randf_range(-8, 8), 0, randf_range(1.5, 9))}]
	v.give(what, "Boşta", null, true)


## A child at play: running about near home, after the other children if there are any.
func _plan_play(v: Villager) -> void:
	var near: Building = v.home if is_instance_valid(v.home) else _nearest(stores(), v.position)
	var at := near.door() if near else v.position
	var other: Villager = null
	for o in villagers:
		if o != v and o.is_child and not o.sleeping and o.position.distance_to(v.position) < 25.0:
			other = o
	var to := (other.position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))) if other and randf() < 0.6 else at + Vector3(randf_range(-7, 7), 0, randf_range(1, 8))
	v.give([{"t": "go", "to": to}, {"t": "work", "time": randf_range(1.0, 3.0), "anim": "chat" if other else "look"}], "Oynuyor", null, true)


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
		v.give(_go_in(h) + [{"t": "do", "f": func() -> bool:
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
