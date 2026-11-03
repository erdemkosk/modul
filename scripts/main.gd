extends Node3D
## The village game: the valley (WorldTerrain, WorldDecor's trees, grass and water, Weather's sky),
## the ways walked across it (Nav), the village on it (Village), seen from above (RtsCamera), and
## the screen over it (Hud). Choosing where to put a building (a ghost that follows the mouse, red
## where it can't go) and picking one to look at happen here.
##
## It starts from the saved game if there is one (VillageSave), else afresh; F5 saves, F9 loads,
## and it saves itself every morning.

static var _load_next := true ## (the next start: from the save if there is one)
static var next_seed := 0 ## the seed the next new valley is made with (0: a random one)
static var title := true ## the title screen first (at launch, and from the menu's YENİ OYUN)
var _titled := false ## this one's only the title screen (no valley made)
var _cam_free := false ## the player's taken the view (it stops riding with the train)
static var start_with := {"people": 6, "supplies": 1.0, "raids": 1, "season": 0} ## the new town's settings

var weather: Weather
var terrain: WorldTerrain
var decor: WorldDecor
var nav: Nav
var village: Village
var cam: RtsCamera
var hud: Hud
var raids: Raids
var seasons: Seasons
var atmosphere: Atmosphere
var ambience: Ambience
var critters: Critters
var selected: Building
var selected_villager: Villager
var selected_wall: Wall
var group: Array[Villager] = [] ## the townsfolk chosen together (Shift+click), the first is selected_villager
var _rings: Array[MeshInstance3D] = []

var _placing := ""
var _placing_mode := "" ## a workshop being placed: the mode it's to have (iron, coal)
var _ghost: Building
var _ghost_yaw := 0.0
var _ghost_pos := Vector3.ZERO
var _ghost_reason := "x"
var _yaw_manual := false ## R pressed: the player's turning it, not the town
var _road_pts: Array = [] ## the road being laid out: its points so far (clicks)
var _road_dir := Vector3.ZERO ## the way the road it starts from runs (it bends away smoothly)
var _road_line: MultiMeshInstance3D ## its planks, shown before they're laid
var _ring: MeshInstance3D
var _menu := false
var _saved_day := -1


var _loading := false ## (the world being made under the loading screen)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Graphics.apply(get_tree()) # (before the world's made: the trees' detail is read as it's built)
	Settings.apply()
	if not get_tree().root.size_changed.is_connected(_on_resized):
		get_tree().root.size_changed.connect(_on_resized)
	if title:
		_titled = true
		var menu := TitleMenu.new()
		menu.game = self
		add_child(menu)
		return
	_loading = true # (the world's made a step at a time under the loading screen; nothing runs on it till it's done)
	var screen := LoadingScreen.new()
	add_child(screen)
	await screen.step("Yolculuk başlıyor", 0.02)
	SaveGame.save_file = "user://village.save"
	var saved := VillageSave.read() if _load_next else {}
	_load_next = true
	if saved.is_empty():
		RutStore.clear() # (a fresh valley)
		if next_seed == 0:
			randomize()
			next_seed = randi_range(1, 999999)
		WorldTerrain.seed = next_seed
		next_seed = 0
	else:
		VillageSave.before_world(saved)
	weather = Weather.new()
	weather.hour = 7.5
	weather.day_length_minutes = 16.0
	weather.preset = "clear"
	add_child(weather)
	Graphics.apply(get_tree(), weather)
	await screen.step("Vadi çiziliyor: dağlar, nehir, göl", 0.08)
	terrain = WorldTerrain.new()
	add_child(terrain)
	await screen.step("Orman dikiliyor", 0.4)
	decor = WorldDecor.new()
	decor.terrain = terrain
	add_child(decor)
	await screen.step("Patikalar açılıyor", 0.75)
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
	await screen.step("Kasaba kuruluyor" if saved.is_empty() else "Kasaba yükleniyor", 0.85)
	var start := terrain.spawn.origin
	village.seed = WorldTerrain.seed
	if saved.is_empty():
		village.start_people = int(start_with.people)
		village.start_crew = start_with.get("crew", [])
		village.supplies = float(start_with.supplies)
		raids.level = int(start_with.raids)
		raids.next_day = [10, 8, 6][raids.level] # (a week or so to settle in before anyone comes)
		if int(start_with.season) != 0:
			seasons.force(int(start_with.season))
		village.start(start)
		if village.station_at() != Vector3.INF:
			start = village.station_at()
	for n: Node in [weather, terrain, decor, nav, village, raids, seasons]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE # (this node runs while paused, for the keys: the world doesn't)
	cam = RtsCamera.new()
	cam.terrain = terrain
	cam.focus = start
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cam)
	cam.make_current()
	Settings.apply(cam)
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
	ambience.village = village
	add_child(ambience)
	critters = Critters.new()
	critters.village = village
	critters.nav = nav
	critters.weather = weather
	add_child(critters)
	critters.process_mode = Node.PROCESS_MODE_PAUSABLE
	var wild := Wildlife.new()
	wild.village = village
	wild.nav = nav
	add_child(wild)
	wild.process_mode = Node.PROCESS_MODE_PAUSABLE
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
	raids.hud = hud
	village.hud = hud
	seasons.message.connect(hud.toast)
	if saved.is_empty():
		hud.toast("Kasaba kuruldu. Önce bir Kesim kampı ve bir Toplayıcı kur (ÜRETİM). F1: tuşlar", "info")
	else:
		await screen.step("Kasabalılar yerine dönüyor", 0.93)
		VillageSave.restore(self, saved)
		cam._dist_to = cam.dist
		hud.toast("Kayıt yüklendi: gün %d" % village.day, "good")
	_saved_day = village.day
	_loading = false
	screen.finish()


