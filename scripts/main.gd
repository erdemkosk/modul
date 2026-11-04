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
var marks: CombatMarks ## the slips over the fighters' heads, the line of fire and the chance to hit
var selected: Building
var selected_villager: Villager
var selected_wall: Wall
var selected_gate: Gate
var _gate_ghost: MeshInstance3D
var group: Array[Villager] = [] ## the townsfolk chosen together (Shift+click), the first is selected_villager
var _rings: Array[MeshInstance3D] = []

var _placing := ""
var _placing_mode := "" ## a workshop being placed: the mode it's to have (iron, coal)
var _ghost: Building
var _ghost_yaw := 0.0
var _ghost_pos := Vector3.ZERO
var _ghost_reason := "x"
var _yaw_manual := false ## Q / E pressed: the player's turning it, not the town
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
		elif village.arriving:
			start = village.train.engine_at()
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
	marks = CombatMarks.new()
	marks.game = self
	add_child(marks)
	village.message.connect(hud.toast)
	raids.message.connect(hud.toast)
	raids.hud = hud
	village.hud = hud
	seasons.message.connect(hud.toast)
	if saved.is_empty():
		hud.toast("Tren vadiyi geçiyor. G: haritaya bak, yer beğenince TRENİ DURDUR. F1: tuşlar", "info")
	else:
		await screen.step("Kasabalılar yerine dönüyor", 0.93)
		VillageSave.restore(self, saved)
		cam._dist_to = cam.dist
		hud.toast("Kayıt yüklendi: gün %d" % village.day, "good")
	_saved_day = village.day
	_loading = false
	screen.finish()


