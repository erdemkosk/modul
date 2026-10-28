class_name DriveHud
extends CanvasLayer
## What you see while driving (Ui's look: smoked glass leaning like armour plate, Barlow, one orange):
##   bottom left    your machine from above, each part shaded by what's left of it (a part just hit
##                  flashes red), the hull's share left, its weight and power, the ground under it
##   bottom middle  the guns as plates, each with its picture, its key (1-9 turns it on or off, 0 all
##                  on), its state and a bar (the minigun spinning up, the cannon loading, the pod's
##                  tubes); over them the battery as a thin bar with what goes in and out, and a red tag
##                  for anything shed for want of charge
##   bottom right   the speed, big, a leaning bar under it, which way it's going and its power
##   top left       where you are and the tally; top right the camera (C) and the frame rate
## Under the panels, CombatOverlay: the screen going red when you're hurt, where it came from, the enemy.

const ICON := {"minigun": "minigun", "cannon": "cannon", "rockets": "rockets"}
const NAME := {"minigun": "MİNİGUN", "cannon": "TOP 76", "rockets": "ROKET"}
const TOP_SPEED := 90.0 ## km/h at the speed bar's end

var game: Node
var _root: Control
var _map: Control
var _hull_pct: Label
var _hull_bar: Control
var _mass: Label
var _ground: Label
var _status: Label
var _bat_head: Label
var _bat_flow: Label
var _bat_bar: Control
var _shed_row: HBoxContainer
var _chips: HBoxContainer
var _speed: Label
var _dir: Label
var _speed_bar: Control
var _engine: Label
var _where: Label
var _tally: Label
var _cam: Label
var _fps: Label
var _t := 0.0
var _flash := 0.0
var _v := 0.0
var _hull := 1.0
var _bat := 1.0
var _bat_low := false
var _hp_seen := {} ## part key -> hp last seen (a drop flashes it)
var _hp_flash := {} ## part key -> seconds of red left


func _ready() -> void:
	layer = 4
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var fx := CombatOverlay.new()
	fx.game = game
	_root.add_child(fx)
	_build_machine()
	_build_guns()
	_build_speed()
	_build_top()


func _box(parent: Control, preset: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(preset)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	return v


func _canvas(parent: Node, size: Vector2, fn: Callable) -> Control:
	var c := Control.new()
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn.bind(c))
	parent.add_child(c)
	return c


# --- Bottom left: the machine -------------------------------------------------------------------

func _build_machine() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_left = 30
	row.offset_bottom = -26
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(row)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", Ui.glass(false, 8.0))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(plate)
	_map = _canvas(plate, Vector2(132, 132), _draw_map)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	_status = Ui.label(col, "", 14, Ui.BAD, "head")
	Ui.label(col, "GÖVDE", 13, Ui.DIM, "head")
	_hull_pct = Ui.label(col, "100", 44, Ui.INK, "display")
	_hull_bar = _canvas(col, Vector2(150, 8), func(c: Control) -> void:
		var col2 := Ui.GOOD if _hull > 0.6 else (Ui.ACCENT if _hull > 0.3 else Ui.BAD)
		Ui.segments(c, Rect2(Vector2.ZERO, c.size), 16, _hull, col2))
	_mass = Ui.label(col, "", 13, Ui.DIM, "label")
	_ground = Ui.label(col, "", 13, Ui.INK, "label")


