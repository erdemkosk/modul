class_name CombatOverlay
extends Control
## Drawn over the world under the HUD's panels:
##   being hurt   the screen's edges go red for a moment, deeper the harder the hit (and a slow red
##                pulse while your cab's low); a red wedge round the middle points to where it came
##                from, fading
##   the enemy    over each of the other side's machines its name and how far, and a bar of what's
##                left of it; one that's off the screen is an arrow at the edge pointing to it
##   your hits    each part you hurt says so where it was hit: the damage and the part's name rising
##                off it (a part that comes off, or a system that gives — a tyre bursting, an engine
##                weakening — bigger and in red); and at the top right the machine you last hit, from
##                above, each part shaded by what's left of it, the one you just hit flashing

var game: Node
var _pain := 0.0
var _marks: Array[Dictionary] = [] ## {from, t}
var _bound: Machine
var _veil: TextureRect
var _t := 0.0
var _pops: Array[Dictionary] = [] ## {at: Vector3, text, col, size, t, key}
var _target: Machine
var _target_t := 0.0
var _first := {} ## machine id -> its parts when you first hit it
var _target_key := ""
var _wired := false


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


## Combat's word of a part hit: if it's yours that hit it, a number rises off it.
func _part_hit(victim: Machine, id: String, at: Vector3, amount: float, by: Machine, broke: bool) -> void:
	if not is_instance_valid(_bound) or by != _bound or victim == _bound:
		return
	var name := Ui.upper(str(Parts.def(id).name))
	var key := "%d:%s" % [victim.get_instance_id(), id]
	_target = victim
	_target_t = 5.0
	if not _first.has(victim.get_instance_id()):
		_first[victim.get_instance_id()] = victim.design.duplicate(true) # (as it was: what goes is shown gone)
	_target_key = id
	if broke:
		# parts coming off together (a shell takes several): one line saying how many
		var bkey := "broke:%d" % victim.get_instance_id()
		for p: Dictionary in _pops:
			if p.key == bkey and float(p.t) > 0.7:
				var names: Dictionary = p.names
				names[name] = int(names.get(name, 0)) + 1
				var total := 0
				for v: int in names.values():
					total += v
				p.text = ("%s ×%d KOPTU!" % [name, total]) if names.size() == 1 else "%d PARÇA KOPTU!" % total
				p.t = 1.4
				return
		_pop(at, "%s KOPTU!" % name, Ui.BAD, 22, bkey)
		_pops.back().names = {name: 1}
		return
	# the same part hit again quickly (a minigun's stream): one number adding up
	for p: Dictionary in _pops:
		if p.key == key and float(p.t) > 0.45:
			p.n = float(p.n) + amount
			p.text = "−%d  %s" % [int(p.n), name]
			p.t = 1.0
			p.at = at
			return
	_pops.append({"at": at, "text": "−%d  %s" % [int(amount), name], "col": Ui.INK, "size": 15, "t": 1.0, "key": key, "n": amount})


func _pop(at: Vector3, text: String, col: Color, size: int, key: String) -> void:
	_pops.append({"at": at, "text": text, "col": col, "size": size, "t": 1.4, "key": key, "n": 0.0, "big": true})
	while _pops.size() > 24:
		_pops.pop_front()


## A system that gave on a machine you hit (a tyre burst, ...): said big where it happened (once:
## said again while it's still up, it's only freshened).
func _their_system(text: String, at: Vector3, victim: Machine) -> void:
	if not is_instance_valid(_bound) or not is_instance_valid(victim) or victim.last_hit_by != _bound:
		return
	var key := "sys:%d:%s" % [victim.get_instance_id(), text]
	for p: Dictionary in _pops:
		if p.key == key:
			p.t = 1.4
			return
	_pop(at + Vector3.UP * 0.6, text + "!", Ui.ACCENT, 20, key)


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
	if not _wired and Combat.current:
		_wired = true
		Combat.current.part_hit.connect(_part_hit)
	# the other side's systems giving (wired as they come)
	for n in get_tree().get_nodes_in_group("machines"):
		var e := n as Machine
		if e != m and not e.has_meta("ov_wired"):
			e.set_meta("ov_wired", true)
			e.system_hit.connect(_their_system.bind(e))
	for k in range(_pops.size() - 1, -1, -1):
		_pops[k].t = float(_pops[k].t) - dt
		if float(_pops[k].t) <= 0.0:
			_pops.remove_at(k)
	_target_t -= dt
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


