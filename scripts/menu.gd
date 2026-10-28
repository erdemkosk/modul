extends Control
## The start, in the game's look (Ui): over a picture of a machine (assets/ui/menu_bg.png), a dark
## fall-off on the left with the name big in condensed capitals, a line under it, and the ways in as
## large words that take an orange bar when the mouse is on them, each with a line on what it is: the
## proving ground (the arena), the valley, the settings, out.


var _settings: SettingsPanel


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
	_item(col, "KAFES", "Seyirci önünde turnuva: her turda yeni zemin, yeni rakip, turlar arası onarım", "cage", 0)
	_item(col, "TEST ALANI", "Arenada kur, dene, dövüş: rakip araçlar, kırılan siper, çamur çukurları", "arena", 1)
	_item(col, "VADİ", "İki kilometrelik vadi: yollar, çamur, kar ve orman", "valley", 2)
	_item(col, "AYARLAR", "", "settings", 3)
	_item(col, "ÇIKIŞ", "", "", 4)
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
		Mode.current = mode
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	# in one after the other
	box.modulate.a = 0.0
	box.create_tween().tween_property(box, "modulate:a", 1.0, 0.35).set_delay(0.15 + k * 0.08)
