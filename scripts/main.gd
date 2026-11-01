extends Node3D
## The village game: the valley (WorldTerrain, WorldDecor's trees, grass and water, Weather's sky),
## the ways walked across it (Nav), the village on it (Village), seen from above (RtsCamera), and
## the screen over it (Hud). Choosing where to put a building (a ghost that follows the mouse, red
## where it can't go) and picking one to look at happen here.
##
## It starts from the saved game if there is one (VillageSave), else afresh; F5 saves, F9 loads,
## and it saves itself every morning.

static var _load_next := true ## (the next start: from the save if there is one)

var weather: Weather
var terrain: WorldTerrain
var decor: WorldDecor
var nav: Nav
var village: Village
var cam: RtsCamera
var hud: Hud
var raids: Raids
var slides: Landslides
var seasons: Seasons
var atmosphere: Atmosphere
var ambience: Ambience
var critters: Critters
var selected: Building
var selected_villager: Villager
var group: Array[Villager] = [] ## the townsfolk chosen together (Shift+click), the first is selected_villager
var _rings: Array[MeshInstance3D] = []

var _placing := ""
var _ghost: Building
var _ghost_yaw := 0.0
var _ghost_pos := Vector3.ZERO
var _ghost_reason := "x"
var _yaw_manual := false ## R pressed: the player's turning it, not the town
var _road_from: Variant = null ## where a road being dragged began
var _road_line: MeshInstance3D
var _ring: MeshInstance3D
var _menu := false
var _saved_day := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveGame.save_file = "user://village.save"
	var saved := VillageSave.read() if _load_next else {}
	_load_next = true
	if saved.is_empty():
		RutStore.clear() # (a fresh valley)
	else:
		VillageSave.before_world(saved)
	weather = Weather.new()
	weather.hour = 7.5
	weather.day_length_minutes = 16.0
	weather.preset = "clear"
	add_child(weather)
	terrain = WorldTerrain.new()
	add_child(terrain)
	decor = WorldDecor.new()
	decor.terrain = terrain
	add_child(decor)
	nav = Nav.new()
	nav.terrain = terrain
	add_child(nav)
	village = Village.new()
	village.terrain = terrain
	village.props = decor.props
	village.nav = nav
	village.weather = weather
	add_child(village)
	raids = Raids.new()
	raids.village = village
	raids.nav = nav
	raids.terrain = terrain
	raids.weather = weather
	village.raids = raids
	add_child(raids)
	seasons = Seasons.new()
	seasons.weather = weather
	seasons.village = village
	village.seasons = seasons
	add_child(seasons)
	slides = Landslides.new()
	slides.village = village
	slides.terrain = terrain
	slides.props = decor.props
	add_child(slides)
	var start := terrain.spawn.origin
	if saved.is_empty():
		village.start(start)
	for n: Node in [weather, terrain, decor, nav, village, raids, slides, seasons]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE # (this node runs while paused, for the keys: the world doesn't)
	cam = RtsCamera.new()
	cam.terrain = terrain
	cam.focus = start
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cam)
	cam.make_current()
	atmosphere = Atmosphere.new()
	atmosphere.weather = weather
	atmosphere.cam = cam
	atmosphere.seasons = seasons
	atmosphere.village = village
	add_child(atmosphere)
	ambience = Ambience.new()
	ambience.weather = weather
	ambience.cam = cam
	ambience.seasons = seasons
	ambience.terrain = terrain
	add_child(ambience)
	critters = Critters.new()
	critters.village = village
	critters.nav = nav
	critters.weather = weather
	add_child(critters)
	critters.process_mode = Node.PROCESS_MODE_PAUSABLE
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Ui.ACCENT
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = rm
	_ring.visible = false
	add_child(_ring)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	village.message.connect(hud.toast)
	raids.message.connect(hud.toast)
	slides.message.connect(hud.toast)
	seasons.message.connect(hud.toast)
	if saved.is_empty():
		hud.toast("Kasaba kuruldu. Önce bir Kesim kampı ve bir Toplayıcı kur (ÜRETİM). F1: tuşlar", "info")
	else:
		VillageSave.restore(self, saved)
		cam._dist_to = cam.dist
		hud.toast("Kayıt yüklendi: gün %d" % village.day, "good")
	_saved_day = village.day