## The machine you last hit: its name and what's left of it, its parts from above (as it was when you
## first hit it: what's come off since is an outline in red), shaded by their hit points, the cab ringed
## and the guns dotted, the one you just hit flashing.
func _draw_target(r: Rect2, font: Font) -> void:
	var m := _target
	var a := clampf(_target_t, 0.0, 1.0)
	var sb := Ui.glass(false, 8.0)
	draw_style_box(sb, Rect2(r.position, Vector2(r.size.x, r.size.y + 30.0)))
	draw_string(font, r.position + Vector2(12.0, 22.0), "HEDEF  ·  %s" % m.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Ui.ACCENT, a))
	draw_string(font, r.position + Vector2(r.size.x - 52.0, 22.0), "%%%d" % int(m.health() * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Ui.INK, a))
	var area := Rect2(r.position + Vector2(14.0, 34.0), r.size - Vector2(28.0, 10.0))
	var first: Array = _first.get(m.get_instance_id(), m.design)
	if first.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p: Dictionary in first:
		var s := Parts.size_of(p.id, p.rot)
		lo = lo.min(Vector2(p.at.x, p.at.z))
		hi = hi.max(Vector2(p.at.x + s.x, p.at.z + s.z))
	var span := hi - lo
	var k := minf(area.size.x / span.x, area.size.y / span.y)
	var off := area.position + (area.size - span * k) * 0.5
	# the grid it's built on, faint
	for x in int(span.x) + 1:
		draw_line(off + Vector2(x * k, 0.0), off + Vector2(x * k, span.y * k), Color(1, 1, 1, 0.06 * a), 1.0)
	for z in int(span.y) + 1:
		draw_line(off + Vector2(0.0, z * k), off + Vector2(span.x * k, z * k), Color(1, 1, 1, 0.06 * a), 1.0)
	var here := {}
	for p: Dictionary in m.design:
		here["%s@%s" % [p.id, p.at]] = p
	var order := range(first.size())
	order.sort_custom(func(x: int, y: int) -> bool: return first[x].at.y < first[y].at.y)
	for i: int in order:
		var p0: Dictionary = first[i]
		var s := Parts.size_of(p0.id, p0.rot)
		var rr := Rect2(off + (Vector2(p0.at.x, p0.at.z) - lo) * k, Vector2(s.x, s.z) * k).grow(-0.75)
		var p: Dictionary = here.get("%s@%s" % [p0.id, p0.at], {})
		if p.is_empty():
			draw_rect(rr.grow(-1.0), Color(Ui.BAD, 0.5 * a), false, 1.0) # (gone)
			continue
		var kind := str(Parts.def(p.id).kind)
		var frac := clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0)
		var col := Color(0.82, 0.82, 0.78) if frac > 0.66 else (Ui.ACCENT if frac > 0.33 else Ui.BAD)
		if kind in ["wheel", "track"]:
			col = col.darkened(0.45)
		elif kind == "block" or kind == "wedge":
			col = col.darkened(0.12)
		if p.id == _target_key and _target_t > 4.6 and fmod(_t * 10.0, 1.0) < 0.6:
			col = Color.WHITE
		col.a = (0.55 + 0.4 * (p.at.y + 2) / 6.0) * a
		draw_rect(rr, col)
		if kind == "cab":
			draw_rect(rr.grow(-1.0), Color(Ui.ACCENT, a), false, 2.0)
		elif kind == "weapon":
			draw_circle(rr.get_center(), maxf(k * 0.3, 2.0), Color(0.1, 0.1, 0.1, 0.8 * a))
		elif kind == "engine":
			draw_line(rr.position + Vector2(2, 2), rr.end - Vector2(2, 2), Color(0.1, 0.1, 0.1, 0.5 * a), 1.0)


