class_name Builder
extends CanvasLayer
## Building (B or Tab): the machine held still and level over a lit grid of its cells; a ghost of the
## chosen part (outlined, breathing) follows the mouse over the machine's faces, green where it fits,
## red where it doesn't, and the part a right click would take off glows. Left click bolts it on: it
## drops into place with the impact gun's rattle (a heavy part with a clang, a light one with the
## ratchet); a right click (not a drag: that turns the view) takes it off, and it lifts away.
## 1-9, 0, Q and E pick a part, R turns it (wheels and tracks turn themselves to face the side they go
## on, and hang down from it). V: an isometric view; M: mirror (what you bolt on one side goes on the
## other too); its centre of mass is marked over the grid.
##
## The screen (a light workshop look, its layout after Besiege's builder): the part groups as tabs
## along the top with the chosen group's parts as tiles under them; the tools down the left (undo,
## redo, turn, mirror, isometric, clear); top left the machine's name and three slots to save to and
## load from; on the right what the machine adds up to (its weight, its power for its weight, the
## wheels' load, its battery against what its guns draw) and what's wrong with it; bottom left the
## chosen part; bottom right the button that drives it. Every change is saved (user://design.json)
## and can be undone (Ctrl+Z, Ctrl+Y).

static var save_path := "user://design.json" ## (tests point it elsewhere)

## Asked before a part goes on (id, at, rot) -> may it (the valley: if you hold one).
var guard: Callable
## What a part costs here, for the part's card ("" when nothing does).
var price_note: Callable
var swap_guard: Callable ## (old rows, new rows) -> bool: may the machine become `new`? (the valley: if what you hold covers it)
signal removed(id: String, at: Vector3i, rot: int)
signal placed(i: int) ## (part `i` of the design was just bolted on)
static var keep_wear := false ## (the valley) a saved design keeps its parts' wear (Machine.to_data)
var swap_rows: Array = [] ## (swap_guard may say what the new design is built of: its rows, worn)
var removed_cond := 1.0 ## (what the part last taken off had left of its hit points, 0..1)
signal closed
const SLOTS := 3
const PANEL := Color(0.06, 0.065, 0.06, 0.86)
const EDGE := Color(0.32, 0.3, 0.26, 0.9)
const AMBER := Color(1.0, 0.72, 0.28)
const INK := Color(0.94, 0.92, 0.86)
const DIM := Color(0.68, 0.66, 0.6)
const BAD := Color(1.0, 0.42, 0.32)
const GOOD := Color(0.55, 0.9, 0.5)
## The keys that pick the parts, in Parts.ORDER (the cab left out).
const KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_Q, KEY_E, KEY_Z, KEY_X,
	KEY_C, KEY_F, KEY_H, KEY_N, KEY_U, KEY_I, KEY_O, KEY_J, KEY_P, KEY_G, KEY_Y, KEY_L]
const KEY_NAMES := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Q", "E", "Z", "X", "C", "F", "H", "N", "U", "I", "O",
	"J", "P", "G", "Y", "L"]
## The cards' groups.
const GROUPS := [["GÖVDE", ["frame", "armor", "wedge", "plate", "spike"]], ["YÜRÜYEN", ["wheel_s", "wheel_l", "track"]],
	["GÜÇ", ["engine_s", "engine", "engine_l", "battery", "light"]], ["SİLAH", ["minigun", "cannon", "rockets", "flamer", "ammo", "barrel", "flipper"]],
	["HAREKET", ["turret", "steer", "hinge", "rotor", "piston"]], ["YÜK", ["crane", "winch"]], ["ALET", ["saw", "collector"]],
	["AHŞAP", ["wood_frame", "wood_plate", "wood_wedge", "wood_wheel", "wood_rack"]]]
const SND := "res://assets/audio/build/"

var machine: Machine
var cam: OrbitCamera
var active := false
var selected := "frame"
var rot := 0
var mirror := false

var _ghost: Node3D
var _ghost2: Node3D ## (mirror)
var _ghost_mat: StandardMaterial3D
var _outline_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _target := {} ## {at, rot, ok, index, mirror} or {} (nothing under the mouse)
var _listen := -1 ## (K pressed over a gun or a flipper: the part waiting for its key)
var _key_tags: Array[Label3D] = []
## Keys the driving already uses (a part can still have one: it's said).
const DRIVE_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_B, KEY_TAB, KEY_L, KEY_T, KEY_C, KEY_K, KEY_ESCAPE,
	KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
var _remove_i := -1
var _glowing: Node3D
var _cards := {}
var _root: Control
var _part_name: Label
var _part_about: Label
var _part_stats: Label
var _numbers: Label
var _bars := {}
var _warn: VBoxContainer
var _hint: Label
var _tools := {}
var _slot_rows: Array[Label] = []
var _clear_armed := 0.0
var _vignette: TextureRect
var _grid: MeshInstance3D
var _grid_mat: ShaderMaterial
var _com: Node3D
var _t := 0.0
var _players: Array[AudioStreamPlayer] = []
var _player_i := 0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_vignette()
	_build_title()
	_build_designs()
	_build_toolbar()
	_build_cards()
	_build_part_info()
	_build_machine_panel()
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_mat.grow = true
	_outline_mat.grow_amount = 0.012
	_ghost_mat.next_pass = _outline_mat
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.albedo_color = Color(1.0, 0.35, 0.2, 0.35)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	visible = false
	machine.changed.connect(_refresh)
	select(selected, false)
	_typeset(_root)


