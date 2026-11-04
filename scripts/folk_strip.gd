class_name FolkStrip
extends PanelContainer
## The townsfolk down the left, always on screen: a little card each, their face, first name and a
## line of health, and a mark when something's wrong (down and bleeding, hurt, cold in the night,
## hungry), the troubled ones first. A click picks them (a second one takes the view to them);
## Shift adds them to those chosen. Its heading folds it away to just the heading (and back); kept
## as it was left (Settings.folk_open).

const MAX := 14 ## cards shown at most (the rest in KASABALILAR)

var game: Node
var _cards: Array = [] ## [Button, face TextureRect, name Label, hp ProgressBar, mark Label] each
var _shown: Array = [] ## the villager each card is showing
var _head: Button
var _cards_box: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", Ui.paper(4.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	add_child(col)
	_head = Button.new()
	_head.flat = true
	_head.focus_mode = Control.FOCUS_NONE
	_head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_head.add_theme_font_override("font", Ui.face("head", 12))
	_head.add_theme_font_size_override("font_size", 12)
	_head.add_theme_color_override("font_color", Ui.ACCENT)
	_head.add_theme_color_override("font_hover_color", Ui.INK)
	_head.tooltip_text = "Tıkla: listeyi aç / kapa"
	_head.pressed.connect(func() -> void:
		Settings.folk_open = not Settings.folk_open
		Settings.save_settings()
		_fold())
	col.add_child(_head)
	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 3)
	col.add_child(_cards_box)
	for i in MAX:
		_cards_box.add_child(_card(i))
	_fold()


func _fold() -> void:
	_cards_box.visible = Settings.folk_open
	var n: int = game.village.villagers.size() if game and game.village else 0
	_head.text = ("KASABALILAR ▾" if Settings.folk_open else "KASABALILAR (%d) ▸" % n)


func _card(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(Ui.ACCENT, 0.18)
	hover.set_corner_radius_all(3)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(func() -> void: _pick(i))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(38, 38)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(face)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var name := Ui.label(top, "", 14, Ui.INK, "head")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mood := Ui.label(top, "•", 18, Ui.GOOD, "display") # (its spirits, by colour)
	mood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.move_child(mood, 0)
	var mark := Ui.label(top, "", 12, Ui.BAD, "head")
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hp := ProgressBar.new()
	hp.show_percentage = false
	hp.custom_minimum_size = Vector2(90, 4)
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.35)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Ui.GOOD
	hp.add_theme_stylebox_override("background", bg)
	hp.add_theme_stylebox_override("fill", fg)
	col.add_child(hp)
	_cards.append([b, face, name, hp, mark, mood])
	return b


## What's wrong with `v`, in a word or two ("" nothing), and how bad (higher first).
func _trouble(v: Villager) -> Array:
	if v.down:
		return ["YERDE", 4]
	if v.bleeding:
		return ["KANIYOR", 4]
	if v.hp < v.max_hp * 0.5:
		return ["YARALI", 3]
	if v.leaving:
		return ["GİDİYOR", 3]
	if v.mood < Villager.BREAK:
		return ["ÇÖKMÜŞ", 3]
	if is_instance_valid(v.home) and v.home.cold_night:
		return ["ÜŞÜDÜ", 2]
	if game.village._hungry:
		return ["AÇ", 1]
	if game.village.controlled(v):
		return ["EMİRDE", 0]
	return ["", 0]


func refresh() -> void:
	var folk: Array = game.village.villagers.filter(func(v: Villager) -> bool: return not v.dead)
	folk.sort_custom(func(a: Villager, b: Villager) -> bool:
		var ta: int = _trouble(a)[1]
		var tb: int = _trouble(b)[1]
		return ta > tb if ta != tb else a.family + a.display_name < b.family + b.display_name)
	_shown = folk.slice(0, MAX)
	if not Settings.folk_open:
		var hurt := folk.filter(func(v: Villager) -> bool: return _trouble(v)[1] >= 2).size()
		_head.text = "KASABALILAR (%d)%s ▸" % [folk.size(), "  · %d sorunlu" % hurt if hurt > 0 else ""]
		_head.add_theme_color_override("font_color", Ui.BAD if hurt > 0 else Ui.ACCENT)
		return
	_head.add_theme_color_override("font_color", Ui.ACCENT)
	var chosen: Array = game._chosen()
	for i in MAX:
		var parts: Array = _cards[i]
		var b: Button = parts[0]
		b.visible = i < _shown.size()
		if not b.visible:
			continue
		var v: Villager = _shown[i]
		(parts[1] as TextureRect).texture = Portraits.of(v)
		(parts[2] as Label).text = v.display_name.split(" ")[0] + (" ·ç" if v.is_child else "")
		(parts[2] as Label).add_theme_color_override("font_color", Ui.ACCENT if v in chosen or v == game.selected_villager else Ui.INK)
		var hp: ProgressBar = parts[3]
		hp.max_value = v.max_hp
		hp.value = v.hp
		(hp.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Ui.BAD if v.hp < v.max_hp * 0.4 else (Ui.ACCENT if v.hp < v.max_hp * 0.8 else Ui.GOOD)
		var m := v.mood
		(parts[5] as Label).add_theme_color_override("font_color", Ui.GOOD if m >= 55.0 else (Ui.ACCENT if m >= 35.0 else Ui.BAD))
		var t: Array = _trouble(v)
		(parts[4] as Label).text = str(t[0])
		(parts[4] as Label).add_theme_color_override("font_color", Ui.ACCENT if t[0] == "EMİRDE" else Ui.BAD)
		b.tooltip_text = "%s\n%s\nMoral: %s (%d)" % [v.display_name, v.job, v.mood_word(), roundi(v.mood)]


func _pick(i: int) -> void:
	if i >= _shown.size() or not is_instance_valid(_shown[i]):
		return
	var v: Villager = _shown[i]
	if Input.is_key_pressed(KEY_SHIFT):
		if not v in game.group:
			if game.group.is_empty() and game.selected_villager:
				game.group.append(game.selected_villager)
			game.group.append(v)
		return
	if game.selected_villager == v:
		game.focus_selected()
		return
	game.select(null)
	game.selected_villager = v
	refresh()
