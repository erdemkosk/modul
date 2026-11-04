class_name TitleMenu
extends CanvasLayer
## The title screen, before any valley's made: the train at the rock fall behind it (assets/ui/title_bg.jpg,
## the game's painting), the name and the menu down the left over a shade, and the settings
## (SettingsPanel) on the right when chosen. A new town has a screen of its own: on the left its
## seed (typed or thrown), how many come on the train, how much they bring, how hard the raids
## come, the season they arrive in; on the right the settlers themselves, each with their face,
## knacks, keenness and traits, each to be thrown again till they're the crew wanted. Esc goes back.

const BG := "res://assets/ui/title_bg.jpg"
const HOT := Color(1.0, 0.66, 0.3) ## (a menu item pointed at, over the dark picture)
const NEW_BG := "res://assets/ui/newtown_bg.jpg" ## the new town's painted board (its logo and foot buttons on it)
const VALLEY := "res://assets/ui/newtown_valley.jpg"
const PARCHMENT := "res://assets/ui/parchment.png" ## (tools/parchment.py)
const STAGE := Vector2(1920, 1080)

var game: Node ## main.gd

var _seed: LineEdit
var _people := 6
var _people_label: Label
var _choice := {"supplies": 1, "raids": 1, "season": 0}
var _groups := {} ## setting -> its buttons
var _new_plate: Control ## the new town's screen
var _stage: Control ## what's on it, scaled to the screen
var _menu: Control ## the name and the menu (put away while the new town's screen is up)
var _settings: SettingsPanel
var _credits: Control ## who made what (EMEĞİ GEÇENLER)
var _crew: Array = [] ## the settlers to come (Villager.candidate), couples one after the other
var _crew_grid: GridContainer
var _crew_faces: Array = [] ## [TextureRect, seed] a card each, its face filled in as it's taken
var _rng := RandomNumberGenerator.new()
var _items := {} ## menu item -> its button
var _open := "" ## the plate shown ("" none)


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	# the picture, filling the screen, and the shades over it: dark down the left for the menu,
	# a little at the foot
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.05, 0.055, 0.06)
	root.add_child(back)
	if ResourceLoader.exists(BG):
		var pic := TextureRect.new()
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.texture = load(BG)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		root.add_child(pic)
	root.add_child(_shade(Vector2(0, 0.5), Vector2(1, 0.5), [Color(0.03, 0.03, 0.035, 0.92), Color(0.03, 0.03, 0.035, 0.7), Color(0.03, 0.03, 0.035, 0.0)], [0.0, 0.32, 0.62]))
	root.add_child(_shade(Vector2(0.5, 1), Vector2(0.5, 0), [Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0)], [0.0, 0.3]))
	# the name and the menu
	_rng.randomize()
	add_child(Portraits.new())
	var col := VBoxContainer.new()
	_menu = col
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 96
	col.offset_top = -250
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	var logo := Logo.new()
	logo.tall = 104.0
	logo.sub = "KORDAL TAYGASI · 1918"
	col.add_child(logo)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	col.add_child(gap)
	Ui.rule(col, 80.0)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap2)
	var saved := VillageSave.read() if VillageSave.exists() else {}
	if not saved.is_empty():
		_item(col, "DEVAM ET", "Gün %d · %d kişi" % [int(saved.get("day", 1)), (saved.get("people", []) as Array).size()], func() -> void: game.continue_game())
	_item(col, "YENİ KASABA", "Bir vadi, bir tren, yeni yerleşimciler", func() -> void: _toggle("new"))
	_item(col, "AYARLAR", "Grafik, ses, oyun", func() -> void: _toggle("settings"))
	_item(col, "EMEĞİ GEÇENLER", "Sesler, modeller, yazılar", func() -> void: _toggle("credits"))
	_item(col, "ÇIK", "", func() -> void: get_tree().quit())
	var foot := Ui.label(root, "Esc: geri", 13, Color(Ui.LIGHT, 0.6))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 96
	foot.offset_top = -44
	# the plates on the right
	_new_game_plate(root)
	_settings = SettingsPanel.new()
	_place_plate(_settings)
	_settings.closed.connect(func() -> void: _toggle(""))
	root.add_child(_settings)
	_settings.visible = false
	_credits = _credits_plate()
	_place_plate(_credits)
	root.add_child(_credits)
	_credits.visible = false
	_toggle("")
	# (in from black)
	root.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(root, "modulate:a", 1.0, 0.6)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_ESCAPE and _open != "":
		_toggle("")
		get_viewport().set_input_as_handled()


