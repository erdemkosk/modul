class_name Minimap
extends Control
## The valley round the town as an old survey map, in the corner: yellowed paper, the woods stippled
## in green-black ink, the water washed in faded blue with ink edges, the line drawn as a railway is
## on a map (a heavy line, ticks across it), the buildings inked in, a compass rose. Over it what
## moves: the townsfolk as little dots, what's coming in red (outlaws, soldiers, a camp found), a
## convoy or an armoured train, the camera's spot circled in pencil. A click takes the view there.
## The paper (ground, woods, water) is drawn once; what's on it every quarter second.

const SIZE := 170.0
const REACH := 270.0 ## m from the store to the map's edge
const PAPER := Color(0.80, 0.72, 0.55)
const INK := Color(0.16, 0.12, 0.08)
const WOOD_INK := Color(0.22, 0.28, 0.16)
const WATER := Color(0.42, 0.55, 0.6)
const RED := Color(0.62, 0.1, 0.06)
const OURS := Color(0.12, 0.2, 0.45)

var game: Node
var _t := 0.0
var _paper: ImageTexture
var _home := Vector3.INF


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Harita: tıkla, kamera oraya gitsin"


func _process(dt: float) -> void:
	_t += dt
	if _t >= 0.25:
		_t = 0.0
		queue_redraw()


func _store_at() -> Vector3:
	var st: Array = game.village.stores()
	return (st[0] as Node3D).global_position if not st.is_empty() else Vector3.ZERO


func _to_map(p: Vector3) -> Vector2:
	return Vector2(SIZE, SIZE) * 0.5 + Vector2(p.x - _home.x, p.z - _home.z) / REACH * SIZE * 0.5


## A point on the map, pulled in to its edge if it's off it.
func _at(p: Vector3) -> Vector2:
	return _to_map(p).clamp(Vector2(4, 4), Vector2(SIZE - 4, SIZE - 4))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var q := ((e as InputEventMouseButton).position - Vector2(SIZE, SIZE) * 0.5) / (SIZE * 0.5) * REACH
		var p := Vector3(_home.x + q.x, 0, _home.z + q.y)
		p.y = game.village.nav.height(p.x, p.z)
		game.cam.jump_to(p)
		accept_event()


