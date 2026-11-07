class_name Ui
extends RefCounted
## The game's look, shared by every screen, and chosen piece by piece the way a town of 1918 would
## have had it: what's always on screen is the clerk's leather and brass (the bars, the dial, the
## map's board) and an enamel sign for the clock; what's opened is paper, each the paper of its
## kind: the day-book a ruled ledger page with its red margin, the townsfolk a green account
## register, the research a Van Dyke print (a drawing's sepia copy) pinned at the corners, a question a telegram form with its
## stamp, the keys a printed card, the pause a railway timetable on its board, a building or a
## settler a buff file card. Writing on leather is a cream ink with brass for what matters; on paper
## it's iron-gall ink, red for trouble, copying-pencil blue for what's chosen.
## Type (assets/fonts, OFL): Old Standard, a Russian printer's face of the 1910s, for everything
## read; Courier Prime, a typewriter, for telegrams, forms and read-outs; Barlow only behind them for
## the few marks they lack (♥ ▲). Writing straight over the world (hints) has a halo round it.

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

# --- ink on paper --------------------------------------------------------------------------------
const P_INK := Color(0.16, 0.12, 0.09) ## iron-gall, browned with age
const P_DIM := Color(0.4, 0.33, 0.25)
const P_RED := Color(0.66, 0.13, 0.09) ## the ruled margin, the stamp, trouble
const P_BLUE := Color(0.5, 0.3, 0.07) ## ochre pencil: what's chosen (the name kept; no blue anywhere)
const P_GREEN := Color(0.18, 0.4, 0.2)
const ENAMEL := Color(0.91, 0.87, 0.77) ## the clock's sign: cream enamel
const CHALK := Color(0.95, 0.9, 0.8) ## the lines of the Van Dyke print (the drawing printed in negative: cream on sepia)

static var _paper: ImageTexture
static var _sheets := {} ## key -> ImageTexture

static var _fonts := {}


## "display" (Old Standard bold: titles), "head" (bold: labels in capitals), "caps" (bold, opened up
## a little: capitals at 16 and over), "label" / "text" (regular: small labels, reading), "strong"
## (bold), "italic", "digital" (Courier Prime bold: read-outs, its figures even), "type" /
## "type_bold" (Courier Prime: telegrams, forms), "narrow" (Barlow Condensed, where a column or a
## map really has no room). Ui.face picks among them by the size the words are set at.
static func font(kind := "text") -> Font:
	if not _fonts.has(kind):
		var file: String = {"display": "OldStandard-Bold", "head": "OldStandard-Bold", "caps": "OldStandard-Bold", "label": "OldStandard-Regular",
			"text": "OldStandard-Regular", "strong": "OldStandard-Bold", "italic": "OldStandard-Italic",
			"digital": "CourierPrime-Bold", "type": "CourierPrime-Regular", "type_bold": "CourierPrime-Bold",
			"narrow": "BarlowCondensed-SemiBold"}.get(kind, "OldStandard-Regular")
		var f := load("res://assets/fonts/%s.ttf" % file) as FontFile
		var back := load("res://assets/fonts/Barlow-Medium.ttf") as FontFile
		if f != back and not f.fallbacks.has(back):
			f.fallbacks = [back] # (♥ ▲ ✓ and the arrows: Old Standard and Courier have none)
		if kind == "caps":
			var v := FontVariation.new()
			v.base_font = f
			v.fallbacks = [back]
			v.spacing_glyph = 1 # (capitals, opened up a little, as a printer would)
			_fonts[kind] = v
		else:
			_fonts[kind] = f
	return _fonts[kind]


## The face for `kind` at `size`, as a compositor would set it: capitals are opened up only from 16
## up; under that a bold label is set plain, and under 14 in the regular weight (bold that small
## clots); a title under 16 is just bold.
static func face(kind: String, size: int) -> Font:
	match kind:
		"head", "caps":
			return font("caps") if size >= 16 else (font("strong") if size >= 14 else font("text"))
		"label":
			return font("text")
		"display":
			return font("display") if size >= 16 else font("strong")
	return font(kind)


static func label(parent: Node, text: String, size: int, color := INK, kind := "text") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", face(kind, size))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# light writing gets a dark halo (it reads straight over the world too); ink on paper none
	if color.get_luminance() >= 0.5:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		l.add_theme_constant_override("outline_size", 3)
	if parent:
		parent.add_child(l)
	return l


## Upper case the Turkish way (i -> İ, ı -> I).
static func upper(s: String) -> String:
	return s.replace("i", "İ").replace("ı", "I").to_upper()


