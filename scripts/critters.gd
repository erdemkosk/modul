class_name Critters
extends Node3D
## The town's animals: hens about every lived-in house (three to a house), scratching and pecking
## near its door, scattering from anyone who walks through them, shut in at night; and a dog to
## every few houses, at the heels of one of the household, sitting when they stop.

const HENS := 3
const DOG_EVERY := 3 ## houses to a dog

var village: Village
var nav: Nav
var weather: Weather

var _hens := {} ## house -> Array[Node3D]
var _dogs: Array[Node3D] = []
var _t := 0.0


func _process(dt: float) -> void:
	_t += dt
	if _t > 2.0:
		_t = 0.0
		_census()
	var night := weather.is_night()
	for house: Building in _hens.keys():
		var flock: Array = _hens[house]
		for hen: Node3D in flock:
			if not is_instance_valid(hen):
				continue
			hen.visible = not night
			if not night:
				_hen(hen, house, dt)
	for dog in _dogs:
		if is_instance_valid(dog):
			_dog(dog, dt)


## Hens for the houses that have people, dogs for every few of them; gone with their house.
func _census() -> void:
	var houses: Array[Building] = []
	for b in village.buildings:
		if b.def.role == "house" and b.state == "done" and not b.residents.is_empty():
			houses.append(b)
	for house: Building in _hens.keys():
		if not is_instance_valid(house) or not house in houses:
			for hen: Node3D in _hens[house]:
				if is_instance_valid(hen):
					hen.queue_free()
			_hens.erase(house)
	for house in houses:
		if not _hens.has(house):
			var flock: Array = []
			for k in HENS:
				var hen := _make_hen()
				add_child(hen)
				hen.global_position = house.door() + Vector3(randf_range(-3, 3), 0, randf_range(0, 3))
				hen.set_meta("to", hen.global_position)
				flock.append(hen)
			_hens[house] = flock
	var want := houses.size() / DOG_EVERY
	while _dogs.size() < want:
		var dog := _make_dog()
		add_child(dog)
		var h := houses[_dogs.size() % houses.size()]
		dog.global_position = h.door()
		dog.set_meta("house", h)
		_dogs.append(dog)
	while _dogs.size() > want:
		_dogs.pop_back().queue_free()


func _ground(p: Vector3) -> float:
	return village.ground_at(p)


func _hen(hen: Node3D, house: Building, dt: float) -> void:
	var to: Vector3 = hen.get_meta("to")
	var p := hen.global_position
	# Anyone walking right by sends them scuttling.
	for v in village.villagers:
		if v.visible and not v.sleeping and v.position.distance_to(p) < 1.6:
			var away := (p - v.position)
			away.y = 0.0
			to = p + away.normalized() * 2.5
			hen.set_meta("to", to)
			hen.set_meta("rush", 1.0)
			break
	var d := Vector2(to.x - p.x, to.z - p.z)
	var head := hen.get_node("Head") as Node3D
	if d.length() < 0.15:
		# Pecking about, then off a little way.
		head.position.y = 0.32 - absf(sin(Time.get_ticks_msec() * 0.012 + hen.get_instance_id())) * 0.12
		if randf() < dt * 0.3:
			var c := house.door() + Vector3(randf_range(-4, 4), 0, randf_range(-0.5, 4))
			hen.set_meta("to", c)
		return
	var speed := 2.6 if float(hen.get_meta("rush", 0.0)) > 0.0 else 0.7
	hen.set_meta("rush", maxf(float(hen.get_meta("rush", 0.0)) - dt, 0.0))
	var step := d.normalized() * minf(speed * dt, d.length())
	p.x += step.x
	p.z += step.y
	p.y = _ground(p)
	hen.global_position = p
	hen.rotation.y = atan2(-d.x, -d.y)
	head.position.y = 0.32 + sin(Time.get_ticks_msec() * 0.02) * 0.02


