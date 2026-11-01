class_name VillageSave
extends RefCounted
## The game kept in `PATH`: the hour and the weather, the store of every building with what's
## fallen off it and what's charred, who lives and works where, the felled trees and their stumps,
## the paths worn into the ground and the scorched earth, when the next raid's due, and where the
## camera was. What's in hand isn't kept: a load on its way to a site goes back to its store, a
## fire goes out, a raid under way is called off (its band comes again the day it's due), and
## the rubble lying about is cleared.

const PATH := "user://village_save.dat"
const VERSION := 1


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func save(game: Node) -> bool:
	game.terrain.save_marks() # (the ruts dug so far, into RutStore)
	var v: Village = game.village
	var nav: Nav = game.nav
	var index := {}
	var bl: Array = []
	for b in v.buildings:
		if b.state == "gone":
			continue
		index[b] = bl.size()
		var alive := PackedByteArray()
		var charred := PackedByteArray()
		var built := PackedByteArray()
		for p in b.pieces:
			alive.append(1 if p.alive or not p.built else 0)
			charred.append(1 if p.charred else 0)
			built.append(1 if p.built else 0)
		var x := b.global_transform
		bl.append({"kind": b.kind, "x": x.origin.x, "z": x.origin.z, "yaw": x.basis.get_euler().y,
			"state": b.state, "work": b.work, "delivered": b.delivered.duplicate(), "goods": b.goods.duplicate(),
			"wanted": b.wanted, "alive": alive, "charred": charred, "built": built,
			"crop": [b.crop.stage, b.crop.sown, b.crop.growth, b.crop.reaped] if b.crop else []})
	# What's on its way to a site goes back to where it came from.
	for vl in v.villagers:
		if vl.owed.is_empty():
			continue
		var from: Variant = vl.owed.get("store")
		if is_instance_valid(from) and index.has(from):
			var g: Dictionary = bl[index[from]].goods
			g[vl.owed.res] = int(g.get(vl.owed.res, 0)) + int(vl.owed.n)
	var people: Array = []
	for vl in v.villagers:
		if vl.dead:
			continue
		var p := vl.position
		if vl.sleeping and is_instance_valid(vl.inside):
			p = vl.inside.door()
		people.append({"x": p.x, "z": p.z, "hp": vl.hp, "child": vl.is_child, "born": vl.born_day,
			"work": index.get(vl.workplace, -1) if vl.workplace else -1,
			"home": index.get(vl.home, -1) if vl.home else -1})
	var stumps: Array = []
	for s: Node3D in v._stumps.get_children():
		stumps.append([s.position.x, s.position.y, s.position.z, ((s as MeshInstance3D).mesh as CylinderMesh).top_radius, int(s.get_meta("prop", -1))])
	var bush := {}
	for i: int in v.bush_rest:
		bush[i] = float(v.bush_rest[i]) - v.clock
	var young := {}
	for i: int in v.saplings:
		young[i] = float(v.saplings[i].left)
	var cam: RtsCamera = game.cam
	var d := {
		"saplings": young,
		"roads": v.roads.duplicate(true),
		"version": VERSION, "day": v.day, "hour": game.weather.hour, "clock": v.clock,
		"raid_next": game.raids.next_day, "season_offset": game.seasons.offset, "cut": RutStore.cut.duplicate(),
		"churned": RutStore.churned.duplicate(), "ruts": RutStore.ruts.duplicate(), "rocks": v.rock_left.duplicate(),
		"bush": bush, "stumps": stumps, "buildings": bl, "people": people,
		"wear": nav.wear.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD), "wear_size": nav.wear.size() * 4,
		"scorch": nav._scorched.duplicate(),
		"cam": [cam.focus.x, cam.focus.y, cam.focus.z, cam.yaw, cam.dist],
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(d)
	return true


static func read() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = f.get_var()
	if not d is Dictionary or int((d as Dictionary).get("version", 0)) != VERSION:
		return {}
	return d