## The game's type (Ui) on the screen's words: the orange headings and the big names in Barlow
## Condensed, the rest in Barlow.
func _typeset(n: Node) -> void:
	for c in n.get_children():
		if c is Label:
			var l := c as Label
			var size := l.get_theme_font_size("font_size")
			if l.get_theme_color("font_color") == ACCENT or l.get_theme_color("font_color") == AMBER:
				l.add_theme_font_override("font", Ui.font("head"))
			elif size >= 18:
				l.add_theme_font_override("font", Ui.font("display"))
				l.add_theme_font_size_override("font_size", size + 4)
		elif c is Button and (c as Button).text != "":
			(c as Button).add_theme_font_override("font", Ui.font("head"))
		_typeset(c)


# --- The screen ---------------------------------------------------------------------------------
# A light workshop look: warm paper panels with soft shadows floating over the darkened world, dark
# ink, one orange accent. Along the top the part groups as tabs and the chosen group's parts as
# tiles; down the left the tools; top left the machine's name and its slots; on the right what the
# machine adds up to; bottom left the chosen part; bottom right the button that drives it.

const PAPER := Color(0.95, 0.925, 0.86, 0.97)
const PAPER_2 := Color(0.9, 0.865, 0.79, 1.0)
const PAPER_EDGE := Color(0.62, 0.53, 0.4, 0.9)
const INK_D := Color(0.17, 0.14, 0.11)
const DIM_D := Color(0.46, 0.4, 0.33)
const ACCENT := Color(0.88, 0.45, 0.12)
const WARN := Color(0.74, 0.2, 0.1)
const OKAY := Color(0.27, 0.58, 0.25)

var _tabs := {}
var _left: VBoxContainer ## (the name and slots and the tools, stacked down the left)
var _title_col: VBoxContainer
var _tiles_box: HBoxContainer
var _group := 0
var _name_edit: LineEdit
var _history: Array = [] ## designs before each change (undo)
var _future: Array = [] ## (redo)


static func _box(fill := PANEL, edge := EDGE, radius := 6, margin := 14.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


## A paper panel with a soft shadow under it.
static func _paper(radius := 10, margin := 14.0, fill := PAPER) -> StyleBoxFlat:
	var sb := _box(fill, PAPER_EDGE, radius, margin)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	sb.anti_aliasing = true
	return sb


static func _label(parent: Node, text: String, size: int, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


## A tool's button: paper, its word, its key small under it; orange while it's on.
static func _button(parent: Node, text: String, size := 13) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", INK_D)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(PAPER_2, PAPER_EDGE, 7, 8.0))
	b.add_theme_stylebox_override("hover", _box(Color(1.0, 0.96, 0.88), ACCENT, 7, 8.0))
	b.add_theme_stylebox_override("pressed", _box(ACCENT, ACCENT.darkened(0.25), 7, 8.0))
	b.add_theme_stylebox_override("hover_pressed", _box(ACCENT.lightened(0.1), ACCENT.darkened(0.25), 7, 8.0))
	parent.add_child(b)
	return b


## The world darkened toward the screen's edges while building (the machine is what you look at).
func _build_vignette() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0.03, 0.025, 0.02, 0.62))
	g.add_point(0.6, Color(0, 0, 0, 0.06))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	tex.width = 256
	tex.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vignette)


## The left column the panels stack in.
func _left_col() -> VBoxContainer:
	if _left == null:
		_left = VBoxContainer.new()
		_left.position = Vector2(24, 22)
		_left.add_theme_constant_override("separation", 12)
		_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_left)
	return _left


## Top left: the machine's name and its three slots.
func _build_title() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _paper())
	panel.custom_minimum_size.x = 320
	_left_col().add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_label(head, "İNŞA", 24, ACCENT)
	_name_edit = LineEdit.new()
	_name_edit.text = "Adsız araç"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", 16)
	_name_edit.add_theme_color_override("font_color", INK_D)
	_name_edit.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), 4, 4.0))
	_name_edit.add_theme_stylebox_override("focus", _box(Color(1, 1, 1, 0.5), ACCENT, 4, 4.0))
	_name_edit.focus_exited.connect(func() -> void: _name_edit.release_focus())
	_name_edit.text_submitted.connect(func(_t: String) -> void: _name_edit.release_focus())
	head.add_child(_name_edit)
	_hint = _label(col, "Sol tık tak  ·  sağ tık sök  ·  sağ sürükle bak", 12, DIM_D)
	_title_col = col


