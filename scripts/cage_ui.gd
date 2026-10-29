class_name CageUi
extends CanvasLayer
## The cage's screens, in the game's look (Ui):
##   the top     the round and its floor, the clock, your credits, each rival's name and a bar of
##               what's left of it, the crowd's mood (COŞKU; YUHALIYORLAR when they boo)
##   the middle  3, 2, 1, DÖVÜŞ!; KAZANDIN and what it paid
##   panels      before the first round (build, then start), the workshop between rounds (what's
##               broken and missing and what it costs, repair all or only the cab, on to the next),
##               the end (out or champion: again, or the start menu), the record and the fame earned
##   top right   the maze's map: its walls, the hazards, the corners, you and which way you face;
##               a rival exactly when it's near, else only the cell it was in a moment ago, pulsing
##               (refreshed every SCAN s), and where lobbed rounds are coming down

var cage: Cage
var _top: VBoxContainer
var _title: Label
var _clock: Label
var _credits: Label
var _bars: VBoxContainer
var _mood_row: HBoxContainer
var _mood_word: Label
var _mood_bar: Control
var _big: Label
var _sub: Label
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _big_t := 0.0
var _map: Control
var _seen := {} ## Machine -> the cell it was last placed in on the map
var _scan_t := 0.0
var _t := 0.0
const MAP := 236.0 ## px
const SCAN := 2.5 ## s
const NEAR := 30.0 ## m: a rival this near is shown where it is


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
	_mood_row = HBoxContainer.new()
	_mood_row.add_theme_constant_override("separation", 10)
	_top.add_child(_mood_row)
	_mood_word = Ui.label(_mood_row, "COŞKU", 14, Color(0.35, 0.9, 1.0), "digital")
	_mood_word.custom_minimum_size.x = 120
	_mood_bar = Control.new()
	_mood_bar.custom_minimum_size = Vector2(240, 12)
	_mood_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mood_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mood_bar.draw.connect(func() -> void:
		Ui.segments(_mood_bar, Rect2(Vector2.ZERO, _mood_bar.size), 24, cage.mood, cage.mood_color()))
	_mood_row.add_child(_mood_bar)
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
	# the map
	var mp := PanelContainer.new()
	mp.add_theme_stylebox_override("panel", Ui.glass(false, 8.0))
	mp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mp.offset_right = -26
	mp.offset_top = 78
	mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mp)
	_map = Control.new()
	_map.custom_minimum_size = Vector2(MAP, MAP)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	mp.add_child(_map)


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


func close() -> void:
	_close_panel()


func hide_panel() -> void:
	_panel.visible = false


func panel_up() -> bool:
	return _panel.visible


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


