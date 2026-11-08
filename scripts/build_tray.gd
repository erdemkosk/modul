class_name BuildTray
extends Control
## The build tray at the foot of the view, as a station counter's furniture: a walnut plinth with a
## brass edge flush on the screen's bottom, the five groups on it as brass medallions (KASABA,
## ÜRETİM, TAŞIMA, SAVUNMA, EMİRLER), each its glyph engraved in its face. A group picked, a lighter
## walnut tray rises over the plinth holding the group's buildings as cards (the sepia engraving
## on cream card in a thin brass frame, its key printed in the corner); the mouse on one, a
## parchment card over it says what it is, what it brings, what it takes against what's in the
## stores, how long it takes to put up and how many stand. The chosen medallion again, a right-click
## or Esc and the tray sinks; Tab opens it and steps through the groups. It stays up while placing.
##
## Its pieces are drawn by tools/build_tray.py (assets/ui/tray, twice the size they're seen at:
## drawn halved here) and the engravings by tools/ink_plates.py (assets/ui/plates).

signal reach_changed ## the tray's top moved (it rose, sank, or changed width): what stands over it follows

const TEX := "res://assets/ui/tray/%s.png"
const SLOT := Vector2(84, 88) ## a medallion and its name under it
const MEDAL := 76.0 ## the medallion's drawn box (its shadow round it)
const PLINTH_H := 96.0
const PLINTH_PAD := 20.0 ## (the plinth's ends, past the outer medallions)
const SHADOW := 12.0 ## the shadow baked round the boards
const TILE := 80.0 ## a building's card, at most
const TILE_MIN := 60.0
const GAP := 8.0
const PAD_X := 16.0 ## the tray's ends
const PAD_T := 16.0 ## (room over the cards for one lifted under the mouse)
const PAD_B := 12.0
const TUCK := 4.0 ## the tray's foot, under the plinth's brass top
const SIDES := 260.0 ## kept clear at either side (the townsfolk at the left, the map at the right)

# the palette: walnut, brass, the cream of the cards, iron-gall ink, the red of the wax
const C_CARD := Color("f0e5cb")
const C_CARD_GREY := Color("c9c2b2")
const C_FRAME := Color("5a4020")
const C_FRAME_HI := Color("d9a95c")
const C_BRASS := Color("b8925a")
const C_BRASS_HI := Color("f0d9a6")
const C_GLYPH := Color("e8d3a4")
const C_GLYPH_ON := Color("3b2918")
const C_PARCH := Color("efe4c9")
const CARD_W := 304.0 ## the hover card's writing, across (its wrapped lines this wide, so it's as tall as they are)
const C_PARCH_EDGE := Color("7a5a3a")

var game: Node
var hud: Node
var category := 0
var is_open := false
var reach := PLINTH_H ## how far up from the screen's foot it reaches now (UI px)

var _plinth: PanelContainer
var _medals: Array[Medal] = []
var _well: Control ## (clips the tray as it rises from behind the plinth)
var _shelf: PanelContainer
var _row: HBoxContainer
var _slide := 0.0 ## 0 sunk .. 1 up
var _slide_tw: Tween
var _tile := TILE
var _hovered: Tile

var _card: PanelContainer
var _card_name: Label
var _card_gives: Label
var _card_costs: GridContainer
var _card_desc: Label
var _card_foot: Label
var _card_rule: ColorRect
var _card_count: Label
var _card_lock: HBoxContainer
var _card_lock_text: Label
var _card_at := 0.0 ## where along the card its notch points

var _state := {} ## kind -> {locked, short, count}
var _was_locked := {} ## kind -> locked at the last look
var _seen_new := {} ## kinds whose "new" tag has been seen (moused over) since they were unlocked
var _new := {} ## kind -> true: unlocked, not yet looked at

## What an order on the ground takes, each piece of it (Main's dig and lay orders): [goods, the piece].
const ORDER_COST := {"tuzak": [{"odun": 2}, "çukur başı"], "mayin": [{"demir": 1, "komur": 1}, "mayın başı"]}

static var _tex := {}
static var _grey_shader: Shader


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(TEX % name) if ResourceLoader.exists(TEX % name) else null
	return _tex[name]


