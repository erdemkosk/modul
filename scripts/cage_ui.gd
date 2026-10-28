class_name CageUi
extends CanvasLayer
## The cage's screens, in the game's look (Ui):
##   the top     the round and its floor, the clock, your credits, each rival's name and a bar of
##               what's left of it
##   the middle  3, 2, 1, DÖVÜŞ!; KAZANDIN and what it paid
##   panels      before the first round (build, then start), the workshop between rounds (what's
##               broken and missing and what it costs, repair all or only the cab, on to the next),
##               the end (out or champion: again, or the start menu)

var cage: Cage
var _top: VBoxContainer
var _title: Label
var _clock: Label
var _credits: Label
var _bars: VBoxContainer
var _big: Label
var _sub: Label
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _big_t := 0.0


func _ready() -> void:
	layer = 7
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# the top
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 16
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", Ui.glass(true, 10.0))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(plate)
	_top = VBoxContainer.new()
	_top.add_theme_constant_override("separation", 2)
	plate.add_child(_top)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 22)
	_top.add_child(head)
	_title = Ui.label(head, "", 15, Ui.ACCENT, "head")
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_clock = Ui.label(head, "", 34, Ui.INK, "display")
	_credits = Ui.label(head, "", 15, Ui.INK, "head")
	_credits.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bars = VBoxContainer.new()
	_bars.add_theme_constant_override("separation", 3)
	_top.add_child(_bars)
	# the middle
	var mid := VBoxContainer.new()
	mid.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mid.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mid.grow_vertical = Control.GROW_DIRECTION_BOTH
	mid.offset_top = -160
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mid)
	_big = Ui.label(mid, "", 120, Ui.INK, "display")
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = Ui.label(mid, "", 22, Ui.ACCENT, "head")
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# the panels
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Ui.glass(false, 24.0, Color(0.05, 0.055, 0.06, 0.93)))
	_panel.custom_minimum_size.x = 560
	center.add_child(_panel)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_panel_box)
	_panel.visible = false


func _clear_panel() -> void:
	for c in _panel_box.get_children():
		c.queue_free()