## A word across the middle for a moment (the crowd's present, the organisers' shelling).
func flash(t: String, sub := "") -> void:
	_big_text(t, sub, 2.0)


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
	var t := Ui.label(_panel_box, "Her tur ayrı bir labirent, her oynayışta yeniden çizilir; zemini, tuzakları (çamur, buz, ateş kapanları, dikenler, çukur) ve rakipleri değişir, rakipler labirentte yolunu bulup sana gelir. Rakibi parçala ya da hareketsiz bırak (8 sn sayılır); süre biterse jüri az hasar alana verir. Kazandıkça kredi kazanırsın, turlar arasında atölyede aracını onarırsın. Kabinin giderse elenirsin. Kafes bir stadyumun ortasında: seyirci kavga ister, vurdukça coşar, coşku dolunca yanına hediye sandık yollar; savaşmadan saklanırsan yuhalar, sonra organizasyon topçu ateşi açar.", 16, Ui.DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 510
	Ui.label(_panel_box, "Her tur inşayla başlar: labirente göre aracını kur (B). Turlar arası yeni parça kredi ister.", 15, Ui.INK, "label")
	Ui.label(_panel_box, "BAŞLANGIÇ KREDİSİ  %d" % cage.credits, 15, Ui.ACCENT, "head")
	var rec := cage.record
	Ui.label(_panel_box, "ŞÖHRET %d   ·   EN İYİ %d TUR   ·   ŞAMPİYONLUK %d   ·   %d DENEME" % [rec.fame, rec.best_round, rec.titles, rec.runs], 14, Ui.INK, "label")
	var nx := rec.next_unlock()
	var nl := Ui.label(_panel_box, "Bütün parçalar açık." if nx.is_empty() else "Sıradaki kilit %d şöhrette: %s. Kazandığın her tur şöhret getirir, ilerideki turlar daha çok." % [int(nx[0]),
		", ".join((nx[1] as Array).map(func(i: String) -> String: return str(Parts.def(i).name)))], 13, Ui.DIM)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size.x = 510
	_button("DÖVÜŞE BAŞLA  ·  ENTER", func() -> void:
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
	var shop := Ui.label(_panel_box, "B: araçta değişiklik (yeni parça fiyatı kadar, sökülen yarı fiyatına)", 13, Ui.DIM)
	shop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button("SONRAKİ TUR  ·  %s  ·  ENTER" % next_name, func() -> void:
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
	var lr := cage.last_run
	if not lr.is_empty():
		Ui.label(_panel_box, "+%d ŞÖHRET   ·   toplam %d   ·   en iyi %d tur" % [int(lr.gained), cage.record.fame, cage.record.best_round], 17, Ui.ACCENT, "head")
		if not (lr.opened as Array).is_empty():
			Ui.label(_panel_box, "YENİ PARÇA AÇILDI: " + ", ".join((lr.opened as Array).map(func(i: String) -> String: return str(Parts.def(i).name))), 16, Ui.GOOD, "head")
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
	_mood_row.visible = cage.state == "fight"
	_mood_word.text = "YUHALIYORLAR" if cage.booing else "COŞKU"
	_mood_word.add_theme_color_override("font_color", cage.mood_color() if cage.booing else Color(0.35, 0.9, 1.0))
	_mood_bar.queue_redraw()
	for row in _bars.get_children():
		if row.get_child_count() > 1:
			(row.get_child(1) as Control).queue_redraw()
	_t += dt
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = SCAN
		for e in cage.rivals:
			if is_instance_valid(e):
				_seen[e] = cage.arena.cell_of(e.global_position)
	_map.get_parent().visible = not panel_up() and cage.state in ["prep", "countdown", "fight", "won", "workshop"]
	_map.queue_redraw()


# --- The map --------------------------------------------------------------------------------------

func _mp(x: float, z: float) -> Vector2:
	return Vector2(x + CageArena.HALF, z + CageArena.HALF) * MAP / (CageArena.HALF * 2.0)


func _draw_map() -> void:
	var a := cage.arena
	var s := MAP / (CageArena.HALF * 2.0)
	_map.draw_rect(Rect2(Vector2.ZERO, Vector2(MAP, MAP)), Color(0.06, 0.07, 0.08, 0.8))
	for z: Rect2 in CageArena.HOUSE_ZONES:
		_map.draw_rect(Rect2(_mp(z.position.x, z.position.y), z.size * s), Color(0.85, 0.65, 0.1, 0.5), false, 1.0)
	_map.draw_rect(Rect2(_mp(-CageArena.HALF, -CageArena.HALF), Vector2(9, 9)), Color(0.8, 0.15, 0.1, 0.8))
	_map.draw_rect(Rect2(_mp(CageArena.HALF, CageArena.HALF) - Vector2(9, 9), Vector2(9, 9)), Color(0.15, 0.35, 0.85, 0.8))
	var lay := a.layout
	if lay.has("pit") and (lay.pit as Rect2).size.x > 0.0:
		var pr: Rect2 = lay.pit
		_map.draw_rect(Rect2(_mp(pr.position.x, pr.position.y), pr.size * s), Color(0.0, 0.0, 0.0, 0.9) if a.pit_open else Color(0.25, 0.25, 0.25))
		_map.draw_rect(Rect2(_mp(pr.position.x, pr.position.y), pr.size * s), Color(0.95, 0.7, 0.1), false, 1.0)
	for r: Rect2 in lay.get("spikes", []):
		_map.draw_rect(Rect2(_mp(r.position.x, r.position.y), r.size * s), Color(0.6, 0.6, 0.62, 0.9))
	for v: Vector2 in lay.get("vents", []):
		_map.draw_circle(_mp(v.x, v.y), 2.6, Color(1.0, 0.45, 0.1))
	for sp: Vector2 in lay.get("spinners", []):
		_map.draw_arc(_mp(sp.x, sp.y), 3.2, 0.0, TAU, 12, Color(0.95, 0.75, 0.1), 1.5)
	for sw: Array in lay.get("saws", []):
		_map.draw_line(_mp((sw[0] as Vector2).x, (sw[0] as Vector2).y), _mp((sw[1] as Vector2).x, (sw[1] as Vector2).y), Color(0.95, 0.75, 0.1), 1.5)
	for w: Array in a.walls:
		_map.draw_line(_mp((w[0] as Vector2).x, (w[0] as Vector2).y), _mp((w[1] as Vector2).x, (w[1] as Vector2).y), Color(0.78, 0.82, 0.86), 2.5)
	_map.draw_rect(Rect2(Vector2.ZERO, Vector2(MAP, MAP)), Color(0.78, 0.82, 0.86), false, 2.0)
	for rg in get_tree().get_nodes_in_group("lob_rings"):
		var p := (rg as Node3D).global_position
		_map.draw_arc(_mp(p.x, p.z), 4.0, 0.0, TAU, 16, Color(1.0, 0.2, 0.15, 0.6 + 0.4 * sin(_t * 12.0)), 2.0)
	var me: Machine = cage.game.get("machine")
	for e in cage.rivals:
		if not is_instance_valid(e) or not e.alive:
			continue
		var near := is_instance_valid(me) and e.global_position.distance_to(me.global_position) < NEAR
		if near:
			_map.draw_circle(_mp(e.global_position.x, e.global_position.z), 4.0, Color(1.0, 0.25, 0.2))
		elif _seen.has(e):
			# where it was a moment ago: its cell, pulsing
			var c: Vector2i = _seen[e]
			var r := Rect2(_mp(-CageArena.HALF + c.x * CageArena.CELL, -CageArena.HALF + c.y * CageArena.CELL), Vector2.ONE * CageArena.CELL * s)
			_map.draw_rect(r.grow(-2.0), Color(1.0, 0.2, 0.15, 0.18 + 0.14 * sin(_t * 4.0)))
			_map.draw_rect(r.grow(-2.0), Color(1.0, 0.25, 0.2, 0.7), false, 1.0)
	if is_instance_valid(me):
		var p := _mp(me.global_position.x, me.global_position.z)
		var f := -me.global_basis.z
		var d := Vector2(f.x, f.z).normalized() * 7.0
		var sd := Vector2(-d.y, d.x) * 0.6
		_map.draw_colored_polygon(PackedVector2Array([p + d, p - d * 0.6 + sd, p - d * 0.6 - sd]), Color(1.0, 0.6, 0.15))