## A board of the tray's (plinth, shelf) drawn over `rect`, its texture halved.
static func draw_board(ci: CanvasItem, sb: StyleBox, rect: Rect2) -> void:
	ci.draw_set_transform(rect.position, 0.0, Vector2(0.5, 0.5))
	ci.draw_style_box(sb, Rect2(Vector2.ZERO, rect.size * 2.0))
	ci.draw_set_transform(Vector2.ZERO)


## A brass screw head let into the wood, its slot turned `ang`.
static func draw_screw(ci: CanvasItem, c: Vector2, ang: float) -> void:
	ci.draw_circle(c + Vector2(0, 1), 3.6, Color(0, 0, 0, 0.45), true, -1.0, true)
	ci.draw_circle(c, 3.2, Color("4a3216"), true, -1.0, true)
	ci.draw_circle(c, 2.6, C_BRASS, true, -1.0, true)
	ci.draw_circle(c + Vector2(-0.8, -0.8), 1.3, Color(C_BRASS_HI, 0.8), true, -1.0, true)
	var d := Vector2(cos(ang), sin(ang)) * 2.3
	ci.draw_line(c - d, c + d, Color("2e1f0e"), 1.0, true)


static func _board_style(name: String, margins: Array) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(name)
	sb.texture_margin_left = margins[0]
	sb.texture_margin_top = margins[1]
	sb.texture_margin_right = margins[2]
	sb.texture_margin_bottom = margins[3]
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the tray, in its well over the plinth (first: the plinth is drawn over its foot)
	_well = Control.new()
	_well.clip_contents = true
	_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_well.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_well.visible = false
	add_child(_well)
	_shelf = PanelContainer.new()
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = PAD_X
	pad.content_margin_right = PAD_X
	pad.content_margin_top = PAD_T
	pad.content_margin_bottom = PAD_B + TUCK
	_shelf.add_theme_stylebox_override("panel", pad)
	_shelf.mouse_filter = Control.MOUSE_FILTER_STOP
	var shelf_sb := _board_style("shelf", [56, 56, 56, 56])
	_shelf.draw.connect(func() -> void:
		draw_board(_shelf, shelf_sb, Rect2(-SHADOW, -SHADOW, _shelf.size.x + SHADOW * 2.0, _shelf.size.y + SHADOW * 2.0))
		var mid := roundf(PAD_T + _tile * 0.5)
		draw_screw(_shelf, Vector2(8, mid), 1.1)
		draw_screw(_shelf, Vector2(_shelf.size.x - 8, mid), 0.2))
	_shelf.gui_input.connect(_on_right_click)
	_shelf.resized.connect(_layout)
	_well.add_child(_shelf)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(GAP))
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shelf.add_child(_row)
	# the plinth and its medallions
	_plinth = PanelContainer.new()
	var ppad := StyleBoxEmpty.new()
	ppad.content_margin_left = PLINTH_PAD
	ppad.content_margin_right = PLINTH_PAD
	ppad.content_margin_top = 4
	ppad.content_margin_bottom = PLINTH_H - SLOT.y - 4.0
	_plinth.add_theme_stylebox_override("panel", ppad)
	_plinth.mouse_filter = Control.MOUSE_FILTER_STOP
	_plinth.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_plinth.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_plinth.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var plinth_sb := _board_style("plinth", [56, 56, 56, 16])
	_plinth.draw.connect(func() -> void:
		draw_board(_plinth, plinth_sb, Rect2(-SHADOW, -SHADOW, _plinth.size.x + SHADOW * 2.0, _plinth.size.y + SHADOW + 8.0))
		draw_screw(_plinth, Vector2(11, 40), 0.6)
		draw_screw(_plinth, Vector2(_plinth.size.x - 11, 40), -0.3))
	_plinth.gui_input.connect(_on_right_click)
	add_child(_plinth)
	var medals := HBoxContainer.new()
	medals.add_theme_constant_override("separation", 4)
	medals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plinth.add_child(medals)
	var glyphs := ["kasaba", "uretim", "tasima", "savunma", "emirler"]
	for i in Hud.CATS.size():
		var m := Medal.new()
		m.index = i
		m.word = Ui.upper(str(Hud.CATS[i][0]))
		m.glyph = tex("glyph_" + glyphs[i])
		m.tooltip_text = "%s · Tab: sıradaki grup" % m.word
		m.pressed.connect(func() -> void: _medal_pressed(i))
		m.gui_input.connect(_on_right_click)
		medals.add_child(m)
		_medals.append(m)
	_make_card()
	get_viewport().size_changed.connect(_on_resize)
	_layout.call_deferred()


