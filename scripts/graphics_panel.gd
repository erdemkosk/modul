class_name GraphicsPanel
extends PanelContainer
## The GRAFİK plate, on the title screen and in the pause menu: the quality, the share of the
## screen the 3D's drawn at, the edge smoothing, a frame cap and vsync (Graphics); each choice put
## on at once and kept. What the machine is and what it was found good for are shown at the top.

signal closed

var weather: Weather ## (in a town: its sky and sun take the quality too)

var _info: Label
var _rows := {} ## setting -> [values, buttons]


func _ready() -> void:
	Graphics.load_settings()
	add_theme_stylebox_override("panel", Ui.glass(false, 18.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(620, 0)
	add_child(col)
	Ui.label(col, "GRAFİK", 30, Ui.INK, "display")
	Ui.rule(col)
	_info = Ui.label(col, "", 14, Ui.DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choices(col, "KALİTE", "quality", Graphics.QUALITIES, Graphics.QUALITIES.map(func(q: String) -> String: return str(Graphics.QUALITY_NAMES[q])),
		"Sis, gölge, yansıma, ortam gölgesi ve ağaçların ayrıntı mesafesi. OTOMATİK: bu bilgisayara göre")
	_choices(col, "ÇÖZÜNÜRLÜK", "scale", Graphics.SCALES, Graphics.SCALES.map(func(s: float) -> String: return "OTOMATİK" if s <= 0.0 else "%%%d" % roundi(s * 100.0)),
		"3D'nin ekranın kaçta kaçında çizilip büyütüleceği (menüler hep keskin). Büyük ekranda en çok bu kazandırır")
	_choices(col, "KENAR", "aa", Graphics.AAS, Graphics.AAS.map(func(a: String) -> String: return str(Graphics.AA_NAMES[a])),
		"Kenar yumuşatma. FXAA ucuz, MSAA keskin ama pahalı, FSR 2 en temizi ama sallanan yapraklarda iz bırakabilir")
	_choices(col, "FPS SINIRI", "fps", Graphics.FPS, Graphics.FPS.map(func(f: int) -> String: return "SINIRSIZ" if f == 0 else str(f)),
		"Kare hızına üst sınır: bilgisayar daha az ısınır")
	_choices(col, "DİKEY EŞ.", "vsync", [true, false], ["AÇIK", "KAPALI"], "Ekranla eşitleme: yırtılma olmaz")
	Ui.rule(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	row.add_child(_button("ÖNERİLENE DÖN", func() -> void:
		Graphics.quality = "auto"
		Graphics.scale = 0.0
		Graphics.aa = "auto"
		_changed(), 0))
	row.add_child(_button("KAPAT", func() -> void:
		visible = false
		closed.emit(), 0))
	_refresh()


func _choices(col: VBoxContainer, title: String, key: String, values: Array, names: Array, tip: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = tip
	col.add_child(row)
	var l := Ui.label(row, title, 15, Ui.ACCENT, "head")
	l.custom_minimum_size = Vector2(120, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	var buttons: Array[Button] = []
	for i in values.size():
		var v: Variant = values[i]
		var b := _button(str(names[i]), func() -> void:
			Graphics.set_value(key, v)
			if key == "quality": # (a quality brings its own resolution and smoothing)
				Graphics.scale = 0.0
				Graphics.aa = "auto"
			_changed(), 0)
		b.tooltip_text = tip
		row.add_child(b)
		buttons.append(b)
	_rows[key] = [values, buttons]


func _changed() -> void:
	Graphics.save_settings()
	Graphics.apply(get_tree(), weather)
	_refresh()


func _refresh() -> void:
	for key: String in _rows:
		var values: Array = _rows[key][0]
		var buttons: Array = _rows[key][1]
		var now: Variant = Graphics.value(key)
		for i in buttons.size():
			var on: bool = values[i] == now
			(buttons[i] as Button).add_theme_color_override("font_color", Ui.ACCENT if on else Ui.INK)
			(buttons[i] as Button).add_theme_stylebox_override("normal", Ui.glass(false, 6.0, Color(1.0, 0.56, 0.14, 0.25) if on else Color(1, 1, 1, 0.06)))
	var h := get_tree().root.size.y
	var s := Graphics.render_scale(h)
	_info.text = "Ekran kartı: %s\nBu bilgisayar için önerilen: %s · Şu an: %s, 3D %d satırda çiziliyor (ekran %d, %%%d), kenar %s" % [
		Graphics.card(), Graphics.QUALITY_NAMES[Graphics.detect()], Graphics.QUALITY_NAMES[Graphics.level()],
		roundi(h * s), h, roundi(s * 100.0), Graphics.AA_NAMES[Graphics.smoothing()]]


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
