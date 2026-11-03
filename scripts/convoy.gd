class_name Convoy
extends Node3D
## A side's men come by road: a truck or two, canvas over their beds, and now and then a tank, an
## iron box on tracks with a gun, grinding in out of the woods from the valley's edge and over
## whatever trees stand in the way. They halt short of the town; an officer gets down and walks in
## with what his side wants. Given, they go. Haggled, they may take half and go, or not. Refused,
## they may go (and the town's the prouder for it), or come in shooting, the tank's gun with them,
## and go when it's over. A side that hates the town doesn't ask.

signal gone

const TRUCK_LEN := 6.8
const TANK_LEN := 9.4
const GAP := 6.0 ## m between one and the next
const SPEED := 4.5 ## m/s on the move (a tank holds them to 2.6)

var village: Village
var side := "merkez"
var tank := false
var path := PackedVector3Array()
var _len := PackedFloat32Array()
var _cars: Array[Dictionary] = [] ## {node, back (m behind the lead), wheels, len}
var _s := 0.0
var _state := "coming" ## coming, halted, leaving
var _engine: AudioStreamPlayer3D
var _officer: Villager
var gun: Node3D ## the tank's muzzle (Raids fires it while its men are at the town)
var _crush_at := -10.0


func _ready() -> void:
	name = "Convoy"
	var trucks := 1 + int(randf() < 0.6)
	var back := 0.0
	if tank:
		_cars.append(_build_tank(back))
		back += TANK_LEN + GAP
	for k in trucks:
		_cars.append(_build_truck(back))
		back += TRUCK_LEN + GAP
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = Ambience._looped("res://assets/audio/war/engine_loop.wav")
	_engine.unit_size = 30.0
	_engine.max_distance = 400.0
	_engine.volume_db = 2.0
	(_cars[0].node as Node3D).add_child(_engine)
	_engine.play()
	_place()


## The road from the valley's edge (`from`) to the halt (`to`), every 2 m on the ground.
func lay(from: Vector3, to: Vector3) -> void:
	path = PackedVector3Array()
	var n := maxi(2, int(from.distance_to(to) / 2.0))
	for k in n + 1:
		var p := from.lerp(to, float(k) / n)
		p.y = village.nav.height(p.x, p.z)
		path.append(p)
	_len.resize(path.size())
	_len[0] = 0.0
	for k in range(1, path.size()):
		_len[k] = _len[k - 1] + path[k].distance_to(path[k - 1])
	_s = 0.0


func _at(s: float) -> Transform3D:
	s = clampf(s, 0.0, _len[_len.size() - 1])
	var k := 0
	while k < _len.size() - 2 and _len[k + 1] < s:
		k += 1
	var t := (s - _len[k]) / maxf(_len[k + 1] - _len[k], 0.001)
	var p := path[k].lerp(path[k + 1], t)
	var dir := path[k + 1] - path[k]
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), p)


func _place() -> void:
	if path.size() < 2:
		return
	for c: Dictionary in _cars:
		var node: Node3D = c.node
		var s := _s - float(c.back) if _state != "leaving" else _s + float(c.back)
		var xf := _at(s)
		if _state == "leaving":
			xf.basis = xf.basis.rotated(Vector3.UP, PI)
		node.global_transform = xf


func _process(dt: float) -> void:
	if path.size() < 2:
		return
	var end := _len[_len.size() - 1]
	var v := (2.6 if tank else SPEED)
	var moved := 0.0
	match _state:
		"coming":
			var was := _s
			_s = minf(_s + v * dt, end)
			moved = _s - was
			if _s >= end - 0.01:
				_state = "halted"
				_halt()
		"leaving":
			var was := _s
			_s = maxf(_s - v * dt, 0.0)
			moved = was - _s
			if _s <= 0.01:
				gone.emit()
				queue_free()
				return
	if moved > 0.0:
		_place()
		for c: Dictionary in _cars:
			for w: Node3D in c.wheels:
				w.rotate_object_local(Vector3.RIGHT, moved / 0.47)
		_crush()
	_engine.pitch_scale = 1.0 if moved > 0.0 else 0.7