func _on_resize() -> void:
	if is_open:
		_fill(false)
	_layout()


## A right-click anywhere on the tray or the plinth: it sinks.
func _on_right_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		close()
		accept_event()


func _medal_pressed(i: int) -> void:
	if is_open and i == category:
		close()
	else:
		open_category(i)


# --- open, step, sink ----------------------------------------------------------------------------

## The tray up with group `i` in it (the numbers then pick its buildings).
func open_category(i: int) -> void:
	var was := category
	category = posmod(i, Hud.CATS.size())
	hud.build_keys = true
	if not is_open or was != category or _row.get_child_count() == 0:
		_fill(true)
	if not is_open:
		is_open = true
		_slide_to(1.0)
	_refresh_medals()


## Tab: up with the group it was left on, or on to the next.
func cycle() -> void:
	open_category(category + 1 if is_open else category)


func close() -> void:
	hud.build_keys = false
	if not is_open:
		return
	is_open = false
	_hide_card()
	_slide_to(0.0)
	_refresh_medals()


func _slide_to(to: float) -> void:
	if _slide_tw:
		_slide_tw.kill()
	_well.visible = true
	_slide_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if to > 0.5 else Tween.EASE_IN)
	_slide_tw.tween_method(func(v: float) -> void:
		_slide = v
		_place_shelf(), _slide, to, 0.2 if to > 0.5 else 0.14)
	if to < 0.5:
		_slide_tw.tween_callback(func() -> void: _well.visible = is_open)


func _refresh_medals() -> void:
	for m in _medals:
		m.on = is_open and m.index == category
		m.queue_redraw()


## The group's cards into the tray, each coming up in turn (`fresh`: a new group; else only resized).
func _fill(fresh: bool) -> void:
	var kinds: Array = Hud.CATS[category][1]
	var n := kinds.size()
	var room := get_viewport_rect().size.x - SIDES * 2.0 - PAD_X * 2.0 - GAP * (n - 1)
	_tile = clampf(floorf(room / maxf(n, 1)), TILE_MIN, TILE)
	if not fresh:
		for t: Node in _row.get_children():
			(t as Control).custom_minimum_size = Vector2(_tile, _tile)
		_row.reset_size()
		_shelf.reset_size()
		return
	_hide_card()
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	for k in n:
		var t := Tile.new()
		t.tray = self
		t.kind = kinds[k]
		t.key = k
		t.custom_minimum_size = Vector2(_tile, _tile)
		t.enter = 0.0
		t.modulate.a = 0.0
		t.plate = load("res://assets/ui/plates/%s.png" % t.kind) if ResourceLoader.exists("res://assets/ui/plates/%s.png" % t.kind) else null
		_row.add_child(t)
		var tw := t.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.025 * k + (0.06 if not is_open else 0.0))
		tw.tween_method(func(v: float) -> void:
			t.enter = v
			t.modulate.a = v
			t.redraw(), 0.0, 1.0, 0.2)
	_apply_state()
	_shelf.custom_minimum_size.x = _plinth.size.x if _plinth.size.x > 0.0 else 0.0
	_shelf.reset_size()
	_layout()


## The well and the plinth sized and set; the shelf in the well as far up as it's slid.
func _layout() -> void:
	if _shelf == null or _plinth == null or _card == null:
		return
	_shelf.custom_minimum_size.x = maxf(_plinth.size.x, 0.0)
	var sz := _shelf.get_combined_minimum_size()
	var w := sz.x + SHADOW * 2.0
	var h := sz.y + SHADOW
	_well.offset_left = -roundf(w * 0.5)
	_well.offset_right = _well.offset_left + w
	_well.offset_bottom = -(PLINTH_H - TUCK)
	_well.offset_top = _well.offset_bottom - h
	_shelf.size = sz
	_place_shelf()


