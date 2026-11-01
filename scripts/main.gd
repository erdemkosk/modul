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
var selected: Building
var selected_villager: Villager

var _placing := ""
var _ghost: Building
var _ghost_yaw := 0.0
var _ghost_pos := Vector3.ZERO
var _ghost_reason := "x"
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
	if e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _placing != "":
				_place_here(mb.shift_pressed)
			else:
				_pick(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _placing != "":
				stop_placing()
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
			KEY_R:
				_ghost_yaw += deg_to_rad(-15.0 if k.shift_pressed else 15.0)
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
	_ghost = Building.new()
	_ghost.setup(kind)
	add_child(_ghost)
	_ghost_reason = "x"
	hud.set_hint("%s: %s · R çevir · Sağ tık iptal" % [BuildingDefs.DEFS[kind].name, BuildingDefs.cost_text(kind)])


func stop_placing() -> void:
	_placing = ""
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
	if p.distance_to(_ghost_pos) < 0.01 and _ghost_reason != "x":
		return
	_ghost_pos = p
	_ghost.global_transform = Transform3D(Basis(Vector3.UP, _ghost_yaw), Vector3(p.x, village.base_height(_placing, p, _ghost_yaw), p.z))
	var reason := village.check(_placing, p, _ghost_yaw)
	if reason != _ghost_reason:
		_ghost.set_ghost(true, reason == "")
		var def: Dictionary = BuildingDefs.DEFS[_placing]
		if reason == "":
			hud.set_hint("%s: %s · R çevir · Shift+tık üst üste · Sağ tık iptal" % [def.name, BuildingDefs.cost_text(_placing)])
		else:
			hud.set_hint(reason, true)
	_ghost_reason = reason


# --- Picking ----------------------------------------------------------------------------------------

func _pick(at: Vector2) -> void:
	var folk := _villager_under(at)
	if folk:
		select(null)
		selected_villager = folk
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
	if _placing != "":
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
