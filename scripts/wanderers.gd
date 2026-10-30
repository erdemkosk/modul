class_name Wanderers
extends Node
## The valley's other machines: Forge's, with crews, out there to be hunted (and hunting). There are
## up to `keep` of them within RANGE of you; a new one comes in now and then, SPAWN_MIN..SPAWN_MAX m
## off on dry ground, as strong as the machine you've built (by its weight: build bigger, they come
## bigger); one that's further than GONE is taken away. What comes off them whole is salvage. In the
## wood age they're wooden, with the wood age's weapons (WoodForge); after, now and then still.

const RANGE := 400.0
const GONE := 550.0
const SPAWN_MIN := 170.0
const SPAWN_MAX := 260.0
const EVERY := 25.0 ## s between arrivals at most

var game: Node
var terrain: Node
var keep := 2
var machines: Array[Machine] = []
var _t := 8.0
var _n := 0


func _physics_process(dt: float) -> void:
	var mv: Variant = game.get("machine")
	if not is_instance_valid(mv):
		return
	var me := mv as Machine
	for k in range(machines.size() - 1, -1, -1):
		var e := machines[k]
		if not is_instance_valid(e) or not e.alive:
			machines.remove_at(k)
			continue
		if e.global_position.distance_to(me.global_position) > GONE:
			e.queue_free()
			machines.remove_at(k)
	_t -= dt
	if _t > 0.0 or machines.size() >= keep:
		return
	_t = EVERY
	spawn_near(me.global_position)


## One more, somewhere dry SPAWN_MIN..SPAWN_MAX m from `at`. Null if nowhere would do.
func spawn_near(at: Vector3) -> Machine:
	var me: Machine = game.get("machine")
	var shop: Variant = game.get("workshop")
	if shop and (shop as Workshop).yours(): # (as strong as your machine, not the workshop truck you're driving)
		me = (shop as Workshop).yours()
	var tier := clampi(int((me.total_mass - 700.0) / 450.0), 0, 5) if is_instance_valid(me) else 0
	for tries in 12:
		var a := randf() * TAU
		var r := randf_range(SPAWN_MIN, SPAWN_MAX)
		var p := at + Vector3(cos(a), 0.0, sin(a)) * r
		if terrain.has_method("is_water") and bool(terrain.call("is_water", p.x, p.z)):
			continue
		p.y = float(terrain.call("height_at", p.x, p.z)) + 1.8
		_n += 1
		var made := WoodForge.make(randi() + _n, tier) if Inventory.age() == 1 or randf() < 0.3 else Forge.make(randi() + _n, tier)
		var face := Basis(Vector3.UP, atan2(p.x - at.x, p.z - at.z))
		var e: Machine = game.call("_spawn", made.data, Transform3D(face, p), 1, true)
		e.label = made.name
		machines.append(e)
		return e
	return null
