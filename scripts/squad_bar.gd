class_name SquadBar
extends PanelContainer
## Everyone in hand (EMİRDE) along the bottom, on a perforated muster slip: a card each with its face,
## a line of health, its cartridges, whether it's in cover and what it's doing, and in its corner the
## number of the group it's kept in (Ctrl+1…9). A click picks it (Shift adds it to those chosen), a
## second takes the view to it; HEPSİ picks the lot, HEPSİNİ BIRAK lets every one of them go.

var game: Node
var _row: HBoxContainer
var _cards: Array = [] ## [Button, face, hp bar, ammo Label, state Label, group Label] each
var _shown: Array[Villager] = []
var _count: Label
var _t := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", Ui.sheet("slip"))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := HBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	col.add_child(head)
	Ui.label(head, "EMİRDE", 15, Ui.P_INK, "display")
	_count = Ui.label(head, "", 12, Ui.P_DIM, "type")
	var all := Button.new()
	all.text = "HEPSİ"
	all.tooltip_text = "Emirdeki herkesi seç"
	all.pressed.connect(func() -> void: _pick_all())
	head.add_child(Ui.ink_button(all, Ui.P_INK, 12))
	var free := Button.new()
	free.text = "HEPSİNİ BIRAK"
	free.tooltip_text = "Emirdeki herkes yine kendi işine döner"
	free.pressed.connect(func() -> void: game.release_all())
	head.add_child(Ui.ink_button(free, Ui.P_RED, 12))
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	col.add_child(_row)
	visible = false


func _pick_all() -> void:
	if _shown.is_empty():
		return
	game.select(null)
	game.group.append_array(_shown)
	game.selected_villager = _shown[0]


func _process(dt: float) -> void:
	_t += dt
	if _t < 0.2:
		return
	_t = 0.0
	var v: Village = game.village
	var squad: Array[Villager] = []
	for o in v.villagers:
		if not o.dead and v.controlled(o):
			squad.append(o)
	visible = not squad.is_empty() and game.hud.visible
	if not visible:
		return
	_count.text = "%d kişi" % squad.size()
	squad = squad.slice(0, 12)
	if squad != _shown:
		_shown = squad
		_build()
	var chosen: Array = game._chosen()
	for i in _shown.size():
		var o := _shown[i]
		var c: Array = _cards[i]
		(c[1] as TextureRect).texture = Portraits.of(o)
		(c[2] as ProgressBar).value = o.hp / maxf(o.max_hp, 1.0) * 100.0
		(c[3] as Label).text = ("%d %s" % [o.ammo, "ok" if o.held == "bow" else "fişek"]) if o.armed else ("baltalı" if o.has_meta("axe") else "silahsız")
		(c[3] as Label).add_theme_color_override("font_color", Ui.P_RED if o.armed and o.ammo <= 2 else Ui.P_DIM)
		var st := "YERDE" if o.down else ("SİPERDE" if o.in_cover else ("AÇIKTA" if o.armed else str(o.job).left(10)))
		(c[4] as Label).text = st
		(c[4] as Label).add_theme_color_override("font_color", Ui.P_RED if o.down else (Ui.P_GREEN if o.in_cover else Ui.P_INK))
		var g: String = game.groups_of(o)
		(c[5] as Label).text = g
		(c[5] as Label).visible = g != ""
		var on := o in chosen
		(c[0] as Button).add_theme_stylebox_override("normal", Ui.ink_box(Ui.P_BLUE if on else Ui.P_INK, 0.0, 0.5, on))


func _build() -> void:
	for ch in _row.get_children():
		ch.queue_free()
	_cards.clear()
	for i in _shown.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(70, 96)
		b.add_theme_stylebox_override("normal", Ui.ink_box(Ui.P_INK, 0.0, 0.5))
		b.add_theme_stylebox_override("hover", Ui.ink_box(Ui.P_BLUE, 0.1, 0.95))
		b.add_theme_stylebox_override("pressed", Ui.ink_box(Ui.P_BLUE, 0.2, 1.0))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_row.add_child(b)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 4
		col.offset_right = -4
		col.offset_top = 3
		b.add_child(col)
		var face := TextureRect.new()
		face.custom_minimum_size = Vector2(60, 46)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(face)
		var hp := ProgressBar.new()
		hp.show_percentage = false
		hp.custom_minimum_size = Vector2(60, 5)
		hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(Ui.P_INK, 0.18)
		var fg := StyleBoxFlat.new()
		fg.bg_color = Ui.P_GREEN
		hp.add_theme_stylebox_override("background", bg)
		hp.add_theme_stylebox_override("fill", fg)
		col.add_child(hp)
		var ammo := Ui.label(col, "", 11, Ui.P_DIM, "digital")
		ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var state := Ui.label(col, "", 10, Ui.P_INK, "head")
		state.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# the group's number, stamped in the face's corner
		var grp := Label.new()
		grp.add_theme_font_override("font", Ui.face("type_bold", 13))
		grp.add_theme_font_size_override("font_size", 13)
		grp.add_theme_color_override("font_color", Ui.ENAMEL)
		var tag := StyleBoxFlat.new()
		tag.bg_color = Color(Ui.P_BLUE, 0.92)
		tag.set_corner_radius_all(1)
		tag.content_margin_left = 3
		tag.content_margin_right = 3
		grp.add_theme_stylebox_override("normal", tag)
		grp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grp.position = Vector2(4, 3)
		grp.visible = false
		b.add_child(grp)
		var who := _shown[i]
		b.tooltip_text = who.display_name + " · tık: seç, iki kez: git · Shift+tık: ekle"
		b.pressed.connect(func() -> void:
			if not is_instance_valid(who):
				return
			if Input.is_key_pressed(KEY_SHIFT):
				if game.group.is_empty() and game.selected_villager:
					game.group.append(game.selected_villager)
				if not who in game.group:
					game.group.append(who)
				return
			if game.selected_villager == who:
				game.focus_selected()
				return
			game.select(null)
			game.selected_villager = who
			game.group.clear())
		_cards.append([b, face, hp, ammo, state, grp])