# --- Input ------------------------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and not e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and _placing == "yol" and _road_from != null:
		var to: Variant = cam.ground_under((e as InputEventMouseButton).position)
		if to != null:
			var got := village.lay_road(_road_from, to)
			if got <= 0.0:
				hud.toast("Depoda odun yok", "bad")
			else:
				hud.toast("Tahta yol döşendi: %d m" % roundi(got), "good")
		_road_from = null
		return
	if e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _placing == "yol":
				_road_from = cam.ground_under(mb.position)
			elif _placing != "":
				_place_here(mb.shift_pressed)
			else:
				_pick(mb.position, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _placing != "":
				stop_placing()
			elif _chosen().any(func(v: Villager) -> bool: return v.drafted):
				_order(mb.position)
			elif selected_villager and is_instance_valid(selected_villager):
				_assign_to(_building_under(mb.position))
			else:
				select(null)
	elif e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		match k.physical_keycode:
			KEY_ESCAPE:
				if hud.help_open():
					hud.toggle_help()
				elif _placing != "":
					stop_placing()
				elif selected or selected_villager:
					select(null)
				else:
					set_menu(not _menu)
			KEY_F1:
				hud.toggle_help()
			KEY_P:
				atmosphere.photo = not atmosphere.photo
				hud.visible = not atmosphere.photo
				_ring.visible = false
			KEY_R:
				_ghost_yaw += deg_to_rad(-15.0 if k.shift_pressed else 15.0)
				_yaw_manual = true
				_ghost_reason = "x"
			KEY_SPACE:
				if not _menu:
					set_speed(Engine.time_scale if get_tree().paused else 0.0)
			KEY_EQUAL, KEY_KP_ADD:
				set_speed(Hud.SPEEDS[mini(Hud.SPEEDS.find(Engine.time_scale) + 1, Hud.SPEEDS.size() - 1)])
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_speed(Hud.SPEEDS[maxi(Hud.SPEEDS.find(Engine.time_scale) - 1, 0)])
			KEY_TAB:
				hud.show_category(hud.category + 1)
			KEY_F:
				ignite_selected()
			KEY_DELETE, KEY_X:
				demolish_selected()
			KEY_F5:
				save_game()
			KEY_F9:
				load_game()
			KEY_O:
				repair_selected()
			KEY_B:
				test_raid()
			KEY_M:
				toggle_militia()
			KEY_G:
				toggle_draft()
			KEY_L:
				toggle_lantern()
			KEY_H:
				var s := village.stores()
				if not s.is_empty():
					cam.jump_to(s[0].global_position)
			_:
				var kind := hud.kind_at(k.physical_keycode - KEY_1)
				if kind != "" and k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_9:
					start_placing(kind)


## 0 pauses; any other runs the game at that speed.
func set_speed(s: float) -> void:
	if _menu:
		return
	if s <= 0.0:
		get_tree().paused = true
		return
	get_tree().paused = false
	Engine.time_scale = s


func set_menu(on: bool) -> void:
	_menu = on
	hud.show_menu(on)
	get_tree().paused = on


func new_game() -> void:
	_load_next = false
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func save_game() -> void:
	if VillageSave.save(self):
		hud.toast("Kaydedildi (gün %d)" % village.day, "good")
	else:
		hud.toast("Kaydedilemedi", "bad")


func load_game() -> void:
	if not VillageSave.exists():
		hud.toast("Kayıt yok", "info")
		return
	_load_next = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# --- Placing ----------------------------------------------------------------------------------------

func start_placing(kind: String) -> void:
	stop_placing()
	select(null)
	_placing = kind
	_yaw_manual = false
	if kind == "yol":
		hud.set_hint("Tahta yol: basılı tutup sürükle, bırakınca döşenir (her 2 m bir odun) · Sağ tık bitir")
		return
	_ghost = Building.new()
	_ghost.setup(kind)
	add_child(_ghost)
	_ghost_reason = "x"
	hud.set_hint("%s: %s · R çevir · Sağ tık iptal" % [BuildingDefs.DEFS[kind].name, BuildingDefs.cost_text(kind)])


func stop_placing() -> void:
	_placing = ""
	_road_from = null
	if _road_line:
		_road_line.visible = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	hud.set_hint("")


func _place_here(keep: bool) -> void:
	if _ghost_reason != "":
		hud.toast(_ghost_reason if _ghost_reason != "x" else "Buraya konmaz", "bad")
		return
	var kind := _placing
	var b := village.place(kind, _ghost_pos, _ghost_yaw)
	hud.toast("%s için yer açıldı: köylüler malzeme taşıyacak" % b.display_name(), "info")
	if not keep:
		stop_placing()
		select(b)
	else:
		_ghost_reason = "x"


func _update_ghost() -> void:
	if _ghost == null:
		return
	var hit: Variant = cam.ground_under(get_viewport().get_mouse_position())
	if hit == null:
		_ghost.visible = false
		return
	_ghost.visible = true
	var p: Vector3 = hit
	p.x = snappedf(p.x, 0.5)
	p.z = snappedf(p.z, 0.5)
	if not _yaw_manual:
		var turned := _auto_yaw(_placing, p)
		if not is_equal_approx(turned, _ghost_yaw):
			_ghost_yaw = turned
			_ghost_reason = "x"
	if p.distance_to(_ghost_pos) < 0.01 and _ghost_reason != "x":
		return
	_ghost_pos = p
	_ghost.global_transform = Transform3D(Basis(Vector3.UP, _ghost_yaw), Vector3(p.x, village.base_height(_placing, p, _ghost_yaw), p.z))
	var reason := village.check(_placing, p, _ghost_yaw)
	if reason != _ghost_reason:
		_ghost.set_ghost(true, reason == "")
		var def: Dictionary = BuildingDefs.DEFS[_placing]
		if reason == "":
			hud.set_hint("%s: %s · %s · Shift+tık üst üste · Sağ tık iptal" % [def.name, BuildingDefs.cost_text(_placing), "R çevir" if _yaw_manual else "kapısı kasabaya dönük (R: elle çevir)"])
		else:
			hud.set_hint(reason, true)
	_ghost_reason = reason


## Which way a building at `p` would face by itself: its door toward the middle of the town (the
## square, else a store, a well), and lined up square with its nearest neighbour when that's near
## enough the same.
func _auto_yaw(kind: String, p: Vector3) -> float:
	var target: Building = null
	var best := 90.0
	for b in village.buildings:
		if b.state == "gone" or b.state == "ghost" or not b.def.role in ["square", "store", "well", "bell"]:
			continue
		var d := b.global_position.distance_to(p) * (0.6 if b.def.role == "square" else 1.0)
		if d < best and d > 1.0:
			best = d
			target = b
	var face := _ghost_yaw
	if target:
		var to := target.global_position - p
		face = atan2(to.x, to.z)
	# lined up with the nearest neighbour
	var nb: Building = null
	var nd := 24.0
	for b in village.buildings:
		if b.state == "gone" or b.def.role in ["farm", "light", "square"]:
			continue
		var d := b.global_position.distance_to(p)
		if d < nd:
			nd = d
			nb = b
	if nb:
		var base := nb.global_rotation.y
		var bestk := face
		var bd := INF
		for k in 4:
			var cand := base + k * PI * 0.5
			var diff := absf(angle_difference(cand, face))
			if diff < bd:
				bd = diff
				bestk = cand
		if bd < 0.75:
			return bestk
	return snappedf(face, deg_to_rad(15.0))


func _update_road_line() -> void:
	if _placing != "yol" or _road_from == null:
		if _road_line:
			_road_line.visible = false
		return
	var to: Variant = cam.ground_under(get_viewport().get_mouse_position())
	if to == null:
		return
	if _road_line == null:
		_road_line = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.8, 0.45, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_road_line.material_override = m
		add_child(_road_line)
	var a: Vector3 = _road_from
	var b: Vector3 = to
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	if flat.length() < 0.2:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.1, flat.length())
	_road_line.mesh = bm
	_road_line.visible = true
	_road_line.global_transform = Transform3D(Basis.looking_at(flat.normalized(), Vector3.UP), (a + b) * 0.5 + Vector3.UP * 0.2)
	hud.set_hint("Tahta yol: %d m · %d odun" % [roundi(flat.length()), ceili(flat.length() / 2.0)])