func _place_shelf() -> void:
	if _card == null:
		return
	var rest := SHADOW
	var down := _well.size.y + 2.0
	_shelf.position = Vector2(SHADOW, roundf(lerpf(down, rest, _slide)))
	_shelf.modulate.a = clampf(_slide * 1.6, 0.0, 1.0)
	var up := (_shelf.size.y - TUCK) * _slide
	reach = PLINTH_H + maxf(up, 0.0)
	reach_changed.emit()
	if _card.visible and is_instance_valid(_hovered):
		_place_card()


# --- what each card shows ------------------------------------------------------------------------

## Looked at a few times a second (Hud): what the stores can pay for, what's locked, what's newly
## open, how many stand, what's in hand.
func refresh(stock: Dictionary) -> void:
	var v: Village = game.village
	var counts := {}
	for o in v.buildings:
		if o.state != "gone":
			counts[o.kind] = int(counts.get(o.kind, 0)) + 1
	for cat: Array in Hud.CATS:
		for kind: String in cat[1]:
			var def: Dictionary = Hud.ORDERS[kind] if Hud.ORDERS.has(kind) else BuildingDefs.DEFS[kind]
			var needs := str(def.get("needs", ""))
			var locked := needs != "" and not v.knows(needs)
			var short := false
			if not Hud.ORDERS.has(kind):
				var cost: Dictionary = BuildingDefs.DEFS[kind].cost
				for r: String in cost:
					if int(stock.get(r, 0)) < int(cost[r]):
						short = true
			if _was_locked.has(kind) and _was_locked[kind] and not locked and not _seen_new.has(kind):
				_new[kind] = true # (just unlocked: tagged till it's looked at)
			_was_locked[kind] = locked
			_state[kind] = {"locked": locked, "short": short, "count": int(counts.get(kind, 0))}
	_apply_state()
	if _card.visible and is_instance_valid(_hovered):
		_fill_card(_hovered.kind, false)


func _apply_state() -> void:
	var held: String = game._placing if game else ""
	for t: Node in _row.get_children():
		var tile := t as Tile
		if tile == null or tile.is_queued_for_deletion():
			continue
		var st: Dictionary = _state.get(tile.kind, {})
		var locked: bool = st.get("locked", false)
		var short: bool = st.get("short", false)
		var nw: bool = _new.has(tile.kind)
		var hd := held == tile.kind
		if tile.locked != locked or tile.short != short or tile.fresh != nw or tile.held != hd:
			tile.locked = locked
			tile.short = short
			tile.fresh = nw
			tile.held = hd
			tile.set_grey(1.0 if locked else (0.85 if short else 0.0))
			tile.redraw()


func _tile_hovered(t: Tile, on: bool) -> void:
	if on:
		_hovered = t
		if _new.has(t.kind):
			_new.erase(t.kind)
			_seen_new[t.kind] = true
			t.fresh = false
		_fill_card(t.kind, true)
	elif _hovered == t:
		_hovered = null
		_hide_card()


func _hide_card() -> void:
	if _card:
		_card.visible = false


# --- the hover card ------------------------------------------------------------------------------

