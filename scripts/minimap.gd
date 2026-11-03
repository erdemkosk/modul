class_name Minimap
extends Control
## The valley round the town, small, in the corner: the lake and the river, the line, the buildings,
## the townsfolk as dots, and what's coming (outlaws and soldiers red, a camp found, a convoy or an
## armoured train), the camera's spot ringed. A click takes the view there.

const SIZE := 170.0
const REACH := 270.0 ## m from the store to the map's edge

var game: Node
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	RenderingServer.canvas_item_set_clip(get_canvas_item(), true) # (what's off the map cut at its edge)
	tooltip_text = "Küçük harita: tıkla, kamera oraya gitsin"


func _process(dt: float) -> void:
	_t += dt
	if _t >= 0.25:
		_t = 0.0
		queue_redraw()


func _home() -> Vector3:
	var st: Array = game.village.stores()
	return (st[0] as Node3D).global_position if not st.is_empty() else Vector3.ZERO


func _to_map(p: Vector3, home: Vector3) -> Vector2:
	return Vector2(SIZE, SIZE) * 0.5 + Vector2(p.x - home.x, p.z - home.z) / REACH * SIZE * 0.5


## A point on the map, pulled in to its edge if it's off it (what's beyond shown at the rim).
func _at(p: Vector3, home: Vector3) -> Vector2:
	return _to_map(p, home).clamp(Vector2(3, 3), Vector2(SIZE - 3, SIZE - 3))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var home := _home()
		var q := ((e as InputEventMouseButton).position - Vector2(SIZE, SIZE) * 0.5) / (SIZE * 0.5) * REACH
		var p := Vector3(home.x + q.x, 0, home.z + q.y)
		p.y = game.village.nav.height(p.x, p.z)
		game.cam.jump_to(p)
		accept_event()


func _draw() -> void:
	var v: Village = game.village
	if v == null:
		return
	var home := _home()
	var c := Vector2(SIZE, SIZE) * 0.5
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(0.11, 0.16, 0.1, 0.92))
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(Ui.EDGE, 0.9), false, 1.5)
	var terrain: WorldTerrain = v.terrain
	var water := Color(0.25, 0.42, 0.55)
	# the lake, the river
	var lake: Dictionary = terrain.meta.lake
	var lc := _to_map(Vector3(float(lake.x), 0, float(lake.z)), home)
	var pts := PackedVector2Array()
	for k in 33:
		var a := TAU * k / 32.0
		pts.append(lc + Vector2(cos(a) * float(lake.rx), sin(a) * float(lake.rz)) / REACH * SIZE * 0.5)
	var frame := PackedVector2Array([Vector2.ZERO, Vector2(SIZE, 0), Vector2(SIZE, SIZE), Vector2(0, SIZE)])
	for poly in Geometry2D.intersect_polygons(pts, frame):
		draw_colored_polygon(poly, water)
	var river := PackedVector2Array()
	for rp: Array in terrain.meta.river.points:
		river.append(_to_map(Vector3(float(rp[0]), 0, float(rp[2])), home))
	for part in Geometry2D.intersect_polyline_with_polygon(river, frame):
		if part.size() > 1:
			draw_polyline(part, water, 2.0, true)
	# the line
	if v.rail.size() > 1:
		var line := PackedVector2Array()
		for k in range(0, v.rail.size(), 8):
			line.append(_to_map(v.rail[k], home))
		for part in Geometry2D.intersect_polyline_with_polygon(line, frame):
			if part.size() > 1:
				draw_polyline(part, Color(0.62, 0.55, 0.45), 1.6, true)
	# trenches, the buildings
	for t: Dictionary in v.trenches:
		draw_line(_to_map(Vector3(t.a.x, 0, t.a.y), home), _to_map(Vector3(t.b.x, 0, t.b.y), home), Color(0.4, 0.3, 0.2), 1.5)
	for b in v.buildings:
		if b.state == "gone":
			continue
		var bp := _to_map(b.global_position, home)
		var sz: Vector2 = b.def.size
		var s := maxf(sz.x, sz.y) / REACH * SIZE * 0.5 + 1.0
		var col := Color(0.86, 0.8, 0.66) if b.state == "done" else Color(0.6, 0.56, 0.48)
		if b.is_burning():
			col = Color(1.0, 0.45, 0.1)
		draw_rect(Rect2(bp - Vector2(s, s) * 0.5, Vector2(s, s)), col)
	# the townsfolk
	for o in v.villagers:
		if not o.dead:
			draw_circle(_at(o.position, home), 1.3, Color(0.95, 0.95, 0.9) if not o.drafted else Color(0.45, 0.85, 1.0))
	var rd: Raids = game.raids
	for a in rd.allies:
		if is_instance_valid(a) and not a.dead:
			draw_circle(_at(a.position, home), 1.5, Color(0.45, 0.85, 1.0))
	# what's coming
	for list: Array in [rd.raiders, rd.camp_men if rd.camp_known else []]:
		for r in list:
			if is_instance_valid(r) and not r.dead:
				draw_circle(_at(r.position, home), 1.8, Color(1.0, 0.25, 0.2))
	if rd.camp_known and rd.camp_at != Vector3.INF:
		var cp := _at(rd.camp_at, home)
		draw_arc(cp, 5.0, 0, TAU, 12, Color(1.0, 0.25, 0.2), 1.5)
	for cv: Variant in [v.convoy, v.relief]:
		if is_instance_valid(cv) and not (cv as Convoy)._cars.is_empty():
			var p := _at(((cv as Convoy)._cars[0].node as Node3D).global_position, home)
			var friend: bool = (cv as Convoy).ally
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(3.5, 3), p + Vector2(-3.5, 3)]), Color(0.45, 0.85, 1.0) if friend else Color(1.0, 0.6, 0.15))
	if is_instance_valid(v.armoured):
		var ap := _at(v.armoured.engine_at(), home)
		draw_rect(Rect2(ap - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.6, 0.15))
	# the camera's spot
	var f := _at(game.cam.focus, home)
	draw_arc(f, 7.0, 0, TAU, 16, Color(1, 1, 1, 0.8), 1.2)
	Ui.font("head")
	draw_string(Ui.font("head"), Vector2(6, 14), "HARİTA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ui.INK, 0.7))