func _draw() -> void:
	var cam := game.get("cam") as Camera3D
	if cam == null or not is_instance_valid(_bound):
		return
	var screen := get_viewport_rect().size # (the screen's, whatever this control's been laid out to)
	if screen.x < 200.0 or screen.y < 200.0:
		return # (no real screen: a headless run)
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
	var font := Ui.font("head")
	# the machine you last hit, from above, at the top right
	if _target_t > 0.0 and is_instance_valid(_target) and _target.alive:
		_draw_target(Rect2(Vector2(screen.x - 230.0, 70.0), Vector2(200.0, 200.0)), font)
	var ms: Variant = game.get("missions")
	var cg: Variant = game.get("cage")
	if (ms and (ms as Missions).panel_up()) or (cg and (cg as Cage).panel_up()):
		return # (a start or end panel's up: nothing over the world)
	# the enemy: the nearest first, each name nudged up off any already there
	var me := _bound.global_position
	var taken: Array[Rect2] = []
	if _target_t > 0.0 and is_instance_valid(_target) and _target.alive:
		taken.append(Rect2(Vector2(screen.x - 240.0, 60.0), Vector2(220.0, 250.0))) # (the target panel)
	var them: Array[Machine] = []
	for n in get_tree().get_nodes_in_group("machines"):
		var e := n as Machine
		if e == _bound or not is_instance_valid(e) or not e.alive or e.team == _bound.team:
			continue
		them.append(e)
	them.sort_custom(func(x: Machine, y: Machine) -> bool: return x.global_position.distance_to(me) < y.global_position.distance_to(me))
	for e in them:
		var top := e.global_transform * Vector3(e.com.x, e.top_y + 1.0, e.com.z)
		var dist := me.distance_to(e.global_position)
		var on_screen := not cam.is_position_behind(top)
		var s := cam.unproject_position(top) if on_screen else Vector2.ZERO
		var inside := on_screen and Rect2(Vector2(40, 40), screen - Vector2(80, 80)).has_point(s)
		var h := e.health()
		var hc := Ui.BAD if h < 0.35 else Ui.ACCENT
		if inside:
			var w := 74.0
			var fs := 13 if dist < 60.0 else 11
			var name := "%s  %d m" % [e.label, int(dist)]
			var ts := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var bw := maxf(ts.x, w) + 4.0
			var box := Rect2(s + Vector2(-bw * 0.5, -10.0 - ts.y), Vector2(bw, ts.y + 18.0))
			var dy := _clear_of(box, taken)
			s.y += dy
			box.position.y += dy
			taken.append(box)
			draw_string_outline(font, s + Vector2(-ts.x * 0.5, -10.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6))
			draw_string(font, s + Vector2(-ts.x * 0.5, -10.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Ui.INK)
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
	# the works robots near you: what each is, how far, what's left of it (on the screen only)
	for n in get_tree().get_nodes_in_group("robots"):
		var rb := n as Node3D
		if not bool(rb.get("alive")):
			continue
		var dist := me.distance_to(rb.global_position)
		var top := rb.global_position + Vector3.UP * 2.4
		if dist > 120.0 or cam.is_position_behind(top):
			continue
		var s := cam.unproject_position(top)
		if not Rect2(Vector2(40, 40), screen - Vector2(80, 80)).has_point(s):
			continue
		var w := 54.0
		var name := "%s  %d m" % [str(rb.call("title")), int(dist)]
		var ts := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var box := Rect2(s + Vector2(-maxf(ts.x, w) * 0.5 - 2.0, -10.0 - ts.y), Vector2(maxf(ts.x, w) + 4.0, ts.y + 16.0))
		var dy := _clear_of(box, taken)
		s.y += dy
		box.position.y += dy
		taken.append(box)
		var h := float(rb.call("hp_frac"))
		draw_string_outline(font, s + Vector2(-ts.x * 0.5, -8.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, 0.6))
		draw_string(font, s + Vector2(-ts.x * 0.5, -8.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.INK)
		draw_rect(Rect2(s + Vector2(-w * 0.5 - 1.0, -1.0), Vector2(w + 2.0, 6.0)), Color(0, 0, 0, 0.5))
		Ui.segments(self, Rect2(s + Vector2(-w * 0.5, 0.0), Vector2(w, 4.0)), 8, h, Ui.BAD if h < 0.35 else Ui.ACCENT, Color(1, 1, 1, 0.15), 0.6)
	# what you hit: numbers rising off it
	for p: Dictionary in _pops:
		var at: Vector3 = p.at
		if cam.is_position_behind(at):
			continue
		var big := bool(p.get("big", false))
		var age := 1.0 - float(p.t) / (1.4 if big else 1.0)
		# stacked: the ones still up round the same spot each a line above the last
		var line := 0
		for q: Dictionary in _pops:
			if q == p:
				break
			if (q.at as Vector3).distance_to(at) < 2.5:
				line += 1
		if line > 3:
			continue # (no more than four lines round one spot)
		var s := cam.unproject_position(at) + Vector2(0.0, -24.0 - age * 40.0 - line * (p.size as int + 6))
		var txt: String = p.text
		var size: int = p.size
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		# off the names and the target panel: below what it would cover
		var box := Rect2(s - Vector2(ts.x * 0.5 + 4.0, ts.y), ts + Vector2(8.0, 6.0))
		for r: Rect2 in taken:
			if r.intersects(box):
				s.y = r.end.y + ts.y + 2.0
				box.position.y = s.y - ts.y
		var a := clampf(float(p.t) * 3.0, 0.0, 1.0)
		var col: Color = p.col
		draw_string_outline(font, s - Vector2(ts.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.7 * a))
		draw_string(font, s - Vector2(ts.x * 0.5, 0.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, a))


## How far up `box` has to go to clear every one of `taken` (0: it's clear already).
static func _clear_of(box: Rect2, taken: Array[Rect2]) -> float:
	var dy := 0.0
	for i in 6:
		var moved := false
		for r: Rect2 in taken:
			var b := Rect2(box.position + Vector2(0.0, dy), box.size)
			if r.intersects(b):
				dy = r.position.y - box.end.y - 2.0
				moved = true
		if not moved:
			break
	return dy