## The parchment card over a building's card: its name, what it brings; what it takes, each good
## with what's in the stores against what's needed, red where it's short; what it is; how long to
## build, how many stand; what unlocks it, if it's locked.
func _make_card() -> void:
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PARCH
	sb.border_color = C_PARCH_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0.06, 0.03, 0.01, 0.42)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 5)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.anti_aliasing = true
	_card.add_theme_stylebox_override("panel", sb)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.top_level = true
	_card.visible = false
	add_child(_card)
	var fib := tex("fibre")
	_card.draw.connect(func() -> void:
		var r := Rect2(Vector2(1, 1), _card.size - Vector2(2, 2))
		if fib:
			_card.draw_set_transform(r.position, 0.0, Vector2(0.5, 0.5))
			_card.draw_texture_rect(fib, Rect2(Vector2.ZERO, r.size * 2.0), true, Color(1, 1, 1, 0.35))
			_card.draw_set_transform(Vector2.ZERO)
		# the printed rule just inside the edge, as on a catalogue card
		_card.draw_rect(Rect2(Vector2(4, 4), _card.size - Vector2(8, 8)), Color(Ui.P_INK, 0.22), false, 1.0)
		# the notch pointing down at the card under it
		var bx := clampf(_card_at, 18.0, _card.size.x - 18.0)
		var y := _card.size.y
		var tri := PackedVector2Array([Vector2(bx - 9, y - 1), Vector2(bx + 9, y - 1), Vector2(bx, y + 8)])
		_card.draw_colored_polygon(tri, C_PARCH)
		_card.draw_polyline(PackedVector2Array([Vector2(bx - 9, y - 0.5), Vector2(bx, y + 8), Vector2(bx + 9, y - 0.5)]), C_PARCH_EDGE, 1.0, true))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	_card_name = Ui.label(head, "", 20, Ui.P_INK, "display")
	_card_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_count = Ui.label(head, "", 13, Ui.P_DIM, "type_bold")
	_card_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_card_gives = Ui.label(col, "", 15, Ui.P_DIM, "italic")
	Ui.double_rule(col, Color(Ui.P_INK, 0.75))
	_card_costs = GridContainer.new()
	_card_costs.columns = 3
	_card_costs.add_theme_constant_override("h_separation", 8)
	_card_costs.add_theme_constant_override("v_separation", 2)
	col.add_child(_card_costs)
	_card_desc = Ui.label(col, "", 14, Ui.P_INK, "text")
	_card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_desc.custom_minimum_size.x = CARD_W
	_card_desc.add_theme_constant_override("line_spacing", 2)
	_card_rule = ColorRect.new()
	_card_rule.color = Color(Ui.P_INK, 0.25)
	_card_rule.custom_minimum_size = Vector2(0, 1)
	col.add_child(_card_rule)
	_card_foot = Ui.label(col, "", 13, Ui.P_DIM, "type")
	_card_lock = HBoxContainer.new()
	_card_lock.add_theme_constant_override("separation", 8)
	col.add_child(_card_lock)
	var seal := TextureRect.new()
	seal.texture = tex("seal")
	seal.custom_minimum_size = Vector2(22, 22)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_card_lock.add_child(seal)
	_card_lock_text = Ui.label(_card_lock, "", 13, Ui.P_RED, "type_bold")
	_card_lock_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_lock_text.custom_minimum_size.x = CARD_W - 30.0
	for n: Node in _card.find_children("*", "Control", true, false):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _fill_card(kind: String, fresh: bool) -> void:
	var order := Hud.ORDERS.has(kind)
	var def: Dictionary = Hud.ORDERS[kind] if order else BuildingDefs.DEFS[kind]
	_card_name.text = str(def.name)
	var gives := str(def.gives) if order else str(BuildingDefs.GIVES.get(kind, ""))
	_card_gives.text = gives
	_card_gives.visible = gives != ""
	var st: Dictionary = _state.get(kind, {})
	var count := int(st.get("count", 0))
	_card_count.text = "" if order else "Kurulu: %d" % count
	for c in _card_costs.get_children():
		_card_costs.remove_child(c)
		c.queue_free()
	var stock: Dictionary = game.village.stock if game.village else {}
	if order and ORDER_COST.has(kind):
		var oc: Dictionary = ORDER_COST[kind][0]
		for good: String in oc:
			var have := int(stock.get(good, 0))
			var need := int(oc[good])
			_cost_row(good, "%s, %s" % [str(BuildingDefs.RES_NAMES.get(good, good)), ORDER_COST[kind][1]], "%d / %d" % [have, need], have < need)
	elif order:
		_cost_row("", "bedava", "", false)
	else:
		var cost: Dictionary = BuildingDefs.DEFS[kind].cost
		if cost.is_empty():
			_cost_row("", "bedava", "", false)
		for good: String in cost:
			var have := int(stock.get(good, 0))
			var need := int(cost[good])
			_cost_row(good, str(BuildingDefs.RES_NAMES.get(good, good)), "%d / %d" % [have, need], have < need)
	_card_desc.text = _gist(str(def.get("desc", "")))
	_card_desc.visible = _card_desc.text != ""
	var foot: Array[String] = []
	if not order:
		var secs := float(def.get("time", 0.0))
		if secs > 0.0:
			foot.append("Yapım %d sn emek" % roundi(secs))
		elif kind in ["sur", "yol"]:
			foot.append("Parça parça kurulur")
		var slots := int(def.get("slots", 0))
		if slots > 0:
			foot.append("%d kişi çalışır" % slots)
	_card_foot.text = " · ".join(foot)
	_card_foot.visible = not foot.is_empty()
	_card_rule.visible = _card_foot.visible
	var locked: bool = st.get("locked", false)
	_card_lock.visible = locked
	if locked:
		var needs := str(def.get("needs", ""))
		var tech: Dictionary = BuildingDefs.TECHS.get(needs, {})
		_card_lock_text.text = "Kilitli: okuma odasında %s araştırılınca açılır" % str(tech.get("name", needs))
	_card.visible = true
	if fresh:
		_card.reset_size()
		_place_card.call_deferred()


