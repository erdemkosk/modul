class_name Structure
extends Node3D
## Something built out on a site to be brought down: a water tower, a chimney, fuel tanks, a
## warehouse, scaffolding, a transformer (Structures builds them). It's its StructurePieces: each
## stands while what it rests on does. When one goes, what's left is worked out again from the
## ground up: a piece stands if it's on the ground, or if more than half of what it first rested on
## still stands (a water tower keeps its tank on three legs of four, not on two); what doesn't is
## let go, turning over toward the side that gave, and falls.
##
## It's down (`destroyed`) when what still stands is under DOWN_AT of what it was, or when a piece
## it can't do without (a tank, a chimney's foot) is gone.

signal destroyed(s: Structure)

const DOWN_AT := 0.45

var title := ""
var terrain: Node
var pieces: Array[StructurePiece] = []
var vital: Array[StructurePiece] = [] ## (any of these gone: it's down)
var down := false
var _start := 0
var _dirty := false


func add(p: StructurePiece, is_vital := false) -> StructurePiece:
	p.structure = self
	add_child(p)
	pieces.append(p)
	if is_vital:
		vital.append(p)
	p.broke.connect(_on_broke)
	return p


func _ready() -> void:
	settle()


## Once every piece is in: who touches whom, who rests on whom, who's on the ground.
func settle() -> void:
	_start = pieces.size()
	var boxes: Array[AABB] = []
	for p in pieces:
		boxes.append(p.world_aabb().grow(0.06))
	for i in pieces.size():
		var a := pieces[i]
		var ground := float(terrain.call("height_at", a.global_position.x, a.global_position.z)) if terrain else 0.0
		a.grounded = boxes[i].position.y < ground + 0.25
		for j in pieces.size():
			if i == j or not boxes[i].intersects(boxes[j]):
				continue
			var b := pieces[j]
			a.touching.append(b)
			# rests on it: its middle's lower and its top reaches up to this one's bottom
			if b.global_position.y < a.global_position.y - 0.05 and boxes[j].end.y <= boxes[i].position.y + 0.3:
				a.below.append(b)
		a.below_at_first = a.below.size()


func standing_share() -> float:
	if _start == 0:
		return 1.0
	var n := 0
	for p in pieces:
		if is_instance_valid(p) and p.standing and p.hp > 0.0:
			n += 1
	return float(n) / float(_start)


## Its middle (the lowest standing pieces' and the highest's), for markers.
func center() -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in pieces:
		if is_instance_valid(p) and p.standing:
			lo = lo.min(p.global_position)
			hi = hi.max(p.global_position)
	return global_position + Vector3.UP * 2.0 if lo.x == INF else (lo + hi) * 0.5


func top() -> Vector3:
	var c := center()
	var y := c.y
	for p in pieces:
		if is_instance_valid(p) and p.standing:
			y = maxf(y, p.global_position.y + p.size.y * 0.5)
	return Vector3(c.x, y, c.z)


func _on_broke(p: StructurePiece) -> void:
	pieces.erase(p)
	_dirty = true


func _physics_process(_dt: float) -> void:
	if _dirty:
		_dirty = false
		_restand()
	if not down:
		var gone := false
		for v in vital:
			if not is_instance_valid(v) or v.hp <= 0.0 or not v.standing:
				gone = true
		if gone or standing_share() < DOWN_AT:
			down = true
			destroyed.emit(self)
	# fallen pieces settle out of the way in time (they stay a while as rubble)
	for p in pieces:
		if is_instance_valid(p) and not p.standing:
			var age := float(p.get_meta("age", 0.0)) + _dt
			p.set_meta("age", age)


## What still stands after something's gone, from the ground up; the rest is let go.
func _restand() -> void:
	var order := pieces.duplicate()
	order.sort_custom(func(a: StructurePiece, b: StructurePiece) -> bool: return a.global_position.y < b.global_position.y)
	var holds := {}
	for p: StructurePiece in order:
		if not is_instance_valid(p) or not p.standing:
			continue
		if p.grounded:
			holds[p] = true
			continue
		var n := 0
		for b in p.below:
			if is_instance_valid(b) and holds.has(b):
				n += 1
		var need := p.below_at_first / 2 + 1 # (more than half: three legs of four hold it, two don't)
		if p.below_at_first == 0:
			# hung off the side of something (a sign, a pipe): it holds while anything it touches does
			for t in p.touching:
				if is_instance_valid(t) and holds.has(t):
					n = 1
			need = 1
		if n >= need:
			holds[p] = true
	# what's let go topples away from the middle of what still holds
	var keep := Vector3.ZERO
	var kn := 0
	var loose: Array[StructurePiece] = []
	for p in pieces:
		if not is_instance_valid(p) or not p.standing:
			continue
		if holds.has(p):
			keep += p.global_position
			kn += 1
		else:
			loose.append(p)
	if loose.is_empty():
		return
	var mid := Vector3.ZERO
	var low := INF
	for p in loose:
		mid += p.global_position
		low = minf(low, p.global_position.y - p.size.y * 0.5)
	mid /= loose.size()
	var away := (mid - (keep / kn if kn > 0 else mid - Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))) * Vector3(1, 0, 1)
	if away.length() < 0.05:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	var axis := Vector3.UP.cross(away.normalized()) # (turning over toward `away`)
	var pivot := Vector3(mid.x, low, mid.z) - away.normalized() * 0.5
	for p in loose:
		p.let_go(pivot, axis * 0.7)
	if Combat.current and loose.size() >= 3:
		Combat.current.sound("res://assets/audio/explosion/debris_metal_0%d.wav" % randi_range(1, 2), mid, 4.0, 0.55)