# --- Picking ----------------------------------------------------------------------------------------

func _pick(at: Vector2, add := false) -> void:
	var folk := _villager_under(at)
	if folk:
		if add and selected_villager and is_instance_valid(selected_villager):
			if folk in group:
				group.erase(folk)
			else:
				group.append(folk)
			return
		select(null)
		selected_villager = folk
		group = [folk]
		return
	select(_building_under(at))


func _building_under(at: Vector2) -> Building:
	var from := cam.project_ray_origin(at)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(at) * 4000.0, 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider as Object).has_meta("building"):
		return null
	return hit.collider.get_meta("building")


## The settler drawn nearest the point on the screen (within a little of it), if any.
func _villager_under(at: Vector2) -> Villager:
	var best: Villager = null
	var bd := 26.0
	for v in village.villagers:
		if v.dead or not v.visible:
			continue
		var p := v.global_position + Vector3.UP * 1.0
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(at)
		if d < bd:
			bd = d
			best = v
	return best


func select(b: Building) -> void:
	selected = b
	selected_villager = null
	group.clear()


## The townsfolk the keys and orders are for: the group, or the one selected.
func _chosen() -> Array[Villager]:
	var out: Array[Villager] = []
	for v in group:
		if is_instance_valid(v) and not v.dead:
			out.append(v)
	if out.is_empty() and selected_villager and is_instance_valid(selected_villager) and not selected_villager.dead:
		out.append(selected_villager)
	return out


