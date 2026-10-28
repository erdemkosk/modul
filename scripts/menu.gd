class_name Menu
extends Control
## The start, in the game's look (Ui): over a picture of a machine (assets/ui/menu_bg.png), a dark
## fall-off on the left with the name big in condensed capitals, a line under it, and the ways in as
## large words that take an orange bar when the mouse is on them, each with a line on what it is: the
## missions (their list: a card each, its stars, locked till the one before is done), the cage,
## the proving ground (the arena), the valley, the settings, out.

static var open_missions := false ## (back from a mission: its list again)

var _settings: SettingsPanel
var _list: PanelContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists("res://assets/ui/menu_bg.png"):
		var pic := TextureRect.new()
		pic.texture = load("res://assets/ui/menu_bg.png")
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(pic)
		# a slow push in on it
		pic.pivot_offset = get_viewport_rect().size * 0.6
		pic.create_tween().set_loops().tween_property(pic, "scale", Vector2(1.06, 1.06), 24.0).from(Vector2.ONE)
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.02, 0.94))
	g.set_color(1, Color(0.02, 0.02, 0.02, 0.0))
	g.add_point(0.55, Color(0.02, 0.02, 0.02, 0.6))
	grad.gradient = g
	grad.fill_from = Vector2(0.0, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	shade.texture = grad
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 1000
	add_child(shade)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -300
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	Ui.label(col, "PARÇA PARÇA  ·  ÇAMURUN İÇİNDE", 16, Ui.ACCENT, "head")
	var title := Ui.label(col, "İNŞA", 168, Ui.INK, "display")
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 4)
	Ui.rule(col, 120.0)
	var tag := Ui.label(col, "Çelikten, motordan, paletten kendi aracını kur. Ağırlık, güç, tutunma ve çamur gerçek.", 19, Ui.DIM)
	tag.custom_minimum_size.x = 560
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var gap := Control.new()
	gap.custom_minimum_size.y = 34
	col.add_child(gap)
	_item(col, "GÖREVLER", "Endüstriyel sahalar: bacayı, su kulesini, yakıt tanklarını indir. Çamur, kar, yağmur hepsine işler", "missions", 0)
	_item(col, "KAFES", "Seyirci önünde turnuva: her turda yeni zemin, yeni rakip, turlar arası onarım", "cage", 1)
	_item(col, "TEST ALANI", "Arenada kur, dene, dövüş: rakip araçlar, kırılan siper, çamur çukurları", "arena", 2)
	_item(col, "VADİ", "İki kilometrelik vadi: yollar, çamur, kar ve orman", "valley", 3)
	_item(col, "AYARLAR", "", "settings", 4)
	_item(col, "ÇIKIŞ", "", "", 5)
	Settings.apply(get_tree())
	_settings = SettingsPanel.new()
	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings.visible = false
	_settings.closed.connect(func() -> void: _settings.visible = false)
	add_child(_settings)
	var foot := Ui.label(self, "B  inşa     1-9  silahlar     C  kamera     Esc  menü", 14, Ui.DIM, "label")
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 110
	foot.offset_top = -52
	_build_list()
	if open_missions:
		open_missions = false
		_list.visible = true


## A way in: its word big, its line under it; under the mouse an orange bar comes out beside it.
func _item(parent: Node, t: String, hint: String, mode: String, k: int) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -4)
	parent.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var bar := ColorRect.new()
	bar.color = Ui.ACCENT
	bar.custom_minimum_size = Vector2(0, 38)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var b := Button.new()
	b.flat = true
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Ui.font("display"))
	b.add_theme_font_size_override("font_size", 54)
	b.add_theme_color_override("font_color", Ui.INK)
	b.add_theme_color_override("font_hover_color", Ui.ACCENT)
	b.add_theme_color_override("font_pressed_color", Ui.ACCENT)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_child(b)
	var h: Label = null
	if hint != "":
		h = Ui.label(box, hint, 16, Ui.DIM)
	b.mouse_entered.connect(func() -> void:
		bar.create_tween().tween_property(bar, "custom_minimum_size:x", 8.0, 0.15)
		if h:
			h.add_theme_color_override("font_color", Ui.INK))
	b.mouse_exited.connect(func() -> void:
		bar.create_tween().tween_property(bar, "custom_minimum_size:x", 0.0, 0.15)
		if h:
			h.add_theme_color_override("font_color", Ui.DIM))
	b.pressed.connect(func() -> void:
		if mode == "":
			get_tree().quit()
			return
		if mode == "settings":
			_settings.visible = true
			return
		if mode == "missions":
			_build_list()
			_list.visible = true
			return
		Mode.current = mode
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	# in one after the other
	box.modulate.a = 0.0
	box.create_tween().tween_property(box, "modulate:a", 1.0, 0.35).set_delay(0.15 + k * 0.08)


## The missions' list: a card for each (its number, name, weather and what's to come down; its
## stars and best time; locked till the one before it's done), and back.
func _build_list() -> void:
	if _list:
		_list.queue_free()
	_list = PanelContainer.new()
	_list.add_theme_stylebox_override("panel", Ui.glass(false, 26.0, Color(0.05, 0.055, 0.06, 0.95)))
	_list.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_list.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_list.grow_vertical = Control.GROW_DIRECTION_BOTH
	_list.visible = false
	add_child(_list)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_list.add_child(col)
	Ui.label(col, "GÖREVLER", 44, Ui.INK, "display")
	Ui.rule(col, 70.0)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)
	for i in Missions.LIST.size():
		grid.add_child(_mission_card(i))
	var back := Button.new()
	back.text = "GERİ"
	back.focus_mode = Control.FOCUS_NONE
	PauseMenu.style_button(back, true)
	back.pressed.connect(func() -> void: _list.visible = false)
	col.add_child(back)


func _mission_card(i: int) -> Control:
	var d: Dictionary = Missions.LIST[i]
	var open := Missions.is_open(i)
	var rec := Missions.record(str(d.id))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(250, 150)
	b.disabled = not open
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if open else Control.CURSOR_ARROW
	var normal := Ui.glass(true, 14.0, Color(0.09, 0.09, 0.09, 0.9))
	var hover := Ui.glass(true, 14.0, Color(0.16, 0.11, 0.05, 0.95), Ui.ACCENT)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", Ui.glass(true, 14.0, Color(0.06, 0.06, 0.06, 0.8)))
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 18
	col.offset_top = 12
	col.offset_right = -14
	col.offset_bottom = -10
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	Ui.label(col, "%02d  ·  %s" % [i + 1, MissionUi._weather_name(str(d.weather))], 13, Ui.ACCENT if open else Ui.DIM, "head")
	Ui.label(col, str(d.name), 28, Ui.INK if open else Ui.DIM, "display")
	var names := []
	for t: Array in d.targets:
		var n: String = Structures.NAMES.get(t[0], t[0])
		if not n in names:
			names.append(n)
	var what := Ui.label(col, ", ".join(names), 13, Ui.DIM)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	if not open:
		Ui.label(col, "KİLİTLİ  ·  önceki görevi bitir", 13, Ui.DIM, "label")
	elif float(rec[0]) >= 0.0:
		Ui.label(col, "%s   %s" % [MissionUi.star_text(int(rec[1])), MissionUi.clock(float(rec[0]))], 18, Ui.ACCENT, "head")
	else:
		Ui.label(col, "YENİ", 14, Ui.GOOD, "head")
	for l in col.get_children():
		if l is Control:
			(l as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func() -> void:
		Mode.current = "mission"
		Mode.mission = str(d.id)
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	return b