## The paper drawn once: its yellow, foxed and darker toward the edges; the slopes shaded and the
## contours drawn faint; the water a faded wash with an inked shore; the woods stippled where the
## trees stand.
func _bake() -> void:
	var v: Village = game.village
	var terrain: WorldTerrain = v.terrain
	var n := int(SIZE)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1918
	var lvl := terrain.lake_level
	var h := PackedFloat32Array()
	h.resize(n * n)
	for y in n:
		for x in n:
			var q := (Vector2(x, y) - Vector2(SIZE, SIZE) * 0.5) / (SIZE * 0.5) * REACH
			h[y * n + x] = terrain.height_at(_home.x + q.x, _home.z + q.y)
	for y in n:
		for x in n:
			var c := PAPER
			var edge := minf(minf(x, y), minf(n - 1 - x, n - 1 - y)) / 14.0
			c = c.darkened(0.12 * (1.0 - clampf(edge, 0.0, 1.0)) + rng.randf() * 0.035)
			var here := h[y * n + x]
			var wet := here < lvl + 0.15
			var dx := h[y * n + mini(x + 1, n - 1)] - h[y * n + maxi(x - 1, 0)]
			var dy := h[mini(y + 1, n - 1) * n + x] - h[maxi(y - 1, 0) * n + x]
			var shade := clampf((dx + dy) * 0.08, -0.12, 0.18)
			if not wet:
				c = c.darkened(maxf(shade, 0.0)) if (x + y) % 2 == 0 or shade < 0.08 else c.darkened(shade + 0.08)
				if int(here / 6.0) != int(h[y * n + mini(x + 1, n - 1)] / 6.0):
					c = c.lerp(Color(0.5, 0.36, 0.22), 0.35) # (a contour every 6 m)
			else:
				c = c.lerp(WATER, 0.7)
				var shore := false
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var xx := clampi(x + o.x, 0, n - 1)
					var yy := clampi(y + o.y, 0, n - 1)
					if h[yy * n + xx] >= lvl + 0.15:
						shore = true
				if shore:
					c = c.lerp(INK, 0.6)
				elif (x * 3 + y) % 7 == 0:
					c = c.lerp(Color(0.3, 0.42, 0.48), 0.4)
			img.set_pixel(x, y, c)
	# the river, washed and edged
	var pts: Array = terrain.meta.river.points
	for k in range(pts.size() - 1):
		var a := _to_map(Vector3(float(pts[k][0]), 0, float(pts[k][2])))
		var b := _to_map(Vector3(float(pts[k + 1][0]), 0, float(pts[k + 1][2])))
		var steps := int(a.distance_to(b) * 2.0) + 1
		for s in steps:
			var p := a.lerp(b, float(s) / steps)
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var xx := int(p.x) + ox
					var yy := int(p.y) + oy
					if xx < 0 or yy < 0 or xx >= n or yy >= n:
						continue
					var r := Vector2(ox, oy).length()
					if r <= 1.6:
						img.set_pixel(xx, yy, img.get_pixel(xx, yy).lerp(WATER, 0.85))
					elif r <= 2.3:
						img.set_pixel(xx, yy, img.get_pixel(xx, yy).lerp(Color(0.2, 0.3, 0.36), 0.25))
	# the woods: a stipple of ink where the trees stand
	for i in v._props_in(_home, REACH * 1.42):
		var info: Dictionary = v.props.prop_info(i)
		if str(info.kind) != "tree":
			continue
		var p := _to_map(info.origin)
		var xx := int(p.x)
		var yy := int(p.y)
		if xx < 1 or yy < 1 or xx >= n - 1 or yy >= n - 1:
			continue
		img.set_pixel(xx, yy, img.get_pixel(xx, yy).lerp(WOOD_INK, 0.75))
		if rng.randf() < 0.5:
			img.set_pixel(xx, yy - 1, img.get_pixel(xx, yy - 1).lerp(WOOD_INK, 0.4))
	_paper = ImageTexture.create_from_image(img)