# --- Input ------------------------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	# a box dragged out ends where the button's let go, over the panels too (they'd swallow it)
	if e is InputEventMouseButton and not e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var up := (e as InputEventMouseButton).position
		if _sel_from != Vector2.INF:
			_end_select(up)
		elif _drag_from != null:
			_area_done(up)
	# Shift and the wheel turn a building being placed (not the zoom)
	if _ghost and e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).shift_pressed and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		rotate_ghost(15.0 if (e as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP else -15.0)
		get_viewport().set_input_as_handled()
		return
	# the wheel sets a trench's width while one's being laid out (not the zoom)
	if _placing == "hendek" and e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_trench_w = clampf(_trench_w + (0.2 if (e as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP else -0.2), 0.8, 2.6)
		hud.set_hint("HENDEK genişliği %.1f m (tekerlek: genişlet / daralt) · çizgi sürükle" % _trench_w)
		get_viewport().set_input_as_handled()


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
				# a click picks; a drag draws a box round folk to pick them all (on release)
				_sel_from = mb.position
				_sel_ground = cam.ground_under(mb.position)
				_sel_far = false
				_sel_shift = mb.shift_pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _placing in ["yol", "sur"] and _road_pts.size() >= 2:
				_road_finish()
			elif _placing != "":
				stop_placing()
			elif not _hands().is_empty():
				_rclick_from = mb.position # (a drag lines them up; on release)
			else:
				_rclick_act(_rclick_intent(mb.position))
	elif e is InputEventMouseButton and not e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and _rclick_from != Vector2.INF:
		var up := (e as InputEventMouseButton).position
		if up.distance_to(_rclick_from) > 14.0:
			_line_order(_rclick_from, up)
		else:
			_rclick_act(_rclick_intent(_rclick_from))
		_rclick_from = Vector2.INF
		_show_formation([])
	elif e is InputEventMouseMotion and _rclick_from != Vector2.INF:
		var at := (e as InputEventMouseMotion).position
		_show_formation(_formation(_rclick_from, at) if at.distance_to(_rclick_from) > 14.0 else [])
	if e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		# Ctrl (Cmd) + a number: the folk chosen kept as that group; a number alone picks them again
		if k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_9 and (k.ctrl_pressed or k.meta_pressed):
			store_group(k.physical_keycode - KEY_0)
			return
		match k.physical_keycode:
			KEY_Q, KEY_E:
				if _ghost:
					rotate_ghost(-15.0 if k.physical_keycode == KEY_Q else 15.0) # (the view holds still meanwhile: RtsCamera.hold_keys)
			KEY_ENTER, KEY_KP_ENTER:
				if _placing in ["yol", "sur"] and _road_pts.size() >= 2:
					_road_finish()
			KEY_BACKSPACE:
				if _placing in ["yol", "sur"] and not _road_pts.is_empty():
					_road_pts.pop_back()
			KEY_ESCAPE:
				if hud.help_open():
					hud.toggle_help()
				elif hud.map_open():
					hud.toggle_map()
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
				elif hud.build_keys:
					hud.build_keys = false # (the numbers are the groups' again)
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
				# R only takes folk in hand or lets them go (a building turns with Q / E)
				if _placing != "":
					hud.toast("Binayı çevirmek için Q / E ya da Shift + tekerlek", "info")
				else:
					toggle_control()
			KEY_SPACE:
				if not _menu:
					set_speed(Engine.time_scale if get_tree().paused else 0.0)
			KEY_EQUAL, KEY_KP_ADD:
				set_speed(Hud.SPEEDS[mini(Hud.SPEEDS.find(Engine.time_scale) + 1, Hud.SPEEDS.size() - 1)])
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_speed(Hud.SPEEDS[maxi(Hud.SPEEDS.find(Engine.time_scale) - 1, 0)])
			KEY_TAB:
				hud.show_category(hud.category + 1)
				hud.build_keys = true
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
			KEY_G:
				hud.toggle_map()
			KEY_J:
				hud.toggle_log()
			KEY_V:
				select_militia()
			KEY_M:
				toggle_militia()
			KEY_L:
				toggle_lantern()
			KEY_HOME:
				follow_chosen()
			KEY_H:
				var s := village.stores()
				if not s.is_empty():
					cam.jump_to(s[0].global_position)
			_:
				# a number: a building of the group shown while the build bar's in use (Tab, a tab
				# clicked, something being placed), else the folk kept under that number
				if k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_9:
					if hud.build_keys or _placing != "":
						var kind := hud.kind_at(k.physical_keycode - KEY_1)
						if kind != "":
							start_placing(kind)
					else:
						pick_group(k.physical_keycode - KEY_0)


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
	if village.arriving:
		hud.toast("Tren yoldayken kaydedilmez", "info")
		return
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
	hud.set_hint("%s: %s · Q / E çevir · Sağ tık iptal" % [BuildingDefs.DEFS[kind].name, BuildingDefs.cost_text(kind)])


## The gate about to be set: a block where it would stand, snapped to the wall, green or red.
func _update_gate_ghost() -> void:
	if _gate_ghost == null:
		_gate_ghost = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(Gate.WIDTH + 0.5, 3.6, 0.5)
		_gate_ghost.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_gate_ghost.material_override = mat
		add_child(_gate_ghost)
	var to: Variant = cam.ground_under(get_viewport().get_mouse_position())
	var hit: Dictionary = village.gate_spot(to) if to != null else {}
	_gate_ghost.visible = not hit.is_empty()
	if hit.is_empty():
		return
	var at: Vector3 = hit.at
	at.y = village.nav.height(at.x, at.z) + 1.8
	var dir: Vector3 = hit.dir
	_gate_ghost.global_transform = Transform3D(Basis.looking_at(dir.cross(Vector3.UP), Vector3.UP), at)
	(_gate_ghost.material_override as StandardMaterial3D).albedo_color = Color(0.3, 0.85, 0.35, 0.45) if hit.why == "" else Color(0.9, 0.25, 0.15, 0.45)


func stop_placing() -> void:
	if _gate_ghost:
		_gate_ghost.visible = false
	_hide_measure()
	_placing = ""
	_show_guide(Vector3.INF, Vector3.INF)
	if _drag_from != null:
		hud.show_select_box(Rect2())
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
	if not keep and not kind in BuildingDefs.CHAINED: # (one length leads on to the next, till right-click)
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
		if _placing == "kule": # (a watchtower near a palisade stands on its line: a corner tower)
			var on: Dictionary = village.gate_spot(p)
			if not on.is_empty():
				p.x = on.at.x
				p.z = on.at.z
				var d: Vector3 = on.dir
				_ghost_yaw = atan2(d.x, d.z)
		if _placing in BuildingDefs.CHAINED:
			var link := _chain_snap(_placing, p)
			if not link.is_empty():
				p = link.at
				if not is_equal_approx(link.yaw, _ghost_yaw):
					_ghost_yaw = link.yaw
					_ghost_reason = "x"
	if _placing == "istasyon": # (it takes hold of the rails, its platform to them)
		var spot: Dictionary = village.station_spot(p)
		if not spot.is_empty():
			p.x = spot.at.x
			p.z = spot.at.z
			_ghost_yaw = spot.yaw
	if p.distance_to(_ghost_pos) < 0.01 and _ghost_reason != "x":
		return
	_ghost_pos = p
	_ghost.global_transform = Transform3D(Basis(Vector3.UP, _ghost_yaw), Vector3(p.x, village.base_height(_placing, p, _ghost_yaw), p.z))
	_measure(_placing, p, _ghost_yaw)
	var reason := village.check(_placing, p, _ghost_yaw)
	if reason != _ghost_reason:
		_ghost.set_ghost(true, reason == "")
		var def: Dictionary = BuildingDefs.DEFS[_placing]
		if reason == "":
			hud.set_hint("%s: %s · %s · Alt: hizasız · Shift+tık üst üste · Sağ tık iptal" % [def.name, BuildingDefs.cost_text(_placing), "ucuna yaklaştır, kendi yapışır" if _placing in BuildingDefs.CHAINED else "Q / E çevir" if _yaw_manual else "kapısı kasabaya dönük (Q / E: elle çevir)"])
		else:
			hud.set_hint(reason, true)
	_ghost_reason = reason


## Placing beside a building facing the same way (or square to it): pulled into line with it, its
## front on the same line and an even 2 m between their walls when it's near that, a brass guide
## line drawn between them while it holds. Alt held: no pulling.
var _guide: MeshInstance3D


## Wire and sandbags near a free end of their own kind: the next length, end to end with it, straight
## on or turned by 45 or 90 degrees toward the pointer ({at, yaw}, {} with none near).
func _chain_snap(kind: String, p: Vector3) -> Dictionary:
	var sz: Vector2 = BuildingDefs.DEFS[kind].size
	var reach := sz.x * 1.15
	var ends: Array = [] # (each end of each length: [where, which way it leads on, the length])
	for b in village.buildings:
		if b.kind != kind or b.state in ["gone", "ghost"]:
			continue
		var axis: Vector3 = b.global_basis * Vector3.RIGHT
		axis.y = 0.0
		axis = axis.normalized()
		for sgn in [1.0, -1.0]:
			var out: Vector3 = axis * sgn
			var at: Vector3 = b.global_position + out * sz.x * 0.5
			at.y = 0.0
			ends.append([at, out, b])
	var bd := reach
	var pick: Array = []
	var flat := Vector3(p.x, 0, p.z)
	for e: Array in ends:
		var d := flat.distance_to(e[0])
		if d >= bd:
			continue
		var taken := false
		for o: Array in ends:
			if o[2] != e[2] and (o[0] as Vector3).distance_to(e[0]) < 0.8:
				taken = true
		if not taken:
			bd = d
			pick = e
	if pick.is_empty():
		return {}
	var on: Vector3 = pick[1]
	var to: Vector3 = flat - (pick[0] as Vector3)
	var turn := 0.0
	if to.length() > 0.5:
		turn = clampf(snappedf(on.signed_angle_to(to, Vector3.UP), PI * 0.25), -PI * 0.5, PI * 0.5)
	var dir := on.rotated(Vector3.UP, turn)
	var at: Vector3 = (pick[0] as Vector3) + dir * sz.x * 0.5
	var own: Vector3 = pick[2].global_basis * Vector3.RIGHT
	var along := dir if own.dot(on) > 0.0 else -dir # (sandbags keep facing the way the last ones do)
	return {"at": Vector3(snappedf(at.x, 0.01), p.y, snappedf(at.z, 0.01)), "yaw": atan2(-along.z, along.x)}


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
	# The gap between the walls: houses far enough apart that their yards fit side by side; and
	# along a row already started, the row's own gap again, so the street keeps an even step.
	var houses: bool = BuildingDefs.DEFS[kind].role == "house" and best.def.role == "house"
	var gap := Yard.SIDE * 2.0 + 0.4 if houses else 2.0
	var row := _row_gap(best)
	if row > 0.0:
		gap = maxf(row, gap)
	# beside it (along its x): the fronts in a line, an even gap between the walls
	var half_x := bs.x * 0.5 + sz.x * 0.5
	if absf(local.z) < 2.5 and absf(absf(local.x) - (half_x + gap)) < 2.5:
		local.z = (bs.y * 0.5) - (sz.y * 0.5) # (fronts flush: the doors on one line)
		local.x = signf(local.x) * (half_x + gap)
		snapped = true
	# behind or in front (along its z): side by side in a column (houses: room for both yards)
	var half_z := bs.y * 0.5 + sz.y * 0.5
	var col_gap := (Yard.BACK + Yard.FRONT + 0.4) if houses else 2.0
	if not snapped and absf(local.x) < 2.0 and absf(absf(local.z) - (half_z + col_gap)) < 2.0:
		local.x = 0.0
		local.z = signf(local.z) * (half_z + col_gap)
		snapped = true
	if not snapped:
		_show_guide(Vector3.INF, Vector3.INF)
		return p
	var out := best.global_transform * local
	out.y = p.y
	_show_guide(best.global_position, out)
	return out


## The gap between `b`'s wall and the next building's along its row (same way, fronts in line), or
## 0 with none: a street's step, for the next to keep.
func _row_gap(b: Building) -> float:
	var bs: Vector2 = b.def.size
	for o in village.buildings:
		if o == b or o.state == "gone" or o.state == "ghost":
			continue
		if absf(angle_difference(o.global_rotation.y, b.global_rotation.y)) > 0.05:
			continue
		var l := b.global_transform.affine_inverse() * o.global_position
		var os: Vector2 = o.def.size
		if absf((l.z + os.y * 0.5) - bs.y * 0.5) > 0.4: # (its front on the same line)
			continue
		var g := absf(l.x) - bs.x * 0.5 - os.x * 0.5
		if g > 0.5 and g < 14.0:
			return g
	return 0.0


## Thin lines from the ghost's walls to its nearest neighbours' with how far it is, in metres:
## green with room, yellow tight (under 2 m), red very close (under 1 m).
var _gaps: Array = [] ## [line MeshInstance3D, Label3D]


func _measure(kind: String, p: Vector3, yaw: float) -> void:
	var sz: Vector2 = BuildingDefs.DEFS[kind].size
	var mine := village._rect_poly(p, yaw, Rect2(-sz * 0.5, sz))
	var near: Array = []
	for o in village.buildings:
		if o.state == "gone" or o.state == "ghost":
			continue
		if o.global_position.distance_to(p) > 30.0:
			continue
		var os: Vector2 = o.def.size
		var their := village._rect_poly(o.global_position, o.global_rotation.y, Rect2(-os * 0.5, os))
		var best := [INF, Vector2.ZERO, Vector2.ZERO]
		for pair in [[mine, their], [their, mine]]:
			var a: PackedVector2Array = pair[0]
			var b: PackedVector2Array = pair[1]
			for q in a:
				for k in b.size():
					var c := Geometry2D.get_closest_point_to_segment(q, b[k], b[(k + 1) % b.size()])
					if q.distance_to(c) < float(best[0]):
						best = [q.distance_to(c), q, c] if pair[0] == mine else [q.distance_to(c), c, q]
		if float(best[0]) < 20.0:
			near.append(best)
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	while _gaps.size() < 3:
		var line := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.03, 1.0)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.material = m
		line.mesh = bm
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(line)
		var tag := Label3D.new()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.fixed_size = true
		tag.pixel_size = 0.0008
		tag.font_size = 30
		tag.outline_size = 8
		tag.font = Ui.font("type_bold")
		add_child(tag)
		_gaps.append([line, tag])
	for i in _gaps.size():
		var line: MeshInstance3D = _gaps[i][0]
		var tag: Label3D = _gaps[i][1]
		line.visible = i < near.size()
		tag.visible = i < near.size()
		if i >= near.size():
			continue
		var d: float = near[i][0]
		var a2: Vector2 = near[i][1]
		var b2: Vector2 = near[i][2]
		var a := Vector3(a2.x, village.nav.height(a2.x, a2.y) + 0.25, a2.y)
		var b := Vector3(b2.x, village.nav.height(b2.x, b2.y) + 0.25, b2.y)
		var col := Color(0.55, 0.95, 0.55) if d >= 2.0 else (Color(1.0, 0.85, 0.3) if d >= 1.0 else Color(1.0, 0.4, 0.3))
		((line.mesh as BoxMesh).material as StandardMaterial3D).albedo_color = Color(col, 0.9)
		if a.distance_to(b) > 0.05:
			line.global_position = (a + b) * 0.5
			line.look_at(b, Vector3.UP)
			line.scale = Vector3(1, 1, a.distance_to(b))
		else:
			line.visible = false
		tag.global_position = (a + b) * 0.5 + Vector3.UP * 0.6
		tag.text = "%.1f m" % d
		tag.modulate = col


func _hide_measure() -> void:
	for g in _gaps:
		(g[0] as Node3D).visible = false
		(g[1] as Node3D).visible = false


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
			hud.toast("Sur çizildi: %d kazık · kasabalılar dikecek · kapıyı sen koy (SUR KAPISI)" % w.line.size(), "good")
		_road_pts.clear()
		_road_dir = Vector3.ZERO
		return
	var got := village.lay_path(_road_pts, false, _road_dir)
	if got > 0.0:
		hud.toast("Tahta yol işaretlendi: %d m · kasabalılar döşeyecek" % roundi(got), "good")
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
					for g in w.gates:
						if is_instance_valid(g) and g.global_position.distance_to(p) < 2.6:
							select(null)
							selected_gate = g
							return
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
	var heap: Array = _stack_under(at)
	if not heap.is_empty():
		select(null)
		picked_heap = heap[0]
		picked_heap.pick_stack(heap[1])
		return
	select(_building_under(at))


## The stack in the open under the point on the screen: [its heap, which], or [].
func _stack_under(at: Vector2) -> Array:
	var best: Array = []
	var nearest := 1.0 # (in stack-widths on the screen)
	for b in village.buildings:
		if not b.def.get("open", false) or b.state == "gone":
			continue
		for k in b.stacks.size():
			var mid: Vector3 = b.stack_world(k)
			if cam.is_position_behind(mid):
				continue
			var c := cam.unproject_position(mid)
			var wide := c.distance_to(cam.unproject_position(mid + cam.global_basis.x * Building.STACK_W * 0.5))
			var d := c.distance_to(at) / maxf(wide, 1.0)
			if d < nearest:
				nearest = d
				best = [b, k]
	return best


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
	if picked_heap and is_instance_valid(picked_heap):
		picked_heap.pick_stack(-1)
	picked_heap = null
	selected = b
	selected_villager = null
	selected_wall = null
	selected_gate = null
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
		if not on and v.has_meta("called_up"):
			# (off the alarm's roll: back to its work, unless it's in hand)
			v.remove_meta("called_up")
			if not village.controlled(v):
				v.drafted = false
				v.focus = null
				v.abort()
		n += 1
	if n > 0:
		hud.toast(("%d kişi milis: tehlike çanında silahlıktan tüfek alır" if on else "%d kişi artık milis değil") % n, "good" if on else "info")
	if on and village.armories().is_empty():
		hud.toast("Silahlık yok: önce SAVUNMA'dan silahlık kur", "bad")


func toggle_lantern() -> void:
	var list := _chosen()
	if list.is_empty():
		return
	var dark := list[0].lantern_mode != "off"
	for v in list:
		v.lantern_mode = "off" if dark else ""
	hud.toast("Fenerler söndürüldü: karanlıkta görünmezler, ama onlar da az görür" if dark else "Fenerler yanıyor", "info")


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


## Those of the town inside a box dragged on the screen, picked together (added to, with Shift).
func _box_select(box: Rect2, add: bool) -> void:
	var cam3 := get_viewport().get_camera_3d()
	var list: Array[Villager] = []
	for v in village.villagers:
		if v.dead or v.is_child:
			continue
		var p := v.global_position + Vector3.UP * 1.0
		if cam3.is_position_behind(p):
			continue
		if box.has_point(cam3.unproject_position(p)):
			list.append(v)
	if not add:
		select(null)
		group.clear()
	for v in list:
		if not v in group:
			group.append(v)
	if not group.is_empty():
		selected_villager = group[0]
		hud.toast("%d kişi seçili · R: emre al · Ctrl+1–9: grup yap" % group.size(), "info")


## Every militiaman picked at once (V), to be taken in hand together (R).
func select_militia() -> void:
	var list: Array[Villager] = []
	for v in village.villagers:
		if not v.dead and not v.down and v.militia:
			list.append(v)
	if list.is_empty():
		hud.toast("Milis yok: bir kasabalının kartından MİLİS YAP (M)", "info")
		return
	select(null)
	group.clear()
	group.append_array(list)
	selected_villager = list[0]
	hud.toast("%d milis seçili · R: emre al" % list.size(), "info")


## The chosen who are in hand (EMİRDE) and on their feet: the ones a right-click gives orders to.
func _hands() -> Array[Villager]:
	var out: Array[Villager] = []
	for v in _chosen():
		if village.controlled(v) and not v.down:
			out.append(v)
	return out


## The chosen taken in hand (R, the card's EMRE AL): they drop their work and wait for orders. If
## every one of them is in hand already, they're let go instead (BIRAK), back to their own judgement.
func toggle_control() -> void:
	var list: Array[Villager] = []
	for v in _chosen():
		if not v.is_child and not v.down:
			list.append(v)
	if list.is_empty():
		hud.toast("Önce kasabalı seç (tık ya da sürükle), sonra R: emre al", "info")
		return
	set_in_hand(list, list.any(func(o: Villager) -> bool: return not village.controlled(o)))


## `list` taken in hand (`on`) or let go, and the player told what that means.
func set_in_hand(list: Array[Villager], on: bool) -> void:
	for v in list:
		if on and not village.controlled(v):
			village.take_control(v)
		elif not on and village.controlled(v):
			village.release_control(v)
	if not on:
		hud.toast("%d kişi bırakıldı: yine kendi işinde" % list.size() if list.size() > 1 else "%s bırakıldı: yine kendi işinde" % list[0].display_name.split(" ")[0], "info")
	elif list.size() > 1:
		hud.toast("%d kişi emrinde · sağ tık: git, saldır, ara, saklan (imleçte yazar) · sağ sürükle: sıraya diz · R: bırak" % list.size(), "good")
	else:
		hud.toast("%s emrinde · sağ tık: git, saldır, ara, saklan (imleçte yazar) · R: bırak" % list[0].display_name.split(" ")[0], "good")


## Everyone in hand let go at once (the squad bar's HEPSİNİ BIRAK).
func release_all() -> void:
	var list: Array[Villager] = []
	for v in village.villagers:
		if village.controlled(v):
			list.append(v)
	if not list.is_empty():
		set_in_hand(list, false)


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


# --- Control groups (Ctrl+1…9 keeps the chosen, 1…9 picks them, twice quickly goes to them) ---------

var _groups: Dictionary = {} ## 1–9 -> Array[Villager]: the folk kept under that number
var _last_group := 0 ## (the number pressed last, and when: twice in a row takes the view there)
var _last_group_t := -9.0


## The folk chosen kept as group `n` (none chosen: the group emptied).
func store_group(n: int) -> void:
	var list: Array[Villager] = []
	for v in _chosen():
		if not v.is_child:
			list.append(v)
	if list.is_empty():
		_groups.erase(n)
		hud.toast("%d. grup boşaltıldı · kasabalı seçip Ctrl+%d: gruba al" % [n, n], "info")
		return
	_groups[n] = list
	hud.toast("%d kişi %d. grupta · %d: seç · iki kez %d: oraya git" % [list.size(), n, n, n], "good")


## Who's left of group `n` (the dead and gone dropped from it).
func group_members(n: int) -> Array[Villager]:
	var out: Array[Villager] = []
	for v: Villager in _groups.get(n, []):
		if is_instance_valid(v) and not v.dead and not v.leaving:
			out.append(v)
	return out


## The numbers of the groups `v` is kept in ("1", "1·3"), "" none (the squad bar's cards).
func groups_of(v: Villager) -> String:
	var out: PackedStringArray = []
	for n in range(1, 10):
		if _groups.has(n) and v in (_groups[n] as Array):
			out.append(str(n))
	return "·".join(out)


## Group `n` picked (a number key); picked again straight after, the view taken to them.
func pick_group(n: int) -> void:
	var list := group_members(n)
	if list.is_empty():
		hud.toast("%d. grup boş · kasabalı seçip Ctrl+%d: gruba al" % [n, n], "info")
		return
	var now := Time.get_ticks_msec() / 1000.0
	var twice := n == _last_group and now - _last_group_t < 0.6
	_last_group = n
	_last_group_t = now
	select(null)
	group.append_array(list)
	selected_villager = list[0]
	if twice:
		var mid := Vector3.ZERO
		for v in list:
			mid += v.global_position
		cam.jump_to(mid / list.size())


# --- Right-click -------------------------------------------------------------------------------------
# One rule a player can predict, and the word by the pointer says it before the click:
#  · placing something: called off (a road or palisade with two points or more: finished);
#  · folk in hand: an order to them, always (a foe: at him; a body: searched, or a downed one taken;
#    the armoury: arm there; a house: hide; cover: take it; ground: go and hold in cover there);
#  · folk chosen, none in hand: a workplace puts them to work there, anything else only says so;
#  · nobody chosen: an order on the ground (a mine, a pit, a trench) called off; else nothing.

const WORKPLACES := ["work", "farm", "carts", "barracks", "tower", "research", "smith", "healer", "mg"]


## What a right-click at screen point `at` would do just now: {do, word, cursor, ...the thing}, or
## empty for nothing. The click and the word by the pointer both come from here, so they agree.
func _rclick_intent(at: Vector2) -> Dictionary:
	if _placing != "":
		return {"do": "stop", "word": "Bitir" if _placing in ["yol", "sur"] and _road_pts.size() >= 2 else "İptal", "cursor": ""}
	var hands := _hands()
	if not hands.is_empty():
		var foe := _raider_under(at)
		if foe:
			return {"do": "attack", "foe": foe, "word": "Saldır", "cursor": "sight"}
		var body := _body_under(at)
		if body:
			return {"do": "body", "body": body, "word": "Ara" if body.dead else "Esir al", "cursor": ""}
		var b := _building_under(at)
		if b and b.state == "done":
			if b.def.role == "barracks" and village._weapon_at(b, "") != "" and hands.any(func(v: Villager) -> bool: return not v.armed):
				return {"do": "arm", "at": b, "word": "Silah al", "cursor": ""}
			if b.def.role in ["house", "store", "barracks"] and not b.is_burning():
				return {"do": "hide", "at": b, "word": "Saklan", "cursor": ""}
		var to: Variant = cam.ground_under(at)
		if to == null:
			return {}
		var cv := village.cover_at(to, b)
		if not cv.is_empty():
			return {"do": "cover", "cover": cv, "word": "Siper al", "cursor": "shield"}
		var armed := hands.any(func(v: Villager) -> bool: return v.armed)
		return {"do": "go", "to": to, "word": "Git · siper" if armed else "Git", "cursor": ""}
	if not _chosen().is_empty():
		var w := _building_under(at)
		if w and w.def.role in WORKPLACES:
			return {"do": "assign", "at": w, "word": "Ata: " + w.display_name(), "cursor": ""}
		return {"do": "hint", "word": "", "cursor": ""}
	var o := _order_at(at)
	if not o.is_empty():
		return {"do": "cancel", "order": o, "word": "İptal", "cursor": "stop"}
	return {}


## A right-click carried out (_rclick_intent says what).
func _rclick_act(i: Dictionary) -> void:
	var hands := _hands()
	match str(i.get("do", "")):
		"stop":
			if _placing in ["yol", "sur"] and _road_pts.size() >= 2:
				_road_finish()
			else:
				stop_placing()
		"attack":
			var foe: Villager = i.foe
			for v in hands:
				v.focus = foe
				if not v.armed: # (bare-handed or with an axe: it goes for him)
					v.abort()
					v.give([{"t": "fight", "foe": foe, "give_up": 60.0}], "Saldırıyor")
			hud.toast("Hedef: %d kişi ona saldırıyor" % hands.size() if hands.size() > 1 else "%s ona saldırıyor" % hands[0].display_name.split(" ")[0], "info")
		"body":
			# the nearest of those in hand goes to it
			var body: Villager = i.body
			var who := hands[0]
			for v in hands:
				if v.position.distance_to(body.position) < who.position.distance_to(body.position):
					who = v
			var why: String = village.ctl_capture(who, body) if not body.dead else village.ctl_search(who, body)
			hud.toast(why if why != "" else ("%s esir alınıyor" % body.display_name if not body.dead else "Cesedin üstü aranıyor"), "info" if why != "" else "good")
		"arm":
			# the unarmed to the rack; those with a weapon hold by its door
			var a: Building = i.at
			for v in hands:
				v.focus = null
				v.abort()
				if v.armed:
					village.hold_at(v, village.cover_near(a.door(), 4.0))
				else:
					village.arm(v, a, false)
			hud.toast("Silahlığa: silahsızlar silah alıyor", "good")
		"hide":
			var into: Building = i.at
			for v in hands:
				v.focus = null
				village.ctl_hide(v, into)
			hud.toast("%d kişi %s içine saklanıyor" % [hands.size(), into.display_name()] if hands.size() > 1 else "%s %s içine saklanıyor" % [hands[0].display_name.split(" ")[0], into.display_name()], "info")
		"cover":
			# sandbags, a trench, the palisade: taken side by side
			for k in hands.size():
				hands[k].focus = null
				village.take_cover(hands[k], i.cover, k, hands.size())
			hud.toast("%d kişi siper alıyor" % hands.size() if hands.size() > 1 else "%s siper alıyor" % hands[0].display_name.split(" ")[0], "good")
		"go":
			# there, spread out a little; those with a weapon hold behind whatever cover's close
			var p: Vector3 = i.to
			for k in hands.size():
				var v := hands[k]
				var off := Vector3.ZERO if k == 0 else Vector3(cos(k * 2.4), 0, sin(k * 2.4)) * (1.6 + k * 0.4)
				v.focus = null
				v.abort()
				if v.armed:
					village.hold_at(v, village.cover_near(p + off, 3.0))
				else:
					v.give([{"t": "go", "to": p + off}], "Emirle gidiyor")
		"assign":
			_assign_to(i.at)
		"hint":
			hud.toast("Sağ tık bir işyerine: oraya ata · R: emre al, sonra sağ tıkla gönder", "info")
		"cancel":
			hud.toast(village.cancel_order(i.order), "info")


## A right-drag with folk in hand: they line up along it, one to a spot, each spot pulled into cover
## close by if there's any (a trench, sandbags, a wall, a house's corner) and shown so while dragging.
var _rclick_from := Vector2.INF
var _form_marks: Array[MeshInstance3D] = []


## The spots along the drag from screen `a` to `b`, one for each in hand: [[pos, in cover], ...].
func _formation(a: Vector2, b: Vector2) -> Array:
	var pa: Variant = cam.ground_under(a)
	var pb: Variant = cam.ground_under(b)
	var who := _hands()
	if pa == null or pb == null or who.is_empty():
		return []
	var from: Vector3 = pa
	var to: Vector3 = pb
	var n := who.size()
	var len := Vector2(to.x - from.x, to.z - from.z).length()
	var dir := (to - from).normalized() if len > 0.1 else Vector3.RIGHT
	var gap := maxf(len / maxf(n - 1, 1), 1.4) if n > 1 else 0.0
	var mid := (from + to) * 0.5
	var out := []
	for i in n:
		var p := mid + dir * gap * (i - (n - 1) * 0.5) if n > 1 else mid
		var q: Vector3 = village.cover_near(p, 2.5) if (who[i] as Villager).armed else p
		q.y = village.nav.height(q.x, q.z)
		out.append([q, village.is_cover(q)])
	return out


func _line_order(a: Vector2, b: Vector2) -> void:
	var spots := _formation(a, b)
	var who := _hands()
	if spots.is_empty():
		return
	# the nearest to each end takes that end (so no one crosses the line to get there)
	var ends: Vector3 = spots[0][0]
	who.sort_custom(func(x: Villager, y: Villager) -> bool: return x.position.distance_to(ends) < y.position.distance_to(ends))
	var covered := 0
	for i in mini(who.size(), spots.size()):
		var v: Villager = who[i]
		v.focus = null
		v.abort()
		if v.armed:
			village.hold_at(v, spots[i][0])
		else:
			v.give([{"t": "go", "to": spots[i][0]}], "Emirle gidiyor")
		covered += int(spots[i][1])
	hud.toast("%d kişi sıraya giriyor · %d siperde" % [spots.size(), covered], "info")


## The spots shown on the ground: a pale ring each, a green one with a shield-post where there's cover.
func _show_formation(spots: Array) -> void:
	while _form_marks.size() < spots.size():
		var m := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.42
		tm.outer_radius = 0.6
		tm.rings = 16
		tm.ring_segments = 4
		m.mesh = tm
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		m.material_override = mat
		var post := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.5, 0.45, 0.08)
		post.mesh = pm
		post.material_override = mat
		post.position = Vector3(0, 0.9, 0)
		post.rotation.x = PI # (a little shield, point down)
		post.name = "Shield"
		m.add_child(post)
		add_child(m)
		_form_marks.append(m)
	for i in _form_marks.size():
		var m := _form_marks[i]
		m.visible = i < spots.size()
		if not m.visible:
			continue
		var cover: bool = spots[i][1]
		m.global_position = (spots[i][0] as Vector3) + Vector3.UP * 0.08
		(m.material_override as StandardMaterial3D).albedo_color = Color(0.35, 0.95, 0.45, 0.9) if cover else Color(0.95, 0.92, 0.8, 0.75)
		(m.get_node("Shield") as Node3D).visible = cover
		var face := cam.global_position
		face.y = m.global_position.y
		if face.distance_to(m.global_position) > 0.1:
			m.look_at(face, Vector3.UP)