# --- Input ------------------------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if _titled or _loading:
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
		_cam_free = true
	if e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if AREA_ORDERS.has(_placing):
				_drag_from = cam.ground_under(mb.position)
			elif _placing in ["yol", "sur"]:
				_road_click(mb.position)
			elif _placing == "kapi":
				var to: Variant = cam.ground_under(mb.position)
				if to != null:
					var why := village.add_gate_at(to)
					hud.toast(why if why != "" else "Sur kapısı kondu", "bad" if why != "" else "good")
			elif _placing != "":
				_place_here(mb.shift_pressed)
			else:
				_pick(mb.position, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _placing in ["yol", "sur"] and _road_pts.size() >= 2:
				_road_finish()
			elif _placing != "":
				stop_placing()
			elif _chosen().any(func(v: Villager) -> bool: return v.drafted):
				_order(mb.position)
			elif selected_villager and is_instance_valid(selected_villager):
				_assign_to(_building_under(mb.position))
			else:
				select(null)
	elif e is InputEventMouseButton and not e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and _drag_from != null:
		_area_done(cam.ground_under((e as InputEventMouseButton).position))
	elif e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		match k.physical_keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if _placing in ["yol", "sur"] and _road_pts.size() >= 2:
					_road_finish()
			KEY_BACKSPACE:
				if _placing in ["yol", "sur"] and not _road_pts.is_empty():
					_road_pts.pop_back()
			KEY_ESCAPE:
				if hud.help_open():
					hud.toggle_help()
				elif hud.people_open():
					hud.toggle_people()
				elif hud.tech_open():
					hud.toggle_tech()
				elif hud.telegraph_open():
					hud.toggle_telegraph()
				elif hud.log_open():
					hud.toggle_log()
				elif _placing != "":
					stop_placing()
				elif selected or selected_villager:
					select(null)
				else:
					set_menu(not _menu)
			KEY_F1:
				hud.toggle_help()
			KEY_P:
				# off → a picture → an old photograph → off
				if not atmosphere.photo:
					atmosphere.photo = true
					atmosphere.sepia = false
				elif not atmosphere.sepia:
					atmosphere.sepia = true
				else:
					atmosphere.photo = false
					atmosphere.sepia = false
				hud.visible = not atmosphere.photo
				_ring.visible = false
			KEY_R:
				if _placing == "" and selected_villager and is_instance_valid(selected_villager):
					toggle_control()
				else:
					rotate_ghost(-15.0 if k.shift_pressed else 15.0)
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
			KEY_N:
				test_build()
			KEY_K:
				hud.toggle_people()
			KEY_T:
				hud.toggle_tech()
			KEY_J:
				hud.toggle_log()
			KEY_V:
				select_militia()
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


## A town begun with the title screen's settings.
func begin_new(settings: Dictionary) -> void:
	title = false
	_load_next = false
	next_seed = int(settings.seed)
	start_with = settings
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func continue_game() -> void:
	title = false
	_load_next = true
	get_tree().paused = false
	get_tree().reload_current_scene()


## Back to the title screen, to set a new town going.
func new_game() -> void:
	title = true
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

## The orders drawn on the ground as a box dragged out with the mouse (not buildings).
const AREA_ORDERS := {"mayin": "MAYIN: bir alan sürükle ya da bir yere tıkla: gizli kara mayınları (mayın başı 1 demir, 1 kömür) · sağ tık / Esc: bitir", "hendek": "HENDEK: bir çizgi sürükle: boştaki köylüler siper hendeği kazar · sağ tık / Esc: bitir", "kes": "KES: bir alan sürükle ya da bir ağaca tıkla: herkes işini bırakıp önce bunları keser · sağ tık / Esc: bitir",
	"tuzak": "TUZAK: bir alan sürükle ya da bir yere tıkla: gizli kazık çukurları (çukur başı 2 odun; bozulanı yeniden kurar) · sağ tık / Esc: bitir",
	"kesme": "KESME: bir alan sürükle, içindeki ağaçların kesim işareti kalksın · sağ tık / Esc: bitir",
	"alan": "ALAN ÇİZ: bu işyerinin işçileri yalnızca sürüklediğin alanda çalışsın · sağ tık / Esc: vazgeç"}
var _drag_from: Variant = null ## where a box being dragged out began (the ground), or null
var _drag_box: MeshInstance3D
var _area_box: MeshInstance3D ## the selected workplace's drawn work area
var _area_for: Building ## (ALAN ÇİZ: the workplace it's for)


func start_placing(kind: String) -> void:
	var was := selected
	stop_placing()
	_placing_mode = ""
	select(null)
	_placing = kind
	_yaw_manual = false
	if AREA_ORDERS.has(kind):
		_area_for = was if kind == "alan" else null
		hud.set_hint(str(AREA_ORDERS[kind]))
		return
	if kind in ["yol", "sur"]:
		hud.set_hint("%s: sol tık ile başla, sol tık ile köşe ekle · sağ tık / Enter: bitir · Geri: son köşeyi sil · Esc: vazgeç" % BuildingDefs.DEFS[kind].name)
		return
	if kind == "kapi":
		hud.set_hint("Sur kapısı: bir surun üstüne tıkla (6 odun) · sağ tık / Esc: vazgeç")
		return
	var needs := str(BuildingDefs.DEFS[kind].get("needs", ""))
	if not village.knows(needs):
		_placing = ""
		hud.toast("Kilitli: önce okuma odasında %s araştırılmalı" % BuildingDefs.TECHS[needs].name, "bad")
		return
	_ghost = Building.new()
	_ghost.setup(kind)
	add_child(_ghost)
	_ghost_reason = "x"
	hud.set_hint("%s: %s · R çevir · Sağ tık iptal" % [BuildingDefs.DEFS[kind].name, BuildingDefs.cost_text(kind)])


func stop_placing() -> void:
	_placing = ""
	_show_guide(Vector3.INF, Vector3.INF)
	_drag_from = null
	if _marks_mm:
		_marks_mm.visible = false
	if _drag_box:
		_drag_box.visible = false
	_road_pts.clear()
	_road_dir = Vector3.ZERO
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
	if kind in BuildingDefs.WORKSHOP_KINDS:
		b.mode = _placing_mode
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
	if not Input.is_key_pressed(KEY_ALT):
		p = _line_up(_placing, p, _ghost_yaw)
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


## Placing beside a building facing the same way (or square to it): pulled into line with it, its
## front on the same line and an even 2 m between their walls when it's near that, a brass guide
## line drawn between them while it holds. Alt held: no pulling.
var _guide: MeshInstance3D


func _line_up(kind: String, p: Vector3, yaw: float) -> Vector3:
	var sz: Vector2 = BuildingDefs.DEFS[kind].size
	if BuildingDefs.DEFS[kind].role in ["farm", "light", "wall", "gate", "road", "obstacle"]:
		_show_guide(Vector3.INF, Vector3.INF)
		return p
	var best: Building = null
	var bd := 18.0
	for b in village.buildings:
		if b.state == "gone" or b.state == "ghost" or b.def.role in ["farm", "light", "square"]:
			continue
		var d := b.global_position.distance_to(p)
		if d < bd and absf(angle_difference(fposmod(b.global_rotation.y - yaw + PI * 0.25, PI * 0.5) - PI * 0.25, 0.0)) < 0.05:
			bd = d
			best = b
	if best == null:
		_show_guide(Vector3.INF, Vector3.INF)
		return p
	var bs: Vector2 = best.def.size
	var local := best.global_transform.affine_inverse() * p
	var snapped := false
	# beside it (along its x): the fronts in a line, an even gap between the walls
	var half_x := bs.x * 0.5 + sz.x * 0.5
	if absf(local.z) < 1.6 and absf(absf(local.x) - (half_x + 2.0)) < 1.6:
		local.z = (bs.y * 0.5) - (sz.y * 0.5) # (fronts flush: the doors on one line)
		local.x = signf(local.x) * (half_x + 2.0)
		snapped = true
	# behind or in front (along its z): side by side in a column, the same gap
	var half_z := bs.y * 0.5 + sz.y * 0.5
	if not snapped and absf(local.x) < 1.6 and absf(absf(local.z) - (half_z + 2.0)) < 1.6:
		local.x = 0.0
		local.z = signf(local.z) * (half_z + 2.0)
		snapped = true
	if not snapped:
		_show_guide(Vector3.INF, Vector3.INF)
		return p
	var out := best.global_transform * local
	out.y = p.y
	_show_guide(best.global_position, out)
	return out


func _show_guide(a: Vector3, b: Vector3) -> void:
	if _guide == null:
		_guide = MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.8, 0.35, 0.8)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.05, 1.0)
		bm.material = m
		_guide.mesh = bm
		_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_guide)
	if a == Vector3.INF or _ghost == null:
		_guide.visible = false
		return
	a.y = village.nav.height(a.x, a.z) + 0.15
	b.y = village.nav.height(b.x, b.z) + 0.15
	_guide.visible = true
	_guide.global_position = (a + b) * 0.5
	_guide.look_at(b, Vector3.UP)
	_guide.scale = Vector3(1, 1, a.distance_to(b))