func _draw() -> void:
	var v: Village = game.village
	if v == null:
		return
	if _paper == null:
		_home = _store_at()
		_bake()
	var frame := PackedVector2Array([Vector2.ZERO, Vector2(SIZE, 0), Vector2(SIZE, SIZE), Vector2(0, SIZE)])
	draw_texture(_paper, Vector2.ZERO)
	# the line: a heavy ink line with ticks across it, as railways are drawn
	if v.rail.size() > 1:
		var line := PackedVector2Array()
		for k in range(0, v.rail.size(), 6):
			line.append(_to_map(v.rail[k]))
		for part in Geometry2D.intersect_polyline_with_polygon(line, frame):
			if part.size() < 2:
				continue
			draw_polyline(part, INK, 2.2, true)
			var acc := 0.0
			for k in range(1, part.size()):
				var a: Vector2 = part[k - 1]
				var b: Vector2 = part[k]
				acc += a.distance_to(b)
				if acc > 5.0:
					acc = 0.0
					var across := (b - a).normalized().orthogonal() * 2.6
					draw_line(b - across, b + across, INK, 1.0, true)
	for t: Dictionary in v.trenches:
		draw_line(_to_map(Vector3(t.a.x, 0, t.a.y)), _to_map(Vector3(t.b.x, 0, t.b.y)), Color(0.4, 0.26, 0.14), 1.6, true)
	# the buildings, inked (red ink when they burn)
	for b in v.buildings:
		if b.state == "gone":
			continue
		var bp := _to_map(b.global_position)
		if bp.x < 0 or bp.y < 0 or bp.x > SIZE or bp.y > SIZE:
			continue
		var sz: Vector2 = b.def.size
		var s := Vector2(sz.x, sz.y) / REACH * SIZE * 0.5 + Vector2(1.2, 1.2)
		var col := INK if b.state == "done" else Color(INK, 0.45)
		if b.is_burning():
			col = RED
		draw_rect(Rect2(bp - s * 0.5, s), col)
	# the townsfolk in blue ink, and those on our side
	for o in v.villagers:
		if not o.dead:
			draw_circle(_at(o.position), 1.1, OURS if not o.drafted else Color(0.15, 0.3, 0.7))
	var rd: Raids = game.raids
	for a in rd.allies:
		if is_instance_valid(a) and not a.dead:
			draw_circle(_at(a.position), 1.4, OURS)
	# what's coming, crossed in red ink
	for list: Array in [rd.raiders, rd.camp_men if rd.camp_known else []]:
		for r in list:
			if is_instance_valid(r) and not r.dead:
				var p := _at(r.position)
				draw_line(p - Vector2(2, 2), p + Vector2(2, 2), RED, 1.4, true)
				draw_line(p - Vector2(2, -2), p + Vector2(2, -2), RED, 1.4, true)
	if rd.camp_known and rd.camp_at != Vector3.INF:
		var cp := _at(rd.camp_at)
		var tri := PackedVector2Array([cp + Vector2(0, -5), cp + Vector2(4.5, 3), cp + Vector2(-4.5, 3)])
		draw_colored_polygon(tri, Color(RED, 0.25))
		tri.append(tri[0])
		draw_polyline(tri, RED, 1.2, true)
	for cv: Variant in [v.convoy, v.relief]:
		if is_instance_valid(cv) and not (cv as Convoy)._cars.is_empty():
			var p := _at(((cv as Convoy)._cars[0].node as Node3D).global_position)
			var col := OURS if (cv as Convoy).ally else RED
			draw_rect(Rect2(p - Vector2(4, 2.5), Vector2(8, 5)), col, false, 1.4)
	if is_instance_valid(v.armoured):
		var ap := _at(v.armoured.engine_at())
		draw_rect(Rect2(ap - Vector2(4, 4), Vector2(8, 8)), RED)
	# the camera's spot, circled in pencil
	draw_arc(_at(game.cam.focus), 7.0, 0, TAU, 20, Color(0.25, 0.22, 0.2, 0.8), 1.0, true)
	# a compass rose, top right: the north point inked, the rest outlined
	var cr := Vector2(SIZE - 16, 20)
	draw_colored_polygon(PackedVector2Array([cr + Vector2(0, -11), cr + Vector2(3, 0), cr + Vector2(-3, 0)]), INK)
	draw_polyline(PackedVector2Array([cr + Vector2(0, 11), cr + Vector2(3, 0), cr + Vector2(-3, 0), cr + Vector2(0, 11)]), INK, 1.0, true)
	draw_polyline(PackedVector2Array([cr + Vector2(-9, 0), cr + Vector2(0, -2.5), cr + Vector2(9, 0), cr + Vector2(0, 2.5), cr + Vector2(-9, 0)]), INK, 0.8, true)
	draw_string(Ui.font("head"), cr + Vector2(-3.5, -13), "K", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, INK)
	# the title in a cartouche, and a scale bar
	draw_rect(Rect2(Vector2(5, 5), Vector2(74, 14)), Color(PAPER, 0.92))
	draw_rect(Rect2(Vector2(5, 5), Vector2(74, 14)), INK, false, 0.8)
	draw_string(Ui.font("head"), Vector2(9, 16), "KORDAL · HARİTA", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, INK)
	var px100 := 100.0 / REACH * SIZE * 0.5
	var sb := Vector2(8, SIZE - 9)
	draw_line(sb, sb + Vector2(px100, 0), INK, 1.4)
	for k in 3:
		draw_line(sb + Vector2(px100 * k / 2.0, -2), sb + Vector2(px100 * k / 2.0, 2), INK, 1.0)
	draw_string(Ui.font("head"), sb + Vector2(px100 + 3, 3), "100 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, INK)
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), INK, false, 1.5)