var _face_t := 0.0


func _process(dt: float) -> void:
	_face_t += dt
	if _face_t < 0.2 or not _new_plate.visible:
		return
	_face_t = 0.0
	for f: Array in _crew_faces:
		if (f[0] as TextureRect).texture == null:
			(f[0] as TextureRect).texture = Portraits.of_look(int(f[1]), str(f[2]))


## A shade across the screen: `colors` at `offsets` from `from` to `to` (0..1 of the screen).
func _shade(from: Vector2, to: Vector2, colors: Array, offsets: Array) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = from
	gt.fill_to = to
	gt.width = 256
	gt.height = 256
	var r := TextureRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A menu item: its name big, a line under it, an orange bar beside it while it's pointed at or open.
func _item(col: VBoxContainer, text: String, note: String, f: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 54)
	b.add_theme_font_override("font", Ui.font("display"))
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", Ui.LIGHT)
	b.add_theme_color_override("font_hover_color", HOT)
	b.add_theme_color_override("font_pressed_color", HOT)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 18
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(1.0, 0.56, 0.14, 0.12)
	lit.border_color = HOT
	lit.border_width_left = 4
	lit.content_margin_left = 18
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("pressed", lit)
	b.pressed.connect(f)
	col.add_child(b)
	_items[text] = b
	if note != "":
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 22)
		m.add_theme_constant_override("margin_bottom", 8)
		col.add_child(m)
		Ui.label(m, note, 14, Color(Ui.LIGHT, 0.6))


## The plate `which` ("new", "settings") shown on the right, or none ("" or the open one again).
func _toggle(which: String) -> void:
	_open = "" if which == _open else which
	_menu.visible = _open != "new"
	if _open == "new" and _crew.is_empty():
		_fill_crew()
	for p: Control in [_new_plate, _settings, _credits]:
		var on := (p == _new_plate and _open == "new") or (p == _settings and _open == "settings") or (p == _credits and _open == "credits")
		if on and not p.visible:
			p.visible = true
			p.modulate.a = 0.0
			var tw := create_tween().set_parallel()
			tw.tween_property(p, "modulate:a", 1.0, 0.18)
		elif not on:
			p.visible = false
	for key: String in _items:
		var open: bool = (key == "YENİ KASABA" and _open == "new") or (key == "AYARLAR" and _open == "settings") or (key == "EMEĞİ GEÇENLER" and _open == "credits")
		(_items[key] as Button).add_theme_color_override("font_color", HOT if open else Ui.LIGHT)


