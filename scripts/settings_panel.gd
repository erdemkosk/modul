class_name SettingsPanel
extends PanelContainer
## The AYARLAR plate, on the title screen and in the pause menu, in three tabs: GRAFİK (Graphics:
## quality, the share of the screen the 3D's drawn at, edge smoothing, a frame cap, vsync, and the
## window or full screen), SES (the loudness) and OYUN (the view panning at the screen's edge).
## Every choice is put on at once and kept.

signal closed

var weather: Weather ## (in a town: its sky and sun take the quality)
var cam: RtsCamera ## (in a town: it takes the edge panning)

var _pages := {} ## tab -> its page
var _tabs := {} ## tab -> its button
var _rows: Array = [] ## [getter, values, buttons]
var _info: Label
var _volume_label: Label
var _reset: Button ## (the graphics' only)


func _ready() -> void:
	Graphics.load_settings()
	Settings.load_settings()
	add_theme_stylebox_override("panel", Ui.glass(false, 20.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(640, 0)
	add_child(col)
	Ui.label(col, "AYARLAR", 34, Ui.INK, "display")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	for t: String in ["GRAFİK", "SES", "OYUN"]:
		var b := _button(t, func() -> void: _show(t), 120)
		tabs.add_child(b)
		_tabs[t] = b
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 12)
		col.add_child(page)
		_pages[t] = page
	Ui.rule(col)
	_graphics_page(_pages["GRAFİK"])
	_sound_page(_pages["SES"])
	_game_page(_pages["OYUN"])
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	col.add_child(foot)
	_reset = _button("ÖNERİLENE DÖN", func() -> void:
		Graphics.quality = "auto"
		Graphics.scale = 0.0
		Graphics.aa = "auto"
		_graphics_changed(), 0)
	foot.add_child(_reset)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	foot.add_child(_button("KAPAT", func() -> void:
		visible = false
		closed.emit(), 140))
	_show("GRAFİK")
	_refresh()


func _graphics_page(page: VBoxContainer) -> void:
	_info = Ui.label(page, "", 14, Ui.DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(620, 0)
	var gset := func(key: String) -> Callable:
		return func(v: Variant) -> void:
			Graphics.set_value(key, v)
			if key == "quality": # (a quality brings its own resolution and smoothing)
				Graphics.scale = 0.0
				Graphics.aa = "auto"
			_graphics_changed()
	_choices(page, "KALİTE", Graphics.QUALITIES, Graphics.QUALITIES.map(func(q: String) -> String: return str(Graphics.QUALITY_NAMES[q])),
		"Sis, gölge, yansıma, ortam gölgesi ve ağaçların ayrıntı mesafesi. OTOMATİK: bu bilgisayara göre",
		func() -> Variant: return Graphics.quality, gset.call("quality"))
	_choices(page, "ÇÖZÜNÜRLÜK", Graphics.SCALES, Graphics.SCALES.map(func(s: float) -> String: return "OTOMATİK" if s <= 0.0 else "%%%d" % roundi(s * 100.0)),
		"3D'nin ekranın kaçta kaçında çizilip büyütüleceği (menüler hep keskin). Büyük ekranda en çok bu kazandırır",
		func() -> Variant: return Graphics.scale, gset.call("scale"))
	_choices(page, "KENAR", Graphics.AAS, Graphics.AAS.map(func(a: String) -> String: return str(Graphics.AA_NAMES[a])),
		"Kenar yumuşatma. FXAA ucuz, MSAA keskin ama pahalı, FSR 2 en temizi ama sallanan yapraklarda iz bırakabilir",
		func() -> Variant: return Graphics.aa, gset.call("aa"))
	_choices(page, "FPS SINIRI", Graphics.FPS, Graphics.FPS.map(func(f: int) -> String: return "SINIRSIZ" if f == 0 else str(f)),
		"Kare hızına üst sınır: bilgisayar daha az ısınır", func() -> Variant: return Graphics.fps, gset.call("fps"))
	_choices(page, "DİKEY EŞ.", [true, false], ["AÇIK", "KAPALI"], "Ekranla eşitleme: görüntü yırtılmaz",
		func() -> Variant: return Graphics.vsync, gset.call("vsync"))
	_choices(page, "EKRAN", [true, false], ["TAM EKRAN", "PENCERE"], "Tam ekran ya da pencere",
		func() -> Variant: return Settings.fullscreen, func(v: Variant) -> void:
			Settings.fullscreen = bool(v)
			_settings_changed())


func _sound_page(page: VBoxContainer) -> void:
	var row := _row(page, "SES DÜZEYİ", "Bütün sesler: orman, rüzgâr, dere, işler, tren, çan")
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.volume
	slider.custom_minimum_size = Vector2(340, 30)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void:
		Settings.volume = v
		_settings_changed())
	row.add_child(slider)
	_volume_label = Ui.label(row, "", 18, Ui.INK, "display")
	_volume_label.custom_minimum_size = Vector2(70, 0)


func _game_page(page: VBoxContainer) -> void:
	_choices(page, "KENAR KAYDIR.", [true, false], ["AÇIK", "KAPALI"], "Fare ekranın kenarına gelince görüş o yana kaysın",
		func() -> Variant: return Settings.edge_pan, func(v: Variant) -> void:
			Settings.edge_pan = bool(v)
			_settings_changed())


func _show(tab: String) -> void:
	if _reset:
		_reset.visible = tab == "GRAFİK"
	for t: String in _pages:
		(_pages[t] as Control).visible = t == tab
		_mark(_tabs[t] as Button, t == tab)


func _row(page: VBoxContainer, title: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = tip
	page.add_child(row)
	var l := Ui.label(row, title, 15, Ui.ACCENT, "head")
	l.custom_minimum_size = Vector2(130, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


func _choices(page: VBoxContainer, title: String, values: Array, names: Array, tip: String, getter: Callable, setter: Callable) -> void:
	var row := _row(page, title, tip)
	var buttons: Array[Button] = []
	for i in values.size():
		var v: Variant = values[i]
		var b := _button(str(names[i]), func() -> void:
			setter.call(v)
			_refresh(), 0)
		b.tooltip_text = tip
		row.add_child(b)
		buttons.append(b)
	_rows.append([getter, values, buttons])


func _graphics_changed() -> void:
	Graphics.save_settings()
	Graphics.apply(get_tree(), weather)
	_refresh()


func _settings_changed() -> void:
	Settings.save_settings()
	Settings.apply(cam)
	_refresh()


func _refresh() -> void:
	for r: Array in _rows:
		var now: Variant = (r[0] as Callable).call()
		for i in (r[2] as Array).size():
			_mark(r[2][i] as Button, r[1][i] == now)
	var h := get_tree().root.size.y
	var s := Graphics.render_scale(h)
	_info.text = "Ekran kartı: %s · bu bilgisayar için önerilen: %s\nŞu an: %s, 3D %d satırda çiziliyor (ekran %d, %%%d), kenar %s" % [
		Graphics.card(), Graphics.QUALITY_NAMES[Graphics.detect()], Graphics.QUALITY_NAMES[Graphics.level()],
		roundi(h * s), h, roundi(s * 100.0), Graphics.AA_NAMES[Graphics.smoothing()]]
	_volume_label.text = "KAPALI" if Settings.volume <= 0.001 else "%%%d" % roundi(Settings.volume * 100.0)


func _mark(b: Button, on: bool) -> void:
	b.add_theme_color_override("font_color", Ui.ACCENT if on else Ui.INK)
	b.add_theme_stylebox_override("normal", Ui.glass(false, 6.0, Color(1.0, 0.56, 0.14, 0.25) if on else Color(1, 1, 1, 0.06)))


func _button(text: String, f: Callable, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(width, 34)
	b.add_theme_font_override("font", Ui.font("head"))
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", Ui.glass(false, 6.0, Color(1, 1, 1, 0.06)))
	b.add_theme_stylebox_override("hover", Ui.glass(false, 6.0, Color(1.0, 0.56, 0.14, 0.3), Ui.ACCENT))
	b.add_theme_stylebox_override("pressed", Ui.glass(false, 6.0, Color(1.0, 0.56, 0.14, 0.45), Ui.ACCENT))
	b.pressed.connect(f)
	return b