## Which way a building at `p` would face by itself: beside a road, its door square onto the road
## (a street of houses); else its door toward the middle of the town (the square, else a store, a
## well), lined up square with its nearest neighbour when that's near enough the same.
func _auto_yaw(kind: String, p: Vector3) -> float:
	var depth: float = (BuildingDefs.DEFS[kind].size as Vector2).y
	var road := village.road_snap(p, depth * 0.5 + 9.0)
	if not road.is_empty() and not BuildingDefs.DEFS[kind].role in ["farm", "light"]:
		var to: Vector3 = (road.at as Vector3) - p
		to.y = 0.0
		var dir: Vector3 = road.dir
		var side := Vector3(-dir.z, 0.0, dir.x) # (square to the road, the side it stands on)
		if side.dot(to) < 0.0:
			side = -side
		return atan2(side.x, side.z)
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


## A road's next point where clicked: the first one taken onto a road already there if one's close
## (the new one leaves it bending smoothly away), any other onto a road it comes to.
func _road_click(at: Vector2) -> void:
	var p: Variant = cam.ground_under(at)
	if p == null:
		return
	var snap := village.road_snap(p, 3.0)
	if not snap.is_empty():
		p = snap.at
		if _road_pts.is_empty() and snap.end:
			_road_dir = snap.dir # (carried on from a road's end: it bends on from it; from its side it branches straight off)
	_road_pts.append(p)