## An order on the ground under the screen point `at` (a mine, a pit, a trench yet to dig).
func _order_at(at: Vector2) -> Dictionary:
	if _placing != "":
		return {}
	var p: Variant = cam.ground_under(at)
	return {} if p == null else village.order_under(p)


## The pointer, and the word by it, say what a right-click would do now (_rclick_intent): a red
## gunsight over a foe, a shield over cover, a struck-through ring over an order to call off. Over the
## interface, and while a box or an area is being dragged out, nothing.
func _update_pointer() -> void:
	var at := _pointer()
	var i: Dictionary = {}
	if _rclick_from != Vector2.INF and at.distance_to(_rclick_from) > 14.0:
		i = {"do": "line", "word": "Sıraya diz", "cursor": ""}
	elif _sel_from == Vector2.INF and _drag_from == null and not _menu and (mouse_pin != Vector2.INF or get_viewport().gui_get_hovered_control() == null):
		i = _rclick_intent(at)
	_set_pointer(str(i.get("cursor", "")))
	marks.rclick_word = str(i.get("word", ""))
	marks.rclick_do = str(i.get("do", ""))


var _cursors_made := false
var _cursor := ""
var picked_heap: Building ## the pile a stack's been clicked on (AlertBoard says what's in it)
var mouse_pin := Vector2.INF ## (a test's: where the pointer's taken to be, as CombatMarks.pointer)


