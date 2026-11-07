class_name Gate
extends Node3D
## A gate in a palisade: two stout posts and a lintel log over them under a little plank roof, an
## icon in its case over the way out, two leaves of pointed planks on battens that swing inward on
## their strap hinges (the models: Details gate_frame, gate_leaf_l/_r, gate_bar). Shut as a rule;
## it opens for one of the town going through (unless an outlaw's close by) and shuts behind them.
## Locked (the bar dropped across it, by order) it opens for no one: the townsfolk know it and go
## round by another, or wait at it if there's none. An outlaw who meets it shut hacks at it
## (Villager._walk), locked or not; beaten in, its leaves hang off their hinges and it stays open.
## (Its frame: the wall runs along x, -z is the way out of the town.)

const HP := 160.0
const WIDTH := 3.0

var wall: Wall
var hp := HP
var broken := false
var is_open := false
var locked := false ## barred by order: shut to everyone
var _bar: Node3D ## the bar across it
var _leaves: Array[Node3D] = []
var _inward := 1.0 ## which way the leaves swing: toward the town
var _hold := 0.0 ## s it stays open for someone going through
var _train := 0.0 ## s it stays open for a train
var _t := 0.0


func _ready() -> void:
	# the frame (Details: gate_frame): its posts down into the ground, the lintel, a little roof
	Details.place(self, "gate_frame")
	# the leaves, each hung at its post and reaching to the middle
	for sx in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(sx * WIDTH * 0.5, 0.15, 0)
		add_child(hinge)
		Details.place(hinge, "gate_leaf_l" if sx < 0.0 else "gate_leaf_r")
		_leaves.append(hinge)
	# swing toward the town (its store)
	var stores: Array = wall.village.stores() if wall and wall.village else []
	if not stores.is_empty():
		var to: Vector3 = (stores[0] as Node3D).global_position - global_position
		_inward = 1.0 if to.dot(global_basis.z) > 0.0 else -1.0
	_swing(false, 0.01)
	# the bar dropped across the leaves on the town's side, in its two iron brackets
	_bar = Node3D.new()
	Details.place(_bar, "gate_bar")
	_bar.position = Vector3(0, 1.45, 0.17 * _inward)
	_bar.visible = locked
	add_child(_bar)


## Barred or unbarred, by order. Barred, its gap's as good as stakes to the way-finding: the
## townsfolk take another gate if there is one.
func set_locked(on: bool) -> void:
	if locked == on:
		return
	locked = on
	if _bar:
		_bar.visible = on
	if wall:
		wall.nav.set_wall(wall.gate_cells(self), on and not broken)
	if on and is_open and not broken:
		_hold = 0.0
		_swing(false)
	Ambience.knock(global_position + Vector3.UP, 0.8)


## A train coming through: it stands open for it, whoever else is about.
func pass_train(time := 6.0) -> void:
	if broken or locked:
		return
	_train = maxf(_train, time)
	if not is_open:
		_swing(true)


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
	_train -= dt
	if _train > 0.0:
		return
	if _t < 0.3:
		return
	_t = 0.0
	if locked:
		return
	var v: Node = wall.village
	var raids: Raids = v.raids
	var near_foe := raids != null and raids.nearest_raider(global_position, 16.0) != null
	var own := false
	for x: Villager in v.villagers:
		# (one on the move and close: not whoever's working by it)
		if not x.dead and not x.down and not x.sleeping and x._path_i < x._path.size() and x.position.distance_to(global_position) < 5.0:
			own = true
			break
	if own and not near_foe:
		_hold = 2.5
	var want: bool = _hold > 0.0 and not near_foe
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
		if wall:
			if locked:
				wall.nav.set_wall(wall.gate_cells(self), false) # (beaten in: open to all, barred or not)
			if wall.village:
				wall.village.message.emit("Firariler sur kapısını kırdı!", "bad")


## Mended (a builder's hands): whole again.
func mend() -> void:
	broken = false
	hp = HP
	for l in _leaves:
		l.rotation = Vector3.ZERO
	_swing(false, 0.01)
	if locked and wall:
		wall.nav.set_wall(wall.gate_cells(self), true)


## Shut and whole, standing in an outlaw's way.
func blocks() -> bool:
	return not broken and not is_open
