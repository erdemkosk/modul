class_name Ui
extends RefCounted
## The game's one look, shared by every screen: a town clerk's ledger, its old leather and the dark
## tobacco-brown leaves inside. Panels are that leather (made here, once: grain, wear, a darker,
## worn edge and a line of stitching round it), buttons are tags tooled into it, the writing is a
## cream ink with brass for what matters, a sage green and a brick red for ready and trouble. Nothing
## bright: it's easy on the eyes. Barlow (assets/fonts, OFL): Barlow Condensed for numbers, titles and labels
## in capitals, Barlow for reading. Writing straight over the world (toasts, hints) has a halo of
## paper round it, so it reads over snow and forest alike; LIGHT is for writing on the title
## screen's dark picture.

const ACCENT := Color(0.88, 0.68, 0.36) ## brass
const INK := Color(0.93, 0.87, 0.75) ## cream
const DIM := Color(0.7, 0.61, 0.49)
const FAINT := Color(0.93, 0.87, 0.75, 0.12)
const GOOD := Color(0.6, 0.78, 0.48)
const BAD := Color(0.93, 0.47, 0.36)
const LIGHT := Color(0.96, 0.93, 0.86) ## (writing on the dark title picture)
const PAPER := Color(0.25, 0.18, 0.13) ## the leather
const GLASS := Color(0.05, 0.055, 0.06, 0.8) ## (callers' fills: a dark one is read as plain leather)
const EDGE := Color(0.93, 0.87, 0.75, 0.25)
const SKEW := 0.22 ## (the bars' lean)

static var _paper: ImageTexture

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
	# a halo round it (paper round ink, dark round light): it reads straight over the world too
	l.add_theme_color_override("font_outline_color", Color(PAPER, 0.55) if color.get_luminance() < 0.5 else Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("outline_size", 3)
	if parent:
		parent.add_child(l)
	return l


## Upper case the Turkish way (i -> İ, ı -> I).
static func upper(s: String) -> String:
	return s.replace("i", "İ").replace("ı", "I").to_upper()


## A leaf of paper (a panel: a margin of 8 or more), or an inked tag on it (a button: a smaller
## margin; `fill` its wash, a dark one read as none, `edge` its line).
static func glass(_lean := true, margin := 12.0, fill := GLASS, edge := EDGE) -> StyleBox:
	if margin >= 8.0:
		return paper(margin)
	var tag := StyleBoxFlat.new()
	var dark := fill.get_luminance() < 0.2
	tag.bg_color = Color(0.36, 0.27, 0.19, 0.85) if dark or fill.a < 0.1 else Color(0.55, 0.4, 0.2, minf(0.55 + fill.a, 0.95)) # (tooled: a shade lighter; brass-tinted when lit)
	tag.border_color = Color(0.1, 0.07, 0.05, 0.8) if edge == EDGE else ACCENT
	tag.shadow_color = Color(0, 0, 0, 0.3)
	tag.shadow_size = 1
	tag.shadow_offset = Vector2(0, 1)
	tag.set_border_width_all(1)
	tag.border_width_bottom = 2 # (the ink pooled at the foot of the line)
	tag.set_corner_radius_all(2)
	tag.set_content_margin_all(margin)
	tag.content_margin_left = margin + 4.0
	tag.content_margin_right = margin + 4.0
	tag.anti_aliasing = true
	return tag


## A leaf of the clerk's paper, with room `margin` inside its torn edge.
static func paper(margin := 12.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _paper_texture()
	sb.set_texture_margin_all(22.0)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.set_content_margin_all(margin + 6.0)
	return sb


## The leather, made once: brown with grain and wear (noise), darker toward a worn, rounded edge,
## a line of stitching just inside it.
static func _paper_texture() -> ImageTexture:
	if _paper:
		return _paper
	var n := 160
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var fib := FastNoiseLite.new()
	fib.seed = 7
	fib.frequency = 0.09
	fib.fractal_octaves = 3
	var fox := FastNoiseLite.new()
	fox.seed = 11
	fox.frequency = 0.025
	var rag := FastNoiseLite.new()
	rag.seed = 3
	rag.frequency = 0.16
	for y in n:
		for x in n:
			var edge := minf(minf(x, n - 1 - x), minf(y, n - 1 - y))
			var wear := 2.0 + rag.get_noise_2d(x * 1.0 + y * 0.37, y * 1.0 - x * 0.21) * 1.2 # (the edge, a little uneven)
			if edge < wear:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var t := clampf((edge - wear) / 12.0, 0.0, 1.0)
			var c := PAPER * (0.94 + fib.get_noise_2d(x * 2.2, y * 2.2) * 0.12) # (grain)
			c = c.lerp(Color(0.34, 0.25, 0.17), clampf(fox.get_noise_2d(x, y) * 0.6, 0.0, 0.35)) # (wear: lighter patches)
			c = c.darkened((1.0 - t) * 0.45) # (darker toward the edge)
			var stitch := absf(edge - wear - 7.0) < 0.8 and int(x + y) % 6 < 3 # (a line of stitching inside it)
			if stitch:
				c = c.lerp(Color(0.62, 0.5, 0.34), 0.55)
			c.a = clampf((edge - wear) * 1.2, 0.0, 1.0) * 0.96
			img.set_pixel(x, y, c)
	_paper = ImageTexture.create_from_image(img)
	return _paper


## A thin rust rule under a heading.
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