## The palisade as it would stand, to the mouse: its stakes, faint.
## The palisade as it would stand along `line`: its stakes, pale as far as the wood goes, red past.
func _wall_ghost(line: PackedVector3Array, into: MultiMeshInstance3D) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Wall.stake_mesh()
	mm.instance_count = line.size()
	var afford := int(village.stock.get("odun", 0)) * Wall.WOOD_PER
	for k in line.size():
		var g := line[k]
		g.y = village.nav.height(g.x, g.z) - 0.3
		var h := fposmod(sin(k * 78.233) * 43758.5453, 1.0)
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, h * TAU).scaled(Vector3(1, 0.9 + h * 0.2, 1)), g))
		mm.set_instance_color(k, Color(0.75, 1.0, 0.7, 0.45) if k < afford else Color(1.0, 0.35, 0.3, 0.45))
	var mi := into if into else MultiMeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mi.get_parent() == null:
		add_child(mi)
	return mi


func _road_finish() -> void:
	if _placing == "sur":
		var w := village.lay_wall(_road_pts, _road_dir)
		if w:
			hud.toast("Sur çizildi: %d kazık, %d kapı · kasabalılar dikecek" % [w.line.size(), w.gates.size()], "good")
		_road_pts.clear()
		_road_dir = Vector3.ZERO
		return
	var got := village.lay_path(_road_pts, false, _road_dir)
	if got <= 0.0:
		hud.toast("Depoda odun yok", "bad")
	else:
		hud.toast("Tahta yol döşendi: %d m" % roundi(got), "good")
	_road_pts.clear()
	_road_dir = Vector3.ZERO


## The road as it would be laid, to the mouse: its planks, green as far as the wood goes, red past.
func _update_road_line() -> void:
	if _placing == "sur" and _road_pts.is_empty():
		# (before the first corner: a stretch of it under the mouse, so it's seen what's being put down)
		var at: Variant = cam.ground_under(get_viewport().get_mouse_position())
		if at != null:
			var across := cam.global_basis.x
			across.y = 0.0
			across = across.normalized() * 1.5
			var pts := PackedVector3Array()
			for k in 11:
				pts.append((at as Vector3) - across + across * 2.0 * k / 10.0)
			_road_line = _wall_ghost(pts, _road_line)
			_road_line.visible = true
	if not _placing in ["yol", "sur"] or _road_pts.is_empty():
		if _road_line and _placing != "sur":
			_road_line.visible = false
		if _placing == "sur":
			hud.set_hint("Kazık sur: sol tık ile başla, köşeleri tıkla, sağ tık / Enter: bitir · yolu kestiği yere kapı konur · Esc: vazgeç")
		elif _placing == "yol":
			hud.set_hint("Tahta yol: sol tık ile başla (bir yolun yanından başlarsan ondan kıvrılarak ayrılır) · Esc: vazgeç")
		return
	var to: Variant = cam.ground_under(get_viewport().get_mouse_position())
	if to == null:
		return
	var snap := village.road_snap(to, 3.0)
	if not snap.is_empty():
		to = snap.at
	var pts := _road_pts.duplicate()
	pts.append(to)
	var line := village.road_curve(pts, _road_dir)
	if line.size() < 2:
		return
	var wood := int(village.stock.get("odun", 0))
	if _placing == "sur":
		_road_line = _wall_ghost(line, _road_line)
		_road_line.visible = true
		hud.set_hint("Kazık sur: %d m · %d kazık · %d odun (kasabalılar parça parça diker) · sol tık: köşe · sağ tık / Enter: bitir · Esc: vazgeç" % [roundi((line.size() - 1) * village.ROAD_STEP), line.size(), ceili(line.size() / float(Wall.WOOD_PER))])
		return
	var afford := int(wood * 2.0 / village.ROAD_STEP)
	if _road_line:
		_road_line.material_override = null
	_road_line = village._road_mesh(line, true, afford, _road_line)
	_road_line.visible = true
	var metres := (line.size() - 1) * village.ROAD_STEP
	var cost := ceili(metres / 2.0)
	hud.set_hint("Tahta yol: %d m · %d odun%s · sol tık: köşe · sağ tık / Enter: döşe · Geri: köşe sil · Esc: vazgeç" % [roundi(metres), cost,
		"" if cost <= wood else " (depoda %d var: kırmızısı döşenmez)" % wood], cost > wood)


# --- Picking ----------------------------------------------------------------------------------------

func _pick(at: Vector2, add := false) -> void:
	var b := _building_under(at)
	if b == null and _villager_under(at) == null:
		var p: Variant = cam.ground_under(at)
		if p != null:
			for w in village.walls:
				if is_instance_valid(w):
					var n := w.nearest(p)
					if not n.is_empty() and float(n.dist) < 2.0:
						select(null)
						selected_wall = w
						return
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
	selected_wall = null
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


## One more to train at the selected armoury ("rifle", "bow"; "" empties the queue).
func train(kind: String) -> void:
	if selected == null or not is_instance_valid(selected) or selected.kind != "silahlik":
		return
	if kind == "":
		selected.training.clear()
		hud.toast("Yetiştirme sırası boşaltıldı", "info")
		return
	selected.training.append(kind)
	var have := village._weapon_at(selected, kind) != ""
	hud.toast(("Sıraya bir %s eklendi" % ("tüfekçi" if kind == "rifle" else "okçu")) + ("" if have else (": rafta %s yok, gelince başlar" % ("tüfek" if kind == "rifle" else "yay ya da ok"))), "good" if have else "info")