## The pointer as `kind`: "sight", "shield", "stop", "" the plain one.
func _set_pointer(kind: String) -> void:
	if kind == _cursor:
		return
	_cursor = kind
	if not _cursors_made:
		_make_cursors()
	Input.set_custom_mouse_cursor(_cursor_tex("shield") if kind == "shield" else null, Input.CURSOR_ARROW, Vector2(16, 16))
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if kind == "sight" else (Input.CURSOR_FORBIDDEN if kind == "stop" else Input.CURSOR_ARROW))


func _make_cursors() -> void:
	_cursors_made = true
	var n := 40
	var c := n / 2.0
	var aim := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var stop := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := x + 0.5 - c
			var dy := y + 0.5 - c
			var d := sqrt(dx * dx + dy * dy)
			# the gunsight: a ring, four ticks breaking in, a dot in the middle (dark edged)
			var on := absf(d - 12.0) < 1.3 or d < 1.8 or ((absf(dx) < 1.1 and absf(dy) > 5.0 and absf(dy) < 18.0) or (absf(dy) < 1.1 and absf(dx) > 5.0 and absf(dx) < 18.0))
			var edge := absf(d - 12.0) < 2.4 or d < 2.9 or ((absf(dx) < 2.2 and absf(dy) > 4.0 and absf(dy) < 19.0) or (absf(dy) < 2.2 and absf(dx) > 4.0 and absf(dx) < 19.0))
			aim.set_pixel(x, y, Color(0.95, 0.18, 0.12) if on else (Color(0.05, 0.03, 0.02, 0.85) if edge else Color(0, 0, 0, 0)))
			# called off: a ring struck through
			var bar := absf(dx - dy) / sqrt(2.0)
			var s_on := (absf(d - 11.0) < 1.5 or (bar < 1.5 and d < 11.0))
			var s_edge := (absf(d - 11.0) < 2.6 or (bar < 2.6 and d < 12.0))
			stop.set_pixel(x, y, Color(1.0, 0.62, 0.16) if s_on else (Color(0.05, 0.03, 0.02, 0.85) if s_edge else Color(0, 0, 0, 0)))
	Input.set_custom_mouse_cursor(ImageTexture.create_from_image(aim), Input.CURSOR_CROSS, Vector2(c, c))
	Input.set_custom_mouse_cursor(ImageTexture.create_from_image(stop), Input.CURSOR_FORBIDDEN, Vector2(c, c))


