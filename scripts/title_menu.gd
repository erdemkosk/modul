class_name TitleMenu
extends CanvasLayer
## The title screen, before any valley's made: the town at dusk behind it (assets/ui/title_bg.jpg,
## a picture from the game), the name and the menu down the left over a shade, and the settings
## (SettingsPanel) on the right when chosen. A new town has a screen of its own: on the left its
## seed (typed or thrown), how many come on the train, how much they bring, how hard the raids
## come, the season they arrive in; on the right the settlers themselves, each with their face,
## knacks, keenness and traits, each to be thrown again till they're the crew wanted. Esc goes back.

const BG := "res://assets/ui/title_bg.jpg"
const HOT := Color(1.0, 0.66, 0.3) ## (a menu item pointed at, over the dark picture)

var game: Node ## main.gd

var _seed: LineEdit
var _people := 6
var _people_label: Label
var _choice := {"supplies": 1, "raids": 1, "season": 0}
var _groups := {} ## setting -> its buttons
var _new_plate: Control ## the new town's screen
var _menu: Control ## the name and the menu (put away while the new town's screen is up)
var _settings: SettingsPanel
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
	Ui.label(col, "İNŞA", 120, Ui.LIGHT, "display")
	var sub := Ui.label(col, "ZAROVYA · KORDAL TAYGASI · 1918 — SAVAŞTAN KAÇANLARIN KURDUĞU KASABA", 18, Color(Ui.LIGHT, 0.7), "head")
	sub.add_theme_constant_override("outline_size", 0)
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
	for p: Control in [_new_plate, _settings]:
		var on := (p == _new_plate and _open == "new") or (p == _settings and _open == "settings")
		if on and not p.visible:
			p.visible = true
			p.modulate.a = 0.0
			var tw := create_tween().set_parallel()
			tw.tween_property(p, "modulate:a", 1.0, 0.18)
		elif not on:
			p.visible = false
	for key: String in _items:
		var open: bool = (key == "YENİ KASABA" and _open == "new") or (key == "AYARLAR" and _open == "settings")
		(_items[key] as Button).add_theme_color_override("font_color", HOT if open else Ui.LIGHT)


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
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.025, 0.55)
	screen.add_child(dim)
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 60
	outer.offset_right = -60
	outer.offset_top = 40
	outer.offset_bottom = -36
	outer.add_theme_constant_override("separation", 14)
	screen.add_child(outer)
	Ui.label(outer, "YENİ KASABA", 52, Ui.LIGHT, "display")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	# the town, on the left
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", Ui.glass(false, 20.0))
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(400, 0)
	plate.add_child(col)
	Ui.label(col, "VADİ", 28, Ui.INK, "display")
	Ui.label(col, "Tren sizi ve yerleşimcileri vadiye bırakır; gerisi size kalmış.", 14, Ui.DIM)
	Ui.rule(col)
	# the seed
	var row := _row(col, "TOHUM", "Aynı tohum aynı yeri, aynı demiryolunu verir")
	_seed = LineEdit.new()
	_seed.custom_minimum_size = Vector2(170, 36)
	_seed.add_theme_font_override("font", Ui.font("display"))
	_seed.add_theme_font_size_override("font_size", 20)
	_seed.text = str(randi_range(1, 999999))
	row.add_child(_seed)
	row.add_child(_button("ZAR AT", func() -> void: _seed.text = str(randi_range(1, 999999)), 0))
	# how many
	row = _row(col, "KİŞİ", "Trenle gelen yerleşimciler")
	row.add_child(_button("−", func() -> void: _set_people(_people - 1), 40))
	_people_label = Ui.label(row, str(_people), 22, Ui.INK, "display")
	_people_label.custom_minimum_size = Vector2(40, 0)
	_people_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_button("+", func() -> void: _set_people(_people + 1), 40))
	_choices(col, "MALZEME", "supplies", ["AZ", "NORMAL", "BOL"], "Trenin getirdiği odun, taş, yiyecek (kişi sayısıyla birlikte artar)")
	_choices(col, "BASKINLAR", "raids", ["KOLAY", "NORMAL", "ZOR"], "Firarilerin ne zaman, ne sıklıkla, kaç kişi geldiği")
	_choices(col, "MEVSİM", "season", ["İLKBAHAR", "YAZ", "SONBAHAR", "KIŞ"], "Trenin geldiği mevsim")
	# the crew, on the right
	var cplate := PanelContainer.new()
	cplate.add_theme_stylebox_override("panel", Ui.glass(false, 20.0))
	cplate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(cplate)
	var ccol := VBoxContainer.new()
	ccol.add_theme_constant_override("separation", 10)
	cplate.add_child(ccol)
	Ui.label(ccol, "EKİBİNİ SEÇ", 28, Ui.INK, "display")
	Ui.label(ccol, "Trenle bunlar gelecek, çift çift. Beğenmediğini YENİDEN ile değiştir: her özelliğin artısı da eksisi de oyunu doğrudan etkiler.", 14, Ui.DIM).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ccol.add_child(scroll)
	_crew_grid = GridContainer.new()
	_crew_grid.columns = 2
	_crew_grid.add_theme_constant_override("h_separation", 10)
	_crew_grid.add_theme_constant_override("v_separation", 10)
	_crew_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_crew_grid)
	# the foot: back, all again, away
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	outer.add_child(foot)
	foot.add_child(_button("GERİ", func() -> void: _toggle(""), 160))
	foot.add_child(_button("HEPSİNİ YENİDEN", func() -> void:
		_crew.clear()
		_fill_crew(), 200))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var go := _button("YOLA ÇIK", func() -> void:
		game.begin_new({"seed": maxi(int(_seed.text), 1), "people": _people, "supplies": [0.6, 1.0, 1.6][_choice.supplies],
			"raids": _choice.raids, "season": _choice.season, "crew": _crew.duplicate(true)}), 260)
	go.custom_minimum_size = Vector2(260, 54)
	go.add_theme_font_override("font", Ui.font("display"))
	go.add_theme_font_size_override("font_size", 26)
	go.add_theme_color_override("font_color", Ui.ACCENT)
	foot.add_child(go)


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
	# (as many columns as fit the screen beside the valley's plate: a card wants ~380)
	var room := get_viewport().get_visible_rect().size.x - 120.0 - 440.0 - 60.0
	_crew_grid.columns = clampi(int(room / 380.0), 1, 3)
	for ch in _crew_grid.get_children():
		ch.queue_free()
	_crew_faces.clear()
	for k in _crew.size():
		_crew_grid.add_child(_settler_card(k))


