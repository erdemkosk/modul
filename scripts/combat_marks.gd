class_name CombatMarks
extends CanvasLayer
## Who's who in a fight, written over their heads the way a staff officer marks up a map: a slip of
## paper with a ruled strip on it, inked in for the life left in the man (copying-pencil blue for the
## town's, a soldier's green for a side fighting beside it, a dull red for the band), and a small
## stamp beside it: a shield behind cover, a red cross lying wounded, an empty cartridge with no
## rounds left. Struck, the strip flares red and what he lost drains out of it.
## Shown only while a band is on the town, and for whoever's in hand (drafted, taken in hand) at any
## time, with the foes close to them. Far off the slips shrink (never past being read) and fade.
## With folk in hand and the mouse over a foe: a dashed line of fire from each of them to him and,
## by the pointer, the best of them's chance to hit him and why (Raids.aim_chance, as the shot itself
## is rolled).
## And by the pointer at any time, a small typed tag with the one word of what a right-click would do
## just then (Main._rclick_intent): "Saldır", "Git · siper", "Ara", "Ata: Kesim kampı", "İptal".
## All of it drawn in one go on one canvas, every frame: no node per man.

const HEAD := 2.15 ## m over the feet the slip sits
const FAR := 260.0 ## m from the view where the slips have faded out
const BAR := Vector2(30.0, 5.0) ## the strip at its full size, px
const FLASH := 0.45 ## s a strip flares red when struck
const TOWN := Color(0.2, 0.27, 0.52) ## Ui.P_BLUE
const ALLY := Color(0.18, 0.4, 0.2) ## Ui.P_GREEN
const FOE := Color(0.6, 0.17, 0.12) ## Ui.P_RED, dulled

var game: Node ## Main
var aim_foe: Villager ## the foe under the mouse with folk in hand (Main), or null
var shooters: Array[Villager] = [] ## the folk in hand, aiming at aim_foe
var pointer := Vector2.INF ## where the tag is pinned (INF: by the mouse)
var rclick_word := "" ## what a right-click would do now, one word or two ("" no tag; Main)
var rclick_do := "" ## (its kind, for the ink: "attack" red, "cancel"/"stop" orange, "assign" blue)

var _canvas: Control
var _tag_canvas: Control
var _seen := {} ## instance id -> {hp, ghost, flash, shield, next}
var _list: Array = [] ## this frame's [Villager, side]
var _aim := {} ## shooter instance id -> [chance, reason, fires], worked out a few times a second
var _aim_t := 0.0
var _aim_for: Villager
var _best: Villager


func _ready() -> void:
	layer = 5 # (under the HUD's cards and bars)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	_canvas.draw.connect(_draw_marks)
	var top := CanvasLayer.new()
	top.layer = 12 # (the tag by the pointer over everything, as the pointer is)
	add_child(top)
	_tag_canvas = Control.new()
	_tag_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.add_child(_tag_canvas)
	_tag_canvas.draw.connect(_draw_aim_tag)


func _process(dt: float) -> void:
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	visible = game.hud.visible
	_gather()
	var now := Time.get_ticks_msec() / 1000.0
	var keep := {}
	for e: Array in _list:
		var v: Villager = e[0]
		var id := v.get_instance_id()
		keep[id] = true
		var hp := clampf(v.hp / maxf(v.max_hp, 1.0), 0.0, 1.0)
		if not _seen.has(id):
			_seen[id] = {"hp": hp, "ghost": hp, "flash": -9.0, "shield": v.in_cover, "next": now + randf() * 0.5}
		var s: Dictionary = _seen[id]
		if hp < float(s.hp) - 0.03:
			s.flash = now # (struck: a bleeding man's slow loss doesn't count)
		s.hp = hp
		s.ghost = maxf(hp, float(s.ghost) - real_dt * 0.5) if now - float(s.flash) > 0.3 else maxf(float(s.ghost), hp)
		if now >= float(s.next):
			s.next = now + 0.6
			s.shield = _shielded(v, int(e[1]))
	for id: int in _seen.keys():
		if not keep.has(id):
			_seen.erase(id)
	_keep_in_sight()
	# the chances at the foe under the mouse, a few times a second (cover() looks round the ground)
	if aim_foe != _aim_for:
		_aim_for = aim_foe
		_aim_t = 0.0
	_aim_t -= real_dt
	if is_instance_valid(aim_foe) and _aim_t <= 0.0:
		_aim_t = 0.2
		_aim.clear()
		_best = null
		var bc := -1.0
		for s in shooters:
			if not is_instance_valid(s) or s.dead or s.down or s.ranged <= 0.0:
				continue
			var a: Array = game.raids.aim_chance(s, aim_foe)
			_aim[s.get_instance_id()] = a
			var score := float(a[0]) + (1.0 if bool(a[2]) else 0.0) # (one that would fire before one that can't)
			if score > bc:
				bc = score
				_best = s
	_canvas.queue_redraw()
	_tag_canvas.queue_redraw()