static var _cursors := {}


## The two pointers, drawn once: a sight (a ring and its ticks, red), a shield (brass, a cross on it).
static func _cursor_tex(kind: String) -> Texture2D:
	if _cursors.has(kind):
		return _cursors[kind]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(0.12, 0.08, 0.05, 1.0)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5)
			if kind == "sight":
				var r := d.length()
				var ring := absf(r - 10.0) < 1.3
				var tick := (absf(d.x) < 1.0 and r > 6.0 and r < 15.5) or (absf(d.y) < 1.0 and r > 6.0 and r < 15.5)
				if ring or tick:
					img.set_pixel(x, y, Color(0.9, 0.2, 0.15))
				elif absf(r - 10.0) < 2.4 or (absf(d.x) < 2.0 and r > 5.0 and r < 15.5) or (absf(d.y) < 2.0 and r > 5.0 and r < 15.5):
					img.set_pixel(x, y, ink)
			else:
				# a heater shield: flat top, the sides curving to a point
				var u := (y - 3.0) / 26.0
				var w := 12.0 * (1.0 if u < 0.45 else cos((u - 0.45) / 0.55 * PI * 0.5))
				if u >= 0.0 and u <= 1.0 and absf(d.x) <= w:
					var edge := absf(d.x) > w - 1.8 or u < 0.07
					var cross := absf(d.x) < 1.2 or absf(y - 12.0) < 1.2
					img.set_pixel(x, y, ink if edge else (Color(0.55, 0.38, 0.18) if cross else Color(0.86, 0.68, 0.36)))
	var tex := ImageTexture.create_from_image(img)
	_cursors[kind] = tex
	return tex


