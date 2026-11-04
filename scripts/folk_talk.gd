class_name FolkTalk
extends CanvasLayer
## What the folk say aloud, now and then: a line on a small slip of buff paper over the speaker's
## head, lettered by hand in iron-gall ink (each letter set a little up or down, the slip torn off
## crooked), held a few seconds and gone. Kept rare and close: two at most on the screen at once,
## no one heard from far off, and while a band is on the town only the short shouts of a fight
## ("Siper alın!", "Yaralı var!"), lettered heavier and underlined in red.
## Drawn on one canvas every frame at the head's point on the screen (as CombatMarks draws its
## slips), one layer made the first time anyone speaks and kept on the Village.

const HEAD := 1.9 ## m over the feet the slip's point sits
const NEAR := 46.0 ## m from the view past which no one is heard
const MOST := 2 ## lines on the screen at once (a shout may make it three)
const LIFE := 4.6 ## s a line stays up (a shout less)
const EACH := 45.0 ## s before one says anything again
const GAP := 3.0 ## s at least between two lines anywhere (not shouts)
const SIZE := 15
const PAPER := Color(0.93, 0.87, 0.7) ## (Ui's slip, buff)

static var _me: FolkTalk

var village: Node
var _canvas: Control
var _lines: Array[Dictionary] = [] ## {who, text, born, life, shout, tilt, seed}
var _said := {} ## instance id -> when it last spoke (s)
var _last := -99.0
var _recent: Array[String] = [] ## (the last few lines said: not said again straight off)
## What last happened in the town worth talking about (the day-book's line) and when (s).
var last_event := ""
var last_event_at := -999.0


## `text` said by `v` over its head, if it may be (true if it was).
static func say(v: Villager, text: String, shout := false) -> bool:
	if text == "" or v == null or not is_instance_valid(v) or v.village == null:
		return false
	var me := of(v.village)
	return me != null and me._say(v, text, shout)


## The layer for `village` (made the first time).
static func of(village: Node) -> FolkTalk:
	if _me != null and is_instance_valid(_me) and _me.village == village:
		return _me
	if village == null or not village.is_inside_tree():
		return null
	_me = FolkTalk.new()
	_me.village = village
	village.add_child(_me)
	return _me


func _ready() -> void:
	layer = 4 # (under the fight's slips and the HUD)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	_canvas.draw.connect(_draw_lines)
	if village.has_signal("message"):
		village.connect("message", _heard)


## The day-book's latest (Village.message): remembered as the last thing that happened.
func _heard(text: String, _kind: String) -> void:
	last_event = text
	last_event_at = Time.get_ticks_msec() / 1000.0


## Whether `text` was said just lately (by anyone).
func said_lately(text: String) -> bool:
	return text in _recent


func _say(v: Villager, text: String, shout: bool) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if v.dead or v.sleeping or not v.visible or not v.is_inside_tree():
		return false
	var raids: Node = village.get("raids")
	if not shout and raids != null and bool(raids.get("active")):
		return false # (in a fight nobody chats)
	var cam := v.get_viewport().get_camera_3d()
	if cam == null:
		return false
	var head := _head(v)
	if cam.is_position_behind(head) or head.distance_to(cam.global_position) > NEAR * (1.3 if shout else 1.0):
		return false
	var p := cam.unproject_position(head)
	var view := _canvas.size
	if p.x < 40.0 or p.y < 30.0 or p.x > view.x - 40.0 or p.y > view.y - 30.0:
		return false
	if _lines.size() >= MOST + (1 if shout else 0):
		return false
	for l: Dictionary in _lines:
		if l.who == v:
			return false
	var id := v.get_instance_id()
	if now - float(_said.get(id, -999.0)) < (EACH * 0.3 if shout else EACH):
		return false
	if not shout and (now - _last < GAP or text in _recent):
		return false
	_said[id] = now
	if not shout:
		_last = now
	_recent.append(text)
	if _recent.size() > 12:
		_recent.pop_front()
	_lines.append({"who": v, "text": text, "born": now, "life": LIFE * (0.7 if shout else 1.0) + text.length() * 0.03,
		"shout": shout, "tilt": randf_range(-0.045, 0.045), "seed": randi() % 1000})
	return true


func _head(v: Villager) -> Vector3:
	var h := HEAD
	if v.seat >= 0.0:
		h -= clampf(0.84 - v.seat, 0.0, 0.84) # (sat: the head as far down as the hips went)
	return v.global_position + Vector3.UP * h * v.scale.y


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_lines.size() - 1, -1, -1):
		var l: Dictionary = _lines[i]
		var w: Variant = l.who
		if now - float(l.born) > float(l.life) or not is_instance_valid(w) or (w as Villager).dead or (w as Villager).sleeping or not (w as Villager).visible:
			_lines.remove_at(i)
	var hud: Object = village.get_parent().get("hud") if village.get_parent() else null
	visible = hud == null or bool(hud.get("visible"))
	if not _lines.is_empty() or _canvas.get_meta("drawn", false):
		_canvas.set_meta("drawn", not _lines.is_empty())
		_canvas.queue_redraw()