## The six of the fight the trees are thinned round for the view (RtsCamera.in_sight): of the town's
## and of the foes, three each, those nearest the middle of the view (the town's in hand first); a
## side with fewer leaves its places to the other.
func _keep_in_sight() -> void:
	var cam: RtsCamera = game.cam
	var ours: Array = []
	var theirs: Array = []
	for e: Array in _list:
		var v: Villager = e[0]
		var head := v.global_position + Vector3.UP * (0.4 if v.down else 1.3)
		if cam.is_position_behind(head):
			continue
		var d := Vector2(v.position.x - cam.focus.x, v.position.z - cam.focus.z).length()
		if d > 140.0:
			continue
		if int(e[1]) == 1:
			theirs.append([d, head])
		else:
			ours.append([d - (60.0 if v.drafted else 0.0), head])
	var near := func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0])
	ours.sort_custom(near)
	theirs.sort_custom(near)
	var n_ours := mini(ours.size(), maxi(3, 6 - theirs.size()))
	var n_theirs := mini(theirs.size(), 6 - n_ours)
	var pts: Array[Vector3] = []
	for i in n_ours:
		pts.append(ours[i][1])
	for i in n_theirs:
		pts.append(theirs[i][1])
	cam.in_sight = pts


## Who gets a slip this frame: [Villager, side] (0 the town's, 1 a foe, 2 a side's soldiers with it).
func _gather() -> void:
	_list.clear()
	var raids: Raids = game.raids
	var village: Village = game.village
	var fight := raids.active
	var hands: Array[Villager] = []
	for v in village.villagers:
		if not is_instance_valid(v) or v.dead or not v.visible or v.hiding:
			continue
		if v.drafted:
			hands.append(v)
			_list.append([v, 0])
		elif fight and (v.armed or v.perched or v.down or (v.fighter and not v.is_child)):
			_list.append([v, 0])
	for a in raids.allies:
		if is_instance_valid(a) and not a.dead and a.visible:
			_list.append([a, 2])
	for list: Array[Villager] in [raids.raiders, raids.wolves, raids.camp_men]:
		for r in list:
			if not is_instance_valid(r) or r.dead or not r.visible:
				continue
			if fight or _near_any(r, hands, 90.0):
				_list.append([r, 1])


static func _near_any(r: Villager, hands: Array[Villager], reach: float) -> bool:
	for h in hands:
		if h.position.distance_squared_to(r.position) < reach * reach:
			return true
	return false


## Whether `v` is covered against the nearest of the other side (what Raids.cover finds from there),
## or, with no one about, whether it stands in cover at all.
func _shielded(v: Villager, side: int) -> bool:
	var raids: Raids = game.raids
	var foe: Villager = null
	if side == 1:
		var bd := 120.0
		for e: Array in _list:
			var o: Villager = e[0]
			if int(e[1]) != 1 and not o.down:
				var d := o.position.distance_to(v.position)
				if d < bd:
					bd = d
					foe = o
	else:
		foe = raids.nearest_raider(v.position, 120.0)
	if foe == null:
		return v.in_cover or game.village.in_trench(v.position)
	var cv: Array = raids.cover(foe.position + Vector3.UP * 1.4, v)
	return str(cv[1]) != "" and float(cv[0]) < 0.8