## A leaf of leather (a panel: a margin of 8 or more), or a tag tooled into it (a button: a smaller
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


## The clerk's leather, with room `margin` inside its worn edge.
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


# --- the papers ----------------------------------------------------------------------------------

const SHADE := 7 ## px of shadow baked round each sheet

## What each sheet is: its colour, its edge, what's printed or pinned on it, its texture margins
## (left, top, right, bottom) and the room inside.
const SHEETS := {
	"ledger": {"base": Color(0.94, 0.9, 0.8), "edge": "deckle", "mark": "margin", "tex": [92, 26, 26, 26], "pad": [20, 18, 24, 18]},
	"register": {"base": Color(0.87, 0.9, 0.81), "edge": "clean", "mark": "band", "tex": [26, 26, 26, 26], "pad": [24, 20, 24, 20]},
	"slip": {"base": Color(0.93, 0.86, 0.66), "edge": "perf", "mark": "", "tex": [24, 24, 24, 24], "pad": [24, 18, 24, 20]},
	"tape": {"base": Color(0.92, 0.87, 0.72), "edge": "clean", "mark": "", "tex": [12, 12, 12, 12], "pad": [12, 4, 12, 5]},
	"card": {"base": Color(0.96, 0.94, 0.88), "edge": "clean", "mark": "print", "tex": [30, 30, 30, 30], "pad": [34, 28, 34, 26]},
	"file": {"base": Color(0.89, 0.81, 0.63), "edge": "clean", "mark": "", "tex": [22, 22, 22, 22], "pad": [20, 16, 20, 16]},
	"blueprint": {"base": Color(0.4, 0.25, 0.15), "edge": "clean", "mark": "pins", "tex": [30, 30, 30, 30], "pad": [30, 24, 30, 26]},
	"timetable": {"base": Color(0.95, 0.93, 0.86), "edge": "clean", "mark": "print", "tex": [30, 30, 30, 30], "pad": [36, 26, 36, 24]},
	"wood": {"base": Color(0.27, 0.17, 0.1), "edge": "board", "mark": "", "tex": [22, 22, 22, 22], "pad": [18, 18, 18, 18]},
	"enamel": {"base": ENAMEL, "edge": "enamel", "mark": "", "tex": [16, 16, 16, 16], "pad": [18, 14, 18, 12]},
	"brass": {"base": Color(0.69, 0.53, 0.27), "edge": "brass", "mark": "", "tex": [14, 12, 14, 12], "pad": [16, 8, 16, 7]},
}


## A sheet of `kind` (SHEETS) as a panel's style.
static func sheet(kind: String) -> StyleBoxTexture:
	var d: Dictionary = SHEETS[kind]
	var sb := StyleBoxTexture.new()
	sb.texture = _sheet_texture(kind)
	var tm: Array = d.tex
	sb.texture_margin_left = tm[0]
	sb.texture_margin_top = tm[1]
	sb.texture_margin_right = tm[2]
	sb.texture_margin_bottom = tm[3]
	var pad: Array = d.pad
	sb.content_margin_left = pad[0]
	sb.content_margin_top = pad[1]
	sb.content_margin_right = pad[2]
	sb.content_margin_bottom = pad[3]
	return sb


