class_name Logo
extends Control
## The game's name as it's drawn on the title, the loading screen and the bar: WHERE RAILS END, the
## engine over the mountains and the rails running out under it (assets/ui/logo.png, clear round it).

const PIC := "res://assets/ui/logo.png"

@export var tall := 120.0 ## the picture's height is 2.6 of this
@export var centred := false
@export var sub := "" ## (the picture says it all)

var _tex: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex = load(PIC)
	var h := tall * 2.6
	custom_minimum_size = Vector2(h * _tex.get_width() / _tex.get_height(), h)
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := custom_minimum_size.x
	var x := (size.x - w) * 0.5 if centred else 0.0
	draw_texture_rect(_tex, Rect2(x, 0, w, custom_minimum_size.y), false)