func _draw_marks() -> void:
	var cam: Camera3D = game.cam
	if cam == null:
		return
	# (the camera's screen points are already the canvas's: both the window's size over the
	# interface's scale)
	var size := _canvas.size
	var now := Time.get_ticks_msec() / 1000.0
	var from_cam := cam.global_position
	var chosen := {}
	for v in shooters:
		if is_instance_valid(v):
			chosen[v.get_instance_id()] = true
	# the lines of fire first, under the slips
	if is_instance_valid(aim_foe) and not aim_foe.dead:
		_draw_fire_lines(cam)
	var placed: Array[Rect2] = []
	for e: Array in _list:
		var v: Villager = e[0]
		var side: int = e[1]
		var head := v.global_position + Vector3.UP * (0.7 if v.down else (1.4 if v is Wolf else HEAD))
		if cam.is_position_behind(head):
			continue
		var d := head.distance_to(from_cam)
		var alpha := 1.0 - smoothstep(FAR * 0.65, FAR, d)
		if alpha <= 0.02:
			continue
		var p := cam.unproject_position(head)
		if p.x < -40.0 or p.y < -40.0 or p.x > size.x + 40.0 or p.y > size.y + 40.0:
			continue
		var sc := clampf(lerpf(1.2, 0.75, (d - 25.0) / 160.0), 0.75, 1.2) # (smaller far off, never too small to read)
		var s: Dictionary = _seen.get(v.get_instance_id(), {})
		if s.is_empty():
			continue
		var flash := clampf(1.0 - (now - float(s.flash)) / FLASH, 0.0, 1.0)
		var icon := ""
		if v.down:
			icon = "down"
		elif v.team == 0 and v.armed and v.ranged > 0.0 and v.ammo <= 0:
			icon = "empty"
		elif bool(s.shield):
			icon = "shield"
		# (folk standing together: each slip lifted clear of the ones already set)
		var box := Rect2(p - Vector2(BAR.x * sc * 0.5 + 6.0, BAR.y * sc + 2.0), Vector2(BAR.x * sc + 22.0 * sc, BAR.y * sc + 4.0))
		for k in 6:
			var hit := false
			for o: Rect2 in placed:
				if o.intersects(box):
					hit = true
					break
			if not hit:
				break
			box.position.y -= box.size.y + 1.0
			p.y -= box.size.y + 1.0
		placed.append(box)
		_draw_slip(p, sc, alpha, side, float(s.hp), float(s.ghost), flash, icon, chosen.has(v.get_instance_id()))


func _draw_aim_tag() -> void:
	var mouse := _tag_canvas.get_local_mouse_position() if pointer == Vector2.INF else pointer
	if rclick_word != "":
		_draw_word_tag(mouse, rclick_word, rclick_do)
	if is_instance_valid(aim_foe) and not aim_foe.dead and is_instance_valid(_best) and _aim.has(_best.get_instance_id()):
		_draw_tag(_tag_canvas.get_local_mouse_position() if pointer == Vector2.INF else pointer, _aim[_best.get_instance_id()], _best)


## One man's slip: the paper strip with its life inked in, ticked at the quarters, and its stamp.
func _draw_slip(p: Vector2, sc: float, alpha: float, side: int, hp: float, ghost: float, flash: float, icon: String, chosen: bool) -> void:
	var w := BAR.x * sc
	var h := maxf(BAR.y * sc, 4.0)
	var jolt := Vector2(randf_range(-1.0, 1.0), 0.0) * flash * 1.5
	var r := Rect2(p - Vector2(w * 0.5, h) + jolt, Vector2(w, h))
	var ink := Color(Ui.P_INK, 0.9 * alpha)
	var col: Color = [TOWN, FOE, ALLY][side]
	# a dark halo so it reads over snow as over the forest, then the paper
	_canvas.draw_rect(r.grow(1.6), Color(0.05, 0.035, 0.025, 0.35 * alpha))
	_canvas.draw_rect(r, Color(Ui.ENAMEL, 0.94 * alpha))
	if ghost > hp:
		_canvas.draw_rect(Rect2(r.position + Vector2(w * hp, 0), Vector2(w * (ghost - hp), h)), Color(Ui.P_RED, 0.55 * alpha))
	var fill := col.lerp(Color(0.85, 0.16, 0.1), flash)
	_canvas.draw_rect(Rect2(r.position, Vector2(w * hp, h)), Color(fill, alpha))
	for q: float in [0.25, 0.5, 0.75]:
		var x := r.position.x + w * q
		_canvas.draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + h * 0.45), Color(Ui.P_INK, 0.5 * alpha), 1.0)
	_canvas.draw_rect(r, Color(0.8, 0.12, 0.08, alpha) if flash > 0.0 else ink, false, 1.0 + flash)
	# the side's mark at the strip's left end: the town's a square tab, the band's a diamond
	var m := r.position + Vector2(-4.0 * sc, h * 0.5)
	var ms := 3.2 * sc
	if side == 1:
		_canvas.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -ms), m + Vector2(ms, 0), m + Vector2(0, ms), m + Vector2(-ms, 0)]), Color(col, alpha))
		_canvas.draw_polyline(PackedVector2Array([m + Vector2(0, -ms), m + Vector2(ms, 0), m + Vector2(0, ms), m + Vector2(-ms, 0), m + Vector2(0, -ms)]), ink, 1.0)
	else:
		var tab := Rect2(m - Vector2(ms, ms) * 0.8, Vector2(ms, ms) * 1.6)
		_canvas.draw_rect(tab, Color(col, alpha))
		_canvas.draw_rect(tab, ink, false, 1.0)
	if chosen:
		# in hand: underlined in copying pencil
		_canvas.draw_line(r.position + Vector2(0, h + 2.5), r.position + Vector2(w, h + 2.5), Color(Ui.ENAMEL, 0.85 * alpha), 1.5)
	if icon != "":
		_draw_stamp(r.position + Vector2(w + 7.5 * sc, h * 0.5), 5.5 * sc, icon, alpha)


