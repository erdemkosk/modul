class_name WoodForge
extends RefCounted
## The wood age's crews' machines (the valley's, while it's in the wood age: Wanderers): carts of
## timber on a salvaged cab and engine, a different one each time. A style picks what it fights with:
##   okcu       a ballista on the cab's roof (from the second round now and then a cask of pitch
##              beside it: fire arrows)
##   mancinik   a catapult over the cab and the engine (pitch beside it later: burning pots)
##   kazanci    a cask of boiling oil on the roof and wedges in front: it closes in and pours
##   kocbasi    no weapon: a double nose of wedges, planked all over, the most power it can carry
## and, whatever the style: a bed of timber frames (bigger by the round), planking over the cab's face,
## wedges across the nose, wooden wheels (four, six when it's heavy; salvaged road wheels later on).
##
##   make(seed_, tier, style = "")  -> {name, style, data}

const STYLES := ["okcu", "mancinik", "kazanci", "kocbasi"]
const NAMES := {
	"okcu": ["OKÇU", "YAYCI", "KİRPİ", "ATMACA"], "mancinik": ["MANCINIKÇI", "TAŞÇI", "KALE KIRAN"],
	"kazanci": ["KAZANCI", "KATRANCI", "ZİFT"], "kocbasi": ["KOÇ", "TOKMAK", "KÜTÜK", "DÜVE"],
}

var rng: RandomNumberGenerator
var tier := 0
var style := ""
var out: Array = []
var _occ := {}


static func make(seed_: int, tier_: int, style_ := "") -> Dictionary:
	var f := WoodForge.new()
	f.rng = RandomNumberGenerator.new()
	f.rng.seed = seed_
	f.tier = tier_
	f.style = style_ if style_ != "" else STYLES[f.rng.randi() % STYLES.size()]
	f._build()
	var names: Array = NAMES[f.style]
	return {"name": names[f.rng.randi() % names.size()], "style": f.style, "data": f.out}


func _put(id: String, at: Vector3i, rot := 0) -> bool:
	var cells := Parts.cells_of(id, at, rot)
	for c in cells:
		if _occ.has(c):
			return false
	for c in cells:
		_occ[c] = id
	out.append([id, at.x, at.y, at.z, rot])
	return true


func _mass() -> float:
	var m := 0.0
	for e: Array in out:
		m += float(Parts.def(str(e[0])).mass)
	return m


func _build() -> void:
	var big := tier >= 2 or style == "mancinik"
	var w := 4 if big else 3
	var l := 6 if big else 5
	var x0 := -1
	var x1 := x0 + w - 1
	var z0 := -2
	var z1 := z0 + l - 1
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			_put("wood_frame", Vector3i(x, 0, z))
	var cx := 0
	var cz := z0
	_put("wood_cab", Vector3i(cx, 1, cz))
	_put("engine" if big or style == "kocbasi" else "engine_s", Vector3i(cx, 1, cz + 2))
	match style:
		"okcu":
			_put("ballista", Vector3i(cx, 3, cz))
		"mancinik":
			_put("catapult", Vector3i(cx, 3, cz))
		"kazanci":
			_put("oilpot", Vector3i(cx, 3, cz))
	# pitch beside the weapon, on a post of frames (later on)
	if style in ["okcu", "mancinik"] and tier >= 1 and rng.randf() < 0.3 + 0.15 * tier:
		var px := cx + 2 if x1 >= cx + 2 else cx - 1
		if _put("wood_frame", Vector3i(px, 1, cz)) and _put("wood_frame", Vector3i(px, 2, cz)):
			_put("pitch", Vector3i(px, 3, cz))
	# the cab's face planked over, wedges across the nose (two rows for a ram)
	for x in range(cx, cx + 2):
		for y: int in [1, 2]:
			_put("wood_plate", Vector3i(x, y, cz - 1))
	for x in range(x0, x1 + 1):
		_put("wood_wedge", Vector3i(x, 0, z0 - 1))
		if style == "kocbasi":
			_put("wood_wedge", Vector3i(x, 0, z0 - 2))
	if style == "kocbasi" or tier >= 2:
		for z in range(z0, z1 + 1):
			_put("wood_plate", Vector3i(x0, 1, z), 1)
			_put("wood_plate", Vector3i(x1, 1, z), 3)
	if style == "kocbasi" and big:
		_put("engine_s", Vector3i(cx, 3, cz + 2)) # (all the power it can carry)
	# the wheels: wooden ones, salvaged road wheels later on; six when it's heavy
	var wheel := "wheel_s" if tier >= 3 and rng.randf() < 0.5 else "wood_wheel"
	var rated := float(Parts.def(wheel).rated)
	var zs: Array[int] = [z0, z1 - 1]
	if _mass() * 1.15 + 4.0 * float(Parts.def(wheel).mass) > 4.0 * rated:
		zs.append(z0 + (l - 2) / 2)
	for z in zs:
		_put(wheel, Vector3i(x1 + 1, -1, z), 0)
		_put(wheel, Vector3i(x0 - 1, -1, z), 2)