func _open_panel() -> void:
	_panel.visible = true
	_panel.modulate.a = 0.0
	_panel.create_tween().tween_property(_panel, "modulate:a", 1.0, 0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_panel() -> void:
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _button(text: String, fn: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	PauseMenu.style_button(b, true)
	if primary:
		b.add_theme_stylebox_override("normal", Ui.glass(true, 8.0, Ui.ACCENT.darkened(0.1), Ui.ACCENT))
		b.add_theme_color_override("font_color", Color(0.08, 0.05, 0.02))
	b.pressed.connect(fn)
	_panel_box.add_child(b)
	return b


func _big_text(t: String, sub := "", secs := 1.2) -> void:
	_big.text = t
	_sub.text = sub
	_big_t = secs
	_big.modulate.a = 1.0
	_sub.modulate.a = 1.0
	_big.pivot_offset = _big.size * 0.5
	_big.scale = Vector2(1.4, 1.4)
	_big.create_tween().tween_property(_big, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- The screens ----------------------------------------------------------------------------------

func show_prep() -> void:
	_clear_panel()
	_top.get_parent().visible = false
	Ui.label(_panel_box, "KAFES", 15, Ui.ACCENT, "head")
	Ui.label(_panel_box, "%d TURLUK TURNUVA" % Cage.ROUNDS.size(), 48, Ui.INK, "display")
	Ui.rule(_panel_box, 80.0)
	var t := Ui.label(_panel_box, "Her turda zemin ve rakip değişir: çamur, buz, ateş kapanları, dikenler, bataklık. Rakibi parçala ya da hareketsiz bırak (8 sn sayılır); süre biterse jüri az hasar alana verir. Kazandıkça kredi kazanırsın, turlar arasında atölyede aracını onarırsın. Kabinin giderse elenirsin.", 16, Ui.DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 510
	Ui.label(_panel_box, "Aracını şimdi kur (B). Turnuva başladıktan sonra yalnız onarılır.", 15, Ui.INK, "label")
	Ui.label(_panel_box, "BAŞLANGIÇ KREDİSİ  %d" % cage.credits, 15, Ui.ACCENT, "head")
	_button("DÖVÜŞE BAŞLA", func() -> void:
		_close_panel()
		cage.start_run(), true)
	_open_panel()


func show_round(name: String, n: int, of: int) -> void:
	_close_panel()
	_top.get_parent().visible = true
	_title.text = "TUR %d/%d  ·  %s" % [n, of, name]
	_big_text(name, "TUR %d" % n, 1.5)
	for c in _bars.get_children():
		c.queue_free()
	for e in cage.rivals:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_bars.add_child(row)
		var l := Ui.label(row, e.label, 14, Ui.INK, "head")
		l.custom_minimum_size.x = 120
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(280, 9)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var w: WeakRef = weakref(e) # (it may be gone in pieces before the bar is)
		bar.draw.connect(func() -> void:
			var m := w.get_ref() as Machine
			var h := m.health() if m != null and m.alive else 0.0
			Ui.segments(bar, Rect2(Vector2.ZERO, bar.size), 20, h, Ui.BAD if h < 0.35 else Ui.ACCENT))
		row.add_child(bar)


func countdown(t: float) -> void:
	var n := ceili(t)
	var txt := str(n) if n <= 3 and n >= 1 else ""
	if t <= 0.0:
		_big_text("DÖVÜŞ!", "", 0.9)
	elif txt != "" and _big.text != txt:
		_big_text(txt, "", 1.0)


func show_won(how: String, pay: int) -> void:
	_big_text(how, "+%d KREDİ" % pay, 2.8)


func show_workshop() -> void:
	_clear_panel()
	Ui.label(_panel_box, "TURLAR ARASI", 15, Ui.ACCENT, "head")
	Ui.label(_panel_box, "ATÖLYE", 48, Ui.INK, "display")
	Ui.rule(_panel_box, 80.0)
	var cred := Ui.label(_panel_box, "", 18, Ui.INK, "head")
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	_panel_box.add_child(list)
	var total := Ui.label(_panel_box, "", 15, Ui.DIM, "label")
	var fill := func() -> void:
		cred.text = "KREDİ  %d" % cage.credits
		for c in list.get_children():
			c.queue_free()
		var d := cage.damage_list()
		var sum := 0
		for k in d.size():
			var e: Dictionary = d[k]
			sum += int(e.cost)
			if k >= 9:
				continue
			var row := HBoxContainer.new()
			list.add_child(row)
			var nm := Ui.label(row, str(Parts.def(e.id).name), 14, Ui.INK)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			Ui.label(row, "YOK" if e.missing else "%%%d" % int(float(e.frac) * 100.0), 14, Ui.BAD if e.missing else Ui.ACCENT, "head")
			var cl := Ui.label(row, "%d" % int(e.cost), 14, Ui.DIM, "head")
			cl.custom_minimum_size.x = 60
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if d.size() > 9:
			Ui.label(list, "… ve %d parça daha" % (d.size() - 9), 13, Ui.DIM)
		if d.is_empty():
			Ui.label(list, "Araç sağlam.", 15, Ui.GOOD, "head")
		total.text = "Tamamını onarmak: %d kredi" % sum
	fill.call()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_panel_box.add_child(row)
	var all := Button.new()
	all.text = "HEPSİNİ ONAR"
	all.focus_mode = Control.FOCUS_NONE
	PauseMenu.style_button(all, true)
	all.pressed.connect(func() -> void:
		if cage.repair(false) > 0:
			fill.call())
	row.add_child(all)
	var cab := Button.new()
	cab.text = "YALNIZ KABİN"
	cab.focus_mode = Control.FOCUS_NONE
	PauseMenu.style_button(cab, true)
	cab.pressed.connect(func() -> void:
		if cage.repair(true) > 0:
			fill.call())
	row.add_child(cab)
	var next_name: String = Cage.ROUNDS[mini(cage.round + 1, Cage.ROUNDS.size() - 1)].name
	_button("SONRAKİ TUR  ·  %s" % next_name, func() -> void:
		_close_panel()
		cage.next_round(), true)
	_open_panel()


func show_final(champion: bool, rounds_won: int, credits: int, why := "") -> void:
	_clear_panel()
	_big.text = ""
	_sub.text = ""
	Ui.label(_panel_box, "TURNUVA BİTTİ" if champion else why, 15, Ui.ACCENT if champion else Ui.BAD, "head")
	Ui.label(_panel_box, "ŞAMPİYON!" if champion else "ELENDİN", 58, Ui.INK, "display")
	Ui.rule(_panel_box, 80.0, Ui.ACCENT if champion else Ui.BAD)
	Ui.label(_panel_box, "Kazanılan tur %d / %d   ·   Kredi %d" % [rounds_won, Cage.ROUNDS.size(), credits], 17, Ui.INK, "label")
	_button("YENİDEN DENE", func() -> void:
		_close_panel()
		cage.restart(), true)
	_button("ANA MENÜ", func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	_open_panel()


func tick(dt: float) -> void:
	_big_t -= dt
	if _big_t < 0.4:
		_big.modulate.a = clampf(_big_t / 0.4, 0.0, 1.0)
		_sub.modulate.a = _big.modulate.a
	if cage.state in ["fight", "countdown"]:
		var t := maxf(cage.time_left, 0.0)
		_clock.text = "%d:%02d" % [int(t) / 60, int(t) % 60]
		_clock.add_theme_color_override("font_color", Ui.BAD if t < 20.0 and fmod(t, 1.0) < 0.5 else Ui.INK)
	_credits.text = "KREDİ  %d" % cage.credits
	for row in _bars.get_children():
		if row.get_child_count() > 1:
			(row.get_child(1) as Control).queue_redraw()