## A dead raider or one lying downed, near the screen point `at`.
func _body_under(at: Vector2) -> Villager:
	var best: Villager = null
	var bd := 28.0
	var list: Array[Villager] = []
	list.append_array(raids.corpses)
	list.append_array(village.downed_outlaws)
	for r in list:
		if not is_instance_valid(r) or not (r.dead or r.down):
			continue
		var p := r.global_position + Vector3.UP * 0.3
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(at)
		if d < bd:
			bd = d
			best = r
	return best


## With folk in hand, the foe under the mouse is what they'd fire on: their lines of fire to him and
## the best one's chance (CombatMarks).
func _update_aim() -> void:
	var hands: Array[Villager] = []
	if _placing == "" and _ghost == null:
		hands = _hands()
	marks.shooters = hands
	marks.aim_foe = _raider_under(get_viewport().get_mouse_position()) if not hands.is_empty() else null


## The view rides with the one chosen (or the middle of those chosen) till it's moved by hand.
func follow_chosen() -> void:
	var list: Array[Node3D] = []
	for v in _chosen():
		list.append(v)
	if list.is_empty():
		hud.toast("İzlenecek kimse seçili değil", "info")
		return
	cam.follow = list
	hud.toast("Kamera %s izliyor · kaydırınca bırakır" % (list[0] as Villager).display_name.split(" ")[0] if list.size() == 1 else "Kamera %d kişiyi izliyor · kaydırınca bırakır" % list.size(), "info")


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


## The chosen put to work at `b` (a right-click on it with nobody in hand), as many as it has room for.
func _assign_to(b: Building) -> void:
	var list := _chosen()
	if b == null or list.is_empty():
		hud.toast("Bir işyerine sağ tıkla", "info")
		return
	var done: Array[Villager] = []
	var why := ""
	for v in list:
		var no := village.assign(v, b)
		if no == "":
			done.append(v)
		elif why == "":
			why = no
	if done.is_empty():
		hud.toast(why, "info")
	elif done.size() == 1:
		hud.toast("%s artık %s'de çalışıyor" % [done[0].display_name, b.display_name()] + (" · " + why if why != "" else ""), "good")
	else:
		hud.toast("%d kişi artık %s'de çalışıyor" % [done.size(), b.display_name()] + (" · " + why if why != "" else ""), "good")


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


