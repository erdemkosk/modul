class_name Crosshair
extends Control
## The aim: a cross where you look, and for each gun a ring where its round would land now (they lag behind as
## the turrets turn: a ring on the cross means that gun is on), filled while it's on; the cannon's
## ring sweeps round as it reloads, the rocket pod's shows how many tubes are full.

var game: Node
var _hit_t := 0.0
var _kill := false
var _tick: AudioStreamPlayer


## Your rounds hit: an X round the cross for a moment (bigger and red for a kill), a tick.
func confirm(killed: bool) -> void:
	_hit_t = 0.18 if not killed else 0.5
	_kill = killed or _kill and _hit_t > 0.0
	if _tick == null:
		_tick = AudioStreamPlayer.new()
		_tick.stream = load("res://assets/audio/impact/metal_01.wav")
		add_child(_tick)
	if not _tick.playing or killed:
		_tick.volume_db = -14.0 if not killed else -4.0
		_tick.pitch_scale = randf_range(1.9, 2.2) if not killed else 1.0
		_tick.play()


func _process(dt: float) -> void:
	_hit_t -= dt
	if _hit_t <= 0.0:
		_kill = false
	queue_redraw()


## A line with a dark edge under it, so it reads over sky and mud alike.
func _line(a: Vector2, b: Vector2, col: Color, w := 2.0) -> void:
	draw_line(a, b, Color(0, 0, 0, col.a * 0.55), w + 2.0, true)
	draw_line(a, b, col, w, true)


func _arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w := 2.0) -> void:
	draw_arc(c, r, a0, a1, 24, Color(0, 0, 0, col.a * 0.5), w + 2.0, true)
	draw_arc(c, r, a0, a1, 24, col, w, true)


func _draw() -> void:
	var c := size * 0.5
	var col := Color(1, 1, 1, 0.92)
	# the cross: a dot and four short ticks round a gap
	draw_circle(c, 2.6, Color(0, 0, 0, 0.5))
	draw_circle(c, 1.6, col)
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_line(c + d * 7.0, c + d * 15.0, col, 1.6)
	if _hit_t > 0.0:
		var hc := Color(1.0, 0.25, 0.2, minf(_hit_t * 6.0, 1.0)) if _kill else Color(1, 1, 1, minf(_hit_t * 8.0, 1.0))
		var r0 := 10.0 if not _kill else 13.0
		var r1 := 18.0 if not _kill else 28.0
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_line(c + d.normalized() * r0, c + d.normalized() * r1, hc, 2.6 if _kill else 2.0)
	var mv: Variant = game.get("machine")
	if not is_instance_valid(mv):
		return
	var m := mv as Machine
	var cam: Camera3D = game.get("cam")
	if cam == null:
		return
	for g in m.guns:
		if g.muzzle == null or not is_instance_valid(g.muzzle):
			continue
		# where its round comes down at the aim's range (the guns lay themselves over for the drop)
		var b := g.muzzle.global_transform
		var reach := clampf(b.origin.distance_to(m.aim_point), 5.0, 600.0)
		var p := b.origin - b.basis.z * reach
		if g.kind != "minigun":
			var t := MachineGun.flight_time(g.kind, reach)
			p.y -= 0.5 * MachineGun.SHELL_DROP * t * t
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p)
		var on := Color(0.45, 1.0, 0.55, 0.95)
		var off := Color(1.0, 0.62, 0.25, 0.9)
		var ring := on if g.on_target else off
		if not g.armed:
			ring = Color(1, 1, 1, 0.22) # (turned off: only a ghost of it)
		match g.kind:
			"minigun":
				# a small ring broken in four, closing as the barrels come up to speed
				var gap := lerpf(0.6, 0.15, g._spin)
				for k in 4:
					var a := k * PI * 0.5 + PI * 0.25
					_arc(s, 9.0, a - (PI * 0.25 - gap * 0.5), a + (PI * 0.25 - gap * 0.5), ring, 1.8)
			"cannon":
				# corner brackets, and the loading sweeping round outside them
				var r := 15.0
				for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
					var corner := s + d * r
					_line(corner, corner - Vector2(d.x * 7.0, 0.0), ring, 2.0)
					_line(corner, corner - Vector2(0.0, d.y * 7.0), ring, 2.0)
				if g.reload_frac() > 0.0 and g.armed:
					_arc(s, r + 7.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - g.reload_frac()), Color(1, 1, 1, 0.75), 2.0)
			"flamer":
				# a wide broken ring: the stream's spread, its reach the aim's (14 m)
				for k in 8:
					var a := k * TAU / 8.0
					_arc(s, 24.0, a + 0.12, a + TAU / 8.0 - 0.12, ring, 1.6)
			"rockets":
				# a tick per tube, lit while it's full
				var r := 21.0
				for k in MachineGun.ROCKETS:
					var a := -PI * 0.5 + TAU * (k + 0.5) / MachineGun.ROCKETS
					var full := k < g.loaded
					_line(s + Vector2.from_angle(a) * (r - 4.0), s + Vector2.from_angle(a) * (r + 4.0),
						ring if full else Color(1, 1, 1, 0.18), 2.4)