func _build_designs() -> void:
	var col := _title_col
	col.add_child(HSeparator.new())
	_label(col, "KAYITLAR", 13, ACCENT)
	for k in SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		col.add_child(row)
		var l := _label(row, "", 13, DIM_D)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		_slot_rows.append(l)
		_button(row, "Kaydet", 12).pressed.connect(save_slot.bind(k))
		_button(row, "Yükle", 12).pressed.connect(load_slot.bind(k))
	_refresh_slots()
	# the ready designs, four to a row, a picture of each (loading one is undoable)
	_label(col, "HAZIR TASARIMLAR", 13, ACCENT)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	for i in Designs.PRESETS.size():
		var b := _button(grid, str(Designs.PRESETS[i][0]), 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pic := "res://assets/ui/presets/%s.png" % Designs.PRESETS[i][2] # (tools/preset_icons.gd)
		if ResourceLoader.exists(pic):
			b.icon = load(pic)
			b.expand_icon = true
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.custom_minimum_size = Vector2(0, 66)
		b.tooltip_text = str(Designs.PRESETS[i][1])
		b.pressed.connect(load_preset.bind(i))


## Under them: the tools, paper buttons with their keys, three to a row.
func _build_toolbar() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _paper(12, 10.0))
	panel.custom_minimum_size.x = 320
	_left_col().add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	_label(col, "ARAÇLAR", 13, ACCENT)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	var tools := [["undo", "Geri al", "Ctrl Z"], ["redo", "İleri al", "Ctrl Y"], ["turn", "Çevir", "R"], ["tilt", "Devir", "T"],
		["keyb", "Tuş ver", "K · fare üstte"], ["mirror", "Ayna", "M"], ["iso", "İzometrik", "V"], ["clear", "Temizle", "kabin kalır"],
		["starter", "Başlangıç", "aracı"]]
	for t: Array in tools:
		var b := _button(grid, "%s\n%s" % [t[1], t[2]], 13)
		b.custom_minimum_size = Vector2(96, 50)
		_tools[t[0]] = b
	_tools.starter.pressed.connect(reset_starter)
	_tools.mirror.toggle_mode = true
	_tools.iso.toggle_mode = true
	_tools.mirror.toggled.connect(func(on: bool) -> void: set_mirror(on))
	_tools.iso.toggled.connect(func(on: bool) -> void: set_iso(on))
	_tools.turn.pressed.connect(_turn)
	_tools.tilt.pressed.connect(_tilt)
	_tools.keyb.pressed.connect(func() -> void: _hint_say("Bir silahın ya da çeviricinin üstüne gel ve K'ye bas"))
	_tools.undo.pressed.connect(undo)
	_tools.redo.pressed.connect(redo)
	_tools.clear.pressed.connect(_on_clear)
	_tools.clear_btn = _tools.clear
	# bottom right: drive it
	var go := Button.new()
	go.text = "SÜR  ›  B"
	go.focus_mode = Control.FOCUS_NONE
	go.add_theme_font_size_override("font_size", 22)
	go.add_theme_color_override("font_color", Color.WHITE)
	go.add_theme_color_override("font_hover_color", Color.WHITE)
	var gs := _paper(14, 18.0, ACCENT)
	gs.border_color = ACCENT.darkened(0.3)
	go.add_theme_stylebox_override("normal", gs)
	var gh := gs.duplicate() as StyleBoxFlat
	gh.bg_color = ACCENT.lightened(0.12)
	go.add_theme_stylebox_override("hover", gh)
	go.add_theme_stylebox_override("pressed", gh)
	go.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	go.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	go.grow_vertical = Control.GROW_DIRECTION_BEGIN
	go.offset_right = -28
	go.offset_bottom = -26
	go.custom_minimum_size = Vector2(170, 64)
	go.pressed.connect(func() -> void: set_active(false))
	_root.add_child(go)


## Along the top: the groups as tabs, under them the chosen group's parts as tiles.
func _build_cards() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _paper(12, 10.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 18
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 4)
	col.add_child(tabs)
	for gi in GROUPS.size():
		var t := Button.new()
		t.text = str(GROUPS[gi][0])
		t.toggle_mode = true
		t.focus_mode = Control.FOCUS_NONE
		t.custom_minimum_size = Vector2(120, 30)
		t.add_theme_font_size_override("font_size", 13)
		t.add_theme_color_override("font_color", DIM_D)
		t.add_theme_color_override("font_hover_color", INK_D)
		t.add_theme_color_override("font_pressed_color", Color.WHITE)
		t.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		t.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), 15, 6.0))
		t.add_theme_stylebox_override("hover", _box(PAPER_2, PAPER_2, 15, 6.0))
		t.add_theme_stylebox_override("pressed", _box(INK_D, INK_D, 15, 6.0))
		t.add_theme_stylebox_override("hover_pressed", _box(INK_D, INK_D, 15, 6.0))
		t.pressed.connect(_show_group.bind(gi, true))
		tabs.add_child(t)
		_tabs[gi] = t
	_tiles_box = HBoxContainer.new()
	_tiles_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_tiles_box.add_theme_constant_override("separation", 8)
	col.add_child(_tiles_box)
	var ids := Parts.ORDER.filter(func(i: String) -> bool: return i != "cab")
	for g: Array in GROUPS:
		for id: String in g[1]:
			var k := ids.find(id)
			var card := _card(id, KEY_NAMES[k] if k >= 0 and k < KEY_NAMES.size() else "")
			card.visible = false
			_tiles_box.add_child(card)
	_show_group(0, false)


func _group_of(id: String) -> int:
	for gi in GROUPS.size():
		if id in GROUPS[gi][1]:
			return gi
	return 0


func _show_group(gi: int, sound: bool) -> void:
	_group = gi
	for k: int in _tabs:
		(_tabs[k] as Button).set_pressed_no_signal(k == gi)
	var ids: Array = GROUPS[gi][1]
	for id: String in _cards:
		var c := _cards[id] as Control
		var show := id in ids
		if show and not c.visible:
			c.visible = true
			c.modulate.a = 0.0
			c.pivot_offset = c.custom_minimum_size * 0.5
			c.scale = Vector2(0.9, 0.9)
			var tw := c.create_tween().set_parallel(true)
			tw.tween_property(c, "modulate:a", 1.0, 0.14).set_delay(ids.find(id) * 0.03)
			tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_delay(ids.find(id) * 0.03).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif not show:
			c.visible = false
	if sound and active:
		_play("tick.wav", -8.0, 1.25)