## The view taken to the one chosen; one in hand (a squad card clicked twice) it then rides with.
func focus_selected() -> void:
	if selected_villager and is_instance_valid(selected_villager):
		cam.jump_to(selected_villager.global_position)
		if village.controlled(selected_villager):
			cam.follow = [selected_villager] as Array[Node3D]


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


## The chosen gate barred, or unbarred.
func toggle_gate_lock() -> void:
	if selected_gate and is_instance_valid(selected_gate):
		selected_gate.set_locked(not selected_gate.locked)
		hud.toast("Kapı kilitlendi: kimse geçemez" if selected_gate.locked else "Kapının kilidi açıldı", "good")
		if selected_gate.locked:
			_count_shut_out()


## Every gate of the town barred, or unbarred.
func lock_all_gates(on: bool) -> void:
	var n := 0
	for w in village.walls:
		if is_instance_valid(w):
			for g in w.gates:
				if is_instance_valid(g):
					g.set_locked(on)
					n += 1
	hud.toast("%d kapı kilitlendi" % n if on else "%d kapının kilidi açıldı" % n, "good")
	if on:
		_count_shut_out()


## Who the barring has left cut off from the stores, said a moment later (the way-finding's grid
## takes its changes between searches).
func _count_shut_out() -> void:
	await get_tree().create_timer(0.6).timeout
	var st: Array = village.stores()
	if st.is_empty():
		return
	var to: Vector3 = (st[0] as Node3D).global_position
	var n := 0
	for v: Villager in village.villagers:
		if v.dead or v.inside != null:
			continue
		var way: PackedVector3Array = village.nav.find_path(v.position, to)
		for i in range(way.size() - 1):
			if not village.barred_at(way[i], way[i + 1]).is_empty():
				n += 1
				break
	if n > 0:
		hud.toast("%d kişi kapıların dışında kaldı: açılana dek giremezler" % n, "bad")


func demolish_selected() -> void:
	if selected_gate and is_instance_valid(selected_gate):
		selected_gate.wall.remove_gate(selected_gate)
		village.add_anywhere("odun", 3, selected_gate.global_position)
		selected_gate = null
		return
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

## The trench as it'll be cut, while it's dragged: a dark strip of its width from where the drag
## began to the mouse, the spoil's side shown lighter.
var _trench_w := 1.3


func _trench_on(box: MeshInstance3D, a: Vector3, b: Vector3) -> MeshInstance3D:
	if box == null:
		box = MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box.material_override = m
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(box)
	var len := Vector2(b.x - a.x, b.z - a.z).length()
	(box.material_override as StandardMaterial3D).albedo_color = Color(0.3, 0.2, 0.12, 0.55) if len >= 2.0 else Color(1.0, 0.3, 0.2, 0.45)
	(box.mesh as BoxMesh).size = Vector3(_trench_w, 0.25, maxf(len, 0.1))
	var mid := (a + b) * 0.5
	mid.y = maxf(village.nav.height(mid.x, mid.z), maxf(a.y, b.y)) + 0.1
	box.visible = true
	box.global_position = mid
	if len > 0.05:
		box.look_at(Vector3(b.x, mid.y, b.z), Vector3.UP)
	return box


func _update_drag() -> void:
	if _drag_from == null:
		if _drag_box:
			_drag_box.visible = false
		return
	var at := _pointer()
	var to: Variant = cam.ground_under(at)
	var color: Color = {"mayin": Color(0.8, 0.25, 0.1, 0.25), "hendek": Color(0.35, 0.25, 0.15, 0.3), "tuzak": Color(0.45, 0.32, 0.2, 0.28), "kes": Color(0.95, 0.2, 0.08, 0.24), "kesme": Color(0.6, 0.75, 1.0, 0.2), "alan": Color(0.55, 0.9, 0.45, 0.2)}[_placing]
	if _placing == "hendek":
		if to == null:
			return
		_drag_box = _trench_on(_drag_box, _drag_from, to)
		hud.set_hint("HENDEK: %d m · genişlik %.1f m (tekerlek: genişlet / daralt) · bırak: kazılsın" % [roundi(Vector2(to.x - _drag_from.x, to.z - _drag_from.z).length()), _trench_w])
		return
	# (the rest drawn on the screen as a plain box, whichever way it's dragged; what's on the ground
	# under it is what's ordered)
	var box := Rect2(_anchored(_drag_from, at), Vector2.ZERO).expand(at)
	hud.show_select_box(box, Color(color, 1.0))
	var quad := _ground_quad(box) if _placing in ["mayin", "tuzak"] else PackedVector2Array()
	_spot_marks(_quad_rect(quad) if quad.size() >= 3 else Rect2(), quad)


## While a box is dragged for mines or pits: a marker where each would go, green if it can, red if
## not (water, a cliff, a building, one there already).
var _marks_mm: MultiMeshInstance3D


func _spot_marks(rect: Rect2, poly := PackedVector2Array()) -> void:
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
	var spots: Array = village.lay_spots(rect, village.MINE_GAP if _placing == "mayin" else village.TRAP_GAP, _placing, poly)
	var mm := _marks_mm.multimesh
	var n := mini(spots.size(), mm.instance_count)
	mm.visible_instance_count = n
	for i in n:
		var e: Array = spots[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, (e[0] as Vector3) + Vector3.UP * 0.08))
		mm.set_instance_color(i, Color(0.3, 0.95, 0.35, 0.75) if str(e[1]) == "" else Color(1.0, 0.25, 0.2, 0.75))
	_marks_mm.visible = true


func _area_done(up: Vector2) -> void:
	var from: Variant = _drag_from
	var to: Variant = cam.ground_under(up)
	_drag_from = null
	hud.show_select_box(Rect2())
	if _drag_box:
		_drag_box.visible = false
	if _marks_mm:
		_marks_mm.visible = false
	if from == null:
		return
	if _placing == "hendek": # (a line, not a box)
		if to == null:
			return
		var n := village.mark_trench(Vector2(from.x, from.z), Vector2(to.x, to.z), _trench_w)
		hud.toast("%d m hendek kazılacak" % (n * 3) if n > 0 else "Hendek o kadar kısa olamaz", "good" if n > 0 else "info")
		return
	var box := Rect2(_anchored(from, up), Vector2.ZERO).expand(up)
	var poly := _ground_quad(box) if box.size.length() > 10.0 else PackedVector2Array()
	var rect := _quad_rect(poly) if poly.size() >= 3 else Rect2()
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		poly = PackedVector2Array()
		if to == null:
			return
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
			var n := village.mark_trees(rect, true, true, poly)
			hud.toast("%d ağaç kesilecek: herkes işini bırakıp gidiyor" % n if n > 0 else "Orada kesilecek ağaç yok", "good" if n > 0 else "info")
		"mayin":
			var n := village.lay_mines(rect, poly)
			hud.toast("%d mayın gömüldü" % n if n > 0 else "Mayın gömülemedi (demir ya da kömür yok, ya da yer uygun değil)", "good" if n > 0 else "info")
		"tuzak":
			var n := village.lay_traps(rect, poly)
			hud.toast("%d kazık tuzağı kuruldu" % n if n > 0 else "Tuzak kurulamadı (odun yok ya da yer uygun değil)", "good" if n > 0 else "info")
		"kesme":
			var n := village.mark_trees(rect, false, false, poly)
			hud.toast("%d ağacın işareti kalktı" % n, "info")
		"alan":
			var b := _area_for
			stop_placing()
			if b and is_instance_valid(b):
				b.work_area = rect
				b.work_poly = poly
				select(b)
				hud.toast("%s yalnızca bu alanda çalışacak" % b.display_name(), "good")