func _dog(dog: Node3D, dt: float) -> void:
	var owner: Villager = dog.get_meta("owner") if dog.has_meta("owner") else null
	if owner == null or not is_instance_valid(owner) or owner.dead:
		var house: Building = dog.get_meta("house") if dog.has_meta("house") else null
		var pick: Villager = null
		if is_instance_valid(house):
			for v in house.residents:
				if is_instance_valid(v) and not v.dead:
					pick = v
		if pick == null and not village.villagers.is_empty():
			pick = village.villagers[randi() % village.villagers.size()]
		dog.set_meta("owner", pick)
		return
	var p := dog.global_position
	var goal := owner.position + owner.global_basis.x * 1.1 + owner.global_basis.z * 0.6
	if owner.sleeping:
		goal = (owner.inside.door() if is_instance_valid(owner.inside) else owner.position) + Vector3(0.8, 0, 0.6)
	dog.visible = true
	var d := Vector2(goal.x - p.x, goal.z - p.z)
	var dist := d.length()
	var legs: Array = dog.get_meta("legs")
	var t := Time.get_ticks_msec() * 0.001
	if dist > 0.4:
		var speed := clampf(dist * 1.5, 1.0, 6.0)
		var step := d / dist * minf(speed * dt, dist)
		p.x += step.x
		p.z += step.y
		dog.rotation.y = lerp_angle(dog.rotation.y, atan2(-d.x, -d.y), 1.0 - exp(-8.0 * dt))
		for i in legs.size():
			(legs[i] as Node3D).rotation.x = sin(t * speed * 4.0 + (PI if i % 3 == 0 else 0.0)) * 0.6
		(dog.get_node("Body") as Node3D).rotation.x = 0.0
	else:
		# Sat down, tail going.
		for i in legs.size():
			(legs[i] as Node3D).rotation.x = (-1.1 if i >= 2 else 0.0)
		(dog.get_node("Body") as Node3D).rotation.x = 0.35
	(dog.get_node("Body/Tail") as Node3D).rotation.y = sin(t * 9.0) * 0.6
	p.y = _ground(p)
	dog.global_position = p


static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	if node_name != "":
		mi.name = node_name
	parent.add_child(mi)
	return mi


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m


func _make_hen() -> Node3D:
	var hen := Node3D.new()
	var feather := _mat([Color(0.92, 0.9, 0.84), Color(0.55, 0.32, 0.16), Color(0.3, 0.22, 0.15)][randi() % 3])
	_box(hen, Vector3(0.18, 0.18, 0.26), Vector3(0, 0.2, 0.02), feather)
	_box(hen, Vector3(0.1, 0.12, 0.08), Vector3(0, 0.3, 0.14), feather) # (the tail feathers)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.32, -0.12)
	hen.add_child(head)
	_box(head, Vector3(0.08, 0.1, 0.09), Vector3.ZERO, feather)
	_box(head, Vector3(0.025, 0.05, 0.05), Vector3(0, 0.06, 0.0), _mat(Color(0.8, 0.12, 0.1)))
	_box(head, Vector3(0.03, 0.025, 0.04), Vector3(0, -0.01, -0.06), _mat(Color(0.85, 0.65, 0.2)))
	for s in [-1.0, 1.0]:
		_box(hen, Vector3(0.02, 0.12, 0.02), Vector3(s * 0.04, 0.06, 0.02), _mat(Color(0.85, 0.65, 0.2)))
	return hen


func _make_dog() -> Node3D:
	var dog := Node3D.new()
	var fur := _mat([Color(0.45, 0.32, 0.2), Color(0.18, 0.16, 0.14), Color(0.7, 0.62, 0.5)][randi() % 3])
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 0.42, 0)
	dog.add_child(body)
	_box(body, Vector3(0.24, 0.24, 0.62), Vector3.ZERO, fur)
	var head := _box(body, Vector3(0.2, 0.2, 0.22), Vector3(0, 0.14, -0.38), fur)
	_box(head, Vector3(0.11, 0.1, 0.14), Vector3(0, -0.04, -0.14), fur)
	for s in [-1.0, 1.0]:
		_box(head, Vector3(0.05, 0.1, 0.04), Vector3(s * 0.07, 0.12, 0.04), fur)
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 0.08, 0.31)
	body.add_child(tail)
	var tm := _box(tail, Vector3(0.05, 0.05, 0.28), Vector3(0, 0.06, 0.12), fur)
	tm.rotation.x = 0.6
	var legs: Array = []
	for z in [-0.22, 0.22]:
		for s in [-1.0, 1.0]:
			var hip := Node3D.new()
			hip.position = Vector3(s * 0.08, 0.36, z)
			dog.add_child(hip)
			_box(hip, Vector3(0.07, 0.36, 0.07), Vector3(0, -0.18, 0), fur)
			legs.append(hip)
	dog.set_meta("legs", legs)
	return dog