## A part's tile: its picture on a paper square, its name, its weight, its key in the corner; it
## lifts under the mouse.
func _card(id: String, key: String) -> Control:
	var d := Parts.def(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(112, 132)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _box(PAPER_2, PAPER_EDGE, 9, 6.0))
	b.add_theme_stylebox_override("hover", _box(Color(1.0, 0.97, 0.9), ACCENT, 9, 6.0))
	b.add_theme_stylebox_override("pressed", _box(Color(1.0, 0.93, 0.8), ACCENT, 9, 6.0))
	b.pressed.connect(select.bind(id))
	b.mouse_entered.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2(1.06, 1.06), 0.1))
	b.mouse_exited.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6
	col.offset_right = -6
	col.offset_top = 4
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var pic := TextureRect.new()
	var icon := "res://assets/parts/icons/%s.png" % id
	if ResourceLoader.exists(icon):
		pic.texture = load(icon)
	pic.custom_minimum_size = Vector2(86, 86)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var n := _label(col, d.name, 13, INK_D)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	var m := _label(col, "%d kg" % int(d.mass), 11, DIM_D)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _box(INK_D, INK_D, 5, 3.0))
	badge.position = Vector2(6, 6)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(badge)
	var kl := _label(badge, key, 11, Color.WHITE)
	kl.custom_minimum_size.x = 12
	kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cards[id] = b
	return b


func _build_part_info() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _paper())
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 24
	panel.offset_bottom = -26
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.custom_minimum_size.x = 380
	_root.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	_part_name = _label(col, "", 22, INK_D)
	_part_stats = _label(col, "", 13, ACCENT)
	_part_about = _label(col, "", 13, DIM_D)
	_part_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_part_about.custom_minimum_size.x = 350


func _build_machine_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _paper())
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -360
	panel.offset_right = -24
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 20
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	_label(col, "ARAÇ", 13, ACCENT)
	_numbers = _label(col, "", 15, INK_D)
	for k: String in ["kw", "load", "power"]:
		var l := _label(col, "", 12, DIM_D)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(300, 9)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.82, 0.78, 0.7)
		bg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", bg)
		var fill := StyleBoxFlat.new()
		fill.bg_color = OKAY
		fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)
		col.add_child(bar)
		_bars[k] = [l, bar, fill]
	_warn = VBoxContainer.new()
	col.add_child(_warn)


func _set_bar(k: String, text: String, frac: float, good: bool) -> void:
	var e: Array = _bars[k]
	(e[0] as Label).text = text
	var bar := e[1] as ProgressBar
	bar.create_tween().tween_property(bar, "value", clampf(frac, 0.0, 1.0) * 100.0, 0.25).set_trans(Tween.TRANS_CUBIC)
	(e[2] as StyleBoxFlat).bg_color = OKAY if good else WARN