## The machine from above, its nose up: each part a block shaded by its hit points left, the cab
## outlined, the guns in orange, a part just hit flashing red.
func _draw_map(c: Control) -> void:
	var mv: Variant = game.get("machine")
	if not is_instance_valid(mv):
		return
	var m := mv as Machine
	if m.design.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p: Dictionary in m.design:
		var s := Parts.size_of(p.id, p.rot)
		lo = lo.min(Vector2(p.at.x, p.at.z))
		hi = hi.max(Vector2(p.at.x + s.x, p.at.z + s.z))
	var span := hi - lo
	var k := minf((c.size.x - 12.0) / span.x, (c.size.y - 12.0) / span.y)
	var off := (c.size - span * k) * 0.5
	var order := range(m.design.size())
	order.sort_custom(func(a: int, b: int) -> bool: return m.design[a].at.y < m.design[b].at.y)
	for i: int in order:
		var p: Dictionary = m.design[i]
		var s := Parts.size_of(p.id, p.rot)
		var r := Rect2(off + (Vector2(p.at.x, p.at.z) - lo) * k, Vector2(s.x, s.z) * k).grow(-0.75)
		var frac := clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0)
		var kind := str(Parts.def(p.id).kind)
		var base := Color(0.82, 0.82, 0.78)
		if kind in ["wheel", "track"]:
			base = Color(0.42, 0.42, 0.42)
		elif kind == "weapon":
			base = Ui.ACCENT
		var col := base if frac > 0.66 else (base.lerp(Ui.ACCENT, 0.7) if frac > 0.33 else Ui.BAD)
		var key := _key(p, i)
		if float(_hp_flash.get(key, 0.0)) > 0.0 and fmod(_flash * 8.0, 1.0) < 0.6:
			col = Color(1.0, 0.25, 0.2)
		col.a = 0.55 + 0.4 * (p.at.y + 2) / 6.0
		c.draw_rect(r, col)
		if p.id == "cab":
			c.draw_rect(r.grow(1.0), Ui.INK, false, 1.5)
	# where its weight sits (it moves as parts come off)
	var cm := off + (Vector2(m.com.x, m.com.z) / Parts.CELL - lo) * k
	c.draw_circle(cm, 4.0, Color(0, 0, 0, 0.6))
	c.draw_circle(cm, 2.6, Ui.ACCENT)
	c.draw_line(cm - Vector2(7, 0), cm + Vector2(7, 0), Ui.ACCENT, 1.0)
	c.draw_line(cm - Vector2(0, 7), cm + Vector2(0, 7), Ui.ACCENT, 1.0)
	# its nose
	c.draw_colored_polygon(PackedVector2Array([Vector2(c.size.x * 0.5, 0.0), Vector2(c.size.x * 0.5 - 5.0, 6.0),
		Vector2(c.size.x * 0.5 + 5.0, 6.0)]), Ui.DIM)


func _key(p: Dictionary, i: int) -> String:
	return "%s@%s/%d" % [p.id, p.at, p.rot]


# --- Bottom middle: the guns and the battery ------------------------------------------------------

func _build_guns() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_bottom = -26
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	_shed_row = HBoxContainer.new()
	_shed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_shed_row.add_theme_constant_override("separation", 6)
	col.add_child(_shed_row)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	_bat_head = Ui.label(head, "", 14, Ui.INK, "head")
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_bat_flow = Ui.label(head, "", 13, Ui.DIM, "label")
	_bat_bar = _canvas(col, Vector2(0, 7), _draw_battery)
	_chips = HBoxContainer.new()
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.add_theme_constant_override("separation", 6)
	col.add_child(_chips)


func _draw_battery(c: Control) -> void:
	var col := Ui.BAD if _bat < Machine.SHED[1] else (Ui.ACCENT if _bat < Machine.SHED[0] else Ui.GOOD)
	if _bat_low and fmod(_flash, 1.0) < 0.5:
		col = col.lightened(0.35)
	Ui.segments(c, Rect2(Vector2.ZERO, c.size), 40, _bat, col, Ui.FAINT, 0.6)
	for s: float in Machine.SHED: # (where each thing gets shed)
		c.draw_line(Vector2(s * c.size.x, -2.0), Vector2(s * c.size.x, c.size.y + 2.0), Color(1, 1, 1, 0.45), 1.0)


