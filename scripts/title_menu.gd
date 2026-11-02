class_name TitleMenu
extends CanvasLayer
## The title screen, before any valley's made: the town at dusk behind it (assets/ui/title_bg.jpg,
## a picture from the game), the name and the menu down the left over a shade, and on the right
## the plate of whatever's chosen: a new town (its seed, typed or thrown, how many come on the
## train, how much they bring, how hard the raids come, the season they arrive in), or the settings
## (SettingsPanel). Esc puts the plate away.

const BG := "res://assets/ui/title_bg.jpg"

var game: Node ## main.gd

var _seed: LineEdit
var _people := 6
var _people_label: Label
var _choice := {"supplies": 1, "raids": 1, "season": 0}
var _groups := {} ## setting -> its buttons
var _new_plate: PanelContainer
var _settings: SettingsPanel
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
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 96
	col.offset_top = -250
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	Ui.label(col, "İNŞA", 120, Ui.INK, "display")
	var sub := Ui.label(col, "TAYGADA BİR KERESTE KASABASI · 1880'LER", 18, Ui.DIM, "head")
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
	var foot := Ui.label(root, "Esc: geri", 13, Ui.DIM)
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
	_toggle("new" if saved.is_empty() else "")
	# (in from black)
	root.modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(root, "modulate:a", 1.0, 0.6)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).physical_keycode == KEY_ESCAPE and _open != "":
		_toggle("")
		get_viewport().set_input_as_handled()


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
	b.add_theme_color_override("font_color", Ui.INK)
	b.add_theme_color_override("font_hover_color", Ui.ACCENT)
	b.add_theme_color_override("font_pressed_color", Ui.ACCENT)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 18
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(1.0, 0.56, 0.14, 0.12)
	lit.border_color = Ui.ACCENT
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
		Ui.label(m, note, 14, Ui.DIM)


## The plate `which` ("new", "settings") shown on the right, or none ("" or the open one again).
func _toggle(which: String) -> void:
	_open = "" if which == _open else which
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
		(_items[key] as Button).add_theme_color_override("font_color", Ui.ACCENT if open else Ui.INK)


func _place_plate(p: Control) -> void:
	p.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.offset_right = -96


func _new_game_plate(root: Control) -> void:
	var plate := PanelContainer.new()
	_new_plate = plate
	plate.add_theme_stylebox_override("panel", Ui.glass(false, 20.0))
	_place_plate(plate)
	root.add_child(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(560, 0)
	plate.add_child(col)
	Ui.label(col, "YENİ KASABA", 34, Ui.INK, "display")
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
	_choices(col, "MALZEME", "supplies", ["AZ", "NORMAL", "BOL"], "Trenin getirdiği odun, taş, yiyecek")
	_choices(col, "BASKINLAR", "raids", ["KOLAY", "NORMAL", "ZOR"], "Haydutların ne zaman, ne sıklıkla, kaç kişi geldiği")
	_choices(col, "MEVSİM", "season", ["İLKBAHAR", "YAZ", "SONBAHAR", "KIŞ"], "Trenin geldiği mevsim")
	Ui.rule(col)
	var go := _button("YOLA ÇIK", func() -> void:
		game.begin_new({"seed": maxi(int(_seed.text), 1), "people": _people, "supplies": [0.6, 1.0, 1.6][_choice.supplies],
			"raids": _choice.raids, "season": _choice.season}), 0)
	go.custom_minimum_size = Vector2(0, 50)
	go.add_theme_font_override("font", Ui.font("display"))
	go.add_theme_font_size_override("font_size", 24)
	go.add_theme_color_override("font_color", Ui.ACCENT)
	col.add_child(go)


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