## The trees in the way: down under the lead, with a crack.
func _crush() -> void:
	if absf(_s - _crush_at) < 1.5:
		return
	_crush_at = _s
	var terrain: WorldTerrain = village.terrain
	for c: Dictionary in _cars:
		var p: Vector3 = (c.node as Node3D).global_position
		var across: Vector3 = (c.node as Node3D).global_basis.x
		# its tracks (or wheels) worn into the ground behind it, the earth churned under a tank
		var tracked: bool = c.get("kind", "") == "tank"
		for sx in ([-1.27, 1.27] if tracked else [-0.86, 0.86]):
			for k in 3:
				var q: Vector3 = p + across * sx + (c.node as Node3D).global_basis.z * (k - 1) * 1.2
				village.nav.tread(q, 3.0, 10.0 if tracked else 4.0)
				if tracked:
					terrain.churn(q, 0.6)
		if tracked:
			terrain.clear_grass(p, 1.8)
		for i in village._props_in(p, 5.0):
			var info: Dictionary = village.props.prop_info(i)
			if str(info.kind) != "cliff" and Vector2(info.origin.x - p.x, info.origin.z - p.z).length() < 2.6:
				village.props.cut_tree(i)
				village.reserved.erase(i)
				Ambience.play("tree_crack", p, 2.0, 0.8, 300.0)


## Halted short of the town: an officer gets down and walks in (or, from a side that hates the town,
## the men come off shooting).
func _halt() -> void:
	var lead: Node3D = _cars[0].node
	if village.standing(side) <= Village.HOSTILE:
		village.convoy_attacks(self)
		return
	_officer = Villager.new()
	_officer.village = village
	_officer.nav = village.nav
	_officer.tunic_color = Color(0.36, 0.38, 0.27) if side == "merkez" else Color(0.3, 0.1, 0.08)
	add_child(_officer)
	var at := lead.global_position + lead.global_basis.x * 2.5
	at.y = village.nav.height(at.x, at.z)
	_officer.position = at
	var stores := village.stores()
	var meet := (stores[0] as Building).door() if not stores.is_empty() else at
	meet = meet + (at - meet).normalized() * 6.0
	meet.y = village.nav.height(meet.x, meet.z)
	_officer.give([{"t": "go", "to": meet}, {"t": "do", "f": func() -> bool:
		village.convoy_demands(self)
		return true}, {"t": "work", "time": 600.0, "anim": "idle"}], "Subay")


## Off back the way they came (the officer up into the truck first).
func leave() -> void:
	if is_instance_valid(_officer):
		var lead: Node3D = _cars[0].node
		var back := lead.global_position + lead.global_basis.x * 2.5
		var o := _officer
		o.abort()
		o.give([{"t": "go", "to": back}, {"t": "do", "f": func() -> bool:
			o.queue_free()
			_state = "leaving"
			return true}], "Subay dönüyor")
	else:
		_state = "leaving"


func halt_point() -> Vector3:
	return path[path.size() - 1] if path.size() > 0 else global_position


# --- the machines ---------------------------------------------------------------------------------

func _mat(c: Color, metal := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.75
	return m








## A model from tools/blender/build_buildings.py (kamyon, tank), dressed as the trains are (its colours
## in its vertices), its wheels found to be turned; the rebels' mark painted red.
func _model(kind: String) -> Array:
	var node := (load("res://assets/buildings/%s.glb" % kind) as PackedScene).instantiate() as Node3D
	add_child(node)
	var wheels: Array[Node3D] = []
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var stuff := String(mi.name).split("-")[0]
		mi.material_override = Building.material((stuff if BuildingDefs.STUFF.has(stuff) else "dark") + "+")
		if String(mi.name).contains("wheel"):
			wheels.append(mi)
		elif String(mi.name).contains("mark") and side == "isyan":
			mi.material_override = _mat(Color(0.62, 0.1, 0.08))
	return [node, wheels]


func _smoke(node: Node3D, at: Vector3, amount: int) -> void:
	var smoke := FireFx.smoke(false)
	smoke.amount = amount
	smoke.lifetime = 3.5
	smoke.local_coords = false
	node.add_child(smoke)
	smoke.position = at


func _build_truck(back: float) -> Dictionary:
	var m := _model("kamyon")
	var node: Node3D = m[0]
	_smoke(node, Vector3(0.55, 0.6, 3.4), 14)
	return {"node": node, "back": back, "wheels": m[1], "len": TRUCK_LEN, "kind": "truck"}


func _build_tank(back: float) -> Dictionary:
	var m := _model("tank")
	var node: Node3D = m[0]
	for x in [-0.4, 0.4]:
		_smoke(node, Vector3(x, 3.05, 2.2), 18)
	gun = Node3D.new()
	node.add_child(gun)
	gun.position = Vector3(2.0, 1.45, -1.65)
	return {"node": node, "back": back, "wheels": m[1], "len": TANK_LEN, "kind": "tank"}