func _draw_lines() -> void:
	var cam := _canvas.get_viewport().get_camera_3d()
	if cam == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var placed: Array[Rect2] = []
	for l: Dictionary in _lines:
		var v := l.who as Villager
		var head := _head(v)
		if cam.is_position_behind(head):
			continue
		var d := head.distance_to(cam.global_position)
		var age := now - float(l.born)
		var alpha := clampf(age / 0.2, 0.0, 1.0) * clampf((float(l.life) - age) / 0.6, 0.0, 1.0)
		alpha *= 1.0 - smoothstep(NEAR * 0.85, NEAR * 1.4, d)
		if alpha <= 0.02:
			continue
		var p := cam.unproject_position(head)
		var sc := clampf(lerpf(1.15, 0.85, (d - 12.0) / 34.0), 0.85, 1.15)
		_draw_slip(p, str(l.text), bool(l.shout), float(l.tilt), int(l.seed), sc, alpha, placed)


## One slip: torn off a sheet a little crooked, its point down at the speaker's head, the line
## lettered across it.
func _draw_slip(at: Vector2, text: String, shout: bool, tilt: float, seed: int, sc: float, alpha: float, placed: Array[Rect2]) -> void:
	var size := roundi((SIZE + (1 if shout else 0)) * sc)
	var font := Ui.font("strong" if shout else "italic")
	var tw := 0.0 # (set a letter at a time, as it's drawn)
	for ch in text:
		tw += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w := tw + 18.0 * sc
	var h := size + 11.0 * sc
	var rise := 10.0 * sc # (the point's length)
	var r := Rect2(at + Vector2(-w * 0.5, -rise - h), Vector2(w, h))
	for k in 5: # (two talking side by side: the second slip set over the first)
		var hit := false
		for o: Rect2 in placed:
			if o.intersects(r.grow(2.0)):
				hit = true
				break
		if not hit:
			break
		r.position.y -= h + 4.0
	placed.append(r)
	_canvas.draw_set_transform(r.get_center(), tilt, Vector2.ONE)
	var c := r.size * 0.5
	# the paper: its edges a little uneven (torn, not cut), a faint shadow under it
	var pts := PackedVector2Array()
	var steps := 7
	for i in steps + 1: # top
		pts.append(Vector2(-c.x + w * i / steps, -c.y + _rag(seed, i) * 1.2))
	for i in range(1, 3): # right
		pts.append(Vector2(c.x + _rag(seed + 31, i) * 1.0, -c.y + h * i / 3.0))
	for i in steps + 1: # bottom, torn rougher
		pts.append(Vector2(c.x - w * i / steps, c.y + _rag(seed + 57, i) * 1.8))
	for i in range(1, 3): # left
		pts.append(Vector2(-c.x + _rag(seed + 83, i) * 1.0, c.y - h * i / 3.0))
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + Vector2(1.5, 2.0))
	_canvas.draw_colored_polygon(shadow, Color(0.05, 0.035, 0.025, 0.32 * alpha))
	_canvas.draw_colored_polygon(pts, Color(PAPER, 0.95 * alpha))
	var edge := pts.duplicate()
	edge.append(pts[0])
	_canvas.draw_polyline(edge, Color(Ui.P_DIM, 0.55 * alpha), 1.0)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the point: a pencilled stroke down from the slip to the head
	var foot := r.get_center() + Vector2(0, h * 0.5)
	_canvas.draw_line(foot + Vector2(-3.0 * sc, 1.0), at + Vector2(0, -3.0), Color(Ui.P_INK, 0.55 * alpha), 1.2)
	_canvas.draw_line(foot + Vector2(3.0 * sc, 1.0), at + Vector2(0, -3.0), Color(Ui.P_INK, 0.55 * alpha), 1.2)
	# the words, a letter at a time, each a little off the line as a hand would set it
	_canvas.draw_set_transform(r.get_center(), tilt, Vector2.ONE)
	var ink := Color(Ui.P_RED if shout else Ui.P_INK, 0.95 * alpha)
	var x := -tw * 0.5
	var base := font.get_ascent(size) * 0.5 - font.get_descent(size) * 0.35
	var i := 0
	for ch in text:
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_canvas.draw_string(font, Vector2(x, base + _rag(seed + 101, i) * 0.7), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
		x += cw
		i += 1
	if shout:
		_canvas.draw_line(Vector2(-tw * 0.5, base + 3.0), Vector2(tw * 0.5, base + 3.0 + _rag(seed, 3)), Color(Ui.P_RED, 0.7 * alpha), 1.3)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A small steady wobble (-1..1) for point `i` of slip `seed`.
static func _rag(seed: int, i: int) -> float:
	return sin(float(seed) * 12.9898 + float(i) * 78.233) * 0.5 + sin(float(seed) * 3.7 + float(i) * 5.1) * 0.5
