class_name Gate
extends Node3D
## A gate in a palisade: two stout posts and a beam over them, two leaves of planks on battens that
## swing inward on their hinges. Open by day; shut at night and when the alarm goes, but it opens
## for one of the town coming up to it (unless an outlaw's close by). An outlaw who meets it shut
## hacks at it (Villager._walk); beaten in, its leaves hang off their hinges and it stays open.
## (Its frame: the wall runs along x, -z is the way out of the town.)

const HP := 160.0
const WIDTH := 3.0

var wall: Wall
var hp := HP
var broken := false
var is_open := true
var _leaves: Array[Node3D] = []
var _inward := 1.0 ## which way the leaves swing: toward the town
var _hold := 0.0 ## s it stays open for someone going through
var _t := 0.0


func _ready() -> void:
	var dark := Building.material("dark")
	var plank := Building.material("plank")
	var log := Building.material("log")
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.2
		pm.bottom_radius = 0.22
		pm.height = 4.0
		pm.radial_segments = 8
		post.mesh = pm
		post.material_override = log
		post.position = Vector3(sx * (WIDTH * 0.5 + 0.2), 1.7, 0)
		add_child(post)
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(WIDTH + 1.2, 0.3, 0.32)
	beam.mesh = bm
	beam.material_override = log
	beam.position = Vector3(0, 3.45, 0)
	add_child(beam)
	# the leaves, each hung at its post and reaching to the middle
	for sx in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(sx * WIDTH * 0.5, 0.15, 0)
		add_child(hinge)
		for k in 5:
			var p := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.28, 2.5 + (k % 2) * 0.12, 0.07)
			p.mesh = b
			p.material_override = plank
			p.position = Vector3(-sx * (0.15 + k * 0.29), 1.25, 0)
			hinge.add_child(p)
		for y in [0.45, 2.1]:
			var batten := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(1.45, 0.14, 0.06)
			batten.mesh = b
			batten.material_override = dark
			batten.position = Vector3(-sx * 0.73, y, 0.06)
			hinge.add_child(batten)
		var brace := MeshInstance3D.new()
		var b2 := BoxMesh.new()
		b2.size = Vector3(0.12, 1.9, 0.06)
		brace.mesh = b2
		brace.material_override = dark
		brace.position = Vector3(-sx * 0.73, 1.27, 0.06)
		brace.rotation.z = sx * 0.65
		hinge.add_child(brace)
		_leaves.append(hinge)
	# swing toward the town (its store)
	var stores: Array = wall.village.stores() if wall and wall.village else []
	if not stores.is_empty():
		var to: Vector3 = (stores[0] as Node3D).global_position - global_position
		_inward = 1.0 if to.dot(global_basis.z) > 0.0 else -1.0
	_swing(true, 0.01)


## How far the leaves stand open (0 shut .. 1 open).
func _swing(open: bool, time := 1.2) -> void:
	is_open = open
	for i in _leaves.size():
		var sx := -1.0 if i == 0 else 1.0
		var to := (-sx * _inward * 1.7) if open else 0.0
		var tw := _leaves[i].create_tween()
		tw.tween_property(_leaves[i], "rotation:y", to, time).set_trans(Tween.TRANS_SINE)


## Every few tenths of a second: open or shut, by the hour, the alarm, and who's coming.
func think(dt: float) -> void:
	if broken:
		return
	_t += dt
	_hold -= dt
	if _t < 0.3:
		return
	_t = 0.0
	var v: Node = wall.village
	var raids: Raids = v.raids
	var danger := raids != null and raids.active
	var near_foe := false
	if raids:
		var r := raids.nearest_raider(global_position, 28.0)
		near_foe = r != null
	var own := false
	for x: Villager in v.villagers:
		if not x.dead and not x.down and not x.sleeping and x.position.distance_to(global_position) < 5.5:
			own = true
			break
	if own and not near_foe:
		_hold = 3.0
	var want: bool = _hold > 0.0 or (not danger and not v.weather.is_night())
	if want != is_open:
		_swing(want)
		Ambience.knock(global_position + Vector3.UP, 0.7)


## Struck (an outlaw's axe): it shudders; beaten in, it stays open, a leaf off its hinge.
func hit(dmg: float) -> void:
	if broken:
		return
	hp -= dmg
	Ambience.knock(global_position + Vector3.UP, 0.9)
	for l in _leaves:
		var tw := l.create_tween()
		tw.tween_property(l, "position:z", 0.06 * _inward, 0.05)
		tw.tween_property(l, "position:z", 0.0, 0.1)
	if hp <= 0.0:
		broken = true
		is_open = true
		for i in _leaves.size():
			var tw := _leaves[i].create_tween()
			tw.tween_property(_leaves[i], "rotation", Vector3(_inward * 0.4 * (1 + i), (-1.0 if i == 0 else 1.0) * -_inward * 1.2, 0.3 * (i * 2 - 1)), 0.5)
		if wall and wall.village:
			wall.village.message.emit("Firariler sur kapısını kırdı!", "bad")


## Mended (a builder's hands): whole again.
func mend() -> void:
	broken = false
	hp = HP
	for l in _leaves:
		l.rotation = Vector3.ZERO
	_swing(is_open, 0.01)


## Shut and whole, standing in an outlaw's way.
func blocks() -> bool:
	return not broken and not is_open