func _refresh() -> void:
	if _numbers == null or not is_instance_valid(machine):
		return
	var r := machine.report()
	var running := "%d tekerlek" % r.wheels
	if int(r.tracks) > 0:
		running = "%d palet" % r.tracks + ("  %d tekerlek" % r.wheels if int(r.wheels) > 0 else "")
	_numbers.text = "%d parça   ·   %d kg\n%d kW   ·   %s   ·   %d silah" % [r.parts, int(r.mass), int(r.power), running, r.guns]
	_set_bar("kw", "Güç / ağırlık  %d kW/ton" % int(r.kw_t), float(r.kw_t) / 150.0, float(r.kw_t) >= 40.0)
	var load_frac := float(r.mass) / maxf(float(r.rated), 1.0)
	_set_bar("load", "Tekerlek yükü  %d / %d kg" % [int(r.mass), int(r.rated)], load_frac, load_frac <= 1.0)
	var peak := float(r.peak)
	var alt := float(r.alternator)
	_set_bar("power", "Akü %.1f kWh  ·  şarj %.1f kW  /  en çok %.1f kW" % [float(r.kwh), alt, peak],
		alt / maxf(peak, 0.1), alt >= peak or int(r.guns) == 0)
	for c in _warn.get_children():
		c.queue_free()
	for w: String in r.warn:
		var l := _label(_warn, "▲ " + w, 12, WARN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 300


func select(id: String, sound := true) -> void:
	selected = id
	if _tiles_box and _group_of(id) != _group:
		_show_group(_group_of(id), false)
	for k: String in _cards:
		var on := k == id
		var b := _cards[k] as Button
		var sb := _box(Color(1.0, 0.93, 0.8) if on else PAPER_2, ACCENT if on else PAPER_EDGE, 9, 6.0)
		if on:
			sb.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", sb)
	var d := Parts.def(id)
	if _part_name:
		_part_name.text = d.name
		var extra := ""
		match str(d.kind):
			"wheel":
				extra = "  ·  r %.2f m  ·  %d kg taşır" % [float(d.radius), int(d.rated)]
			"track":
				extra = "  ·  %d kg taşır" % int(float(d.rated) * int(d.bogies))
			"engine":
				extra = "  ·  %d kW" % int(d.power)
			"battery":
				extra = "  ·  %.1f kWh" % float(d.kwh)
			"weapon":
				var dk: Array = MachineGun.DRAW[str(d.weapon)]
				extra = "  ·  en çok %.1f kW çeker" % (float(dk[0]) + float(dk[1]) + float(dk[2]))
		var s: Vector3i = d.size
		_part_stats.text = "%d kg  ·  %d can  ·  %d×%d×%d hücre%s" % [int(d.mass), int(Parts.hp_of(id)), s.x, s.y, s.z, extra]
		_part_about.text = d.about
		if price_note.is_valid():
			var note := str(price_note.call(id))
			if note != "":
				_part_stats.text += "  ·  " + note
	if sound and active:
		_play("tick.wav", -6.0, randf_range(0.95, 1.1))
	_make_ghost()


# --- Undo ---------------------------------------------------------------------------------------

## Remembers the design as it is, before a change.
func _remember() -> void:
	_history.append(machine.to_data(keep_wear))
	if _history.size() > 60:
		_history.pop_front()
	_future.clear()


func undo() -> void:
	if _history.is_empty():
		return
	var now := machine.to_data(keep_wear)
	var back: Array = _history.pop_back()
	if _swap_design(back, false):
		_future.append(now)
	else:
		_history.append(back) # (refused: as it was)


func redo() -> void:
	if _future.is_empty():
		return
	var now := machine.to_data(keep_wear)
	var on: Array = _future.pop_back()
	if _swap_design(on, false):
		_history.append(now)
	else:
		_future.append(on)


## A new machine to build on (the old one came apart): its signals, the ghost under it.
func rebind() -> void:
	if not machine.changed.is_connected(_refresh):
		machine.changed.connect(_refresh)
	_make_ghost()
	_refresh()


func set_active(on: bool) -> void:
	if not is_instance_valid(machine):
		return
	active = on
	visible = on
	machine.set_building(on)
	cam.free_mouse = on
	if not on:
		cam.set_iso(false)
		_tools.iso.set_pressed_no_signal(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	if _ghost:
		_ghost.visible = false
	if _ghost2:
		_ghost2.visible = false
	_unglow()
	_floor(on)
	if not on:
		closed.emit()
	if on:
		_root.modulate.a = 0.0
		_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.2)
		_refresh_slots()
	else:
		save()
	_refresh()


func set_iso(on: bool) -> void:
	cam.set_iso(on)
	_tools.iso.set_pressed_no_signal(on)
	_play("turn.wav", -8.0, 1.2)


func set_mirror(on: bool) -> void:
	mirror = on
	_tools.mirror.set_pressed_no_signal(on)
	_play("turn.wav", -8.0, 0.9)


func _turn() -> void:
	rot = (rot / 4) * 4 + (rot % 4 + 1) % 4
	_play("turn.wav", -6.0, randf_range(0.95, 1.05))


## Tips the part over (upright, forward, upside down, back, on its right side, its left).
func _tilt() -> void:
	if not Parts.can_tilt(selected):
		_hint_say("%s yalnız dik takılır" % Parts.def(selected).name)
		return
	rot = ((rot / 4 + 1) % 6) * 4 + rot % 4
	_play("turn.wav", -6.0, randf_range(0.8, 0.9))
	_hint_say("Duruş: %s" % Parts.TILT_NAMES[rot / 4])


func _hint_say(t: String) -> void:
	var g := get_parent()
	if g and g.has_method("say"):
		g.call("say", t)


func _make_ghost() -> void:
	for g: Node3D in [_ghost, _ghost2]:
		if g:
			g.queue_free()
	_ghost = _ghost_of(selected)
	_ghost2 = _ghost_of(selected)


func _ghost_of(id: String) -> Node3D:
	var g := ((load(Parts.model(id)) if ResourceLoader.exists(Parts.model(id)) else Machine._stand_in(id)) as PackedScene).instantiate() as Node3D
	for mi: MeshInstance3D in g.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _ghost_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visible = false
	if is_instance_valid(machine):
		machine.get_parent().add_child(g)
	return g


# --- The floor: the grid of its cells, its centre of mass ----------------------------------------

func _floor(on: bool) -> void:
	if _grid == null:
		_grid = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(20.0, 20.0)
		_grid.mesh = pm
		_grid_mat = ShaderMaterial.new()
		_grid_mat.shader = preload("res://shaders/build_grid.gdshader")
		_grid.material_override = _grid_mat
		_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_com = _com_marker()
	for n: Node3D in [_grid, _com]:
		if n.get_parent() != machine.get_parent() and is_instance_valid(machine):
			if n.get_parent():
				n.get_parent().remove_child(n)
			machine.get_parent().add_child(n)
		n.visible = on


## A ball at the centre of mass with a ring round it and a line down to the floor, seen through the
## machine.
func _com_marker() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.albedo_color = Color(1.0, 0.55, 0.15)
	mat.render_priority = 10
	var ball := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	s.material = mat
	ball.mesh = s
	root.add_child(ball)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.17
	t.outer_radius = 0.2
	t.material = mat
	ring.mesh = t
	root.add_child(ring)
	var line := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.008
	c.bottom_radius = 0.008
	c.height = 1.0
	var lm := mat.duplicate() as StandardMaterial3D
	lm.albedo_color = Color(1.0, 0.55, 0.15, 0.5)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	c.material = lm
	line.mesh = c
	line.name = "Line"
	root.add_child(line)
	for n in root.get_children():
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


func _update_floor() -> void:
	if _grid == null or not _grid.visible or not is_instance_valid(machine):
		return
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for p: Dictionary in machine.design:
		for c in Parts.cells_of(p.id, p.at, p.rot):
			lo = lo.min(c)
			hi = hi.max(c)
	if machine.design.is_empty():
		lo = Vector3i.ZERO
		hi = Vector3i.ZERO
	var floor_y := lo.y * Parts.CELL - 0.02
	_grid.global_transform = machine.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, floor_y, 0.0))
	_grid_mat.set_shader_parameter("foot_lo", Vector2(lo.x, lo.z) * Parts.CELL)
	_grid_mat.set_shader_parameter("foot_hi", Vector2(hi.x + 1, hi.z + 1) * Parts.CELL)
	var c := machine.com_global()
	_com.global_position = c
	var ground := (machine.global_transform * Vector3(0.0, floor_y, 0.0)).y
	var line := _com.get_node("Line") as Node3D
	var h := maxf(c.y - ground, 0.05)
	line.scale = Vector3(1.0, h, 1.0)
	line.position = Vector3(0.0, -h * 0.5, 0.0)
	var ring := _com.get_child(1) as Node3D
	ring.rotation = Vector3(0.0, _t * 1.5, 0.0)


