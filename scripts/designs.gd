class_name Designs
extends RefCounted
## Ready machines (the same [id, x, y, z, rot] rows a saved design has): the starter you begin with,
## the builder's ready designs (PRESETS), and the ones the other side drives in the arena. (The
## cage's rivals are Forge's, a new one each fight.)

## The builder's ready designs: [name, what it is, the function].
const PRESETS := [
	["GEZGİN", "Başlangıç aracı: dört yol tekerleği, bir motor.", "starter"],
	["AKINCI", "Hafif ve çevik: minigun, küçük gövde.", "raider"],
	["TOPÇU", "Ağır: top, zırh, iki motor, arazi tekerleği.", "tank"],
	["ROKETATAR", "Paletli: roket kovanı, akü, iki motor.", "tracked"],
	["KOÇBAŞI", "Silahsız: dikenli burun, iki motor, büyük teker.", "spiked"],
	["ATEŞBAZ", "Alev makinesi ve dikenli burun: yanaşır, yakar.", "brawler"],
	["GÜRZ", "V8'ler, palet, top ve ikinci silah: ağır topçu.", "heavy"],
]


static func preset(i: int) -> Array:
	return (Callable(Designs, str(PRESETS[i][2]))).call()

## A cab on a 4 x 6 lattice bed, the engine behind it, four road wheels, two lights. ~800 kg, 90 kW.
static func starter() -> Array:
	var out := _bed(-1, 2, -2, 3)
	out.append_array([["cab", 0, 1, 0, 0], ["engine", 0, 1, 2, 0], ["light", -1, 1, -2, 0], ["light", 2, 1, -2, 0],
		["wheel_s", 3, -1, -2, 0], ["wheel_s", 3, -1, 2, 0], ["wheel_s", -2, -1, -2, 2], ["wheel_s", -2, -1, 2, 2]])
	return out


## Light and quick: a 3 x 5 bed, the cab, the engine, four road wheels, a minigun on the cab's roof.
## ~780 kg, 90 kW.
static func raider() -> Array:
	var out := _bed(-1, 1, -2, 2)
	out.append_array([["cab", -1, 1, -1, 0], ["engine", -1, 1, 1, 0], ["minigun", -1, 3, -1, 0],
		["wheel_s", 2, -1, -2, 0], ["wheel_s", 2, -1, 1, 0], ["wheel_s", -2, -1, -2, 2], ["wheel_s", -2, -1, 1, 2]])
	return out


## Heavy: a 4 x 6 bed, armour across the middle, two engines, four off-road wheels, the cannon on the
## cab's roof. ~2 t, 180 kW.
static func tank() -> Array:
	var out := _bed(-2, 1, -3, 2)
	out.append_array([["cab", -1, 1, -3, 0], ["engine", -2, 1, 1, 0], ["engine", 0, 1, 1, 0], ["cannon", -1, 3, -3, 0],
		["wheel_l", 2, -1, -3, 0], ["wheel_l", 2, -1, 0, 0], ["wheel_l", -4, -1, -3, 2], ["wheel_l", -4, -1, 0, 2]])
	for x in range(-2, 2):
		for z in range(-1, 1):
			out.append(["armor", x, 1, z, 0])
	return out


## Tracked: a 4 x 6 bed on two tracks, two engines behind the cab, a battery, the rocket pod on the
## cab's roof. ~2.1 t, 180 kW.
static func tracked() -> Array:
	var out := _bed(-1, 2, -3, 2)
	out.append_array([["cab", 0, 1, -3, 0], ["engine", -1, 1, 1, 0], ["engine", 1, 1, 1, 0], ["rockets", 0, 3, -3, 0],
		["battery", -1, 1, -1, 0], ["track", 3, -1, -3, 0], ["track", -3, -1, -3, 2], ["light", 2, 1, -3, 0]])
	return out


## The rammer: no guns, a wedge nose of armour, two engines on big wheels; it drives in under you and
## shoves. ~1.9 t, 180 kW.
static func rammer() -> Array:
	var out := _bed(-1, 2, -2, 2)
	out.append_array([["cab", 0, 1, -1, 0], ["engine", -1, 1, 1, 0], ["engine", 1, 1, 1, 0],
		["wheel_l", 3, -1, -2, 0], ["wheel_l", 3, -1, 1, 0], ["wheel_l", -3, -1, -2, 2], ["wheel_l", -3, -1, 1, 2]])
	for x in range(-1, 3):
		out.append(["wedge", x, 0, -3, 0])
		out.append(["armor", x, 1, -2, 0])
		out.append(["wedge", x, 1, -3, 0])
	return out


## The rammer with rams along the top of its nose: it hurts more where it strikes, shoves less.
static func spiked() -> Array:
	var out := rammer()
	for e: Array in out:
		if e[0] == "wedge" and e[2] == 1:
			e[0] = "spike"
	return out


## The flamethrower brawler: it closes in behind a spiked nose and burns (Forge's, always the same).
static func brawler() -> Array:
	return Forge.make(7, 2, "brawler").data


## The heavy gunner: V8s on tracks, the cannon and a second gun (Forge's, always the same).
static func heavy() -> Array:
	return Forge.make(11, 4, "artillery").data


## The cage's house robot: wide and low, armour all over the front and the top, two engines on big
## wheels, a light on top. ~2.6 t, 180 kW. (It takes no harm: HouseDriver drives it.)
static func house() -> Array:
	var out := _bed(-2, 2, -2, 2)
	out.append_array([["cab", -1, 1, -1, 0], ["engine", -2, 1, 1, 0], ["engine", 1, 1, 1, 0],
		["wheel_l", 3, -1, -2, 0], ["wheel_l", 3, -1, 1, 0], ["wheel_l", -4, -1, -2, 2], ["wheel_l", -4, -1, 1, 2],
		["light", 0, 3, 0, 0]])
	for x in range(-2, 3):
		out.append(["wedge", x, 0, -3, 0])
		out.append(["armor", x, 1, -2, 0])
		out.append(["wedge", x, 1, -3, 0])
	for x: int in [-2, 1, 2]:
		out.append(["armor", x, 1, -1, 0])
	return out


## A target that doesn't move: a cab behind an armour wall on a bed, no engine.
static func dummy() -> Array:
	var out := _bed(-1, 2, -1, 1)
	out.append(["cab", 0, 1, 0, 0])
	for x in range(-1, 3):
		out.append(["armor", x, 1, -1, 0])
	return out


static func _bed(x0: int, x1: int, z0: int, z1: int) -> Array:
	var out := []
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			out.append(["frame", x, 0, z, 0])
	return out