## A gun's plate: its picture, its key, its name, its state, its bar.
func _chip(g: MachineGun, i: int) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", Ui.glass(true, 8.0))
	plate.custom_minimum_size = Vector2(196, 0)
	plate.set_meta("gun", g)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	plate.add_child(row)
	var key := PanelContainer.new()
	var ks := StyleBoxFlat.new()
	ks.bg_color = Ui.ACCENT
	ks.set_corner_radius_all(2)
	ks.content_margin_left = 6
	ks.content_margin_right = 6
	ks.skew = Vector2(-Ui.SKEW, 0.0)
	key.add_theme_stylebox_override("panel", ks)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(key)
	var kl := Ui.label(key, str(i + 1) if i < 9 else "", 18, Color(0.08, 0.05, 0.02), "display")
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pic := TextureRect.new()
	var icon := "res://assets/parts/icons/%s.png" % ICON.get(g.kind, g.kind)
	if ResourceLoader.exists(icon):
		pic.texture = load(icon)
	pic.custom_minimum_size = Vector2(52, 52)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	Ui.label(col, NAME.get(g.kind, g.kind), 16, Ui.INK, "head")
	var st := Ui.label(col, "", 12, Ui.DIM, "label")
	var bar := _canvas(col, Vector2(92, 5), func(c: Control) -> void:
		var f := float(plate.get_meta("frac", 1.0))
		var lit := g.armed
		var on_col := (Ui.GOOD if f >= 0.999 else Ui.ACCENT) if lit else Color(1, 1, 1, 0.3)
		if g.kind == "rockets":
			Ui.segments(c, Rect2(Vector2.ZERO, c.size), MachineGun.ROCKETS, f, on_col, Ui.FAINT, 0.6)
		else:
			Ui.segments(c, Rect2(Vector2.ZERO, c.size), 12, f, on_col, Ui.FAINT, 0.6))
	plate.set_meta("state", st)
	plate.set_meta("bar", bar)
	plate.set_meta("key", ks)
	return plate


func _weapons(m: Machine) -> void:
	var stale := _chips.get_child_count() != m.guns.size()
	if not stale:
		for i in m.guns.size():
			if _chips.get_child(i).get_meta("gun") != m.guns[i]:
				stale = true
	if stale:
		for c in _chips.get_children():
			_chips.remove_child(c)
			c.queue_free()
		for i in m.guns.size():
			_chips.add_child(_chip(m.guns[i], i))
	for i in m.guns.size():
		var g := m.guns[i]
		var plate := _chips.get_child(i) as PanelContainer
		var frac := 1.0
		var text := "HAZIR"
		match g.kind:
			"minigun":
				frac = g._spin
				text = "DÖNÜYOR" if g._spin > 0.95 else ("HIZLANIYOR" if g._spin > 0.05 else "HAZIR")
				if not g.can_spin:
					text = "MOTOR KAPALI"
			"cannon":
				frac = 1.0 - g.reload_frac()
				text = "HAZIR" if frac >= 1.0 else "DOLDURULUYOR"
				if not g.can_load and frac < 1.0:
					text = "DOLDURUCU KAPALI"
			"rockets":
				frac = float(g.loaded) / MachineGun.ROCKETS
				text = "%d / %d ROKET" % [g.loaded, MachineGun.ROCKETS]
		if not m.powered:
			text = "AKÜ BİTTİ"
		var lit := g.armed
		var st := plate.get_meta("state") as Label
		st.text = text if lit else "KAPALI  ·  %d İLE AÇ" % (i + 1)
		st.add_theme_color_override("font_color", (Ui.BAD if ("KAPALI" in text or not m.powered) else (Ui.GOOD if frac >= 1.0 else Ui.ACCENT)) if lit else Ui.DIM)
		plate.set_meta("frac", frac)
		(plate.get_meta("bar") as Control).queue_redraw()
		var sb := plate.get_theme_stylebox("panel") as StyleBoxFlat
		sb.border_color = Ui.ACCENT if lit else Ui.EDGE
		sb.set_border_width_all(2 if lit else 1)
		sb.bg_color = Color(0.11, 0.075, 0.04, 0.84) if lit else Ui.GLASS
		(plate.get_meta("key") as StyleBoxFlat).bg_color = Ui.ACCENT if lit else Color(0.45, 0.44, 0.42)
		plate.modulate.a = 1.0 if lit else 0.6
	var w := 0.0
	for c in _chips.get_children():
		w += (c as Control).size.x + 6.0
	_bat_bar.custom_minimum_size.x = maxf(w - 6.0, 400.0)