## The sheet's picture, made once: the paper's colour mottled by its fibre and foxed in spots, a
## shade darker toward an edge torn, cut or perforated as its kind is, a shadow under it; and what
## comes printed on it (a ledger's red margin, a card's double rule, a register's green band, the
## brass pins of a drawing on the board).
static func _sheet_texture(kind: String) -> ImageTexture:
	if _sheets.has(kind):
		return _sheets[kind]
	var d: Dictionary = SHEETS[kind]
	var n := 192
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var base: Color = d.base
	var edge_kind: String = d.edge
	var mark: String = d.mark
	var fib := FastNoiseLite.new()
	fib.seed = 21
	fib.frequency = 0.05
	fib.fractal_octaves = 4
	var fox := FastNoiseLite.new()
	fox.seed = 5 + kind.length()
	fox.frequency = 0.03
	var rag := FastNoiseLite.new()
	rag.seed = 9
	rag.frequency = 0.22
	var grain := FastNoiseLite.new() # (the board's grain: long along x)
	grain.seed = 17
	grain.frequency = 0.04
	var s := float(SHADE)
	for y in n:
		for x in n:
			var ex := minf(x, n - 1 - x)
			var ey := minf(y, n - 1 - y)
			var edge := minf(ex, ey)
			var rim := s
			match edge_kind:
				"deckle":
					rim = s + 1.2 + rag.get_noise_2d(x * 1.3 + y * 0.7, y * 1.3 - x * 0.5) * 1.6
				"perf": # (torn off a pad along the top: little bites)
					if ey == y and y < s + 4.0:
						rim = s + (2.0 if int(x) % 7 < 3 else 0.0)
				"enamel", "brass", "board":
					var cr := 6.0 if edge_kind == "enamel" else (3.0 if edge_kind == "brass" else 4.0)
					var cx := maxf(s + cr - ex, 0.0)
					var cy := maxf(s + cr - ey, 0.0)
					if cx > 0.0 and cy > 0.0:
						rim = s + cr - (cr - Vector2(cx, cy).length()) # (a rounded corner)
			if edge < rim:
				# the shadow under the sheet, soft, a little lower than it
				var dy := float(n - 1 - y) - float(y)
				var lift := clampf((edge - (rim - s)) / s, 0.0, 1.0)
				var a := lift * lift * (0.38 if dy < 0.0 else 0.22)
				img.set_pixel(x, y, Color(0.03, 0.02, 0.01, a))
				continue
			var inner := edge - rim
			var c := base
			match edge_kind:
				"board":
					var g := grain.get_noise_2d(x * 0.35, y * 4.0)
					c = base * (0.9 + g * 0.25)
					c = c.darkened(clampf(1.0 - inner / 10.0, 0.0, 1.0) * 0.35)
					if absf(inner - 9.0) < 0.6:
						c = c.darkened(0.3) # (the frame's mitre line)
				"enamel":
					c = base * (0.97 + fib.get_noise_2d(x * 3.0, y * 3.0) * 0.04)
					if absf(inner - 5.5) < 0.8:
						c = Color(0.4, 0.23, 0.12) # (the brown line round the sign)
					if inner < 2.5:
						c = c.darkened(0.18) # (the rolled rim)
					if inner < 2.5 and fox.get_noise_2d(x * 2.0, y * 2.0) > 0.6:
						c = Color(0.24, 0.17, 0.12) # (a chip or two, to the iron)
				"brass":
					var brush := fib.get_noise_2d(x * 0.2, y * 6.0)
					c = base * (0.95 + brush * 0.12)
					c = c.lightened(clampf(1.0 - y / float(n) * 2.0, 0.0, 1.0) * 0.12) # (lit from above)
					c = c.darkened(clampf(1.0 - inner / 2.5, 0.0, 1.0) * 0.4)
				_:
					var f := fib.get_noise_2d(x, y)
					c = base * (0.97 + f * 0.05)
					var spot := fox.get_noise_2d(x * 1.7, y * 1.7)
					if spot > 0.35 and kind != "blueprint":
						c = c.lerp(Color(0.72, 0.56, 0.36), (spot - 0.35) * 0.5) # (foxing)
					c = c.darkened(clampf(1.0 - inner / 14.0, 0.0, 1.0) * (0.12 if kind != "blueprint" else 0.25)) # (handled at the edges)
			# what's printed on it
			match mark:
				"margin":
					if absf(x - (s + 70.0)) < 0.8 or absf(x - (s + 74.0)) < 0.8:
						c = c.lerp(P_RED, 0.75)
				"print":
					if absf(inner - 9.0) < 1.1 or absf(inner - 12.5) < 0.55:
						c = c.lerp(P_INK, 0.85)
				"band":
					if absf(inner - 8.0) < 0.6:
						c = c.lerp(P_GREEN, 0.6)
				"pins":
					for corner in [Vector2(s + 13, s + 13), Vector2(n - s - 14, s + 13), Vector2(s + 13, n - s - 14), Vector2(n - s - 14, n - s - 14)]:
						var dd := Vector2(x, y).distance_to(corner)
						if dd < 7.5:
							c = c.lerp(Color(0, 0, 0), 0.35 * (1.0 - dd / 7.5)) # (its shadow)
						var dp := Vector2(x, y).distance_to(corner - Vector2(1.5, 1.5))
						if dp < 5.5:
							c = Color(0.82, 0.64, 0.3).darkened(dp / 5.5 * 0.4).lightened(0.4 if dp < 1.6 else 0.0)
			c.a = clampf(inner + 1.0, 0.0, 1.0)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_sheets[kind] = tex
	return tex


# --- writing and marks on paper ------------------------------------------------------------------