func toggle_militia() -> void:
	var list := _chosen()
	if list.is_empty():
		return
	var on := not list[0].militia
	var n := 0
	for v in list:
		if v.is_child:
			continue
		if on and v.has_trait("coward"):
			hud.toast("%s korkak: milis olmaz" % v.display_name, "info")
			continue
		if on and v.has_trait("no_rifle"):
			hud.toast("%s tek kollu: silah tutamaz" % v.display_name, "info")
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
			var a: Building = village.armory_for(v)
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
## The test panel's events, at once.
func test_event(what: String) -> void:
	var v := village
	var side := "merkez" if randf() < 0.5 else "isyan"
	match what:
		"convoy_tank", "convoy", "convoy_hostile":
			if is_instance_valid(v.convoy):
				hud.toast("Zaten bir konvoy yolda", "info")
				return
			if what == "convoy_hostile":
				v._shift(side, -60)
			v.send_convoy(side, what != "convoy")
		"armoured", "armoured_hostile":
			if is_instance_valid(v.train):
				v.train.queue_free()
			if is_instance_valid(v.armoured):
				hud.toast("Zaten bir zırhlı tren var", "info")
				return
			if what == "armoured_hostile":
				v._shift(side, -60)
			v.send_armoured(side)
		"camp":
			if raids.camp_at != Vector3.INF:
				raids._camp_found("")
				return
			var home: Vector3 = v.stores()[0].global_position if not v.stores().is_empty() else Vector3.ZERO
			for k in 30:
				var a := randf() * TAU
				var p := home + Vector3(cos(a), 0, sin(a)) * randf_range(90.0, 140.0)
				if v.nav.is_open(p):
					p.y = v.nav.height(p.x, p.z)
					raids.make_camp(p, 4, false)
					raids._camp_found("")
					return
		"help":
			if is_instance_valid(v.relief):
				hud.toast("Yardım zaten burada", "info")
				return
			if v.standing(side) < Village.FRIENDLY:
				v._shift(side, Village.FRIENDLY + 15 - v.standing(side))
			v._send_relief(side)
		"beg":
			raids.next_day = v.day + 1
			raids._asked_for = -1
			raids._ask_food()
		"news":
			v._news_last = -10
			v._news_morning(["zirhli", "yarali", "devriye", "yardim"].pick_random())
		"mail":
			if v.depot():
				v._mail(v.depot())
		"douse":
			v.grass_fires.douse_all()
			var n := 0
			for b in v.buildings:
				if b.is_burning():
					n += 1
					for p in b.pieces:
						if p.burn > 0.0:
							p.burn = 0.0
							p.wet = 30.0
					if b.crop:
						b.crop.burning = 0.0
						for f in b.crop._flames:
							f.emitting = false
			hud.toast("%d bina söndürüldü" % n, "good")
		"techs":
			for t: String in BuildingDefs.TECHS:
				if not v.knows(t):
					v.known.append(t)
			hud.toast("Bütün araştırmalar açıldı", "good")
		"stock":
			var st: Vector3 = v.stores()[0].global_position if not v.stores().is_empty() else Vector3.ZERO
			for r: String in ["odun", "tas", "yiyecek", "kerpic", "komur", "demir", "ot"]:
				v.add_anywhere(r, 100, st)
			v.rubles += 200
			hud.toast("Her maldan 100, kasaya 200 mirka", "good")


## Every militiaman picked at once (V), to be sent together.
func select_militia() -> void:
	var list: Array[Villager] = []
	for v in village.villagers:
		if not v.dead and not v.down and (v.militia or v.drafted):
			list.append(v)
	if list.is_empty():
		hud.toast("Milis yok: bir kasabalının kartından MİLİS YAP (M)", "info")
		return
	select(null)
	group.clear()
	group.append_array(list)
	selected_villager = list[0]
	hud.toast("%d milis seçili: sağ tıkla mevzi göster" % list.size(), "info")


## The selected one taken in hand (R), or let go again.
func toggle_control() -> void:
	var v := selected_villager
	if v == null or not is_instance_valid(v) or v.is_child or v.down:
		return
	if village.controlled(v):
		village.release_control(v)
		hud.toast("%s yine kendi işinde" % v.display_name, "info")
	else:
		village.take_control(v)
		hud.toast("%s emrinde: sağ tık git / saldır / binaya gir · kartta SİLAH AL, SİPER, SAKLAN, TAŞI · R bırak" % v.display_name.split(" ")[0], "good")


## A card order for the one in hand: "weapon", "cover", "hide", "carry".
func control_order(what: String) -> void:
	var v := selected_villager
	if v == null or not is_instance_valid(v):
		return
	if not village.controlled(v):
		village.take_control(v)
	var why := ""
	match what:
		"weapon": why = village.ctl_weapon(v)
		"cover": village.ctl_cover(v)
		"hide": why = village.ctl_hide(v)
		"carry": why = village.ctl_carry(v)
	if why != "":
		hud.toast(why, "info")