# --- Bottom right: the speed -----------------------------------------------------------------------

func _build_speed() -> void:
	var col := _box(_root, Control.PRESET_BOTTOM_RIGHT)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_right = -34
	col.offset_bottom = -26
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_END
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	_speed = Ui.label(row, "0", 88, Ui.INK, "display")
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed.custom_minimum_size.x = 130
	var unit := VBoxContainer.new()
	unit.alignment = BoxContainer.ALIGNMENT_END
	unit.add_theme_constant_override("separation", 0)
	row.add_child(unit)
	_dir = Ui.label(unit, "", 14, Ui.ACCENT, "head")
	Ui.label(unit, "KM/SA", 16, Ui.DIM, "head")
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	unit.add_child(spacer)
	_speed_bar = _canvas(col, Vector2(240, 10), func(c: Control) -> void:
		Ui.segments(c, Rect2(Vector2.ZERO, c.size), 24, _v / TOP_SPEED, Ui.ACCENT if _v < TOP_SPEED * 0.85 else Ui.BAD))
	_speed_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	_engine = Ui.label(col, "", 13, Ui.DIM, "label")
	_engine.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


# --- Top -------------------------------------------------------------------------------------------

func _build_top() -> void:
	var l := _box(_root, Control.PRESET_TOP_LEFT)
	l.offset_left = 30
	l.offset_top = 22
	l.add_theme_constant_override("separation", 4)
	_where = Ui.label(l, "", 15, Ui.ACCENT, "head")
	Ui.rule(l)
	_tally = Ui.label(l, "", 15, Ui.INK, "label")
	var r := _box(_root, Control.PRESET_TOP_RIGHT)
	r.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	r.offset_right = -30
	r.offset_top = 22
	r.add_theme_constant_override("separation", 2)
	_cam = Ui.label(r, "", 14, Ui.INK, "head")
	_cam.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps = Ui.label(r, "", 12, Ui.DIM, "label")
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


# --- Each frame ------------------------------------------------------------------------------------

func flash_guns() -> void:
	pass # (the plates show which are on as they change)


func _process(dt: float) -> void:
	_t += dt
	_flash += dt
	var mv: Variant = game.get("machine")
	var building: bool = (game.get("builder") as Builder).active if game.get("builder") else false
	visible = is_instance_valid(mv) and not building
	if not visible:
		return
	var m := mv as Machine
	_v = lerpf(_v, absf(m.speed) * 3.6, 1.0 - exp(-10.0 * dt))
	_speed.text = "%d" % int(round(_v))
	_dir.text = "İLERİ" if m.speed > 0.5 else ("GERİ" if m.speed < -0.5 else "")
	_speed_bar.queue_redraw()
	_bat_bar.queue_redraw()
	_weapons(m)
	# parts just hit
	var seen := {}
	for i in m.design.size():
		var p: Dictionary = m.design[i]
		var key := _key(p, i)
		seen[key] = true
		if _hp_seen.has(key) and float(p.hp) < float(_hp_seen[key]) - 0.01:
			_hp_flash[key] = 0.6
		_hp_seen[key] = float(p.hp)
	for key: String in _hp_flash.keys():
		_hp_flash[key] = float(_hp_flash[key]) - dt
		if float(_hp_flash[key]) <= 0.0 or not seen.has(key):
			_hp_flash.erase(key)
	_map.queue_redraw()
	if _t < 0.1:
		return
	_t = 0.0
	_slow(m)


