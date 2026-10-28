class_name WarMap
extends RefCounted
## What the terrain needs from the valley's map data (assets/world/world.json): its roads.

const WORLD_JSON := "res://assets/world/world.json"

static var _data: Dictionary = _read()
static var _roads := {}


static func _read() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(WORLD_JSON))
	return d if d is Dictionary else {}


## Road polylines: name -> PackedVector2Array (x, z).
static func roads() -> Dictionary:
	if _roads.is_empty() and _data.has("roads"):
		for k: String in _data.roads:
			var pts := PackedVector2Array()
			for q in _data.roads[k]:
				pts.append(Vector2(float(q[0]), float(q[1])))
			_roads[k] = pts
	return _roads