## Who made what the game's made of: every outside source, its author and its licence (the full lists
## are in each folder's CREDITS.md).
const CREDITS := [
	["OYUN", [["Tasarım ve geliştirme", "erdemkosk"], ["Motor", "Godot Engine 4.7 (MIT)"]]],
	["SESLER · CC0", [
		["Buharlı tren düdüğü, tüfek, makineli tüfek, top", "Joseph Sardin · BigSoundBank.com"],
		["Orman, kuşlar, dere, soğuk rüzgâr", "Joseph Sardin · BigSoundBank.com"],
		["Karda ve toprakta ayak sesi, ocak çıtırtısı, yangın, tren buharı, cenaze ilahisi", "Joseph Sardin · BigSoundBank.com"],
		["Balta, kütük, ağaç devrilmesi", "Joseph Sardin · BigSoundBank.com"],
		["İnşaat sesleri", "dudebrobrodude, SamuelGremaud, AlaskaRobotics, Bibow, celadon_noise, Anthousai, CallFlan · Freesound.org"],
		["Telgraf, çan, cırcır böcekleri, yağmur, gök gürültüsü", "oyunun içinde üretildi"]]],
	["KARAKTERLER · CC0", [
		["Kasabalı gövdesi", "Mud Run projesinin survivor modeli"],
		["Hareket kayıtları (yürüme, taşıma, yeme...)", "Quaternius · Universal Animation Library"],
		["Yüzler, ten, kaş, sakal", "MakeHuman ekibi, Jartur69, Mindfront, onlytheghosts, Toigo, Rehman Polanski · MakeHuman Community"]]],
	["DÜNYA", [
		["Binalar, tren, ağaçlar, kayalar", "Blender ile kodla üretildi (tools/blender)"],
		["Arazi, gökyüzü, su, hava", "oyunun içinde üretildi"]]],
	["YAZI TİPLERİ · SIL Open Font License", [["Barlow, Barlow Condensed", "The Barlow Project Authors"], ["Chakra Petch", "The Chakra Petch Project Authors"], ["Old Standard", "The Old Standard Project Authors"], ["Courier Prime", "The Courier Prime Project Authors"]]],
]