# --- Designs ------------------------------------------------------------------------------------

static func slot_path(k: int) -> String:
	return save_path.get_basename() + "_slot%d.json" % (k + 1)


func save_slot(k: int) -> void:
	var f := FileAccess.open(slot_path(k), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"name": _name_edit.text if _name_edit else "", "parts": machine.to_data(keep_wear)}))
		f.close()
	_play("ratchet_0%d.wav" % randi_range(1, 3), -4.0)
	_refresh_slots()


func load_slot(k: int) -> void:
	var s := _read_slot(k)
	var parts: Array = s.get("parts", [])
	if parts.is_empty():
		return
	if _name_edit and str(s.get("name", "")) != "":
		_name_edit.text = str(s.name)
	_swap_design(parts)


## A slot's {name, parts} ({} if it's empty); an old slot is only its parts.
static func _read_slot(k: int) -> Dictionary:
	if not FileAccess.file_exists(slot_path(k)):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_path(k)))
	if d is Array:
		return {"name": "", "parts": d}
	return d if d is Dictionary else {}


## Only the cab left: press twice (the first press asks).
func _on_clear() -> void:
	if _clear_armed <= 0.0:
		_clear_armed = 2.5
		(_tools.clear_btn as Button).text = "Emin misin?\ntekrar bas"
		_play("tick.wav", -4.0, 0.8)
		return
	_clear_armed = 0.0
	(_tools.clear_btn as Button).text = "Temizle\nkabin kalır"
	var cab := machine.cab_index()
	var keep: Array = [["cab", 0, 1, 0, 0]]
	if cab >= 0:
		var p: Dictionary = machine.design[cab]
		keep = [["cab", p.at.x, p.at.y, p.at.z, p.rot]]
	_swap_design(keep)


func reset_starter() -> void:
	_swap_design(Designs.starter())


func load_preset(i: int) -> void:
	_swap_design(Designs.preset(i))


## A whole new design: the old parts lift away, the new ones drop in (undoable unless it's the undo).
func _swap_design(data: Array, remember := true) -> bool:
	swap_rows = []
	if swap_guard.is_valid() and not bool(swap_guard.call(machine.to_data(keep_wear), data)):
		_play("tick.wav", -4.0, 0.6)
		return false
	if not swap_rows.is_empty(): # (the parts it'll be built of, as worn as they are)
		data = swap_rows
	if remember:
		_remember()
	for n in machine.part_nodes:
		_fly_off(n, randf_range(0.0, 0.15))
	machine.from_data(data)
	machine.set_building(true)
	for i in machine.part_nodes.size():
		_drop_in(machine.part_nodes[i], 0.1 + i * 0.012)
	_play("heavy_01.wav", -6.0)
	_play("bolt_on_0%d.wav" % randi_range(1, 3), -4.0)
	save()
	return true
	_refresh()


func _refresh_slots() -> void:
	for k in _slot_rows.size():
		var l := _slot_rows[k]
		var s := _read_slot(k)
		if not s.is_empty():
			var parts: Array = s.get("parts", [])
			var kg := 0.0
			for e: Variant in parts:
				if e is Array and Parts.DEFS.has(str(e[0])):
					kg += float(Parts.def(str(e[0])).mass)
			var nm := str(s.get("name", ""))
			l.text = "%d.  %s · %d kg" % [k + 1, nm if nm != "" else "%d parça" % parts.size(), int(kg)]
			l.add_theme_color_override("font_color", INK_D)
		else:
			l.text = "%d.  boş" % (k + 1)
			l.add_theme_color_override("font_color", DIM_D)


# --- Placing ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active or not is_instance_valid(machine):
		return
	var key := event as InputEventKey
	if _name_edit and _name_edit.has_focus():
		return
	if key and key.pressed and key.ctrl_pressed and key.keycode in [KEY_Z, KEY_Y]:
		if key.keycode == KEY_Z and not key.shift_pressed:
			undo()
		else:
			redo()
		get_viewport().set_input_as_handled()
		return
	if key and key.pressed and not key.echo and _listen >= 0:
		_bind_key(key) # (waiting for a part's key: this is it, whatever it is)
		get_viewport().set_input_as_handled()
		return
	if key and key.pressed and not key.echo:
		var ids := Parts.ORDER.filter(func(i: String) -> bool: return i != "cab")
		var n := KEYS.find(key.keycode)
		if n >= 0 and n < ids.size():
			select(ids[n])
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_R:
			_turn()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_T:
			_tilt()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_K:
			_listen_for_key()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_V:
			set_iso(not cam.iso)
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_M:
			set_mirror(not mirror)
			get_viewport().set_input_as_handled()
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		if not _target.is_empty() and _target.ok:
			place_target()
		elif not _target.is_empty():
			_play("tick.wav", -10.0, 0.6)
		get_viewport().set_input_as_handled()
	elif mb and mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed and cam.drag_moved < 6.0:
		remove_at(_remove_i)


