class_name SettingsPanel
extends PanelContainer
## The settings as a panel (in the pause menu and the start menu): a slider or a switch each, in
## the game's look, every change saved and put into effect at once (Settings). `closed` when you're
## done with it.

signal closed

const ROWS := [
	["sensitivity", "FARE HASSASİYETİ", 0.3, 2.5, 0.05, "x%.2f"],
	["fov", "GÖRÜŞ AÇISI", 55.0, 95.0, 1.0, "%d°"],
	["shake", "KAMERA SARSINTISI", 0.0, 1.5, 0.05, "%%%d"],
	["volume", "SES", 0.0, 1.0, 0.01, "%%%d"],
	["fullscreen", "TAM EKRAN"],
	["shadows", "GÖLGELER"],
	["ssao", "ORTAM GÖLGELEMESİ (SSAO)"],
	["show_fps", "FPS GÖSTER"],
]


func _ready() -> void:
	add_theme_stylebox_override("panel", Ui.glass(false, 22.0, Color(0.05, 0.055, 0.06, 0.94)))
	custom_minimum_size = Vector2(520, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	Ui.label(col, "AYARLAR", 30, Ui.INK, "display")
	Ui.rule(col, 60.0)
	for r: Array in ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		col.add_child(row)
		var name := Ui.label(row, str(r[1]), 15, Ui.INK, "head")
		name.custom_minimum_size.x = 230
		var key: String = r[0]
		if r.size() > 2:
			var s := HSlider.new()
			s.min_value = r[2]
			s.max_value = r[3]
			s.step = r[4]
			s.value = float(Settings.get_value(key))
			s.custom_minimum_size = Vector2(170, 22)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			s.focus_mode = Control.FOCUS_NONE
			_style_slider(s)
			row.add_child(s)
			var val := Ui.label(row, "", 15, Ui.ACCENT, "head")
			val.custom_minimum_size.x = 56
			var fmt: String = r[5]
			var show := func(v: float) -> void:
				val.text = fmt % (v * 100.0 if "%%" in fmt else v)
			show.call(s.value)
			s.value_changed.connect(func(v: float) -> void:
				show.call(v)
				Settings.set_value(key, v))
		else:
			var t := CheckButton.new()
			t.button_pressed = bool(Settings.get_value(key))
			t.focus_mode = Control.FOCUS_NONE
			t.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
			row.add_child(t)
	var again := Button.new()
	again.text = "İPUÇLARINI YENİDEN GÖSTER"
	again.focus_mode = Control.FOCUS_NONE
	PauseMenu.style_button(again, true)
	again.pressed.connect(func() -> void:
		Hints.reset()
		again.text = "İPUÇLARI YENİDEN GÖSTERİLECEK")
	col.add_child(again)
	var back := Button.new()
	back.text = "GERİ"
	back.focus_mode = Control.FOCUS_NONE
	PauseMenu.style_button(back, true)
	back.pressed.connect(func() -> void: closed.emit())
	col.add_child(back)


func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Ui.ACCENT
	fill.set_corner_radius_all(2)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