func _order(at: Vector2) -> void:
	var drafted: Array[Villager] = []
	for v in _chosen():
		if v.drafted and not v.down:
			drafted.append(v)
	var foe := _raider_under(at)
	if foe:
		for v in drafted:
			v.focus = foe
			if not v.armed: # (bare-handed: it goes for him)
				v.abort()
				v.give([{"t": "fight", "foe": foe, "give_up": 60.0}], "Saldırıyor")
		hud.toast("Hedef: %d kişi ona ateş edecek" % drafted.size(), "info")
		return
	# a building under it, for the one in hand: the armoury to arm at, a house to hide in
	var b := _building_under(at)
	if b and drafted.size() == 1 and village.controlled(drafted[0]) and b.state == "done":
		var v := drafted[0]
		if b.def.role == "barracks" and not v.armed:
			if village._weapon_at(b, "") == "":
				hud.toast("%s rafında silah yok" % b.display_name(), "info")
			else:
				v.abort()
				village.arm(v, b, false)
			return
		if b.def.role in ["house", "store", "barracks"]:
			village.ctl_hide(v, b)
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
	for r in raids.raiders + raids.camp_men:
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


## (A test, to come out later: N, DENEME's İNŞAATI BİTİR) every building site and mending
## finished at once, whatever's been carried to it.
func test_build() -> void:
	var n := 0
	for b in village.buildings.duplicate():
		if b.state == "site":
			b.complete_now()
		elif b.state == "repair":
			for r: String in b.cost:
				b.delivered[r] = b.cost[r]
			b.work = b._time()
			b._raise()
			b._finish()
		else:
			continue
		village._let_go(b)
		n += 1
	# the palisades every stretch up, broken gates mended, the trenches dug
	for w in village.walls:
		if not is_instance_valid(w):
			continue
		var raised := false
		for st in w.stretches():
			if w.left_in(st) > 0:
				w.raise(st)
				raised = true
		for g in w.gates:
			if is_instance_valid(g) and g.broken:
				g.mend()
				raised = true
		if raised:
			n += 1
	for t: Dictionary in village.trenches:
		if float(t.done) < 1.0:
			village.dig_on(t, 1.0)
			n += 1
	hud.toast("%d inşaat bitirildi" % n if n > 0 else "Yapımda bir şey yok", "good" if n > 0 else "info")


func test_raid() -> void:
	if not raids.active:
		raids.start(raids.band_size())
		hud.toast("Firariler yola çıktı: %d kişi" % raids.raiders.size(), "bad")


func release_selected() -> void:
	if selected_villager and is_instance_valid(selected_villager):
		village.free_from_work(selected_villager)


func focus_building() -> void:
	if selected_wall and is_instance_valid(selected_wall):
		cam.jump_to(selected_wall.line[selected_wall.line.size() / 2])
		return
	if selected and is_instance_valid(selected):
		cam.jump_to(selected.global_position)


## The ghost turned by `deg` (the placing panel's buttons, R).
func rotate_ghost(deg: float) -> void:
	_ghost_yaw += deg_to_rad(deg)
	_yaw_manual = true
	_ghost_reason = "x"


func focus_selected() -> void:
	if selected_villager and is_instance_valid(selected_villager):
		cam.jump_to(selected_villager.global_position)


func change_workers(d: int) -> void:
	if selected and is_instance_valid(selected):
		village.set_wanted(selected, selected.wanted + d)


## The selected palisade made stronger, if the stores can cover it.
func strengthen_wall() -> void:
	var w := selected_wall
	if w == null or not is_instance_valid(w) or w.level >= 2:
		return
	var cost := w.strengthen_cost()
	for r: String in cost:
		if int(village.stock.get(r, 0)) < int(cost[r]):
			hud.toast("Güçlendirmek için %s gerek" % BuildingDefs.cost_text_of(cost), "info")
			return
	for r: String in cost:
		var left := int(cost[r])
		while left > 0:
			var s := village.store_with(r, w.line[0])
			if s == null:
				break
			left -= s.take_goods(r, left)
	w.strengthen()
	hud.toast("Sur güçlendirildi: kalın kütükler, taş temel", "good")


func demolish_selected() -> void:
	if selected_wall and is_instance_valid(selected_wall):
		var up := 0
		for k in selected_wall.built:
			if k == 1:
				up += 1
		var back := up / Wall.WOOD_PER / 2
		village.add_anywhere("odun", back, selected_wall.line[0])
		village.walls.erase(selected_wall)
		selected_wall.pull_down()
		selected_wall = null
		hud.toast("Sur söküldü: %d odun geri alındı" % back, "info")
		return
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


## The window resized (or made full screen): the 3D drawn at the share the new size asks.
func _on_resized() -> void:
	if is_inside_tree() and not _loading:
		Settings.apply_ui(get_tree())
		Graphics.apply(get_tree(), weather if is_instance_valid(weather) else null)


# --- Areas dragged out: trees to fell, a workplace's ground ---------------------------------------

func _rect(a: Vector3, b: Vector3) -> Rect2:
	return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))