func _slow(m: Machine) -> void:
	_hull = m.health()
	# the cab (it's the driver) and whether it can still move
	var cab := m.cab_frac()
	var warn := ""
	if m.immobile():
		var hold: float = game.get("_recover_t") if game.get("_recover_t") != null else 0.0
		warn = "HAREKETSİZ  ·  K BASILI TUT: YENİDEN KUR" if hold <= 0.0 else "YENİDEN KURULUYOR  %%%d" % int(hold / 1.5 * 100.0)
	elif cab < 0.4:
		warn = "KABİN %%%d  ·  KABİN GİDERSE ARAÇ GİDER" % int(cab * 100.0)
	_status.text = warn
	_status.visible = warn != ""
	_status.modulate.a = 1.0 if fmod(_flash, 0.8) < 0.55 else 0.45
	_hull_pct.text = "%%%d" % int(_hull * 100.0)
	_hull_pct.add_theme_color_override("font_color", Ui.INK if _hull > 0.3 else Ui.BAD)
	_hull_bar.queue_redraw()
	_mass.text = "%d KG   ·   %d KW   ·   %d KW/T" % [int(m.total_mass), int(m.power_kw), int(m.power_kw / maxf(m.total_mass / 1000.0, 0.01))]
	var sink := 0.0
	for w in m.wheels:
		sink = maxf(sink, w.sink)
	var ground := Ui.upper(game.call("_ground_name", m.ground_label) as String) if m.ground_label != "" else "HAVADA"
	_ground.text = ground + ("   ·   %d CM BATTI" % int(sink * 100.0) if sink > 0.02 else "")
	_ground.add_theme_color_override("font_color", Ui.ACCENT if sink > 0.08 else Ui.INK)
	_engine.text = "%d KW MOTOR   ·   %d KW/T" % [int(m.power_kw), int(m.power_kw / maxf(m.total_mass / 1000.0, 0.01))]
	# the battery
	_bat = m.charge_frac()
	_bat_low = not m.powered or m.shed > 0
	_bat_head.text = "AKÜ  %%%d" % int(_bat * 100.0)
	_bat_head.add_theme_color_override("font_color", Ui.BAD if _bat_low else Ui.INK)
	var net := m.charge_kw - m.draw_kw
	var when := ""
	if not m.powered:
		when = "BİTTİ"
	elif net < -0.05:
		var secs := m.energy_kj / -net
		when = "~%d DK" % maxi(int(secs / 60.0), 1) if secs >= 60.0 else "~%d SN" % int(secs)
	elif _bat > 0.995:
		when = "DOLU"
	else:
		when = "DOLUYOR"
	_bat_flow.text = "+%.1f KW   −%.1f KW   ·   %s" % [m.charge_kw, m.draw_kw, when]
	_bat_flow.add_theme_color_override("font_color", Ui.BAD if net < -0.05 else Ui.DIM)
	# what's been shed, as red tags
	var tags: Array[String] = []
	for c: Dictionary in m.consumers:
		if not bool(c.on) and str(c.off_why) != "":
			tags.append(Ui.upper(str(c.name)) + " KAPALI")
	if _shed_row.get_child_count() != tags.size():
		for c in _shed_row.get_children():
			c.queue_free()
		for t in tags:
			var p := PanelContainer.new()
			p.add_theme_stylebox_override("panel", Ui.glass(true, 4.0, Color(0.5, 0.08, 0.05, 0.85), Ui.BAD))
			_shed_row.add_child(p)
			Ui.label(p, t, 12, Ui.INK, "head")
	else:
		for k in tags.size():
			((_shed_row.get_child(k) as PanelContainer).get_child(0) as Label).text = tags[k]
	# the top
	var arena: bool = game.get("arena")
	_where.text = str(game.get("place_name"))
	var enemies := 0
	for n in m.get_tree().get_nodes_in_group("machines"):
		if n != m and (n as Machine).team != 0:
			enemies += 1
	_tally.text = ("Düşman %d   ·   Vurulan %d%s" % [enemies, game.get("kills"), "   ·   HASAR KAPALI" if m.invulnerable else ""]) if arena else ""
	var cam := game.get("cam") as OrbitCamera
	_cam.text = "KAMERA  ·  %s   [C]" % Ui.upper(OrbitCamera.MODE_NAMES[cam.mode]) if cam else ""
	_fps.text = "%d FPS" % Engine.get_frames_per_second() if bool(Settings.get_value("show_fps")) else ""