## Bolts the chosen part on where the ghost is (and its mirror image, if mirroring and it fits).
func place_target() -> void:
	var t := _target
	var before := machine.to_data(keep_wear)
	if guard.is_valid() and not bool(guard.call(selected, t.at, t.rot)):
		_play("tick.wav", -8.0, 0.6)
		return
	if not machine.place(selected, t.at, t.rot):
		return
	placed.emit(machine.design.size() - 1)
	_history.append(before)
	_future.clear()
	var dropped: Array[Node3D] = [machine.part_nodes.back()]
	var m: Dictionary = t.get("mirror", {})
	if not m.is_empty() and machine.can_place(selected, m.at, m.rot) and (not guard.is_valid() or bool(guard.call(selected, m.at, m.rot))) \
			and machine.place(selected, m.at, m.rot):
		placed.emit(machine.design.size() - 1)
		dropped.append(machine.part_nodes.back())
	# (a rebuild made every part's node anew: the new ones are the last)
	var n := machine.part_nodes.size()
	for k in dropped.size():
		_drop_in(machine.part_nodes[n - dropped.size() + k], k * 0.08)
	_bolt_sound(selected)
	save()


func remove_at(i: int) -> void:
	if i < 0 or i >= machine.design.size() or not machine.can_remove(i):
		return
	var id: String = machine.design[i].id
	var at: Vector3i = machine.design[i].at
	var r: int = machine.design[i].rot
	removed_cond = clampf(float(machine.design[i].hp) / Parts.hp_of(id), 0.0, 1.0)
	var before := machine.to_data(keep_wear)
	_fly_off(machine.part_nodes[i], 0.0)
	if machine.remove(i):
		removed.emit(id, at, r)
		_history.append(before)
		_future.clear()
		_unglow()
		_play("bolt_off_0%d.wav" % randi_range(1, 2), -3.0, randf_range(0.95, 1.05))
		_play("clank_0%d.wav" % randi_range(1, 3), -8.0 if Parts.def(id).mass < 100.0 else -3.0, randf_range(0.9, 1.1))
		save()


func _bolt_sound(id: String) -> void:
	var d := Parts.def(id)
	var heavy := float(d.mass) >= 150.0
	if str(d.kind) in ["wheel", "track"] or heavy:
		_play("bolt_on_0%d.wav" % randi_range(1, 3), -2.0, randf_range(0.95, 1.05))
	else:
		_play("ratchet_0%d.wav" % randi_range(1, 3), -3.0, randf_range(0.95, 1.08))
	if heavy:
		_play("heavy_01.wav", -6.0, randf_range(0.9, 1.05))
	else:
		_play("clank_0%d.wav" % randi_range(1, 3), -10.0, randf_range(1.0, 1.2))


## A part comes down into its place: from a little above, a touch big, settling with a bounce.
func _drop_in(node: Node3D, delay: float) -> void:
	if not is_instance_valid(node):
		return
	var rest := node.transform
	node.position = rest.origin + Vector3.UP * 0.45
	node.scale = Vector3.ONE * 0.8
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "position", rest.origin, 0.22).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ONE, 0.26).set_delay(delay).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## A copy of a part that's coming off lifts away turning, shrinks and goes.
func _fly_off(node: Node3D, delay: float) -> void:
	if not is_instance_valid(node) or not is_instance_valid(machine):
		return
	var c := node.duplicate() as Node3D
	machine.get_parent().add_child(c)
	c.global_transform = node.global_transform
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 1.2
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "global_position", c.global_position + Vector3.UP * 1.4 + spin * 0.3, 0.45).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", c.rotation + spin, 0.45).set_delay(delay)
	tw.tween_property(c, "scale", Vector3.ONE * 0.05, 0.45).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(c.queue_free)


func _play(file: String, db := 0.0, pitch := 1.0) -> void:
	var path := SND + file
	if not ResourceLoader.exists(path):
		return
	var p := _players[_player_i]
	_player_i = (_player_i + 1) % _players.size()
	p.stream = load(path)
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _process(dt: float) -> void:
	_show_key_tags()
	_t += dt
	if _clear_armed > 0.0:
		_clear_armed -= dt
		if _clear_armed <= 0.0:
			(_tools.clear_btn as Button).text = "Temizle\nkabin kalır"
	if not active or not is_instance_valid(machine):
		return
	_aim(get_viewport().get_mouse_position())
	_update_floor()
	# the ghost breathes
	var a := 0.32 + 0.12 * sin(_t * 5.0)
	var ok: bool = not _target.is_empty() and _target.ok
	_ghost_mat.albedo_color = Color(0.3, 1.0, 0.45, a) if ok else Color(1.0, 0.25, 0.2, a)
	_outline_mat.albedo_color = Color(0.6, 1.0, 0.7) if ok else Color(1.0, 0.45, 0.35)


## What's under the mouse: the ghost where the part would go (and its mirror image), and the part a
## right click takes off, glowing.
func _aim(mouse: Vector2) -> void:
	_target = {}
	_remove_i = -1
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var t := aim_ray(from, dir)
	if t.is_empty():
		_ghost.visible = false
		_ghost2.visible = false
		_unglow()
		return
	_target = t
	_remove_i = int(t.index)
	_ghost.visible = true
	_ghost.global_transform = machine.global_transform * Parts.xform_of(selected, t.at, t.rot)
	var m: Dictionary = t.get("mirror", {})
	_ghost2.visible = not m.is_empty()
	if not m.is_empty():
		_ghost2.global_transform = machine.global_transform * Parts.xform_of(selected, m.at, m.rot)
	_glow(_remove_i)


