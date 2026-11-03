class_name Logo
extends Control
## The game's name as it's drawn on the title and the loading screen: LAST VERST in a 1910s print
## face, spaced wide, and beside it a verst post (the striped milestone of the old roads, black and
## white bands slanting round it, a plate near the top with the distance on it, here 0: the end of
## the line). Under the name the rails run in and stop at a buffer; under them KORDAL · 1918.

@export var tall := 120.0 ## the capitals' height, more or less (all else is scaled from it)
@export var ink := Color(0.96, 0.93, 0.86)
@export var sub := "KORDAL · 1918"
@export var centred := false

const BLACK := Color(0.07, 0.065, 0.06)
const WHITE := Color(0.93, 0.9, 0.82)
const RED := Color(0.62, 0.16, 0.1)


var _name: Label
var _sub: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the name and the line under it as text (spaced capitals: the way a station board or a book's
	# title page had them); the post, the rails and the buffer drawn round them
	_name = _text("LAST VERST", "OldStandard-Bold", int(tall), tall * 0.09)
	_sub = _text(sub, "OldStandard-Regular", int(tall * 0.21), tall * 0.12)
	_sub.add_theme_color_override("font_color", Color(ink, 0.8))
	_sub.visible = sub != ""
	_lay()
	resized.connect(_lay)


func _text(t: String, face: String, fs: int, spacing: float) -> Label:
	var l := Label.new()
	l.text = t
	var v := FontVariation.new()
	v.base_font = load("res://assets/fonts/%s.ttf" % face) as Font
	v.spacing_glyph = int(spacing)
	l.add_theme_font_override("font", v)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", ink)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _post_w() -> float:
	return tall * 0.27


func _lay() -> void:
	var name_sz := _name.get_combined_minimum_size()
	var w := tall * 0.18 + _post_w() + tall * 0.42 + name_sz.x
	custom_minimum_size = Vector2(w, tall * 1.95)
	var x0 := (size.x - w) * 0.5 if centred else 0.0
	_name.position = Vector2(x0 + tall * 0.18 + _post_w() + tall * 0.42, tall * 0.05 - name_sz.y * 0.12)
	var sub_sz := _sub.get_combined_minimum_size()
	_sub.position = Vector2(_name.position.x + (name_sz.x - sub_sz.x) * 0.5, tall * 1.62 - sub_sz.y * 0.5)
	queue_redraw()


func _draw() -> void:
	if _name == null:
		return
	var post_w := _post_w()
	var x0 := (size.x - custom_minimum_size.x) * 0.5 if centred else 0.0
	var base := tall * 1.05 # (the capitals' foot, more or less)
	# -- the post, to the left
	var px := x0 + tall * 0.18
	_post(Rect2(px, base - tall * 0.92, post_w, tall * 1.3))
	var word_end := _name.position.x + _name.get_combined_minimum_size().x - tall * 0.09
	# -- the rails under it, run in from the right and stopped at a buffer by the post
	var ry := base + tall * 0.2
	var rail := Color(ink, 0.85)
	var rail_x0 := px + post_w + tall * 0.12
	for k in range(0, int((word_end - rail_x0) / (tall * 0.11)) + 1):
		var sx := rail_x0 + tall * 0.05 + k * tall * 0.11
		draw_rect(Rect2(sx, ry - tall * 0.035, tall * 0.035, tall * 0.13), Color(ink, 0.45))
	draw_line(Vector2(rail_x0, ry), Vector2(word_end, ry), rail, maxf(tall * 0.022, 1.5))
	draw_line(Vector2(rail_x0, ry + tall * 0.06), Vector2(word_end, ry + tall * 0.06), rail, maxf(tall * 0.022, 1.5))
	# the buffer stop: a red-painted beam across the rails' end, a strut back
	draw_rect(Rect2(rail_x0 - tall * 0.02, ry - tall * 0.1, tall * 0.05, tall * 0.26), RED)
	draw_line(Vector2(rail_x0 + tall * 0.03, ry - tall * 0.08), Vector2(rail_x0 + tall * 0.17, ry + tall * 0.06), Color(ink, 0.7), maxf(tall * 0.018, 1.2))


## The verst post: a squared post banded black and white on the slant, a little pyramid cap, the
## plate high on it (a black edge, "0" on white), its foot in a mound of earth.
func _post(r: Rect2) -> void:
	var w := r.size.x
	draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r, WHITE)
	var band := w * 0.62
	var slant := w * 0.55
	var y := r.position.y + w * 0.9
	var k := 0
	while y < r.end.y:
		if k % 2 == 0:
			var pts := PackedVector2Array([Vector2(r.position.x, y + slant), Vector2(r.end.x, y),
				Vector2(r.end.x, minf(y + band, r.end.y)), Vector2(r.position.x, minf(y + slant + band, r.end.y))])
			if pts[0].y < r.end.y:
				draw_colored_polygon(pts, BLACK)
		y += band
		k += 1
	# the cap
	draw_colored_polygon(PackedVector2Array([Vector2(r.position.x - w * 0.12, r.position.y), Vector2(r.end.x + w * 0.12, r.position.y),
		Vector2(r.get_center().x, r.position.y - w * 0.55)]), BLACK)
	# the plate, nailed on high
	var plate := Rect2(r.position.x - w * 0.35, r.position.y + w * 0.75, w * 1.7, w * 1.25)
	draw_rect(Rect2(plate.position + Vector2(2, 2), plate.size), Color(0, 0, 0, 0.35))
	draw_rect(plate, BLACK)
	draw_rect(plate.grow(-w * 0.1), WHITE)
	# the 0 painted on it (an upright oval, thicker at the sides as a serif face's is)
	var c := plate.get_center()
	var ring := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		ring.append(c + Vector2(cos(a) * w * 0.27, sin(a) * w * 0.4))
	draw_polyline(ring, BLACK, maxf(w * 0.13, 1.5), true)
	# the mound at its foot
	draw_colored_polygon(PackedVector2Array([Vector2(r.position.x - w * 0.9, r.end.y), Vector2(r.position.x - w * 0.2, r.end.y - w * 0.3),
		Vector2(r.end.x + w * 0.2, r.end.y - w * 0.3), Vector2(r.end.x + w * 0.9, r.end.y)]), Color(0.22, 0.17, 0.12))