## The first sentence or two of a building's description: what it is, as a catalogue would say it.
static func _gist(desc: String) -> String:
	var out := ""
	for part in desc.split(". ", false):
		var sent := part if part.ends_with(".") else part + "."
		if out != "" and (out.length() + sent.length() > 150):
			break
		out = sent if out == "" else out + " " + sent
		if out.length() > 70:
			break
	return out


func _cost_row(good: String, name: String, fig: String, short: bool) -> void:
	var icn := TextureRect.new()
	icn.custom_minimum_size = Vector2(22, 22)
	icn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icn.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if good != "" and ResourceLoader.exists("res://assets/ui/ink/%s.png" % good):
		icn.texture = load("res://assets/ui/ink/%s.png" % good)
		if short:
			icn.modulate = Color(1.0, 0.55, 0.5)
	_card_costs.add_child(icn)
	var n := Ui.label(_card_costs, name, 15, Ui.P_RED if short else Ui.P_INK, "italic" if good == "" else "text")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := Ui.label(_card_costs, fig, 15, Ui.P_RED if short else Ui.P_INK, "type_bold")
	f.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE


## The card set just over the hovered building's card, kept on the screen.
func _place_card() -> void:
	if not is_instance_valid(_hovered) or not _card.visible:
		return
	_card.reset_size()
	var w := _card.size.x
	var mid := _hovered.global_position.x + _hovered.size.x * 0.5
	var vw := get_viewport_rect().size.x
	var x := roundf(clampf(mid - w * 0.5, 8.0, vw - w - 8.0))
	var top := _shelf.global_position.y
	_card.global_position = Vector2(x, roundf(top - _card.size.y - 10.0))
	_card_at = mid - x
	_card.queue_redraw()


## The kind under key `n` (0-based) in the group shown, or "".
func kind_at(n: int) -> String:
	var kinds: Array = Hud.CATS[category][1]
	return kinds[n] if n >= 0 and n < kinds.size() else ""


# --- the pieces ----------------------------------------------------------------------------------