func _glow(i: int) -> void:
	var n: Node3D = machine.part_nodes[i] if i >= 0 and i < machine.part_nodes.size() else null
	if n == _glowing:
		return
	_unglow()
	if n == null or not machine.can_remove(i):
		return
	_glowing = n
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = _glow_mat


func _unglow() -> void:
	if is_instance_valid(_glowing):
		for mi: MeshInstance3D in _glowing.find_children("*", "MeshInstance3D", true, false):
			mi.material_overlay = null
	_glowing = null


## Where the chosen part would go along a ray (world): {at, rot, ok, index, mirror} or {}.
func aim_ray(from: Vector3, dir: Vector3) -> Dictionary:
	var hit := machine.pick(from, dir)
	if hit.is_empty():
		return {}
	var r := rot if Parts.can_tilt(selected) else rot % 4
	var kind := str(Parts.def(selected).kind)
	if kind == "wheel":
		r = Machine.wheel_rot_for(hit.normal, rot)
	elif kind == "track":
		r = 2 if hit.normal.x < 0 else (0 if hit.normal.x > 0 else (rot / 2) * 2)
	var at := Machine.anchor_for(selected, r, hit.cell, hit.normal)
	var out := {"at": at, "rot": r, "ok": machine.can_place(selected, at, r), "index": hit.index}
	if mirror:
		var m := mirrored(selected, at, r)
		if not m.is_empty():
			out.mirror = m
	return out


## The part's mirror image across the cab's middle (left and right swapped), or {} if it's on the
## middle itself.
func mirrored(id: String, at: Vector3i, r: int) -> Dictionary:
	var cab := machine.cab_index()
	if cab < 0:
		return {}
	var cp: Dictionary = machine.design[cab]
	var mid2: int = cp.at.x * 2 + Parts.size_of("cab", cp.rot).x # (twice the middle, in cells)
	var r2 := r
	if str(Parts.def(id).kind) in ["wheel", "track"]:
		r2 = (r + 2) % 4 if r % 2 == 0 else r
	else:
		# (the mirror turns it the other way about up, and swaps its right side for its left)
		var tilt: int = [0, 1, 2, 3, 5, 4][(r / 4) % 6]
		r2 = tilt * 4 + (4 - r % 4) % 4
	var s := Parts.size_of(id, r2)
	var at2 := Vector3i(mid2 - at.x - s.x, at.y, at.z)
	if at2 == at and r2 == r:
		return {}
	return {"at": at2, "rot": r2}


func save() -> void:
	if not is_instance_valid(machine):
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(machine.to_data(keep_wear)))


static func load_saved() -> Array:
	if not FileAccess.file_exists(save_path):
		return []
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	return d if d is Array else []



# --- Keys -------------------------------------------------------------------------------------------

## K over a gun or a flipper: the next key pressed is the one it answers to (Esc: none, back to the
## mouse or F).
func _listen_for_key() -> void:
	var i := _remove_i
	if i < 0 or i >= machine.design.size() or not str(Parts.def(machine.design[i].id).kind) in ["weapon", "flipper", "joint", "crane", "winch", "saw"]:
		_hint_say("Tuş vermek için farenin altında bir silah, çevirici ya da hareketli parça olsun, sonra K")
		return
	_listen = i
	_hint_say("%s için bir tuşa bas  ·  Esc: tuşu kaldır" % Parts.def(machine.design[i].id).name)
	_play("tick.wav", -4.0, 1.3)


func _bind_key(key: InputEventKey) -> void:
	var i := _listen
	_listen = -1
	if i < 0 or i >= machine.design.size():
		return
	var p: Dictionary = machine.design[i]
	var code := key.physical_keycode
	if code == KEY_ESCAPE:
		p.erase("key")
		_hint_say("%s: tuşu kaldırıldı (%s)" % [Parts.def(p.id).name, "F" if p.id == "flipper" else ("nişanı kendi izler" if p.id == "turret" else ("E" if str(Parts.def(p.id).kind) == "joint" else "farenin sol tuşu"))])
	else:
		p.key = code
		var name := OS.get_keycode_string(code)
		_hint_say("%s artık %s ile%s" % [Parts.def(p.id).name, name, "  ·  bu tuş sürüşte de kullanılıyor" if code in DRIVE_KEYS else ""])
	machine.rebuild()
	machine.set_building(true)
	save()
	_play("bolt_on_0%d.wav" % randi_range(1, 3), -6.0, 1.3)


## While building: the key each part answers to, over it.
func _show_key_tags() -> void:
	var want: Array[int] = []
	if active:
		for i in machine.design.size():
			if int(machine.design[i].get("key", 0)) != 0:
				want.append(i)
	while _key_tags.size() < want.size():
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font = Ui.font("display")
		l.font_size = 64
		l.pixel_size = 0.004
		l.outline_size = 12
		l.modulate = Ui.ACCENT
		add_child(l)
		_key_tags.append(l)
	for k in _key_tags.size():
		var l := _key_tags[k]
		l.visible = k < want.size()
		if l.visible:
			var p: Dictionary = machine.design[want[k]]
			l.text = OS.get_keycode_string(int(p.key))
			l.global_position = machine.global_transform * (Parts.xform_of(p.id, p.at, p.rot).origin + Vector3.UP * 0.6)
