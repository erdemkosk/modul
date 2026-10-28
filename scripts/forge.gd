class_name Forge
extends RefCounted
## Builds the other side's machines: a different one each time, put together the way a builder with
## sense would. A style picks what it fights with and how it's laid out:
##   skirmisher  light and quick: a small bed, a minigun, a small engine or two, road wheels
##   gunner      a minigun on the cab, armour across its nose
##   artillery   the cannon, armour, big engines, off-road wheels or tracks
##   rocketeer   the rocket pod, a battery, tracks when it's heavy
##   brawler     a flamethrower and a spiked nose: it closes in and burns
##   rammer      no guns, a nose of spikes and wedges, all the power it can carry
## and then, whatever the style: the cab at the front of the bed, the guns on the cab's roof (a
## second gun from the fourth round), armour or plates or rams across the front by the round, a
## battery if the guns draw more than the engines charge, the running gear chosen for the weight (road
## wheels, off-road wheels, tracks: rated for what it weighs, with a margin), and engines added until
## its power for its weight reaches the round's mark. Everything's checked to bolt to the cab.
##
##   make(seed_, tier, style = "")  -> {name, style, data}  (data: the [id, x, y, z, rot] rows)

const STYLES := ["skirmisher", "gunner", "artillery", "rocketeer", "brawler", "rammer"]
const NAMES := {
	"skirmisher": ["PASLI", "SİNEK", "ÇAKAL", "SERÇE"], "gunner": ["AVCI", "ŞAHİN", "KARABİBER", "DOĞAN"],
	"artillery": ["TOPÇU", "GÜRZ", "BALYOZ", "DEMİRYUMRUK"], "rocketeer": ["YILDIRIM", "KATYUŞA", "ŞİMŞEK"],
	"brawler": ["ATEŞBÖCEĞİ", "EJDER", "KIVILCIM"], "rammer": ["KOÇBAŞI", "BOĞA", "MANDA", "TOSUN"],
}


