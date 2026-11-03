class_name TechTree
extends Control
## What can be found out, as a tree (the HUD's ARAŞTIRMA, T): a card each, laid out in columns by
## what it comes after, a line from each to what it opens. Each card: its name, what it gives, how
## far it's got (or that it's known), and ARAŞTIR to set the reading rooms to it. Drawn as on a
## Van Dyke print, a drawing's sepia copy: cream lines on the brown, a faint squared grid under them, what's being read pencilled
## in yellow. Built once; the cards' state and the lines drawn again as things change.

const PENCIL := Color(1.0, 0.86, 0.45) ## (what's being read)

const CARD := Vector2(250, 150)
const GAP := Vector2(70, 22)

var game: Node
var _cards := {} ## tech -> [PanelContainer, status Label, ProgressBar, Button]
var _at := {} ## tech -> its card's top-left


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	# columns by depth (how many must come before), in the order they're listed
	var cols := {}
	for t: String in BuildingDefs.TECHS:
		var d := _depth(t)
		if not cols.has(d):
			cols[d] = []
		(cols[d] as Array).append(t)
	var tall := 0
	for d: int in cols:
		tall = maxi(tall, (cols[d] as Array).size())
	for d: int in cols:
		var col: Array = cols[d]
		var top := (tall - col.size()) * (CARD.y + GAP.y) * 0.5
		for i in col.size():
			_at[col[i]] = Vector2(d * (CARD.x + GAP.x), top + i * (CARD.y + GAP.y))
			_make_card(col[i])
	custom_minimum_size = Vector2(cols.size() * (CARD.x + GAP.x) - GAP.x, tall * (CARD.y + GAP.y) - GAP.y)


static func _depth(t: String) -> int:
	var after := str(BuildingDefs.TECHS[t].get("after", ""))
	return 0 if after == "" else _depth(after) + 1


func _make_card(t: String) -> void:
	var td: Dictionary = BuildingDefs.TECHS[t]
	var p := PanelContainer.new()
	p.position = _at[t]
	p.size = CARD
	p.custom_minimum_size = CARD
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	p.add_child(col)
	Ui.label(col, Ui.upper(str(td.name)), 16, Ui.CHALK, "head").remove_theme_constant_override("outline_size")
	var desc := Ui.label(col, str(td.desc), 13, Color(Ui.CHALK, 0.72))
	desc.remove_theme_constant_override("outline_size")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(CARD.x - 24, 0)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = float(td.pts)
	bar.custom_minimum_size = Vector2(0, 5)
	var bg := StyleBoxFlat.new() # (a scale drawn in outline, filled in as it's read)
	bg.bg_color = Color(0, 0, 0, 0)
	bg.border_color = Color(Ui.CHALK, 0.45)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = PENCIL
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	col.add_child(bar)
	var row := HBoxContainer.new()
	col.add_child(row)
	var status := Ui.label(row, "", 12, Color(Ui.CHALK, 0.7), "head")
	status.remove_theme_constant_override("outline_size")
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var go := Ui.ink_button(Button.new(), Ui.CHALK, 13)
	go.text = "ARAŞTIR"
	go.pressed.connect(func() -> void:
		game.village.study(t)
		refresh())
	row.add_child(go)
	_cards[t] = [p, status, bar, go]


func refresh() -> void:
	var v: Village = game.village
	for t: String in _cards:
		var parts: Array = _cards[t]
		var p: PanelContainer = parts[0]
		var status: Label = parts[1]
		var bar: ProgressBar = parts[2]
		var go: Button = parts[3]
		var known := v.knows(t)
		var on := v.studying == t
		var open := v.can_study(t)
		bar.value = float(BuildingDefs.TECHS[t].pts) if known else (v.study_pts if on else 0.0)
		go.visible = open and not on
		if known:
			status.text = "BİLİNİYOR"
		elif on:
			status.text = "ARAŞTIRILIYOR · %%%d" % roundi(v.study_pts / float(BuildingDefs.TECHS[t].pts) * 100.0)
		elif open:
			status.text = "%d puan" % roundi(float(BuildingDefs.TECHS[t].pts))
		else:
			status.text = "ÖNCE %s" % Ui.upper(str(BuildingDefs.TECHS[BuildingDefs.TECHS[t].after].name))
		status.add_theme_color_override("font_color", Ui.CHALK if known else (PENCIL if on else Color(Ui.CHALK, 0.7)))
		var box := StyleBoxFlat.new() # (the study's outline: doubled once it's known, in pencil while it's read)
		box.bg_color = Color(Ui.CHALK, 0.1) if known else (Color(PENCIL, 0.08) if on else Color(0.22, 0.13, 0.07, 0.4))
		box.border_color = PENCIL if on else Color(Ui.CHALK, 0.95 if known or open else 0.5)
		box.set_border_width_all(3 if known else (2 if on else 1))
		box.set_content_margin_all(12)
		p.add_theme_stylebox_override("panel", box)
		p.modulate.a = 1.0 if known or open else 0.7
	queue_redraw()


func _draw() -> void:
	var v: Village = game.village if game else null
	# the squared grid the draughtsman worked on
	var step := 24.0
	for i in int(size.x / step) + 1:
		draw_line(Vector2(i * step, -6), Vector2(i * step, size.y + 6), Color(Ui.CHALK, 0.06 if i % 5 else 0.12), 1.0)
	for i in int(size.y / step) + 1:
		draw_line(Vector2(-6, i * step), Vector2(size.x + 6, i * step), Color(Ui.CHALK, 0.06 if i % 5 else 0.12), 1.0)
	for t: String in _at:
		var after := str(BuildingDefs.TECHS[t].get("after", ""))
		if after == "":
			continue
		var a: Vector2 = _at[after] + Vector2(CARD.x, CARD.y * 0.5)
		var b: Vector2 = _at[t] + Vector2(0, CARD.y * 0.5)
		var mid := (a.x + b.x) * 0.5
		var known := v != null and v.knows(after)
		var c := Ui.CHALK if known else Color(Ui.CHALK, 0.55)
		var path := PackedVector2Array([a, Vector2(mid, a.y), Vector2(mid, b.y), b])
		for k in path.size() - 1:
			if known:
				draw_line(path[k], path[k + 1], c, 2.0, true)
			else:
				draw_dashed_line(path[k], path[k + 1], c, 1.5, 6.0)
		draw_colored_polygon(PackedVector2Array([b, b + Vector2(-9, -5), b + Vector2(-9, 5)]), c)
