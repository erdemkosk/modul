class_name Critters
extends Node3D
## The town's animals: hens about every lived-in house (three to a house), scratching and pecking
## near its door, scattering from anyone who walks through them, shut in at night; and a dog to
## every few houses, at the heels of one of the household, sitting when they stop. Both made in
## Blender (assets/animals/hen.glb, dog.glb: a laika) and walked in their own gaits (AnimalBody).

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
	var a := hen as AnimalBody
	var to: Vector3 = hen.get_meta("to")
	var p := hen.global_position
	# Anyone walking right by sends them scuttling, wings going.
	for v in village.villagers:
		if v.visible and not v.sleeping and v.position.distance_to(p) < 1.6:
			var away := (p - v.position)
			away.y = 0.0
			to = p + away.normalized() * 2.5
			hen.set_meta("to", to)
			hen.set_meta("rush", 1.0)
			break
	var d := Vector2(to.x - p.x, to.z - p.z)
	var rush := float(hen.get_meta("rush", 0.0))
	hen.set_meta("rush", maxf(rush - dt, 0.0))
	a.flap = move_toward(a.flap, 1.0 if rush > 0.4 else 0.0, dt * 6.0)
	if d.length() < 0.15:
		# Pecking about, then off a little way.
		var tt := Time.get_ticks_msec() * 0.001 + float(hen.get_instance_id() % 97)
		a.graze = 1.0 if fmod(tt, 2.3) < 1.3 and sin(tt * 14.0) > -0.2 else 0.25
		a.look = sin(tt * 0.9) * 0.6
		a.step(dt, 0.0)
		if randf() < dt * 0.3:
			var c := house.door() + Vector3(randf_range(-4, 4), 0, randf_range(-0.5, 4))
			hen.set_meta("to", c)
		return
	a.graze = 0.0
	a.look = 0.0
	var speed := 2.6 if rush > 0.0 else 0.7
	var step := d.normalized() * minf(speed * dt, d.length())
	p.x += step.x
	p.z += step.y
	p.y = _ground(p)
	hen.global_position = p
	hen.rotation.y = lerp_angle(hen.rotation.y, atan2(-d.x, -d.y), 1.0 - exp(-12.0 * dt))
	a.step(dt, speed)


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
	var a := dog as AnimalBody
	var speed := 0.0
	if dist > 0.4:
		speed = clampf(dist * 1.5, 1.0, 6.0)
		var step := d / dist * minf(speed * dt, dist)
		p.x += step.x
		p.z += step.y
		dog.rotation.y = lerp_angle(dog.rotation.y, atan2(-d.x, -d.y), 1.0 - exp(-8.0 * dt))
	# Sat down when it's caught up, tail going; the nose down to the ground now and then as it goes.
	var tt := Time.get_ticks_msec() * 0.001 + float(dog.get_instance_id() % 53)
	a.sit = move_toward(a.sit, 1.0 if speed == 0.0 else 0.0, dt * (2.5 if speed == 0.0 else 6.0))
	a.wag = 1.0 if speed == 0.0 or speed > 3.0 else 0.3
	a.graze = 1.0 if speed > 0.0 and speed < 2.0 and fmod(tt, 7.0) < 1.5 else 0.0
	a.look = sin(tt * 0.5) * 0.5 if speed == 0.0 else 0.0
	p.y = _ground(p)
	dog.global_position = p
	a.fit_ground(func(q: Vector3) -> float: return _ground(q), dt)
	a.step(dt, speed)


const HEN_COATS := [Color(0.95, 0.93, 0.87), Color(0.62, 0.5, 0.4), Color(0.32, 0.29, 0.26), Color(0.78, 0.7, 0.57)]
const DOG_COATS := [Color(0.64, 0.54, 0.46), Color(0.52, 0.5, 0.47), Color(0.2, 0.19, 0.18), Color(0.8, 0.75, 0.66)]


func _make_hen() -> Node3D:
	var hen := AnimalBody.make("hen", HEN_COATS[randi() % HEN_COATS.size()], Color(-1, 0, 0), false, 90.0)
	hen.name = "Hen"
	return hen


## A laika: red, grey-wolf, black or pale, its chest and legs white.
func _make_dog() -> Node3D:
	var dog := AnimalBody.make("dog", DOG_COATS[randi() % DOG_COATS.size()], Color(-1, 0, 0), false, 130.0)
	dog.name = "Dog"
	return dog