## A group's medallion on the plinth: brass, its glyph engraved in its walnut face; chosen, polished
## and its face pale brass, the glyph dark; its name in capitals under it.
class Medal extends Button:
	var index := 0
	var word := ""
	var glyph: Texture2D
	var on := false

	func _init() -> void:
		custom_minimum_size = BuildTray.SLOT
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func _draw() -> void:
		var hov := is_hovered()
		var down := 1.0 if is_pressed() else 0.0
		var name := "medal_on" if on else ("medal_hover" if hov else "medal_idle")
		var t := BuildTray.tex(name)
		var box := Rect2(Vector2(roundf((size.x - BuildTray.MEDAL) * 0.5), down), Vector2(BuildTray.MEDAL, BuildTray.MEDAL))
		if t:
			draw_set_transform(box.position, 0.0, Vector2(0.5, 0.5))
			draw_texture(t, Vector2.ZERO)
			draw_set_transform(Vector2.ZERO)
		var c := box.get_center()
		if glyph:
			var g := Rect2(c - Vector2(15, 15), Vector2(30, 30))
			if on:
				# cut into polished brass: a bright lip on its foot, the cut dark
				draw_texture_rect(glyph, Rect2(g.position + Vector2(0, 1), g.size), false, Color(BuildTray.C_BRASS_HI, 0.75))
				draw_texture_rect(glyph, g, false, BuildTray.C_GLYPH_ON)
			else:
				# inlaid in the walnut: a dark hair over it, the brass bright
				draw_texture_rect(glyph, Rect2(g.position + Vector2(0, -1), g.size), false, Color(0, 0, 0, 0.55))
				draw_texture_rect(glyph, g, false, BuildTray.C_GLYPH.lightened(0.1) if hov else BuildTray.C_GLYPH)
		# its name under it
		var size_f := 14
		var f := Ui.face("head", size_f)
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_f).x
		var at := Vector2(roundf((size.x - w) * 0.5), size.y - 5.0)
		var ink := BuildTray.C_BRASS_HI if on or hov else Color(0.85, 0.75, 0.56)
		draw_string(f, at + Vector2(0, 1), word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_f, Color(0, 0, 0, 0.6))
		draw_string(f, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_f, ink)
		if on: # (a little brass rule under the chosen one's name)
			draw_rect(Rect2(Vector2(roundf(size.x * 0.5 - 10.0), size.y - 1.0), Vector2(20, 1)), Color(BuildTray.C_BRASS_HI, 0.8))


