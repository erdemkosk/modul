class_name CombatOverlay
extends Control
## Drawn over the world under the HUD's panels:
##   being hurt   the screen's edges go red for a moment, deeper the harder the hit (and a slow red
##                pulse while your cab's low); a red wedge round the middle points to where it came
##                from, fading
##   the enemy    over each of the other side's machines its name and how far, and a bar of what's
##                left of it; one that's off the screen is an arrow at the edge pointing to it

var game: Node
var _pain := 0.0
var _marks: Array[Dictionary] = [] ## {from, t}
var _bound: Machine
var _veil: TextureRect
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.75, 0.02, 0.0, 0.9))
	g.add_point(0.62, Color(0.6, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	_veil = TextureRect.new()
	_veil.texture = tex
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.stretch_mode = TextureRect.STRETCH_SCALE
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.modulate.a = 0.0
	add_child(_veil)


func _hurt(amount: float, from: Vector3, kind: String) -> void:
	var m := _bound
	if not is_instance_valid(m):
		return
	_pain = minf(_pain + clampf(amount / 140.0, 0.08, 0.6), 0.9)
	if kind != "çarpışma" or amount > 30.0:
		_marks.append({"from": from, "t": 1.4})
		while _marks.size() > 6:
			_marks.pop_front()


func _process(dt: float) -> void:
	_t += dt
	position = Vector2.ZERO
	size = get_viewport_rect().size # (over the whole screen, whatever it's been laid out to)
	var mv: Variant = game.get("machine")
	var m: Machine = mv if is_instance_valid(mv) else null
	if m != _bound:
		if is_instance_valid(_bound) and _bound.damaged.is_connected(_hurt):
			_bound.damaged.disconnect(_hurt)
		_bound = m
		_marks.clear()
		if m:
			m.damaged.connect(_hurt)
	_pain = maxf(_pain - dt * 1.2, 0.0)
	var low := 0.0
	if m and m.cab_frac() < 0.4:
		low = (0.15 + 0.1 * sin(_t * 4.0)) * (1.0 - m.cab_frac() / 0.4)
	_veil.modulate.a = maxf(_pain, low)
	for k in range(_marks.size() - 1, -1, -1):
		_marks[k].t = float(_marks[k].t) - dt
		if float(_marks[k].t) <= 0.0:
			_marks.remove_at(k)
	queue_redraw()


func _draw() -> void:
	var cam := game.get("cam") as Camera3D
	if cam == null or not is_instance_valid(_bound):
		return
	var screen := get_viewport_rect().size # (the screen's, whatever this control's been laid out to)
	var c := screen * 0.5
	# where the hurt came from: a wedge round the middle
	for mk: Dictionary in _marks:
		var v := cam.global_basis.inverse() * ((mk.from as Vector3) - cam.global_position)
		var a := atan2(v.x, -v.z) - PI * 0.5 # (0 straight ahead: up the screen)
		var alpha := clampf(float(mk.t) / 0.5, 0.0, 1.0)
		var r := 150.0
		var col := Color(1.0, 0.2, 0.12, 0.85 * alpha)
		draw_arc(c, r, a - 0.32, a + 0.32, 20, Color(0, 0, 0, 0.4 * alpha), 12.0, true)
		draw_arc(c, r, a - 0.3, a + 0.3, 20, col, 8.0, true)
		var tip := c + Vector2.from_angle(a) * (r + 18.0)
		var side := Vector2.from_angle(a + PI * 0.5) * 9.0
		draw_colored_polygon(PackedVector2Array([tip, c + Vector2.from_angle(a) * (r + 6.0) + side,
			c + Vector2.from_angle(a) * (r + 6.0) - side]), col)
	# the enemy
	var font := Ui.font("head")
	var me := _bound.global_position
	for n in get_tree().get_nodes_in_group("machines"):
		var e := n as Machine
		if e == _bound or not is_instance_valid(e) or not e.alive or e.team == _bound.team:
			continue
		var top := e.global_transform * Vector3(e.com.x, e.top_y + 1.0, e.com.z)
		var dist := me.distance_to(e.global_position)
		var on_screen := not cam.is_position_behind(top)
		var s := cam.unproject_position(top) if on_screen else Vector2.ZERO
		var inside := on_screen and Rect2(Vector2(40, 40), screen - Vector2(80, 80)).has_point(s)
		var h := e.health()
		var hc := Ui.BAD if h < 0.35 else Ui.ACCENT
		if inside:
			var w := 74.0
			var name := "%s  %d m" % [e.label, int(dist)]
			var ts := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			draw_string_outline(font, s + Vector2(-ts.x * 0.5, -10.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.6))
			draw_string(font, s + Vector2(-ts.x * 0.5, -10.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.INK)
			draw_rect(Rect2(s + Vector2(-w * 0.5 - 1.0, -1.0), Vector2(w + 2.0, 7.0)), Color(0, 0, 0, 0.5))
			Ui.segments(self, Rect2(s + Vector2(-w * 0.5, 0.0), Vector2(w, 5.0)), 10, h, hc, Color(1, 1, 1, 0.15), 0.6)
		else:
			# off the screen: an arrow at its edge toward it
			var v := cam.global_basis.inverse() * (e.global_position - cam.global_position)
			var dir := Vector2(v.x, -v.y)
			if v.z > 0.0: # (behind you: low on the side it's on)
				dir = Vector2(v.x if absf(v.x) > 0.01 else 0.01, absf(v.x) * 0.6 + 0.2)
			dir = dir.normalized()
			var edge := c + dir * minf((screen.x * 0.5 - 50.0) / maxf(absf(dir.x), 0.01), (screen.y * 0.5 - 50.0) / maxf(absf(dir.y), 0.01))
			var a := dir.angle()
			var p := PackedVector2Array([edge + Vector2.from_angle(a) * 14.0, edge + Vector2.from_angle(a + 2.4) * 10.0,
				edge + Vector2.from_angle(a - 2.4) * 10.0])
			draw_colored_polygon(p, Color(0, 0, 0, 0.5))
			draw_colored_polygon(p, hc)
			var txt := "%d m" % int(dist)
			draw_string(font, edge - dir * 22.0 + Vector2(-12.0, 4.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK)