## A round stamp on the paper: a shield (in cover), a red cross (down), an empty cartridge struck
## through (no rounds).
func _draw_stamp(c: Vector2, rad: float, icon: String, alpha: float) -> void:
	var ink := Color(Ui.P_INK, alpha)
	_canvas.draw_circle(c, rad + 1.4, Color(0.05, 0.035, 0.025, 0.35 * alpha))
	_canvas.draw_circle(c, rad, Color(Ui.ENAMEL, 0.96 * alpha))
	_canvas.draw_arc(c, rad, 0.0, TAU, 16, ink, 1.0)
	var u := rad * 0.62
	match icon:
		"shield":
			var pts := PackedVector2Array([c + Vector2(-u, -u), c + Vector2(u, -u), c + Vector2(u, -u * 0.1),
				c + Vector2(u * 0.55, u * 0.6), c + Vector2(0, u * 1.05), c + Vector2(-u * 0.55, u * 0.6), c + Vector2(-u, -u * 0.1)])
			_canvas.draw_colored_polygon(pts, Color(Ui.P_BLUE, alpha))
			pts.append(pts[0])
			_canvas.draw_polyline(pts, ink, 1.0)
		"down":
			var t := maxf(u * 0.42, 1.2)
			_canvas.draw_rect(Rect2(c - Vector2(t, u), Vector2(t * 2.0, u * 2.0)), Color(Ui.P_RED, alpha))
			_canvas.draw_rect(Rect2(c - Vector2(u, t), Vector2(u * 2.0, t * 2.0)), Color(Ui.P_RED, alpha))
		"empty":
			var body := Rect2(c + Vector2(-u * 0.38, -u * 0.55), Vector2(u * 0.76, u * 1.5))
			_canvas.draw_rect(body, ink, false, 1.0)
			_canvas.draw_line(c + Vector2(-u * 0.2, -u * 0.55), c + Vector2(0, -u * 1.0), ink, 1.0)
			_canvas.draw_line(c + Vector2(u * 0.2, -u * 0.55), c + Vector2(0, -u * 1.0), ink, 1.0)
			_canvas.draw_line(c + Vector2(-u, u), c + Vector2(u, -u), Color(Ui.P_RED, alpha), 1.6)


## Faint dashed lines from each man in hand to the foe under the mouse: cream for one who'd fire,
## red for one who can't (out of reach, or he can't be seen); the best of them drawn firmer.
func _draw_fire_lines(cam: Camera3D) -> void:
	var to3 := aim_foe.global_position + Vector3.UP * 1.2
	if cam.is_position_behind(to3):
		return
	var to := cam.unproject_position(to3)
	for s in shooters:
		if not is_instance_valid(s) or s.dead or s.down or s.ranged <= 0.0:
			continue
		var at3 := s.global_position + Vector3.UP * 1.3
		if cam.is_position_behind(at3):
			continue
		var a: Array = _aim.get(s.get_instance_id(), [])
		var fires := not a.is_empty() and bool(a[2])
		var best := s == _best
		var from := cam.unproject_position(at3)
		var c := Color(Ui.INK, 0.75 if best else 0.42) if fires else Color(Ui.BAD, 0.6 if best else 0.35)
		_canvas.draw_dashed_line(from, to, Color(0, 0, 0, 0.3), 3.0, 7.0)
		_canvas.draw_dashed_line(from, to, c, 1.5 if best else 1.0, 7.0)
	_canvas.draw_arc(to, 9.0, 0.0, TAU, 20, Color(Ui.BAD, 0.8), 1.5)