## A building's card in the tray: the engraving on cream card in a thin dark brass frame, its key
## printed in the corner. Lifts and warms under the mouse; in hand, its frame thick polished brass;
## the stores short, the card greyed and the engraving faded; locked, greyed with a red wax seal on
## its corner; newly open, an inked YENİ tag on its frame.
class Tile extends Button:
	var tray: BuildTray
	var kind := ""
	var key := 0
	var plate: Texture2D
	var lift := 0.0
	var enter := 1.0
	var locked := false
	var short := false
	var fresh := false
	var held := false
	var _over: Control
	var _lift_tw: Tween

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		if BuildTray._grey_shader == null:
			BuildTray._grey_shader = Shader.new()
			BuildTray._grey_shader.code = """shader_type canvas_item;
uniform float grey : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(vec3(l) * vec3(1.0, 0.98, 0.94), vec3(0.74, 0.71, 0.66), 0.3);
	c.rgb = mix(c.rgb, g, grey);
	COLOR = c;
}"""
		var m := ShaderMaterial.new()
		m.shader = BuildTray._grey_shader
		material = m
		_over = Control.new()
		_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_over.set_anchors_preset(Control.PRESET_FULL_RECT)
		_over.draw.connect(_draw_over)
		add_child(_over)
		mouse_entered.connect(func() -> void:
			_lift_to(1.0)
			tray._tile_hovered(self, true))
		mouse_exited.connect(func() -> void:
			_lift_to(0.0)
			tray._tile_hovered(self, false))
		button_down.connect(func() -> void: _lift_to(0.3))
		button_up.connect(func() -> void: _lift_to(1.0 if is_hovered() else 0.0))
		pressed.connect(func() -> void: tray.game.start_placing(kind))
		gui_input.connect(func(ev: InputEvent) -> void: tray._on_right_click(ev))

	func set_grey(g: float) -> void:
		(material as ShaderMaterial).set_shader_parameter("grey", g)

	func redraw() -> void:
		queue_redraw()
		_over.queue_redraw()

	func _lift_to(to: float) -> void:
		if _lift_tw:
			_lift_tw.kill()
		_lift_tw = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_lift_tw.tween_method(func(v: float) -> void:
			lift = v
			redraw(), lift, to, 0.12)

	## Where the card is drawn: lifted under the mouse, coming up as the group opens.
	func _card_rect() -> Rect2:
		var y := -4.0 * maxf(lift, 0.75 if held else 0.0) + (1.0 - enter) * 12.0
		return Rect2(Vector2(0, roundf(y)), size)

	func _draw() -> void:
		var r := _card_rect()
		# its shadow on the tray: closer when it's down, softer when lifted
		draw_rect(Rect2(r.position + Vector2(-1, 2.0 + 3.0 * lift), r.size + Vector2(2, 1)), Color(0, 0, 0, 0.16))
		draw_rect(Rect2(r.position + Vector2(0, 1.0 + 2.0 * lift), r.size), Color(0, 0, 0, 0.3))
		# the card
		var card := r.grow(-2.0)
		var paper := BuildTray.C_CARD.lerp(Color("f7eed8"), lift * 0.6)
		if short or locked:
			paper = BuildTray.C_CARD_GREY
		draw_rect(card, paper)
		var fib := BuildTray.tex("fibre")
		if fib:
			draw_set_transform(card.position, 0.0, Vector2(0.5, 0.5))
			draw_texture_rect(fib, Rect2(Vector2(key * 37 % 64, 0), card.size * 2.0), true, Color(1, 1, 1, 0.5))
			draw_set_transform(Vector2.ZERO)
		# a faint printed rule inside the edge
		draw_rect(card.grow(-3.0), Color(Ui.P_INK, 0.14), false, 1.0)
		if plate:
			var s := roundf(card.size.x * 0.96)
			var pic := Rect2((card.get_center() - Vector2(s, s) * 0.5 + Vector2(1, 1)).round(), Vector2(s, s))
			var a := 0.5 if locked else (0.62 if short else 1.0)
			draw_texture_rect(plate, pic, false, Color(1, 1, 1, a))

	func _draw_over() -> void:
		var o := _over
		var r := _card_rect()
		var hov := lift > 0.01 and not held
		# the frame
		if held: # (thick polished brass, lit along its top and left)
			o.draw_rect(r.grow(2.5), Color(1.0, 0.8, 0.45, 0.35), false, 3.0)
			o.draw_rect(r.grow(-1.5), BuildTray.C_BRASS, false, 3.0)
			o.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 1)), BuildTray.C_BRASS_HI)
			o.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(1, r.size.y - 2)), BuildTray.C_BRASS_HI)
			o.draw_rect(Rect2(r.position + Vector2(1, r.size.y - 2), Vector2(r.size.x - 2, 1)), Color("7a5a2c"))
			o.draw_rect(Rect2(r.position + Vector2(r.size.x - 2, 1), Vector2(1, r.size.y - 2)), Color("7a5a2c"))
			o.draw_rect(r, Color("22160b"), false, 1.0)
			o.draw_rect(r.grow(-4.5), Color("22160b", 0.7), false, 1.0)
		else:
			if hov: # (a warm light round it, not over it)
				o.draw_rect(r.grow(2.5), Color(1.0, 0.78, 0.42, 0.16 * lift), false, 3.0)
				o.draw_rect(r.grow(1.0), Color(1.0, 0.8, 0.45, 0.45 * lift), false, 1.0)
			var fc := BuildTray.C_FRAME.lerp(BuildTray.C_FRAME_HI, lift)
			o.draw_rect(r.grow(-1.0), fc, false, 2.0)
			o.draw_rect(r, Color("22160b", 0.85), false, 1.0)
		# its key, printed in the corner
		var kf := Ui.face("type_bold", 12)
		o.draw_string(kf, r.position + Vector2(6, 15), str(key + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Ui.P_INK, 0.8))
		# locked: a red wax seal on its corner
		if locked:
			var t := BuildTray.tex("seal")
			if t:
				o.draw_set_transform(r.position + Vector2(r.size.x - 21, -3), 0.0, Vector2(0.5, 0.5))
				o.draw_texture(t, Vector2.ZERO)
				o.draw_set_transform(Vector2.ZERO)
		# newly open: an inked tag on the frame
		if fresh and not locked:
			var tf := Ui.face("type_bold", 10)
			var word := "YENİ"
			var tw := tf.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var tag := Rect2(Vector2(roundf(r.end.x - tw - 14.0), r.position.y - 6.0), Vector2(roundf(tw + 10.0), 14))
			o.draw_rect(Rect2(tag.position + Vector2(0, 1), tag.size), Color(0, 0, 0, 0.3))
			o.draw_rect(tag, Color("f6eedb"))
			o.draw_rect(tag, Ui.P_RED, false, 1.0)
			o.draw_string(tf, tag.position + Vector2(5, 11), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.P_RED)
