class_name MissionUi
extends CanvasLayer
## A mission's screens, in the game's look (Ui):
##   before    the brief: the site, what's to come down, the stars' times, your best; build (B), start
##   the top   the mission's name, the clock, the targets (each ticked as it comes down)
##   markers   over each target still standing: its name and how far, an arrow at the edge when it's
##             off the screen; a cross where one's come down
##   after     done (the time, the stars, a new best) or failed (why): again, the next, the list

var missions: Missions
var _root: Control
var _top: PanelContainer
var _title: Label
var _clock: Label
var _list: VBoxContainer
var _rows := {} ## Structure -> its row's label
var _marks: Control
var _big: Label
var _big_t := 0.0
var _panel: PanelContainer
var _box: VBoxContainer


func _ready() -> void:
	layer = 7
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_marks = Control.new()
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	_root.add_child(_marks)
	# the top: name and clock, the targets under
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 16
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	_top = PanelContainer.new()
	_top.add_theme_stylebox_override("panel", Ui.glass(true, 10.0))
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_top)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_top.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 22)
	col.add_child(head)
	_title = Ui.label(head, "", 15, Ui.ACCENT, "head")
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_clock = Ui.label(head, "0:00", 34, Ui.INK, "display")
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	col.add_child(_list)
	_top.visible = false
	# the middle
	_big = Ui.label(_root, "", 96, Ui.INK, "display")
	_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_big.offset_top = -200
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# the panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Ui.glass(false, 24.0, Color(0.05, 0.055, 0.06, 0.93)))
	_panel.custom_minimum_size.x = 580
	center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_box)
	_panel.visible = false


func panel_up() -> bool:
	return _panel.visible


func _clear() -> void:
	for c in _box.get_children():
		c.queue_free()


