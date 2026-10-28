class_name Designs
extends RefCounted
## Ready machines (the same [id, x, y, z, rot] rows a saved design has): the starter you begin with,
## and the ones the other side drives.

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
