class_name PauseMenu
extends CanvasLayer
## Esc while playing: the game stops under a dark veil and the choices come up (go on, settings, the
## start menu, out); Esc again or DEVAM goes on where it stopped.

signal to_menu

var _veil: ColorRect
var _list: VBoxContainer
var _settings: SettingsPanel
var _was_captured := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_veil = ColorRect.new()
	_veil.color = Color(0.0, 0.0, 0.0, 0.55)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_veil)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	center.add_child(_list)
	Ui.label(_list, "DURAKLATILDI", 15, Ui.ACCENT, "head")
	Ui.label(_list, "İNŞA", 72, Ui.INK, "display")
	Ui.rule(_list, 80.0)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	_list.add_child(gap)
	_button("DEVAM", func() -> void: close())
	_button("AYARLAR", func() -> void: _show_settings(true))
	_button("ANA MENÜ", func() -> void:
		close()
		to_menu.emit())
	_button("ÇIKIŞ", func() -> void: get_tree().quit())
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void: _show_settings(false))
	center.add_child(_settings)


## A big word button in the game's look: an orange plate under the mouse.
static func style_button(b: Button, small := false) -> void:
	b.add_theme_font_override("font", Ui.font("display"))
	b.add_theme_font_size_override("font_size", 22 if small else 34)
	b.add_theme_color_override("font_color", Ui.INK)
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.05, 0.02))
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.05, 0.02))
	b.add_theme_stylebox_override("normal", Ui.glass(true, 8.0, Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.12)))
	b.add_theme_stylebox_override("hover", Ui.glass(true, 8.0, Ui.ACCENT, Ui.ACCENT))
	b.add_theme_stylebox_override("pressed", Ui.glass(true, 8.0, Ui.ACCENT.darkened(0.15), Ui.ACCENT))
	b.custom_minimum_size = Vector2(0 if small else 300, 0)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _button(text: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	style_button(b)
	b.pressed.connect(fn)
	_list.add_child(b)


func _show_settings(on: bool) -> void:
	_settings.visible = on
	_list.visible = not on


func open() -> void:
	if visible:
		return
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	visible = true
	_show_settings(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_veil.modulate.a = 0.0
	_veil.create_tween().tween_property(_veil, "modulate:a", 1.0, 0.15)


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if visible and k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		if _settings.visible:
			_show_settings(false)
		else:
			close()
		get_viewport().set_input_as_handled()