## A button drawn on paper: its word in `ink`, a thin ruled box round it, washed with the ink when
## the mouse is on it. On the enamel and the blueprint the ink is light.
static func ink_button(b: Button, ink := P_INK, size := 14, kind := "head") -> Button:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", face(kind, size))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_constant_override("outline_size", 0)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, ink)
	b.add_theme_color_override("font_disabled_color", Color(ink, 0.38))
	b.add_theme_stylebox_override("normal", ink_box(ink, 0.0, 0.55))
	b.add_theme_stylebox_override("hover", ink_box(ink, 0.1, 0.95))
	b.add_theme_stylebox_override("pressed", ink_box(ink, 0.2, 1.0))
	b.add_theme_stylebox_override("hover_pressed", ink_box(ink, 0.2, 1.0))
	b.add_theme_stylebox_override("disabled", ink_box(ink, 0.0, 0.2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## The ruled box of a button on paper (`wash` its fill, `line` its border's strength; `on`: chosen,
## its line doubled).
static func ink_box(ink := P_INK, wash := 0.0, line := 0.55, on := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ink, wash if not on else 0.16)
	sb.border_color = Color(ink, line if not on else 1.0)
	sb.set_border_width_all(2 if on else 1)
	sb.set_corner_radius_all(1)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


## Every button under `node` redrawn for paper (a card's, a form's).
static func inkify(node: Node, ink := P_INK) -> void:
	for n: Node in node.find_children("*", "Button", true, false):
		var b := n as Button
		var own := ink
		if b.has_theme_color_override("font_color") and b.get_theme_color("font_color").get_luminance() < 0.5:
			own = b.get_theme_color("font_color") # (a button already inked its own colour keeps it: İDAM in red)
		ink_button(b, own, mini(b.get_theme_font_size("font_size"), 14) if b.has_theme_font_size_override("font_size") else 14)


## A key, as printed in a manual: the letter in a little bordered box with its foot darker.
static func keycap(parent: Node, text: String, size := 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.99, 0.95)
	sb.border_color = P_INK
	sb.set_border_width_all(1)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := label(p, text, size, P_INK, "type_bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(p)
	return p


## A printed rule across: thick over thin, as under a title in a gazette.
static func double_rule(parent: Node, color := P_INK) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for h: int in [2, 1]:
		var r := ColorRect.new()
		r.color = color
		r.custom_minimum_size = Vector2(0, h)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(r)
	parent.add_child(box)
	return box


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


## A rubber stamp struck a little crooked: a double ring, its office's name round the top and the
## bottom, the day across the middle, the ink thin in places.
class Stamp extends Control:
	var ring := "" ## round the ring
	var middle := "" ## across it
	var ink := Color(0.45, 0.2, 0.45, 0.78) ## (aniline violet, the telegraph office's)
	var tilt := -0.18

	func _init(ring_text := "", middle_text := "", angle := -0.18) -> void:
		ring = ring_text
		middle = middle_text
		tilt = angle
		custom_minimum_size = Vector2(96, 96)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		draw_set_transform(c, tilt)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, ink, 2.2, true)
		draw_arc(Vector2.ZERO, r - 4.0, 0.0, TAU, 64, ink, 1.0, true)
		draw_arc(Vector2.ZERO, r * 0.56, 0.0, TAU, 48, ink, 1.0, true)
		var f := Ui.font("type_bold")
		var fs := 9
		# the name round the ring, its letters set along the arc
		var chars := ring.length()
		if chars > 0:
			var span := minf(PI * 1.5, chars * 0.2)
			for i in chars:
				var a := -PI * 0.5 - span * 0.5 + span * (i + 0.5) / chars
				var p := Vector2(cos(a), sin(a)) * (r - 12.0)
				draw_set_transform(c + p.rotated(tilt), a + PI * 0.5 + tilt)
				var ch := ring.substr(i, 1)
				var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(f, Vector2(-w * 0.5, fs * 0.35), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		draw_set_transform(c, tilt)
		var lines := middle.split("\n")
		for i in lines.size():
			var w := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1).x
			draw_string(f, Vector2(-w * 0.5, (i - (lines.size() - 1) * 0.5) * 11.0 + 4.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 1, ink)
		# where the stamp didn't take: the paper showing through
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(ring + middle)
		for k in 26:
			var a := rng.randf() * TAU
			var d := rng.randf_range(r * 0.2, r)
			draw_circle(Vector2(cos(a), sin(a)) * d, rng.randf_range(0.6, 1.8), Color(0.93, 0.86, 0.66, 0.7))
		draw_set_transform(Vector2.ZERO, 0.0)