## A settler's card: their face, name and family, their three best knacks (♥ keen), their traits'
## good and bad, and YENİDEN to throw them again (a wife keeps her husband's name).
func _settler_card(k: int) -> Control:
	var c: Dictionary = _crew[k]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Ui.glass(false, 10.0, Color(1, 1, 1, 0.05)))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(84, 84)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var kind := "woman" if bool(c.get("female", false)) else "man"
	face.texture = Portraits.of_look(int(c.look_seed), kind)
	row.add_child(face)
	_crew_faces.append([face, int(c.look_seed), kind])
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var name := Ui.label(head, str(c.name), 20, Ui.INK, "display")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	head.add_child(_button("YENİDEN", func() -> void:
		var fam := str(_crew[k].family)
		_crew[k] = Villager.candidate(_rng, bool(_crew[k].female), fam) # (the family's name kept: a couple stays one)
		_show_crew(), 0))
	Ui.label(col, "%s · %s ailesi" % ["kadın" if c.female else "erkek", c.family], 13, Ui.DIM)
	var from := str(c.get("origin", ""))
	if from != "":
		var o: Dictionary = Villager.ORIGINS[from]
		Ui.label(col, Ui.upper(str(o.name)), 13, Ui.ACCENT, "head")
		_wrap(Ui.label(col, "%s (%s +%d)" % [o.desc, Villager.SKILLS[o.skill], int(o.by)], 12, Ui.DIM))
	var ks: Array = (c.skills as Dictionary).keys()
	ks.sort_custom(func(a: String, b: String) -> bool: return float(c.skills[a]) > float(c.skills[b]))
	var best: Array[String] = []
	for sk: String in ks.slice(0, 3):
		best.append("%s %d%s" % [Villager.SKILLS[sk], int(c.skills[sk]), " ♥" if sk in c.keen else ""])
	var weak: String = ks[ks.size() - 1]
	_wrap(Ui.label(col, " · ".join(best), 14, Ui.INK, "strong"))
	var extra := []
	for kk: String in c.keen:
		if not kk in ks.slice(0, 3):
			extra.append("%s ♥" % Villager.SKILLS[kk])
	_wrap(Ui.label(col, ("hevesli: " + ", ".join(extra) + " · " if not extra.is_empty() else "") + "zayıf: %s %d" % [Villager.SKILLS[weak], int(c.skills[weak])], 12, Ui.DIM))
	if (c.traits as Array).is_empty():
		Ui.label(col, "Özelliği yok: sıradan biri", 13, Ui.DIM)
	for t: String in c.traits:
		var tr: Dictionary = Villager.TRAITS[t]
		Ui.label(col, Ui.upper(str(tr.name)), 13, Ui.ACCENT, "head")
		_wrap(Ui.label(col, "+ " + str(tr.plus), 13, Ui.GOOD))
		_wrap(Ui.label(col, "− " + str(tr.minus), 13, Ui.BAD))
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
	var l := Ui.label(row, title, 15, Ui.ACCENT, "head")
	l.custom_minimum_size = Vector2(120, 0)
	return row


func _choices(col: VBoxContainer, title: String, key: String, names: Array, tip: String) -> void:
	var row := _row(col, title, tip)
	var group: Array[Button] = []
	for i in names.size():
		var b := _button(names[i], func() -> void:
			_choice[key] = i
			_mark(key), 0)
		row.add_child(b)
		group.append(b)
	_groups[key] = group
	_mark(key)


func _mark(key: String) -> void:
	var group: Array = _groups[key]
	for i in group.size():
		(group[i] as Button).add_theme_color_override("font_color", Ui.ACCENT if i == int(_choice[key]) else Ui.INK)
		(group[i] as Button).add_theme_stylebox_override("normal", Ui.glass(false, 6.0, Color(1.0, 0.56, 0.14, 0.25) if i == int(_choice[key]) else Color(1, 1, 1, 0.06)))


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
