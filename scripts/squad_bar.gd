class_name SquadBar
extends PanelContainer
## The militia along the bottom while there's fighting (or any of them taken in hand): a card each,
## its face, a line of health, its cartridges, whether it's in cover and what it's doing. A click
## picks it (Shift adds it to those chosen), a second takes the view to it; ALL picks the lot (V).

var game: Node
var _row: HBoxContainer
var _cards: Array = [] ## [Button, face, hp bar, ammo Label, state Label] each
var _shown: Array[Villager] = []
var _t := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", Ui.glass(false, 6.0))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := HBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := VBoxContainer.new()
	col.add_child(head)
	Ui.label(head, "BİRLİK", 13, Ui.ACCENT, "head")
	var all := Button.new()
	all.text = "HEPSİ (V)"
	all.focus_mode = Control.FOCUS_NONE
	all.add_theme_font_override("font", Ui.font("head"))
	all.add_theme_font_size_override("font_size", 12)
	all.pressed.connect(func() -> void: game.select_militia())
	head.add_child(all)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	col.add_child(_row)
	visible = false


func _process(dt: float) -> void:
	_t += dt
	if _t < 0.2:
		return
	_t = 0.0
	var v: Village = game.village
	var squad: Array[Villager] = []
	for o in v.villagers:
		if not o.dead and (o.drafted or (o.militia and game.raids.active)):
			squad.append(o)
	visible = not squad.is_empty() and game.hud.visible
	if not visible:
		return
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
		(c[3] as Label).text = ("%d %s" % [o.ammo, "ok" if o.held == "bow" else "fişek"]) if o.armed else "silahsız"
		(c[3] as Label).add_theme_color_override("font_color", Ui.BAD if o.armed and o.ammo <= 2 else Ui.DIM)
		var st := "YERDE" if o.down else ("SİPERDE" if o.in_cover else ("AÇIKTA" if o.armed else str(o.job).left(10)))
		(c[4] as Label).text = st
		(c[4] as Label).add_theme_color_override("font_color", Ui.BAD if o.down else (Ui.GOOD if o.in_cover else Ui.ACCENT))
		(c[0] as Button).modulate = Color(1, 1, 1) if o in chosen else Color(0.82, 0.82, 0.82)


func _build() -> void:
	for ch in _row.get_children():
		ch.queue_free()
	_cards.clear()
	for i in _shown.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(70, 96)
		b.add_theme_stylebox_override("normal", Ui.glass(false, 3.0, Color(1, 1, 1, 0.05)))
		b.add_theme_stylebox_override("hover", Ui.glass(false, 3.0, Color(1.0, 0.56, 0.14, 0.25), Ui.ACCENT))
		_row.add_child(b)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
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
		bg.bg_color = Color(0, 0, 0, 0.5)
		var fg := StyleBoxFlat.new()
		fg.bg_color = Ui.GOOD
		hp.add_theme_stylebox_override("background", bg)
		hp.add_theme_stylebox_override("fill", fg)
		col.add_child(hp)
		var ammo := Ui.label(col, "", 11, Ui.DIM, "head")
		ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var state := Ui.label(col, "", 11, Ui.ACCENT, "head")
		state.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var who := _shown[i]
		b.tooltip_text = who.display_name
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
		_cards.append([b, face, hp, ammo, state])
