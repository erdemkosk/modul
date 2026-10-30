class_name Ui
extends RefCounted
## The game's one look, shared by every screen: Barlow (assets/fonts, OFL) — Barlow Condensed for
## numbers, titles and labels in capitals, Barlow for reading — dark smoked glass with a hairline
## edge, slanted like a vehicle's armour plate, one hot orange accent, green for ready and red for
## trouble. The workshop (Builder) uses the light paper version of the same.

const ACCENT := Color(1.0, 0.56, 0.14)
const INK := Color(0.96, 0.94, 0.9)
const DIM := Color(0.63, 0.62, 0.6)
const FAINT := Color(1.0, 1.0, 1.0, 0.1)
const GOOD := Color(0.42, 0.9, 0.52)
const BAD := Color(1.0, 0.33, 0.24)
const GLASS := Color(0.05, 0.055, 0.06, 0.8)
const EDGE := Color(1.0, 1.0, 1.0, 0.1)
const SKEW := 0.22 ## how far the plates lean

static var _fonts := {}


## "display" (condensed bold: big numbers, titles), "head" (condensed semibold: labels), "text"
## (Barlow medium), "strong" (Barlow semibold), "digital" (Chakra Petch: read-outs).
static func font(kind := "text") -> Font:
	if not _fonts.has(kind):
		var file: String = {"display": "BarlowCondensed-Bold", "head": "BarlowCondensed-SemiBold",
			"label": "BarlowCondensed-Medium", "text": "Barlow-Medium", "strong": "Barlow-SemiBold",
			"digital": "ChakraPetch-SemiBold"}.get(kind, "Barlow-Medium")
		var f := load("res://assets/fonts/%s.ttf" % file) as FontFile
		if kind in ["head", "label"]:
			var v := FontVariation.new()
			v.base_font = f
			v.spacing_glyph = 1 # (capitals, opened up a little)
			_fonts[kind] = v
		else:
			_fonts[kind] = f
	return _fonts[kind]


static func label(parent: Node, text: String, size: int, color := INK, kind := "text") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# a soft dark edge under it: it reads over a bright sky or snow as well as over the glass
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 4)
	if parent:
		parent.add_child(l)
	return l


## Upper case the Turkish way (i -> İ, ı -> I).
static func upper(s: String) -> String:
	return s.replace("i", "İ").replace("ı", "I").to_upper()


## A smoked glass plate, leaning (skew) or square.
static func glass(lean := true, margin := 12.0, fill := GLASS, edge := EDGE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(margin)
	sb.content_margin_left = margin + (10.0 if lean else 0.0)
	sb.content_margin_right = margin + (10.0 if lean else 0.0)
	if lean:
		sb.skew = Vector2(-SKEW, 0.0)
	sb.anti_aliasing = true
	return sb


## A thin orange rule under a heading.
static func rule(parent: Node, width := 28.0, color := ACCENT) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(width, 2)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(r)
	return r


## Draws a leaning bar of `n` segments, `frac` of them lit.
static func segments(c: CanvasItem, rect: Rect2, n: int, frac: float, on: Color, off := FAINT, lean := 0.35) -> void:
	var gap := 2.0
	var w := (rect.size.x - (n - 1) * gap) / n
	var h := rect.size.y
	for k in n:
		var x := rect.position.x + k * (w + gap)
		var lit := (k + 0.5) / n <= frac
		var pts := PackedVector2Array([Vector2(x + h * lean, rect.position.y), Vector2(x + w + h * lean, rect.position.y),
			Vector2(x + w, rect.position.y + h), Vector2(x, rect.position.y + h)])
		c.draw_colored_polygon(pts, on if lit else off)