func toggle_militia() -> void:
	var list := _chosen()
	if list.is_empty():
		return
	var on := not list[0].militia
	var n := 0
	for v in list:
		if v.is_child:
			continue
		if v.workplace and v.workplace.def.role in ["barracks", "tower"]:
			hud.toast("%s bekçi: zaten tüfekli" % v.display_name, "info")
			continue
		v.militia = on
		if not on and v.drafted:
			v.drafted = false
		n += 1
	if n > 0:
		hud.toast(("%d kişi milis: tehlike çanında silahlıktan tüfek alır" if on else "%d kişi artık milis değil") % n, "good" if on else "info")
	if on and village.armories().is_empty():
		hud.toast("Silahlık yok: önce SAVUNMA'dan silahlık kur", "bad")


## Draft the chosen militia under your orders, or let them go back to their own judgement.
func toggle_draft() -> void:
	var list := _chosen()
	if list.is_empty():
		return
	var on := not list[0].drafted
	for v in list:
		if not v.militia or v.down:
			hud.toast("%s milis değil (önce M)" % v.display_name, "info")
			continue
		if not on:
			v.drafted = false
			v.focus = null
			v.abort()
			continue
		v.drafted = true
		if v.sleeping:
			v.wake()
		v.abort()
		if v.armed:
			village.hold_at(v, village.cover_near(v.position))
		else:
			var a := village.armory_with_rifle(v.position)
			if a:
				village.arm(v, a)
			else:
				hud.toast("Silahlıkta tüfek yok", "bad")
				v.drafted = false
	hud.toast("Toplandı: sağ tık ile mevzi ya da hedef göster" if on else "Bırakıldı", "info")


func toggle_lantern() -> void:
	var list := _chosen()
	if list.is_empty():
		return
	var dark := list[0].lantern_mode != "off"
	for v in list:
		v.lantern_mode = "off" if dark else ""
	hud.toast("Fenerler söndürüldü: karanlıkta görünmezler, ama onlar da az görür" if dark else "Fenerler yanıyor", "info")