func _credits_plate() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.glass(false, 18.0))
	p.custom_minimum_size = Vector2(560, 0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	Ui.label(col, "EMEĞİ GEÇENLER", 30, Ui.LIGHT, "display")
	Ui.rule(col)
	for sec: Array in CREDITS:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		col.add_child(gap)
		Ui.label(col, str(sec[0]), 15, HOT, "head")
		for row: Array in sec[1]:
			var what := Ui.label(col, str(row[0]), 15, Ui.LIGHT, "head")
			what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			what.custom_minimum_size = Vector2(500, 0)
			var who := Ui.label(col, str(row[1]), 13, Color(Ui.LIGHT, 0.65))
			who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			who.custom_minimum_size = Vector2(500, 0)
	var note := Ui.label(col, "\nCC0: kamu malı, izin ya da atıf gerekmez; yine de hepsine teşekkürler.", 12, Color(Ui.LIGHT, 0.5))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(500, 0)
	return p


func _place_plate(p: Control) -> void:
	p.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.offset_right = -96


func _new_game_plate(root: Control) -> void:
	var screen := Control.new()
	_new_plate = screen
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	var dark := ColorRect.new()
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.color = Color(0.05, 0.045, 0.04)
	screen.add_child(dark)
	# laid out for 1920 x 1080 on the painted board and scaled whole to fit the screen
	_stage = Control.new()
	_stage.size = STAGE
	screen.add_child(_stage)
	get_viewport().size_changed.connect(_fit_stage)
	_fit_stage()
	var pic := TextureRect.new()
	pic.texture = load(NEW_BG)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.size = STAGE
	_stage.add_child(pic)
	var name := Logo.new()
	name.tall = 44.0
	name.position = Vector2(150, 0)
	_stage.add_child(name)
	# the town, on the left
	var col := _sheet(Rect2(16, 112, 556, 610), 12)
	Ui.label(col, "YENİ KASABA", 44, Ui.P_INK, "display")
	Ui.label(col, "Trenini hazırla, ekibini seç ve Kordal Taygası'nda yeni bir yerleşim kur.", 14, Ui.P_INK)
	var valley := PanelContainer.new()
	valley.add_theme_stylebox_override("panel", _line_box())
	col.add_child(valley)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 14)
	valley.add_child(vrow)
	var thumb := TextureRect.new()
	thumb.texture = load(VALLEY)
	thumb.custom_minimum_size = Vector2(92, 80)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	vrow.add_child(thumb)
	var vcol := VBoxContainer.new()
	vcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vrow.add_child(vcol)
	Ui.label(vcol, "VADİ", 18, Ui.P_INK, "head")
	_wrap(Ui.label(vcol, "Tohum vadiyi ve demiryolunu belirler. Tren vadide ilerler, nerede ineceğinize siz karar verirsiniz.", 14, Ui.P_INK))
	# the seed
	var row := _row(col, "TOHUM", "Aynı tohum aynı yeri, aynı demiryolunu verir")
	_seed = LineEdit.new()
	_seed.custom_minimum_size = Vector2(240, 38)
	_seed.add_theme_font_override("font", Ui.font("display"))
	_seed.add_theme_font_size_override("font_size", 21)
	_seed.add_theme_color_override("font_color", Ui.INK)
	var well := StyleBoxFlat.new()
	well.bg_color = Color(0.27, 0.19, 0.13)
	well.set_corner_radius_all(3)
	well.content_margin_left = 12
	_seed.add_theme_stylebox_override("normal", well)
	_seed.add_theme_stylebox_override("focus", well)
	_seed.text = str(randi_range(1, 999999))
	row.add_child(_seed)
	row.add_child(_key("ZAR", func() -> void: _seed.text = str(randi_range(1, 999999))))
	# how many
	row = _row(col, "KİŞİ", "Trenle gelen yerleşimciler")
	row.add_child(_key("‹", func() -> void: _set_people(_people - 1), 42))
	_people_label = Ui.label(row, str(_people), 24, Ui.P_INK, "display")
	_people_label.custom_minimum_size = Vector2(70, 0)
	_people_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_key("›", func() -> void: _set_people(_people + 1), 42))
	_choices(col, "MALZEME", "supplies", ["AZ", "NORMAL", "BOL"], "Trenin getirdiği odun, taş, yiyecek (kişi sayısıyla birlikte artar)")
	_choices(col, "BASKINLAR", "raids", ["KOLAY", "NORMAL", "ZOR"], "Firarilerin ne zaman, ne sıklıkla, kaç kişi geldiği")
	_choices(col, "MEVSİM", "season", ["İLKBAHAR", "YAZ", "SONBAHAR", "KIŞ"], "Trenin geldiği mevsim")
	# the crew, on the right
	var ccol := _sheet(Rect2(562, 124, 1344, 622), 8)
	var top := HBoxContainer.new()
	ccol.add_child(top)
	var heads := VBoxContainer.new()
	heads.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.add_theme_constant_override("separation", 2)
	top.add_child(heads)
	Ui.label(heads, "EKİBİNİ SEÇ", 32, Ui.P_INK, "display")
	Ui.label(heads, "Trenle bunlar gelecek, çift çift. Beğenmediğini YENİDEN ile değiştir; her özelliğin artısı da eksisi de oyunu doğrudan etkiler.", 14, Ui.P_INK)
	var again := _key("RASTGELE EKİP", func() -> void:
		_crew.clear()
		_fill_crew(), 180)
	again.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(again)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ccol.add_child(scroll)
	_crew_grid = GridContainer.new()
	_crew_grid.columns = 3
	_crew_grid.add_theme_constant_override("h_separation", 6)
	_crew_grid.add_theme_constant_override("v_separation", 6)
	_crew_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_crew_grid)
	# the foot: the board's own painted buttons, lit under the pointer
	_foot(Rect2(38, 1000, 174, 58), func() -> void: _toggle(""))
	_foot(Rect2(1532, 972, 350, 86), func() -> void:
		game.begin_new({"seed": maxi(int(_seed.text), 1), "people": _people, "supplies": [0.6, 1.0, 1.6][_choice.supplies],
			"raids": _choice.raids, "season": _choice.season, "crew": _crew.duplicate(true)}))


## The stage scaled and centred on the screen.
func _fit_stage() -> void:
	if not is_instance_valid(_stage):
		return
	var room := get_viewport().get_visible_rect().size
	var k := minf(room.x / STAGE.x, room.y / STAGE.y)
	_stage.scale = Vector2(k, k)
	_stage.position = (room - STAGE * k) * 0.5