## Before the world's built: the trees that were down.
static func before_world(d: Dictionary) -> void:
	RutStore.ruts = (d.get("ruts", {}) as Dictionary).duplicate()
	RutStore.churned = (d.get("churned", {}) as Dictionary).duplicate()
	RutStore.trail = {}
	RutStore.cut = (d.get("cut", {}) as Dictionary).duplicate()
	RutStore.loaded = true
	RutStore.save_marks()


## Once the world's built: the village as it was.
static func restore(game: Node, d: Dictionary) -> void:
	var v: Village = game.village
	var nav: Nav = game.nav
	v.loading = true
	v.day = int(d.day)
	v.clock = float(d.clock)
	game.weather.hour = float(d.hour)
	game.raids.next_day = maxi(int(d.raid_next), v.day)
	game.seasons.offset = int(d.get("season_offset", 0))
	v.rock_left = (d.rocks as Dictionary).duplicate()
	for i: int in d.bush:
		v.bush_rest[i] = v.clock + float(d.bush[i])
	for s: Array in d.stumps:
		v.add_stump(Vector3(s[0], s[1], s[2]), float(s[3]), int(s[4]) if s.size() > 4 else -1)
	for rd: Array in d.get("roads", []):
		v.lay_road(Vector3(float(rd[0]), 0, float(rd[1])), Vector3(float(rd[2]), 0, float(rd[3])), true)
	var young: Dictionary = d.get("saplings", {})
	for i: int in young:
		v.plant(i, float(young[i]))
	var made: Array[Building] = []
	for bd: Dictionary in d.buildings:
		var b := v.place(str(bd.kind), Vector3(float(bd.x), 0, float(bd.z)), float(bd.yaw))
		made.append(b)
		var st := str(bd.state)
		if st == "site":
			b.restore_site(bd.delivered, bd.get("built", PackedByteArray()))
		else:
			b.complete_now()
			b.apply_damage(bd.alive, bd.charred)
			if st == "ruin":
				b.state = "ruin"
			elif st == "repair":
				b.state = "done" if b.standing_share() >= 0.45 else "ruin"
				if b.start_repair():
					for r: String in bd.delivered:
						if b.delivered.has(r):
							b.delivered[r] = mini(int(bd.delivered[r]), int(b.cost[r]))
					b.work = minf(float(bd.work), b._time() * b.materials_share())
					b._raise()
		for r: String in bd.goods:
			if int(bd.goods[r]) > 0:
				b.add_goods(r, int(bd.goods[r]))
		b.wanted = int(bd.wanted)
		var cr: Array = bd.get("crop", [])
		if b.crop and cr.size() == 4:
			b.crop.stage = str(cr[0])
			b.crop.sown = float(cr[1])
			b.crop.growth = float(cr[2])
			b.crop.reaped = int(cr[3])
			b.crop._draw()
	for pd: Dictionary in d.people:
		var vl := v.spawn_villager(Vector3(float(pd.x), 0, float(pd.z)), bool(pd.get("child", false)))
		vl.born_day = int(pd.get("born", v.day))
		vl.hp = float(pd.hp)
		var w := int(pd.work)
		if w >= 0 and w < made.size() and made[w].state == "done":
			v.employ(vl, made[w])
		var h := int(pd.home)
		if h >= 0 and h < made.size() and made[h].state == "done" and made[h].def.role == "house":
			vl.home = made[h]
			made[h].residents.append(vl)
	v._house_people()
	var raw: PackedByteArray = (d.wear as PackedByteArray).decompress(int(d.wear_size), FileAccess.COMPRESSION_ZSTD)
	nav.restore(raw.to_float32_array(), d.scorch)
	var c: Array = d.cam
	game.cam.focus = Vector3(c[0], c[1], c[2])
	game.cam.yaw = float(c[3])
	game.cam.dist = float(c[4])
	v.loading = false
