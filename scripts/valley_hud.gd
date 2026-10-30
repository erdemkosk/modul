class_name ValleyHud
extends CanvasLayer
## The valley's line on the screen (top left), small: the wood in the store, the saw's cut while it's
## biting, the expedition only while there's one, the workshop only when it's far, a giant near.
## And the radio (J): the jobs offered, each with ÜSTLEN, and the one taken with BIRAK.

var game: Node
var exp_: Expeditions
var shop: Workshop
var life: ValleyLife
var giants: Colossus
var board_open := false
var _lines: Label
var _warn: Label
var _board: PanelContainer
var _list: VBoxContainer
var _t := 0.0
var _box: Control


func _ready() -> void:
	layer = 6
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Ui.glass(true, 10.0))
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	box.offset_left = 26
	box.offset_top = 22
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var v := VBoxContainer.new()
	box.add_child(v)
	_lines = Ui.label(v, "", 15, Ui.INK, "head")
	_warn = Ui.label(v, "", 14, Ui.ACCENT, "head")
	_box = box
	_board = PanelContainer.new()
	_board.add_theme_stylebox_override("panel", Ui.glass(false, 22.0))
	_board.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_board.custom_minimum_size = Vector2(620, 0)
	_board.visible = false
	add_child(_board)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 12)
	_board.add_child(bv)
	Ui.label(bv, "TELSİZ  ·  SEFERLER", 28, Ui.INK, "display")
	Ui.label(bv, "Bir yükü bir yerden ötekine taşı. Aracın taşıyabilmeli: tekerleklerin taşıdığı yük, aracın ağırlığı artı yük.", 15, Ui.DIM)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	bv.add_child(_list)
	var close := Button.new()
	close.text = "KAPAT  (J)"
	close.pressed.connect(toggle_board)
	bv.add_child(close)
	exp_.changed.connect(_fill)


func toggle_board() -> void:
	board_open = not board_open
	_board.visible = board_open
	if board_open:
		_fill()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _fill() -> void:
	if not board_open:
		return
	for c in _list.get_children():
		c.queue_free()
	if not exp_.job.is_empty():
		var row := HBoxContainer.new()
		_list.add_child(row)
		var l := Ui.label(row, "ŞU ANKİ: " + exp_.status(), 16, Ui.ACCENT, "head")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var b := Button.new()
		b.text = "BIRAK"
		b.pressed.connect(exp_.abandon)
		row.add_child(b)
	for i in exp_.offers.size():
		var row := HBoxContainer.new()
		_list.add_child(row)
		var l := Ui.label(row, exp_.describe(exp_.offers[i]), 15, Ui.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Button.new()
		b.text = "ÜSTLEN"
		b.disabled = not exp_.job.is_empty()
		b.pressed.connect(func() -> void: exp_.accept(i))
		row.add_child(b)


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.25
	var lines := PackedStringArray()
	var me: Machine = shop.yours() if shop else null
	var top := "Odun %d" % Inventory.wood
	if Inventory.scrap > 0:
		top += "   Hurda %d" % Inventory.scrap
	if me:
		for t in me.tools:
			if t.kind == "saw" and t.cutting >= 0:
				top += "   ·   kesiliyor %%%d" % roundi(t.cut_frac() * 100.0)
	lines.append(top)
	if not exp_.job.is_empty():
		lines.append(exp_.status())
	if shop and me and not shop.driving() and shop.dist(me) > Workshop.REACH * 2.0:
		var to := shop.truck.global_position - me.global_position
		lines.append("Atölye %d m %s" % [roundi(shop.dist(me)), Workshop.compass(atan2(to.x, -to.z))])
	_lines.text = "\n".join(lines)
	var g := giants.status() if giants else ""
	_warn.text = g
	_warn.visible = g != ""
