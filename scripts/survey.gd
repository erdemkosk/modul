class_name Survey
extends RefCounted
## What's known of the valley: the seams of stone, iron and coal lie where they lie, far apart, and
## none of them is on the map till someone's seen it. Whoever walks near one finds it, a watchtower
## sees further; the nearest stone is known from the start (the line's surveyors marked it).

const SIGHT := 45.0 ## m a walker finds a seam at
const TOWER_SIGHT := 130.0 ## m from a watchtower
const NAMES := {"stone": "Taş ocağı", "iron": "Demir damarı", "coal": "Kömür damarı"}
const WORDS := ["doğuda", "güneydoğuda", "güneyde", "güneybatıda", "batıda", "kuzeybatıda", "kuzeyde", "kuzeydoğuda"]

var v: Node ## the Village
var found: Array[int] = [] ## indices into props.veins


func _init(village: Node) -> void:
	v = village


## Rocks still standing in vein `i`.
func left(i: int) -> int:
	var n := 0
	for r: int in v.props.veins[i].rocks:
		if not v.props.cut.has(r):
			n += 1
	return n


## Every couple of seconds: anyone near a seam not yet on the map, and the towers.
func tick() -> void:
	if v.props == null or v.props.veins.is_empty() or v.stores().is_empty():
		return
	var veins: Array[Dictionary] = v.props.veins
	if found.is_empty():
		_first_stone(veins)
	if found.size() >= veins.size():
		return
	for i in veins.size():
		if i in found:
			continue
		var at: Vector2 = veins[i].at
		var who: Variant = _seen_by(at)
		if who != null:
			found.append(i)
			_tell(veins[i], str(who))


func _first_stone(veins: Array[Dictionary]) -> void:
	var from := _home()
	var best := -1
	var bd := INF
	for i in veins.size():
		var d: float = (veins[i].at as Vector2).distance_to(from)
		if veins[i].ore == "stone" and d < bd:
			bd = d
			best = i
	if best >= 0:
		found.append(best)


## Who's seen `at`: a name, or null.
func _seen_by(at: Vector2) -> Variant:
	for o: Villager in v.villagers:
		if not o.dead and Vector2(o.position.x, o.position.z).distance_to(at) < SIGHT:
			return o.display_name
	for b: Building in v.buildings:
		if b.def.role == "tower" and b.state == "done" and Vector2(b.global_position.x, b.global_position.z).distance_to(at) < TOWER_SIGHT:
			return b.display_name()
	return null


func _home() -> Vector2:
	var st: Array = v.stores()
	if st.is_empty():
		return Vector2.ZERO
	var p: Vector3 = (st[0] as Node3D).global_position
	return Vector2(p.x, p.z)


func _tell(e: Dictionary, who: String) -> void:
	var d: Vector2 = (e.at as Vector2) - _home()
	var side: String = WORDS[posmod(roundi(d.angle() / (TAU / 8.0)), 8)]
	v.message.emit("%s bir %s buldu: %d m %s (G: harita)." % [who, str(NAMES[e.ore]).to_lower(), roundi(d.length()), side], "good")


func save() -> Array:
	return found.duplicate()


func restore(d: Array) -> void:
	found.clear()
	for i: Variant in d:
		found.append(int(i))