## A torn sheet at `at` on the stage: the column to write on.
func _sheet(at: Rect2, gap: int) -> VBoxContainer:
	var sheet := PanelContainer.new()
	var box := StyleBoxTexture.new()
	box.texture = load(PARCHMENT)
	box.set_texture_margin_all(110.0)
	box.content_margin_left = 44.0
	box.content_margin_right = 46.0
	box.content_margin_top = 52.0
	box.content_margin_bottom = 40.0
	sheet.add_theme_stylebox_override("panel", box)
	sheet.position = at.position
	sheet.size = at.size
	_stage.add_child(sheet)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", gap)
	sheet.add_child(col)
	return col


## A thin ruled box on the paper.
func _line_box(margin := 10.0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(1.0, 0.95, 0.82, 0.16)
	b.border_color = Color(0.36, 0.24, 0.13, 0.42)
	b.set_border_width_all(1)
	b.set_corner_radius_all(2)
	b.set_content_margin_all(margin)
	return b


## A key on the paper: raised card, dark ink; `on` the chosen one, burnt orange.
func _key_box(on: bool, hover := false) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.7, 0.4, 0.12) if on else Color(0.84, 0.74, 0.57).lightened(0.1 if hover else 0.0)
	b.border_color = Color(0.36, 0.23, 0.12, 0.9)
	b.set_border_width_all(1)
	b.border_width_bottom = 2
	b.set_corner_radius_all(3)
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 5
	b.content_margin_bottom = 5
	return b


func _key(text: String, f: Callable, w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 36)
	b.add_theme_font_override("font", Ui.face("head", 15))
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_constant_override("outline_size", 0)
	for st: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(st, Ui.P_INK)
	b.add_theme_stylebox_override("normal", _key_box(false))
	b.add_theme_stylebox_override("hover", _key_box(false, true))
	b.add_theme_stylebox_override("pressed", _key_box(true))
	b.pressed.connect(f)
	return b


## One of the buttons painted on the board at `at`: a clear button over it, a warm light when pointed at.
func _foot(at: Rect2, f: Callable) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = at.position
	b.size = at.size
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(1.0, 0.75, 0.4, 0.14)
	lit.set_corner_radius_all(6)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("pressed", lit)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(f)
	_stage.add_child(b)


## The crew made up to how many come: couples, a man and then his wife with his name (those there
## already kept).
func _fill_crew() -> void:
	while _crew.size() > _people:
		_crew.pop_back()
	while _crew.size() < _people:
		var k := _crew.size()
		_crew.append(_new_settler(k))
	_show_crew()


func _new_settler(k: int) -> Dictionary:
	var used: Array = _crew.map(func(c: Dictionary) -> String: return str(c.family))
	var fam := str(_crew[k - 1].family) if k % 2 == 1 and k - 1 < _crew.size() else ""
	var c := Villager.candidate(_rng, k % 2 == 1, fam)
	var tries := 0
	while fam == "" and str(c.family) in used and tries < 12: # (a new family's name, not one there)
		c = Villager.candidate(_rng, false, "")
		tries += 1
	return c


func _show_crew() -> void:
	for ch in _crew_grid.get_children():
		ch.queue_free()
	_crew_faces.clear()
	for k in _crew.size():
		_crew_grid.add_child(_settler_card(k))


