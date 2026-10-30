class_name ValleyHud
extends CanvasLayer
## The valley's lines on the screen (top left, under the place's name): the expedition (what, where to,
## how far, how it's holding up, the time left), the workshop (where, or what it's doing), the scrap
## held, the ground (how soaked), the roads shut and the fords in flood, a giant near.
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


func _ready() -> void:
	layer = 6
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Ui.glass(true, 10.0))
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	box.offset_left = 30
	box.offset_top = 100
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var v := VBoxContainer.new()
	box.add_child(v)
	_lines = Ui.label(v, "", 16, Ui.INK, "head")
	_warn = Ui.label(v, "", 15, Ui.ACCENT, "head")
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
	lines.append("SEFER  " + exp_.status())
	var s := shop.status() if shop else ""
	if s != "":
		lines.append(s)
	var me: Machine = shop.yours() if shop else null
	var binned := ""
	if me and me.bin_holds() > 0:
		binned = "  ·  Kasa %d/%d" % [Inventory.bin, me.bin_holds()]
	var sawing := ""
	if me:
		for t in me.tools:
			if t.kind == "saw":
				sawing = "  ·  Testere %s" % ("kesiyor %%%d" % roundi(t.cut_frac() * 100.0) if t.cutting >= 0 else ("açık" if t.on else "kapalı (R)"))
	lines.append("Odun %d%s%s" % [Inventory.wood, binned, sawing])
	lines.append("%s  ·  Planlar %d/%d  ·  Hurda %d  ·  Zemin %s  ·  Gün %d" % ["AHŞAP ÇAĞI" if Inventory.age() == 1 else "METAL ÇAĞI",
		Inventory.plans.size(), Parts.PLANS.size(), Inventory.scrap, life.ground_word(), ValleyLife.day])
	_lines.text = "\n".join(lines)
	var warn := PackedStringArray()
	for r in life.shut_roads():
		warn.append("Kapalı: " + r)
	for f in life.flooded():
		warn.append(f)
	var g := giants.status() if giants else ""
	if g != "":
		warn.append(g)
	_warn.text = "\n".join(warn)
	_warn.visible = not warn.is_empty()