func _open() -> void:
	_panel.visible = true
	_panel.modulate.a = 0.0
	_panel.create_tween().tween_property(_panel, "modulate:a", 1.0, 0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _button(parent: Node, text: String, fn: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	PauseMenu.style_button(b, true)
	if primary:
		b.add_theme_stylebox_override("normal", Ui.glass(true, 8.0, Ui.ACCENT.darkened(0.1), Ui.ACCENT))
		b.add_theme_color_override("font_color", Color(0.08, 0.05, 0.02))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


static func clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


## Three marks, `n` of them lit.
static func star_text(n: int) -> String:
	var s := ""
	for k in 3:
		s += "★" if k < n else "☆"
	return s


# --- The screens ----------------------------------------------------------------------------------

func show_prep() -> void:
	var d := missions.def
	_clear()
	Ui.label(_box, "GÖREV  ·  %s" % _weather_name(str(d.weather)), 15, Ui.ACCENT, "head")
	Ui.label(_box, str(d.name), 52, Ui.INK, "display")
	Ui.rule(_box, 80.0)
	var t := Ui.label(_box, str(d.brief), 17, Ui.DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 530
	Ui.label(_box, "YIKILACAKLAR", 14, Ui.ACCENT, "head")
	var names := {}
	for s in missions.targets:
		names[s.title] = int(names.get(s.title, 0)) + 1
	var parts := []
	for n: String in names:
		parts.append("%s ×%d" % [n, names[n]] if int(names[n]) > 1 else n)
	Ui.label(_box, "  ·  ".join(parts), 17, Ui.INK, "head")
	var st: Array = d.stars
	Ui.label(_box, "★★★  %s altı     ★★  %s altı     ★  bitir" % [clock(float(st[0])), clock(float(st[1]))], 15, Ui.DIM, "label")
	if missions.best >= 0.0:
		Ui.label(_box, "EN İYİ  %s  %s" % [clock(missions.best), star_text(int(Missions.record(str(d.id))[1]))], 15, Ui.GOOD, "head")
	if not d.get("guards", []).is_empty():
		Ui.label(_box, "Sahada %d bekçi araç var." % d.guards.size(), 15, Ui.BAD, "label")
	Ui.label(_box, "Önce aracını kur (B): görev başlayınca değişmez.", 15, Ui.INK, "label")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	_button(row, "GÖREVLER", func() -> void: _to_menu(true))
	_button(row, "BAŞLA  ·  ENTER", func() -> void: missions.start(), true)
	_open()


func show_run() -> void:
	_close()
	_top.visible = true
	_title.text = str(missions.def.name)
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	for s in missions.targets:
		var l := Ui.label(_list, "", 14, Ui.INK, "label")
		_rows[s] = l
	_flash("BAŞLA", 1.0)


func target_down(s: Structure) -> void:
	_flash("%s YIKILDI" % Ui.upper(s.title), 1.2)
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/heavy_01.wav", s.center(), 4.0, 0.7)


func show_done(new_best: bool) -> void:
	_clear()
	Ui.label(_box, "GÖREV TAMAM", 15, Ui.GOOD, "head")
	Ui.label(_box, str(missions.def.name), 52, Ui.INK, "display")
	Ui.rule(_box, 80.0, Ui.GOOD)
	var stars := Ui.label(_box, star_text(missions.stars), 54, Ui.ACCENT, "display")
	stars.pivot_offset = Vector2(60, 30)
	stars.scale = Vector2(1.5, 1.5)
	stars.create_tween().tween_property(stars, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Ui.label(_box, "SÜRE  %s%s" % [clock(missions.time), "   ·   YENİ REKOR" if new_best else "   ·   EN İYİ %s" % clock(missions.best)],
		18, Ui.INK, "head")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	_button(row, "GÖREVLER", func() -> void: _to_menu(true))
	_button(row, "TEKRAR", func() -> void: missions.restart())
	var nx := missions.next_index()
	if nx >= 0:
		_button(row, "SONRAKİ  ·  ENTER", func() -> void: missions.go_to(nx), true)
	_open()


func show_failed(why: String) -> void:
	_clear()
	Ui.label(_box, "GÖREV BAŞARISIZ", 15, Ui.BAD, "head")
	Ui.label(_box, why, 46, Ui.INK, "display")
	Ui.rule(_box, 80.0, Ui.BAD)
	Ui.label(_box, "Yıkılan  %d / %d   ·   %s" % [missions.targets_down(), missions.targets.size(), clock(missions.time)], 17, Ui.DIM, "head")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	_button(row, "GÖREVLER", func() -> void: _to_menu(true))
	_button(row, "TEKRAR  ·  ENTER", func() -> void: missions.restart(), true)
	_open()


func _to_menu(list: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Menu.open_missions = list
	missions.game.get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _flash(t: String, secs: float) -> void:
	_big.text = t
	_big_t = secs
	_big.modulate.a = 1.0
	_big.pivot_offset = _big.size * 0.5
	_big.scale = Vector2(1.3, 1.3)
	_big.create_tween().tween_property(_big, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _weather_name(w: String) -> String:
	return {"clear": "AÇIK", "overcast": "KAPALI", "rain": "YAĞMUR", "snow": "KAR", "fog": "SİS", "storm": "FIRTINA"}.get(w, "")


func tick(dt: float) -> void:
	_big_t -= dt
	_big.modulate.a = clampf(_big_t / 0.4, 0.0, 1.0)
	if missions.state == "run":
		_clock.text = clock(missions.time)
	for s: Structure in _rows:
		var l: Label = _rows[s]
		var gone := not is_instance_valid(s) or s.down
		var title := s.title if is_instance_valid(s) else "?"
		l.text = ("✓  %s" if gone else "○  %s  %%%d") % ([title] if gone else [title, int(s.standing_share() * 100.0)])
		l.add_theme_color_override("font_color", Ui.GOOD if gone else Ui.INK)
	_marks.queue_redraw()


## Over each target: what it is and how far; at the screen's edge when it's off it.
func _draw_marks() -> void:
	if missions.state == "prep" and _panel.visible:
		return
	var cam := get_viewport().get_camera_3d()
	var me: Variant = missions.game.get("machine")
	if cam == null or not is_instance_valid(me):
		return
	var screen := get_viewport().get_visible_rect().size
	if screen.x < 200.0:
		return
	var font := Ui.font("head")
	var c := screen * 0.5
	for s in missions.targets:
		if not is_instance_valid(s):
			continue
		var top := s.top() + Vector3.UP * 1.5
		var dist := (me as Machine).global_position.distance_to(s.center())
		var col := Ui.GOOD if s.down else Ui.ACCENT
		if not cam.is_position_behind(top):
			var p := cam.unproject_position(top)
			if Rect2(Vector2(40, 40), screen - Vector2(80, 80)).has_point(p):
				var r := 9.0
				var dia := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
				_marks.draw_colored_polygon(dia, Color(0, 0, 0, 0.5))
				if s.down:
					_marks.draw_line(p + Vector2(-5, 0), p + Vector2(-1, 4), col, 2.5)
					_marks.draw_line(p + Vector2(-1, 4), p + Vector2(6, -5), col, 2.5)
				else:
					_marks.draw_polyline(dia + PackedVector2Array([dia[0]]), col, 2.0)
					var txt := "%s  %d m" % [Ui.upper(s.title), int(dist)]
					var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
					_marks.draw_string_outline(font, p + Vector2(-ts.x * 0.5, -16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.6))
					_marks.draw_string(font, p + Vector2(-ts.x * 0.5, -16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.INK)
				continue
		if s.down:
			continue
		# off the screen: a diamond at its edge toward it
		var v := cam.global_basis.inverse() * (s.center() - cam.global_position)
		var dir := Vector2(v.x, -v.y)
		if v.z > 0.0:
			dir = Vector2(v.x if absf(v.x) > 0.01 else 0.01, absf(v.x) * 0.6 + 0.2)
		dir = dir.normalized()
		var edge := c + dir * minf((screen.x * 0.5 - 60.0) / maxf(absf(dir.x), 0.01), (screen.y * 0.5 - 60.0) / maxf(absf(dir.y), 0.01))
		var e := 8.0
		_marks.draw_colored_polygon(PackedVector2Array([edge + Vector2(0, -e), edge + Vector2(e, 0), edge + Vector2(0, e), edge + Vector2(-e, 0)]), col)
		_marks.draw_string(font, edge - dir * 24.0 + Vector2(-14, 4), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK)