## The tag by the pointer: a typed slip, the chance large, who'd take the shot and why under it.
func _draw_tag(mouse: Vector2, a: Array, who: Villager) -> void:
	var big := Ui.face("type_bold", 18)
	var small := Ui.face("type", 13)
	var pct := "%%%d" % roundi(float(a[0]) * 100.0)
	var line := "%s · %s" % [who.display_name.split(" ")[0], str(a[1])]
	var bw := big.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var lw := small.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var w := maxf(bw, lw) + 22.0
	var h := 44.0
	var p := mouse + Vector2(24, 16)
	if p.x + w > _tag_canvas.size.x - 8.0:
		p.x = mouse.x - w - 16.0
	if p.y + h > _tag_canvas.size.y - 8.0:
		p.y = mouse.y - h - 12.0
	var r := Rect2(p, Vector2(w, h))
	_tag_canvas.draw_rect(r.grow(2.0), Color(0.05, 0.035, 0.025, 0.4))
	_tag_canvas.draw_rect(r, Color(Ui.ENAMEL, 0.97))
	_tag_canvas.draw_line(r.position + Vector2(8, 0), r.position + Vector2(8, h), Color(Ui.P_RED, 0.7), 1.0) # (the ruled margin)
	_tag_canvas.draw_rect(r, Color(Ui.P_INK, 0.85), false, 1.0)
	var chance := float(a[0])
	var pc := Ui.P_RED if chance < 0.25 or not bool(a[2]) else (Ui.P_GREEN if chance >= 0.55 else Ui.P_INK)
	_tag_canvas.draw_string(big, p + Vector2(14, 19), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, pc)
	_tag_canvas.draw_string(small, p + Vector2(14, 36), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.P_INK)


## The right-click's word on a small typed slip up and to the right of the pointer: a margin rule,
## a mouse with its right button inked in before it, the word typed in the ink of what it'd do.
func _draw_word_tag(mouse: Vector2, word: String, kind: String) -> void:
	var f := Ui.face("type_bold", 14)
	var tw := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var w := tw + 34.0
	var h := 21.0
	var p := mouse + Vector2(20, -h - 8.0)
	if p.x + w > _tag_canvas.size.x - 6.0:
		p.x = mouse.x - w - 14.0
	if p.y < 6.0:
		p.y = mouse.y + 22.0
	var r := Rect2(p, Vector2(w, h))
	var ink: Color = {"attack": Ui.P_RED, "cancel": Color(0.62, 0.3, 0.05), "stop": Color(0.62, 0.3, 0.05), "assign": Ui.P_BLUE,
		"hint": Ui.P_DIM}.get(kind, Ui.P_INK)
	_tag_canvas.draw_rect(r.grow(1.5), Color(0.05, 0.035, 0.025, 0.35))
	_tag_canvas.draw_rect(r, Color(Ui.ENAMEL, 0.97))
	_tag_canvas.draw_line(r.position + Vector2(20, 0), r.position + Vector2(20, h), Color(Ui.P_RED, 0.6), 1.0) # (the ruled margin)
	_tag_canvas.draw_rect(r, Color(Ui.P_INK, 0.8), false, 1.0)
	# the mouse, its right button inked in
	var m := Rect2(p + Vector2(6, 4), Vector2(9, 13))
	_tag_canvas.draw_rect(m, Color(Ui.P_INK, 0.85), false, 1.0)
	_tag_canvas.draw_rect(Rect2(m.position + Vector2(m.size.x * 0.5, 0), Vector2(m.size.x * 0.5, m.size.y * 0.42)), Color(ink, 0.9))
	_tag_canvas.draw_line(m.position + Vector2(0, m.size.y * 0.42), m.position + Vector2(m.size.x, m.size.y * 0.42), Color(Ui.P_INK, 0.85), 1.0)
	_tag_canvas.draw_string(f, p + Vector2(26, 15.5), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
