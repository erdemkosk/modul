class_name RutStore
## What the world remembers of you (user://world_marks.save): the ruts dug into
## every patch of mud and snow, the ground churned to mud where wheels spun
## on wet grass, and the trail your wheels have run along. Saved with the
## world, put back as the world is built.

const TRAIL_CELL := 1.0 ## m

## Next to the world save (so a test has its own).
static func _file() -> String:
	return SaveGame.save_file.get_basename() + "_marks.save"
static var ruts := {} ## "x,z" tile -> zstd depth grid
static var churned := {} ## soft-map texel index -> mud value 0..255
## Where your wheels have run: 1 m cell (Vector2i) -> the day you first drove it. A route
## driven on an earlier day is known ground: the night's mines go round it (Minefield).
static var trail := {}
## Trees you felled with the axe: WorldProps prop index -> the day. They stay down.
static var cut := {}
static var loaded := false


static func load_marks() -> void:
	loaded = true
	var f := FileAccess.open(_file(), FileAccess.READ)
	if f == null:
		return
	var d: Variant = f.get_var()
	if d is Dictionary:
		ruts = d.get("ruts", {})
		churned = d.get("churned", {})
		trail = d.get("trail", {})
		cut = d.get("cut", {})


static func save_marks() -> void:
	var f := FileAccess.open(_file(), FileAccess.WRITE)
	if f:
		f.store_var({"ruts": ruts, "churned": churned, "trail": trail, "cut": cut})


static func clear() -> void:
	ruts = {}
	churned = {}
	trail = {}
	cut = {}
	loaded = true
	save_marks()


## A wheel ran over (x, z) on `day`.
static func drive_over(x: float, z: float, day: int) -> void:
	var c := Vector2i(floori(x / TRAIL_CELL), floori(z / TRAIL_CELL))
	if not trail.has(c):
		trail[c] = day


## Driven over before `day` within about a metre of (x, z): ground you know is clear.
static func known_before(x: float, z: float, day: int) -> bool:
	var c := Vector2i(floori(x / TRAIL_CELL), floori(z / TRAIL_CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var d: Variant = trail.get(c + Vector2i(dx, dz))
			if d != null and int(d) < day:
				return true
	return false