## An order to the drafted: a raider clicked is the one to shoot; ground, a post there (behind
## whatever cover's close), spread out a little.
func _order(at: Vector2) -> void:
	var drafted: Array[Villager] = []
	for v in _chosen():
		if v.drafted and not v.down:
			drafted.append(v)
	var foe := _raider_under(at)
	if foe:
		for v in drafted:
			v.focus = foe
		hud.toast("Hedef: %d kişi ona ateş edecek" % drafted.size(), "info")
		return
	var to: Variant = cam.ground_under(at)
	if to == null:
		return
	var p: Vector3 = to
	for i in drafted.size():
		var v := drafted[i]
		var off := Vector3.ZERO if i == 0 else Vector3(cos(i * 2.4), 0, sin(i * 2.4)) * (1.6 + i * 0.4)
		v.focus = null
		v.abort()
		if v.armed:
			village.hold_at(v, village.cover_near(p + off, 3.0))
		else:
			v.give([{"t": "go", "to": p + off}], "Emirle gidiyor")


func _raider_under(at: Vector2) -> Villager:
	var best: Villager = null
	var bd := 30.0
	for r in raids.raiders:
		if not is_instance_valid(r) or r.dead:
			continue
		var p := r.global_position + Vector3.UP * 1.0
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(at)
		if d < bd:
			bd = d
			best = r
	return best


func _assign_to(b: Building) -> void:
	var v := selected_villager
	if b == null:
		hud.toast("Bir işyerine sağ tıkla", "info")
		return
	var why := village.assign(v, b)
	if why != "":
		hud.toast(why, "info")
	else:
		hud.toast("%s artık %s'de çalışıyor" % [v.display_name, b.display_name()], "good")


func test_raid() -> void:
	if not raids.active:
		raids.start(raids.band_size())
		hud.toast("Haydutlar yola çıktı: %d kişi" % raids.raiders.size(), "bad")


func release_selected() -> void:
	if selected_villager and is_instance_valid(selected_villager):
		village.free_from_work(selected_villager)


func focus_selected() -> void:
	if selected_villager and is_instance_valid(selected_villager):
		cam.jump_to(selected_villager.global_position)


func change_workers(d: int) -> void:
	if selected and is_instance_valid(selected):
		village.set_wanted(selected, selected.wanted + d)


func demolish_selected() -> void:
	if selected and is_instance_valid(selected) and selected.state != "gone":
		village.remove_building(selected)
		select(null)


func repair_selected() -> void:
	if selected and is_instance_valid(selected):
		var why := village.repair(selected)
		if why != "":
			hud.toast(why, "info")
		else:
			hud.toast("%s onarılacak: köylüler malzeme taşıyacak" % selected.display_name(), "info")


func ignite_selected() -> void:
	if selected and is_instance_valid(selected) and selected.state in ["done", "site", "ruin"]:
		if not selected.ignite():
			hud.toast("Burada yanacak bir şey yok", "info")


func _process(_dt: float) -> void:
	if village.day != _saved_day and weather.hour > 6.0 and not raids.active:
		_saved_day = village.day
		VillageSave.save(self) # (every morning)
	if _placing == "yol":
		_update_road_line()
	elif _placing != "":
		_update_ghost()
	if selected_villager and is_instance_valid(selected_villager) and not selected_villager.dead and selected_villager.visible:
		_ring.visible = true
		_ring.global_transform = Transform3D(Basis().scaled(Vector3(0.7, 0.4, 0.7)), selected_villager.global_position + Vector3.UP * 0.08)
	elif selected and is_instance_valid(selected) and selected.state != "gone":
		_ring.visible = true
		var r := selected.radius + 0.8
		_ring.global_transform = Transform3D(Basis().scaled(Vector3(r, 0.6, r)), selected.global_position + Vector3.UP * 0.5)
	else:
		_ring.visible = false
		if selected and (not is_instance_valid(selected) or selected.state == "gone"):
			selected = null
	# the others chosen with it, each ringed (red if drafted)
	var others: Array[Villager] = []
	for v in _chosen():
		if v != selected_villager and v.visible:
			others.append(v)
	while _rings.size() < others.size():
		var rr := _ring.duplicate() as MeshInstance3D
		add_child(rr)
		_rings.append(rr)
	for i in _rings.size():
		_rings[i].visible = i < others.size()
		if i < others.size():
			_rings[i].global_transform = Transform3D(Basis().scaled(Vector3(0.7, 0.4, 0.7)), others[i].global_position + Vector3.UP * 0.08)