## A flat box over the ground on `rect`, `color` (made the first time).
func _box_on(box: MeshInstance3D, rect: Rect2, color: Color) -> MeshInstance3D:
	if box == null:
		box = MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = false
		box.material_override = m
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(box)
	(box.material_override as StandardMaterial3D).albedo_color = color
	var c := rect.get_center()
	var lo := INF
	var hi := -INF
	for p: Vector2 in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), c]:
		var h := terrain.height_at(p.x, p.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	(box.mesh as BoxMesh).size = Vector3(maxf(rect.size.x, 0.2), hi - lo + 2.0, maxf(rect.size.y, 0.2))
	box.global_position = Vector3(c.x, (lo + hi) * 0.5, c.y)
	box.visible = true
	return box


func _update_drag() -> void:
	if _drag_from == null:
		if _drag_box:
			_drag_box.visible = false
		return
	var to: Variant = cam.ground_under(get_viewport().get_mouse_position())
	if to == null:
		return
	var color: Color = {"mayin": Color(0.8, 0.25, 0.1, 0.25), "hendek": Color(0.35, 0.25, 0.15, 0.3), "tuzak": Color(0.45, 0.32, 0.2, 0.28), "kes": Color(0.95, 0.2, 0.08, 0.24), "kesme": Color(0.6, 0.75, 1.0, 0.2), "alan": Color(0.55, 0.9, 0.45, 0.2)}[_placing]
	_drag_box = _box_on(_drag_box, _rect(_drag_from, to), color)
	_spot_marks(_rect(_drag_from, to) if _placing in ["mayin", "tuzak"] else Rect2())


## While a box is dragged for mines or pits: a marker where each would go, green if it can, red if
## not (water, a cliff, a building, one there already).
var _marks_mm: MultiMeshInstance3D


func _spot_marks(rect: Rect2) -> void:
	if _marks_mm == null:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.45
		disc.bottom_radius = 0.45
		disc.height = 0.06
		disc.radial_segments = 12
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc.material = m
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = disc
		mm.instance_count = 400
		_marks_mm = MultiMeshInstance3D.new()
		_marks_mm.multimesh = mm
		_marks_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_marks_mm)
	if rect.size == Vector2.ZERO:
		_marks_mm.visible = false
		return
	var spots: Array = village.lay_spots(rect, village.MINE_GAP if _placing == "mayin" else village.TRAP_GAP, _placing)
	var mm := _marks_mm.multimesh
	var n := mini(spots.size(), mm.instance_count)
	mm.visible_instance_count = n
	for i in n:
		var e: Array = spots[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, (e[0] as Vector3) + Vector3.UP * 0.08))
		mm.set_instance_color(i, Color(0.3, 0.95, 0.35, 0.75) if str(e[1]) == "" else Color(1.0, 0.25, 0.2, 0.75))
	_marks_mm.visible = true


func _area_done(to: Variant) -> void:
	var from: Variant = _drag_from
	_drag_from = null
	if _drag_box:
		_drag_box.visible = false
	if _marks_mm:
		_marks_mm.visible = false
	if from == null or to == null:
		return
	var rect := _rect(from, to)
	if _placing == "hendek": # (a line, not a box)
		var n := village.mark_trench(Vector2(from.x, from.z), Vector2(to.x, to.z))
		hud.toast("%d m hendek kazılacak" % (n * 3) if n > 0 else "Hendek o kadar kısa olamaz", "good" if n > 0 else "info")
		return
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		if _placing in ["tuzak", "mayin"]: # (a click: one pit, one mine there)
			rect = Rect2(Vector2(to.x - 0.3, to.z - 0.3), Vector2(0.6, 0.6))
		elif _placing in ["kes", "kesme"]: # (a click, not a drag: the one tree there)
			var i := village.find_prop(to, 4.0, "tree")
			if i < 0:
				return
			var o: Vector3 = village.props._xf[i].origin
			rect = Rect2(Vector2(o.x - 0.3, o.z - 0.3), Vector2(0.6, 0.6))
		else:
			return
	match _placing:
		"kes": # (marked to be felled first: everyone drops their work for it)
			var n := village.mark_trees(rect, true, true)
			hud.toast("%d ağaç kesilecek: herkes işini bırakıp gidiyor" % n if n > 0 else "Orada kesilecek ağaç yok", "good" if n > 0 else "info")
		"mayin":
			var n := village.lay_mines(rect)
			hud.toast("%d mayın gömüldü" % n if n > 0 else "Mayın gömülemedi (demir ya da kömür yok, ya da yer uygun değil)", "good" if n > 0 else "info")
		"tuzak":
			var n := village.lay_traps(rect)
			hud.toast("%d kazık tuzağı kuruldu" % n if n > 0 else "Tuzak kurulamadı (odun yok ya da yer uygun değil)", "good" if n > 0 else "info")
		"kesme":
			var n := village.mark_trees(rect, false)
			hud.toast("%d ağacın işareti kalktı" % n, "info")
		"alan":
			var b := _area_for
			stop_placing()
			if b and is_instance_valid(b):
				b.work_area = rect
				select(b)
				hud.toast("%s yalnızca bu alanda çalışacak" % b.display_name(), "good")


## The selected workplace's drawn area, while it's selected.
func _show_work_area() -> void:
	var b := selected
	if b and is_instance_valid(b) and b.work_area.has_area() and _placing == "":
		_area_box = _box_on(_area_box, b.work_area, Color(0.55, 0.9, 0.45, 0.14))
	elif _area_box:
		_area_box.visible = false


func clear_work_area() -> void:
	if selected and is_instance_valid(selected):
		selected.work_area = Rect2()
		hud.toast("%s yine her yerde çalışacak" % selected.display_name(), "info")


func upgrade_selected(what := "oda") -> void:
	if selected and is_instance_valid(selected):
		var why := village.upgrade(selected, what)
		var done := {"oda": "%s büyütülecek: arkasına oda eklenecek", "siva": "%s sıvanacak: çamur taşınacak", "soba": "%s evine soba yapılacak: kerpiç taşınacak"}
		hud.toast(why if why != "" else str(done[what]) % selected.display_name(), "info")