## A settler's card: their face in a dark frame, name and sign, what they did, their three best knacks
## (♥ keen), their traits' good and bad, and YENİDEN to throw them again (a wife keeps her husband's
## name).
func _settler_card(k: int) -> Control:
	var c: Dictionary = _crew[k]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _line_box(8.0))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 226)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(128, 200)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var kind := "woman" if bool(c.get("female", false)) else "man"
	face.texture = Portraits.of_look(int(c.look_seed), kind)
	row.add_child(face)
	_crew_faces.append([face, int(c.look_seed), kind])
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var name := Ui.label(head, str(c.name), 20, Ui.P_INK, "display")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	var redo := _key("YENİDEN", func() -> void:
		var fam := str(_crew[k].family)
		_crew[k] = Villager.candidate(_rng, bool(_crew[k].female), fam) # (the family's name kept: a couple stays one)
		_show_crew())
	redo.custom_minimum_size = Vector2(0, 26)
	redo.add_theme_font_size_override("font_size", 12)
	head.add_child(redo)
	var from := str(c.get("origin", ""))
	var said := "%s ailesi." % c.family
	if from != "":
		var o: Dictionary = Villager.ORIGINS[from]
		Ui.label(col, "%s · %s" % [Ui.upper(str(o.name)), "KADIN" if c.female else "ERKEK"], 14, Ui.P_INK, "head")
		said = "%s ailesi. %s (%s +%d)" % [c.family, o.desc, Villager.SKILLS[o.skill], int(o.by)]
	_wrap(Ui.label(col, said, 13, Ui.P_DIM))
	var ks: Array = (c.skills as Dictionary).keys()
	ks.sort_custom(func(a: String, b: String) -> bool: return float(c.skills[a]) > float(c.skills[b]))
	for sk: String in ks.slice(0, 3):
		Ui.label(col, "+  %s +%d%s" % [Villager.SKILLS[sk], int(c.skills[sk]), " ♥" if sk in c.keen else ""], 15, Ui.P_GREEN, "strong")
	var weak: String = ks[ks.size() - 1]
	var tip := "Zayıf: %s %d" % [Villager.SKILLS[weak], int(c.skills[weak])]
	if (c.traits as Array).is_empty():
		Ui.label(col, "–  Özelliği yok (sıradan biri)", 14, Ui.P_RED, "strong")
	for t: String in c.traits:
		var tr: Dictionary = Villager.TRAITS[t]
		_wrap(Ui.label(col, "–  %s (%s)" % [tr.name, tr.minus], 14, Ui.P_RED, "strong"))
		tip += "\n%s: %s" % [tr.name, tr.plus]
	card.tooltip_text = tip
	return card


## A label that wraps to its card's width rather than stretching it.
func _wrap(l: Label) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _row(col: VBoxContainer, title: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.tooltip_text = tip
	col.add_child(row)
	var l := Ui.label(row, title, 17, Ui.P_INK, "head")
	l.custom_minimum_size = Vector2(124, 0)
	return row


func _choices(col: VBoxContainer, title: String, key: String, names: Array, tip: String) -> void:
	var row := _row(col, title, tip)
	var group: Array[Button] = []
	for i in names.size():
		var b := _key(names[i], func() -> void:
			_choice[key] = i
			_mark(key))
		row.add_child(b)
		group.append(b)
	_groups[key] = group
	_mark(key)


func _mark(key: String) -> void:
	var group: Array = _groups[key]
	for i in group.size():
		var on: bool = i == int(_choice[key])
		for st: String in ["font_color", "font_hover_color"]:
			(group[i] as Button).add_theme_color_override(st, Ui.INK if on else Ui.P_INK)
		(group[i] as Button).add_theme_stylebox_override("normal", _key_box(on))
		(group[i] as Button).add_theme_stylebox_override("hover", _key_box(on, true))


func _set_people(n: int) -> void:
	_people = clampi(n, 4, 12)
	_people_label.text = str(_people)
	if not _crew.is_empty():
		_fill_crew()


func _button(text: String, f: Callable, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 36)
	b.add_theme_font_override("font", Ui.font("head"))
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_stylebox_override("normal", Ui.glass(false, 6.0, Color(1, 1, 1, 0.06)))
	b.add_theme_stylebox_override("hover", Ui.glass(false, 6.0, Color(1.0, 0.56, 0.14, 0.3), Ui.ACCENT))
	b.add_theme_stylebox_override("pressed", Ui.glass(false, 6.0, Color(1.0, 0.56, 0.14, 0.45), Ui.ACCENT))
	b.pressed.connect(f)
	return b