## The selected workplace's drawn area, while it's selected.
func _show_work_area() -> void:
	var b := selected
	if b and is_instance_valid(b) and b.work_area.has_area() and _placing == "":
		var r: Rect2 = b.work_area
		var q: PackedVector2Array = b.work_poly if b.work_poly.size() >= 3 else PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		if _area_box == null or q != _area_shown:
			_area_shown = q
			_area_line(q)
		_area_box.visible = true
	elif _area_box:
		_area_box.visible = false


var _area_shown := PackedVector2Array() ## (the outline drawn just now)


## The work area's outline lying on the ground: a green ribbon, over the rises and falls.
func _area_line(q: PackedVector2Array) -> void:
	if _area_box == null:
		_area_box = MeshInstance3D.new()
		_area_box.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(0.55, 0.9, 0.45, 0.8)
		_area_box.material_override = m
		_area_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_area_box)
	var im := _area_box.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for k in q.size():
		var a := q[k]
		var b := q[(k + 1) % q.size()]
		var across := (b - a).normalized().orthogonal() * 0.3
		var n := maxi(ceili(a.distance_to(b) / 2.0), 1)
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			for s: Vector2 in [p + across, p - across]:
				im.surface_add_vertex(Vector3(s.x, terrain.height_at(s.x, s.y) + 0.35, s.y))
	im.surface_end()


func clear_work_area() -> void:
	if selected and is_instance_valid(selected):
		selected.work_area = Rect2()
		selected.work_poly = PackedVector2Array()
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
var _sel_from := Vector2.INF ## a left press with nothing being placed: where (to tell a click from a drag)
var _sel_shift := false
var _sel_ground: Variant = null ## the ground under where it began: the box stays on it if the view moves
var _sel_far := false ## the pointer's gone far enough for this to be a box, not a click


## Where the mouse is (a test's pin if it has one).
func _pointer() -> Vector2:
	return get_viewport().get_mouse_position() if mouse_pin == Vector2.INF else mouse_pin


## Where a box began on the screen as the view stands now: on the `ground` it was begun over, else
## where it was pressed.
func _anchored(ground: Variant, pressed: Vector2) -> Vector2:
	var c := get_viewport().get_camera_3d()
	if ground == null or c.is_position_behind(ground):
		return pressed
	return c.unproject_position(ground)


## A left drag in the world, each frame: the box from where it began to the pointer, any way round,
## over the panels too.
func _update_select() -> void:
	if _sel_from == Vector2.INF:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): # (let go somewhere that never told us)
		_sel_from = Vector2.INF
		hud.show_select_box(Rect2())
		return
	var at := _pointer()
	var start := _anchored(_sel_ground, _sel_from)
	_sel_far = _sel_far or at.distance_to(start) > 10.0
	if _sel_far:
		hud.show_select_box(Rect2(start, Vector2.ZERO).expand(at))


func _end_select(up: Vector2) -> void:
	var start := _anchored(_sel_ground, _sel_from)
	if _sel_far or up.distance_to(start) > 10.0:
		_box_select(Rect2(start, Vector2.ZERO).expand(up), _sel_shift)
	else:
		_pick(_sel_from, _sel_shift)
	_sel_from = Vector2.INF
	hud.show_select_box(Rect2())
	hud.build_keys = false # (picking in the world: the numbers go back to the groups)


## The ground under a box on the screen: its four corners as they fall (a corner off the map or in
## the sky pulled in toward the middle till it's on the ground).
func _ground_quad(box: Rect2) -> PackedVector2Array:
	var mid := box.get_center()
	var out := PackedVector2Array()
	for c: Vector2 in [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]:
		for k in 6:
			var g: Variant = cam.ground_under(c.lerp(mid, k / 6.0))
			if g != null:
				out.append(Vector2(g.x, g.z))
				break
	return out


func _quad_rect(q: PackedVector2Array) -> Rect2:
	var r := Rect2(q[0], Vector2.ZERO)
	for p in q:
		r = r.expand(p)
	return r
var _trouble_i := -1 ## which of the troubled places was shown last (show_trouble)


## The next of what's stopped the work (a workshop with its pile full, or with the stores full the
## fullest store): picked, and the view taken to it.
func show_trouble() -> void:
	if raids.camp_known and not _camp_turn:
		_camp_turn = true
		cam.jump_to(raids.camp_at)
		hud.toast("Firari kampı · %d kişi: milisi seç (V), R ile emre al, kampa sağ tıkla" % raids.camp_men.size(), "bad")
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
	hud.set_hint("Atölye (%s): %s · Q / E çevir · Sağ tık iptal" % [w.word, BuildingDefs.cost_text(_placing)])


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
	cam.hold_keys = _ghost != null # (placing: Q and E turn the building, not the view)
	_update_pointer()
	_update_aim()
	# The first train in: the view rides with it till it stops at the platform.
	if village.arriving and is_instance_valid(village.train) and not village.train.is_standing() and not _cam_free:
		cam.focus = cam.focus.lerp(village.train.engine_at(), 0.08)
	if village.day != _saved_day and weather.hour > 6.0 and not raids.active and not village.arriving:
		_saved_day = village.day
		VillageSave.save(self) # (every morning)
	_update_select()
	if _placing in ["yol", "sur"]: # (the palisade's stakes shown to the mouse as the road's planks are)
		_update_road_line()
	elif _placing == "kapi":
		_update_gate_ghost()
	elif AREA_ORDERS.has(_placing):
		_update_drag()
	elif _placing != "":
		_update_ghost()
	_show_work_area()
	if selected_villager and is_instance_valid(selected_villager) and not selected_villager.dead and selected_villager.visible:
		_ring.visible = true
		_ring.global_transform = Transform3D(Basis().scaled(Vector3(0.7, 0.4, 0.7)), selected_villager.global_position + Vector3.UP * 0.08)
	elif selected_gate and is_instance_valid(selected_gate):
		_ring.visible = true
		_ring.global_transform = Transform3D(Basis().scaled(Vector3(3.0, 0.6, 3.0)), selected_gate.global_position + Vector3.UP * 0.5)
	elif selected and is_instance_valid(selected) and selected.state != "gone":
		_ring.visible = true
		var r := selected.radius + 0.8
		_ring.global_transform = Transform3D(Basis().scaled(Vector3(r, 0.6, r)), selected.global_position + Vector3.UP * 0.5)
	else:
		_ring.visible = false
		if selected and (not is_instance_valid(selected) or selected.state == "gone"):
			selected = null
	# the others chosen with it, each ringed
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