## A mud pit put to bricks, or back to mud.
func toggle_mode_selected() -> void:
	if selected and is_instance_valid(selected) and selected.kind == "camur":
		selected.mode = "" if selected.mode == "kerpic" else "kerpic"
		hud.toast("%s: %s" % [selected.display_name(), "kerpiç dökülecek" if selected.mode == "kerpic" else "çamur kazılacak"], "info")



## The selected workshop set to make `what`.
func refit_selected(what: String) -> void:
	var b := selected
	if b == null or not is_instance_valid(b) or BuildingDefs.workshop_of(b) == "" or not b.state in ["done", "site"]:
		return
	var why: Array = []
	var nb := village.refit(b, what, why)
	if nb == null:
		hud.toast(str(why[0]), "bad")
		return
	select(nb)
	hud.toast("%s %s" % [nb.display_name(), "kuruldu" if nb.state == "done" else "olarak kurulacak"], "good")


var _camp_turn := false ## (show_trouble: the camp shown, the rest next)
var _trouble_i := -1 ## which of the troubled places was shown last (show_trouble)


## The next of what's stopped the work (a workshop with its pile full, or with the stores full the
## fullest store): picked, and the view taken to it.
func show_trouble() -> void:
	if raids.camp_known and not _camp_turn:
		_camp_turn = true
		cam.jump_to(raids.camp_at)
		hud.toast("Firari kampı · %d kişi: milisi TOPLA, seç, kampa sağ tıkla" % raids.camp_men.size(), "bad")
		return
	_camp_turn = false
	var list: Array[Building] = village.full_yards()
	var why := "yığın dolu: %s" % ("arabacılar yetişemiyor" if village.carters_about() else "arabacı yok")
	if list.is_empty():
		list = village.unmanned()
		why = "çalışan yok: boşta kasabalı kalmadı"
	var fill := village.store_fill()
	if fill.y > 0 and fill.x >= fill.y:
		list = village.stores()
		list.sort_custom(func(a: Building, b: Building) -> bool: return a.goods_total() > b.goods_total())
		why = "depolar dolu: yeni depo kur"
	if list.is_empty() and village.line_shut() and village.depot() != null:
		list = [village.depot()]
		why = "hat karla kapalı: bir atölyede HAT KÜRE seçin"
	if list.is_empty():
		return
	_trouble_i = (_trouble_i + 1) % list.size()
	var b := list[_trouble_i]
	select(b)
	cam.jump_to(b.global_position)
	hud.toast("%s · %s (%d/%d)" % [b.display_name(), why, _trouble_i + 1, list.size()], "bad")


## A side line laid to the selected building.
func lay_spur_selected() -> void:
	var b := selected
	if b == null or not is_instance_valid(b):
		return
	var why := village.lay_spur(b)
	if why != "":
		hud.toast(why, "bad")


## While a workshop's being placed: what it'll be set to make (its ghost the one for that).
func place_workshop_as(what: String) -> void:
	if not _placing in BuildingDefs.WORKSHOP_KINDS:
		return
	var w: Dictionary = BuildingDefs.WORKSHOP[what]
	var needs := str(w.get("needs", ""))
	if not village.knows(needs):
		hud.toast("Önce okuma odasında %s araştırılmalı" % BuildingDefs.TECHS[needs].name, "bad")
		return
	_placing_mode = str(w.get("mode", ""))
	if _placing == str(w.kind):
		return
	_placing = str(w.kind)
	if _ghost:
		_ghost.queue_free()
	_ghost = Building.new()
	_ghost.setup(_placing)
	add_child(_ghost)
	_ghost_reason = "x"
	hud.set_hint("Atölye (%s): %s · R çevir · Sağ tık iptal" % [w.word, BuildingDefs.cost_text(_placing)])


## Oxen bought for the selected carter's: its carts ox carts from now on.
func buy_oxen() -> void:
	var b := selected
	if b == null or not is_instance_valid(b) or b.kind != "arabaci" or b.ox:
		return
	if not village.pay(BuildingDefs.OX_COST, b.global_position):
		hud.toast("Öküz için %s gerek" % BuildingDefs.cost_text_of(BuildingDefs.OX_COST), "info")
		return
	b.ox = true
	for w in b.workers:
		if is_instance_valid(w):
			w.give_ox(true)
	hud.toast("%s: öküzler geldi, arabalar artık öküz arabası" % b.display_name(), "good")


func ignite_selected() -> void:
	if selected and is_instance_valid(selected) and selected.state in ["done", "site", "ruin"]:
		if not selected.ignite():
			hud.toast("Burada yanacak bir şey yok", "info")


func _process(_dt: float) -> void:
	if _titled or _loading:
		return
	# The first train in: the view rides with it till it stops at the platform.
	if village.arriving and is_instance_valid(village.train) and not village.train.is_standing() and not _cam_free:
		cam.focus = cam.focus.lerp(village.train.engine_at(), 0.08)
	if village.day != _saved_day and weather.hour > 6.0 and not raids.active:
		_saved_day = village.day
		VillageSave.save(self) # (every morning)
	if _placing in ["yol", "sur"]: # (the palisade's stakes shown to the mouse as the road's planks are)
		_update_road_line()
	elif _placing == "kapi":
		pass
	elif AREA_ORDERS.has(_placing):
		_update_drag()
	elif _placing != "":
		_update_ghost()
	_show_work_area()
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
