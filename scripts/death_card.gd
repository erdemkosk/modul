class_name DeathCard
extends CanvasLayer
## When your cab goes: the screen darkens and reddens at its edges, and a card rises with what did it
## ("TANK · TOP ATIŞI"), how long you lasted and what you took with you, counting down to a new
## machine; Space (or a click) builds it now.

signal respawn

const WAIT := 6.0 ## s before it's built anyway
const KIND := {"minigun": "MİNİGUN ATEŞİ", "top": "TOP ATIŞI", "roket": "ROKET", "patlama": "PATLAMA",
	"çarpışma": "ÇARPIŞMA"}

var _veil: TextureRect
var _card: PanelContainer
var _why: Label
var _stats: Label
var _count: Label
var _t := 0.0
var _on := false


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, 0.25))
	g.set_color(1, Color(0.35, 0.02, 0.0, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.1, 0.5)
	_veil = TextureRect.new()
	_veil.texture = tex
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.stretch_mode = TextureRect.STRETCH_SCALE
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Ui.glass(true, 26.0, Color(0.05, 0.04, 0.04, 0.92), Ui.BAD))
	row.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_card.add_child(col)
	Ui.label(col, "KABİN VURULDU", 16, Ui.BAD, "head")
	Ui.label(col, "ARACIN PARÇALANDI", 58, Ui.INK, "display")
	Ui.rule(col, 90.0, Ui.BAD)
	_why = Ui.label(col, "", 22, Ui.INK, "head")
	_stats = Ui.label(col, "", 16, Ui.DIM, "label")
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	col.add_child(gap)
	_count = Ui.label(col, "", 18, Ui.ACCENT, "head")


func show_card(who: String, kind: String, lived: float, took: int) -> void:
	var what: String = KIND.get(kind, "")
	if who != "" and what != "":
		_why.text = "%s  ·  %s" % [who, what]
	elif who != "":
		_why.text = who
	else:
		_why.text = what if what != "" else "BİLİNMEYEN"
	_stats.text = "Dayandığın süre %d:%02d   ·   Parçaladığın %d araç" % [int(lived) / 60, int(lived) % 60, took]
	_t = 0.0
	_on = true
	visible = true
	_veil.modulate.a = 0.0
	_card.modulate.a = 0.0
	_card.position.y = 30.0
	var tw := create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.tween_property(_veil, "modulate:a", 1.0, 0.4)
	tw.tween_property(_card, "modulate:a", 1.0, 0.35).set_delay(0.5)
	tw.tween_property(_card, "position:y", 0.0, 0.45).set_delay(0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_dt: float) -> void:
	if not _on:
		return
	_t += get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	var left := WAIT - _t
	_count.text = "YENİDEN KUR  ·  SPACE   (%d)" % ceili(maxf(left, 0.0))
	if left <= 0.0:
		_go()


func _unhandled_input(event: InputEvent) -> void:
	if not _on or _t < 1.0:
		return
	var k := event as InputEventKey
	var mb := event as InputEventMouseButton
	if (k and k.pressed and k.keycode == KEY_SPACE) or (mb and mb.pressed):
		get_viewport().set_input_as_handled()
		_go()


func _go() -> void:
	_on = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	respawn.emit()
