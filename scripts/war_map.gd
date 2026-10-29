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


## The valley's named places: [{id, name, kind, pos: Vector2 (x, z), radius}].
static func places() -> Array:
	var out := []
	for p: Dictionary in _data.get("places", []):
		out.append({"id": str(p.id), "name": str(p.name), "kind": str(p.kind), "pos": Vector2(float(p.pos[0]), float(p.pos[1])),
			"radius": float(p.get("radius", 40.0))})
	return out


## Where roads go through the river (no bridge): [{road, at: Vector2}].
static func fords() -> Array:
	var out := []
	for f: Dictionary in _data.get("fords", []):
		out.append({"road": str(f.road), "at": Vector2(float(f.x), float(f.z))})
	return out


## The river's line (x, z) and how wide it is either side.
static func river() -> Dictionary:
	var r: Dictionary = _data.get("river", {})
	var pts := PackedVector2Array()
	for q: Array in r.get("points", []):
		pts.append(Vector2(float(q[0]), float(q[2])))
	return {"points": pts, "half_width": float(r.get("half_width", 8.0))}


## A road's name as the map has it ("Geçit yolu").
static func road_name(id: String) -> String:
	var info: Dictionary = _data.get("road_info", {})
	return str(info.get(id, {}).get("name", id))


## The nearest point on any road to `p`, with the road's id: {at: Vector2, road, dist}.
static func nearest_road(p: Vector2) -> Dictionary:
	var best := {"at": p, "road": "", "dist": INF}
	var rs := roads()
	for k: String in rs:
		var pts: PackedVector2Array = rs[k]
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			var d := q.distance_to(p)
			if d < float(best.dist):
				best = {"at": q, "road": k, "dist": d}
	return best