static func make(seed_: int, tier: int, style := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	if style == "":
		var pool := ["skirmisher", "gunner", "brawler", "rammer"]
		if tier >= 1:
			pool.append_array(["artillery", "rocketeer"])
		style = pool[rng.randi() % pool.size()]
	var f := Forge.new()
	f.rng = rng
	f.tier = tier
	f.style = style
	f._build()
	var names: Array = NAMES[style]
	return {"name": names[rng.randi() % names.size()], "style": style, "data": f.out}


var rng: RandomNumberGenerator
var tier := 0
var style := ""
var out: Array = []
var _occ := {} ## cell -> the kind of part in it
var x0 := 0
var x1 := 0
var z0 := 0
var z1 := 0


func _put(id: String, at: Vector3i, rot := 0) -> bool:
	var cells := Parts.cells_of(id, at, rot)
	for c in cells:
		if _occ.has(c):
			return false
	for c in cells:
		_occ[c] = str(Parts.def(id).kind)
	out.append([id, at.x, at.y, at.z, rot])
	return true


func _mass() -> float:
	var m := 0.0
	for e: Array in out:
		m += float(Parts.def(str(e[0])).mass)
	return m


func _power() -> float:
	var p := 0.0
	for e: Array in out:
		var d := Parts.def(str(e[0]))
		if str(d.kind) == "engine":
			p += float(d.power)
	return p


func _build() -> void:
	var light := style == "skirmisher"
	var heavy := style in ["artillery", "rocketeer"]
	# the bed: 3 or 4 wide for the light, 4 (now and then 5 later on, always for a heavy one late on)
	# for the rest; 5 long for the light, 6 (or 7 later on) for the rest
	var w := (3 + rng.randi() % 2) if light else (5 if heavy and tier >= 3 or tier >= 2 and rng.randf() < 0.25 else 4)
	var l := 5 if light else (7 if tier >= 2 and rng.randf() < 0.3 else 6)
	x0 = -(w / 2)
	x1 = x0 + w - 1
	z0 = -(l / 2)
	z1 = z0 + l - 1
	var plated := tier >= 3 and not light and rng.randf() < 0.6
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			_put("plate" if plated and (x == x0 or x == x1) else "frame", Vector3i(x, 0, z))
	# the cab at the front, in the middle, its gun on its roof
	var cx := x0 + (w - 2) / 2
	_put("cab", Vector3i(cx, 1, z0))
	var guns: Array[String] = []
	match style:
		"skirmisher", "gunner":
			guns.append("minigun")
		"artillery":
			guns.append("cannon")
		"rocketeer":
			guns.append("rockets")
		"brawler":
			guns.append("flamer")
	if not guns.is_empty():
		_put(guns[0], Vector3i(cx, 3, z0))
	# the nose: rams for those that close in, else wedges or plate (from the second round)
	var nose := "wedge" if rng.randf() < 0.65 else "plate"
	for x in range(x0, x1 + 1):
		if style == "rammer" or style == "brawler" and (x < cx or x > cx + 1):
			_put("spike", Vector3i(x, 0, z0 - 1))
		elif style == "brawler" or tier >= 1:
			_put(nose, Vector3i(x, 0, z0 - 1))
	var face := "armor" if tier >= 4 or style == "rammer" or rng.randf() < 0.3 else "plate"
	for x in range(x0, x1 + 1):
		if x >= cx and x <= cx + 1:
			continue # (the cab's there)
		if style == "rammer" or tier >= 2 and not light:
			_put(face, Vector3i(x, 1, z0))
	if style == "rammer":
		for x in range(cx, cx + 2):
			_put("spike", Vector3i(x, 1, z0 - 1)) # (in front of the cab)
	# the first engine, then a battery if the guns draw more than it charges, then a second gun (from
	# the third round now and then), then engines till it's quick enough for the round
	_add_engine(light, heavy)
	var draw := 0.0
	for g in guns:
		var dk: Array = MachineGun.DRAW[g]
		draw += float(dk[0]) + float(dk[1]) + float(dk[2])
	if draw > 2.8:
		_place_on_bed("battery")
	if not guns.is_empty() and rng.randf() < (0.6 if tier >= 3 else (0.25 if tier == 2 else 0.0)):
		var second: String = "minigun" if style == "brawler" else ["minigun", "rockets", "flamer"][rng.randi() % 3]
		if _place_on_bed(second):
			guns.append(second)
			if not _has("battery"):
				_place_on_bed("battery")
	var gear_kind := _gear_kind(light, heavy)
	var mark := (70.0 + 12.0 * tier) * (1.2 if light or style == "rammer" else 1.0)
	for i in 8:
		gear_kind = _gear_kind(light, heavy)
		if _power() / ((_mass() + _gear_mass(gear_kind)) / 1000.0) >= mark:
			break
		if not _add_engine(light, heavy):
			break
	# lights at the front corners (or on the roof of a cab with no gun)
	for x: int in [x0, x1]:
		_put("light", Vector3i(x, 1, z0))
	if guns.is_empty():
		_put("light", Vector3i(cx, 3, z0))
	_running_gear(_gear_kind(light, heavy))
	# what doesn't reach the cab through bolted faces doesn't go on
	out = _connected(out)


func _has(id: String) -> bool:
	for e: Array in out:
		if str(e[0]) == id:
			return true
	return false


## Where an engine (or a battery) goes: on the bed behind the cab, the first free spot from the back.
func _place_on_bed(id: String) -> bool:
	var s := Parts.size_of(id, 0)
	for y: int in [1, 3]: # (on the bed, else on top of an engine)
		for z in range(z1 - s.z + 1, z0 + 1, -1):
			for x in range(x0, x1 - s.x + 2):
				var at := Vector3i(x, y, z)
				if y > 1 and not _held(id, at):
					continue
				if _put(id, at):
					return true
	return false


## Every cell of it has an engine's under it (what's stacked stands on something).
func _held(id: String, at: Vector3i) -> bool:
	for c in Parts.cells_of(id, at, 0):
		var under := c + Vector3i.DOWN
		if not _occ.has(under) or _occ[under] != "engine":
			return false
	return true


## The engine its kind would have (small for the light early on, the V8 for the heavy later), or,
## if there's no room for that, whatever does fit: the V8, the diesel, the small one.
func _add_engine(light: bool, heavy: bool) -> bool:
	var choice := "engine_s" if light and tier < 3 else ("engine_l" if heavy and tier >= 2 else "engine")
	for id: String in [choice, "engine_l", "engine", "engine_s"]:
		if _place_on_bed(id):
			return true
	return false


## Road wheels if they'll carry it (off-road ones now and then anyway on all but the light), else
## off-road wheels, else tracks; the heavy ones on tracks from the third round, now and then before.
## (Fixed once it's chosen: the same answer each time it's asked.)
var _gear_roll := -1.0


func _gear_kind(light: bool, heavy: bool) -> String:
	if _gear_roll < 0.0:
		_gear_roll = rng.randf()
	var m := _mass()
	if heavy and (tier >= 3 or tier >= 1 and _gear_roll < 0.5) and z1 - z0 + 1 >= 6:
		return "track"
	if m * 1.15 + 4 * 32.0 <= 4 * 450.0 and (light or _gear_roll >= 0.4):
		return "wheel_s"
	if m * 1.15 + 4 * 85.0 <= 4 * 1200.0:
		return "wheel_l"
	return "track"


func _gear_mass(kind: String) -> float:
	return 2.0 * 380.0 if kind == "track" else 4.0 * float(Parts.def(kind).mass)


## Wheels (two a side, front and back) or a track a side, hung under the bed's edges.
func _running_gear(kind: String) -> void:
	var s := Parts.size_of(kind, 0)
	if kind == "track":
		_put("track", Vector3i(x1 + 1, -1, z0), 0)
		_put("track", Vector3i(x0 - s.x, -1, z0), 2)
		return
	for z: int in [z0, z1 - s.z + 1]:
		_put(kind, Vector3i(x1 + 1, -1, z), 0)
		_put(kind, Vector3i(x0 - s.x, -1, z), 2)


## Only the rows reaching the cab through bolted faces.
static func _connected(rows: Array) -> Array:
	var parts := []
	for e: Array in rows:
		parts.append({"id": str(e[0]), "at": Vector3i(int(e[1]), int(e[2]), int(e[3])), "rot": int(e[4])})
	var kept := Cage._connected(parts)
	var outr := []
	for p: Dictionary in kept:
		outr.append([p.id, p.at.x, p.at.y, p.at.z, p.rot])
	return outr
