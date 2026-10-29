class_name CageRecord
extends RefCounted
## What KAFES remembers from run to run (user://cage_record.cfg): ŞÖHRET (fame, earned by the rounds
## you win, more the further in, and a champion's purse of it), the runs, the furthest you got, the
## titles; and the parts fame opens for building there (UNLOCKS: a part not yet open can't be put on,
## nor a design with it loaded).

static var save_path := "user://cage_record.cfg" ## (tests point it elsewhere)

const ROUND_FAME := 20 ## a round won (+ ROUND_STEP a round further in)
const ROUND_STEP := 10
const TITLE_FAME := 150 ## the championship
## Fame -> the parts it opens (the rest are open from the start).
const UNLOCKS := [[60, ["track", "barrel"]], [140, ["flipper", "turret"]], [240, ["flamer", "engine_l"]],
	[380, ["rockets", "hinge"]], [560, ["rotor", "piston"]]]

var fame := 0
var runs := 0
var best_round := 0 ## rounds won in the best run
var titles := 0


static func load_record() -> CageRecord:
	var r := CageRecord.new()
	var cf := ConfigFile.new()
	if cf.load(save_path) == OK:
		r.fame = int(cf.get_value("kafes", "fame", 0))
		r.runs = int(cf.get_value("kafes", "runs", 0))
		r.best_round = int(cf.get_value("kafes", "best_round", 0))
		r.titles = int(cf.get_value("kafes", "titles", 0))
	return r


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("kafes", "fame", fame)
	cf.set_value("kafes", "runs", runs)
	cf.set_value("kafes", "best_round", best_round)
	cf.set_value("kafes", "titles", titles)
	cf.save(save_path)


## The fame a run that won `won` rounds (and the title with `champion`) earns.
static func fame_for(won: int, champion: bool) -> int:
	var f := 0
	for i in won:
		f += ROUND_FAME + ROUND_STEP * i
	return f + (TITLE_FAME if champion else 0)


## A run over: its fame added, the record kept; what it opened ([part ids]).
func add_run(won: int, champion: bool) -> Dictionary:
	var before := fame
	var gained := fame_for(won, champion)
	fame += gained
	runs += 1
	best_round = maxi(best_round, won)
	if champion:
		titles += 1
	save()
	var opened := []
	for u: Array in UNLOCKS:
		if before < int(u[0]) and fame >= int(u[0]):
			opened.append_array(u[1])
	return {"gained": gained, "opened": opened}


## The fame a part needs (0: open from the start).
static func needs(id: String) -> int:
	for u: Array in UNLOCKS:
		if id in u[1]:
			return int(u[0])
	return 0


func is_open(id: String) -> bool:
	return fame >= needs(id)


## "" if `id` is open; else what it needs, for the builder's tile.
func lock_note(id: String) -> String:
	return "" if is_open(id) else "%d ŞÖHRET" % needs(id)


## The parts of a design not open yet.
func locked_in(data: Array) -> Array:
	var out := []
	for e: Array in data:
		if not is_open(str(e[0])) and not str(e[0]) in out:
			out.append(str(e[0]))
	return out


## The next unlock: [fame, [ids]] (empty when all are open).
func next_unlock() -> Array:
	for u: Array in UNLOCKS:
		if fame < int(u[0]):
			return u
	return []
