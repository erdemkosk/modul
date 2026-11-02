class_name TitleMenu
extends CanvasLayer
## The title screen, before any valley's made: carry on with the saved town, or start a new one,
## choosing its seed (typed, or thrown at random), how many come on the train, how much they bring,
## how hard the raids come, and the season they arrive in.

var game: Node ## main.gd

var _seed: LineEdit
var _people := 6
var _people_label: Label
var _choice := {"supplies": 1, "raids": 1, "season": 0}
var _groups := {} ## setting -> its buttons
var _new_plate: PanelContainer
var _graphics: GraphicsPanel


func _ready() -> void:
	layer = 20
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.055, 0.06)
	add_child(bg)
	# a dusk sky over a dark treeline, drawn, behind it all
	var sky := Control.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.draw.connect(func() -> void:
		var r := sky.get_rect()
		for i in 40:
			var u := i / 40.0
			sky.draw_rect(Rect2(0, r.size.y * u * 0.75, r.size.x, r.size.y * 0.75 / 40.0 + 1.0), Color(0.09, 0.1, 0.13).lerp(Color(0.42, 0.24, 0.14), u * u))
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var x := 0.0
		while x < r.size.x:
			var h := rng.randf_range(0.12, 0.3) * r.size.y
			var w := rng.randf_range(18.0, 34.0)
			var base := r.size.y * 0.78
			sky.draw_colored_polygon(PackedVector2Array([Vector2(x, base), Vector2(x + w * 0.5, base - h), Vector2(x + w, base)]), Color(0.03, 0.04, 0.035))
			x += w * rng.randf_range(0.45, 0.8)
		sky.draw_rect(Rect2(0, r.size.y * 0.78, r.size.x, r.size.y * 0.22), Color(0.03, 0.04, 0.035)))
	add_child(sky)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 80
	col.offset_top = -260
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	Ui.label(col, "İNŞA", 76, Ui.INK, "display")
	Ui.label(col, "Taygada bir kereste kasabası", 20, Ui.DIM, "head")
	Ui.rule(col, 60.0)
	if VillageSave.exists():
		col.add_child(_button("DEVAM ET", func() -> void: game.continue_game(), 260))
	col.add_child(_button("GRAFİK", func() -> void: _show_graphics(not _graphics.visible), 260))
	col.add_child(_button("ÇIK", func() -> void: get_tree().quit(), 260))
	_new_game_plate()
	_graphics = GraphicsPanel.new()
	_graphics.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_graphics.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_graphics.offset_right = -80
	_graphics.offset_top = -250
	_graphics.visible = false
	_graphics.closed.connect(func() -> void: _show_graphics(false))
	add_child(_graphics)


## The graphics plate shown in place of the new town's (and back).
func _show_graphics(on: bool) -> void:
	_graphics.visible = on
	_new_plate.visible = not on


func _new_game_plate() -> void:
	var plate := PanelContainer.new()
	_new_plate = plate
	plate.add_theme_stylebox_override("panel", Ui.glass(false, 18.0))
	plate.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	plate.offset_right = -80
	plate.offset_top = -250
	add_child(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(520, 0)
	plate.add_child(col)
	Ui.label(col, "YENİ KASABA", 30, Ui.INK, "display")
	Ui.rule(col)
	# the seed
	var row := _row(col, "TOHUM", "Aynı tohum aynı yeri, aynı demiryolunu verir")
	_seed = LineEdit.new()
	_seed.custom_minimum_size = Vector2(170, 34)
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
	var go := _button("BAŞLA", func() -> void:
		game.begin_new({"seed": maxi(int(_seed.text), 1), "people": _people, "supplies": [0.6, 1.0, 1.6][_choice.supplies],
			"raids": _choice.raids, "season": _choice.season}), 0)
	go.custom_minimum_size = Vector2(0, 46)
	col.add_child(go)


func _row(col: VBoxContainer, title: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.tooltip_text = tip
	col.add_child(row)
	var l := Ui.label(row, title, 15, Ui.ACCENT, "head")
	l.custom_minimum_size = Vector2(110, 0)
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
