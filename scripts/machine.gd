class_name Machine
extends RigidBody3D
## A machine put together from parts (Parts) on a grid: one rigid body whose mass is its parts'
## mass and whose centre of mass is theirs, its blocks' boxes for collision. The front is -z.
##
## Wheels are rays: a spring and a damper over the wheel's travel (as stiff as the wheel's rated
## load asks: overloaded it sits on its bump stop), the tyre's grip from the ground under it
## (Surface: asphalt grips, mud doesn't) times the tyre's own (lugs in the soft, rubber on the
## hard), a friction circle shared between driving and cornering. On soft ground (mud, bog, snow)
## each wheel sinks by how hard it presses (its load over its tyre's footprint), digs in when it
## spins, drags for being down in it, and leaves its rut in the ground (SoftPatch).
## The engines' power is shared by the wheels on the ground (P = F v: strong at a crawl, less as
## it goes faster); the wheels ahead of the centre of mass steer, and every wheel helps turn by
## pushing harder on the outside (skid steer), so a six-wheeler turns too. The air drags on its
## front.
##
## Tracks (MachineTrack) are five road wheels each, pressing through a belt that spreads the load;
## they don't steer but turn the machine by driving one side harder (or back: on the spot), sliding
## round as they do.
##
## Electricity: the cab's small battery and any battery parts hold energy; the engines' alternators
## charge it (more as they rev), the guns' motors, the turrets turning, the loaders and the lights
## draw on it. Running low, it sheds what's least needed first: under SHED[0] of its charge the lights
## go out, under SHED[1] the loaders stop, under SHED[2] the minigun's motor; flat, the turrets stop
## too, until the engines have put some back (each comes back on a little above where it went off).
## `consumers` says what draws what this moment and what's been shed (the drive HUD shows it).
##
## Weapons (MachineGun) turn to `aim_point` and fire while `firing`. Hit, a part loses hit points
## (Parts.hp_of); at none it comes off as debris (Combat), and so does whatever was bolted on only
## through it; the cab gone, the whole machine comes apart.
##
## Knocks hurt too: a blow on its body (ramming, being rammed, a wall, landing hard off a ramp) takes
## hit points off the part where it struck, by how sharply it changed the machine's speed past what
## its build takes without harm (IMPACT_SAFE m/s). Whatever comes off, the machine is worked out anew
## (its mass, centre of mass, wheels, power), so it sits, steers and drives as what's left of it.
## It's dead when its cab is gone (the driver's in it); with no engine or nothing to run on it's
## `immobile` (the player can have it rebuilt).
##
## What a hurt part does: an engine gives less power as it's hurt (sputtering when badly), a tyre
## bursts under TYRE_BURST of its hit points (it sits lower, grips half as well, drags and wobbles),
## a track is thrown under TRACK_THROWN (its side drives no more and slides), a battery hit loses
## charge and holds less, a hurt gun turns slower and, badly hurt, jams. Each says so (system_hit),
## and every hit on a part is told to Combat (part_hit) for the HUD's numbers.
##
## Hurt shows: a part darkens with soot and the pocks of rounds as it's hurt (part_wear.gdshader), and
## one badly hurt smokes (an engine black and burning) — at most SMOKERS of them, the worst.
##
## The design is a list of {id, at (Vector3i: the footprint's low corner), rot (quarter turns), hp}.

signal changed
signal died
## It took `amount` hp from `from` (where the shot came from, or the burst or the knock was), by
## `kind` (minigun, top, roket, patlama, çarpışma): what the HUD shows you.
signal damaged(amount: float, from: Vector3, kind: String)
## One of its systems gave (a tyre burst, the engine weakened, ...): `text` for the screen.
signal system_hit(text: String, at: Vector3)

const RAY_MASK := 1
const DRIVER_AT := {"wood_cab": Vector3(0.0, -0.1, 0.12), "cab": Vector3(0.0, -0.3, 0.12)} ## the driver's seat, in the cab's space
const MAX_STEER := 0.55 ## rad, slow; less going faster
const AIR_DENSITY := 1.2
const CD := 0.9
const BUMP_STIFF := 8.0 ## the bump stop, times the spring
const TRACTION := 0.6 ## the most the drive pushes at a crawl, times its weight
const STAMP_STEP := 0.12
const IMPACT_SAFE := 3.0 ## m/s a knock changes its speed by without harm
const BLAST_DV := 2.5 ## m/s the most a burst's heave changes its speed by
const TYRE_BURST := 0.55 ## a wheel's share of hit points under which its tyre's burst
const TRACK_THROWN := 0.4 ## a track's under which it's thrown
const MAX_RISE := 9.0 ## m/s up it can be going at most (whatever's gone wrong, it doesn't fly off)
const MAX_SPIN := 7.0 ## rad/s it can be turning at most
const IMPACT_HURT := 6.0 ## hp per (m/s past it) squared
const IMPACT_REACH := 0.8 ## m round where it struck that the parts take it
const RAM_BITE := 1.7 ## times the knock a ram's spikes give (a third of a ram's blow past the safe takes)
const SMOKERS := 4 ## parts that smoke at once at most
const WEAR := preload("res://shaders/part_wear.gdshader")
static var _wear_mat: ShaderMaterial
var _smoke: Array[GPUParticles3D] = [] ## m a wheel rolls between ruts pressed in

var design: Array = [] ## [{id, at, rot}]
var terrain: Node ## WorldTerrain (surface_at, patch_at); rays find its ground either way
var building := false
## Inputs (Game sets them while you drive): throttle -1..1, steer -1..1 (+ right), brake 0..1.
var throttle := 0.0
var steer := 0.0
var brake := 0.0
var lights_on := false
var team := 0 ## 0 yours, 1 theirs
var alive := true
var aim_point := Vector3.ZERO
var firing := false
var guns: Array[MachineGun] = []
var flippers: Array[MachineFlipper] = []
var hoists: Array[MachineHoist] = [] ## (its cranes and winches)
var tools: Array[MachineTool] = [] ## (its saws)
var joints: Array[MachineJoint] = []
var _chain := {} ## part index -> the joints that carry it, outermost first
var _shapes := {} ## part index -> [[its CollisionShape3D, its box at rest]]
var _cur := -1 ## (rebuilding: the part whose boxes are being made)
var _struck := {} ## (a moving part's blows: what it struck -> s till it can again)
var keyed := false ## (yours: its parts answer to the keys they're given)
var last_hit_by: Machine
var last_hit_kind := "" ## (what hurt it last: the death card's line)
var label := "" ## what it's called on the screen (AKINCI, TANK, ...)
var invulnerable := false ## (the proving ground's G) hits push it but take nothing off
var ammo_limited := false ## its guns' ammunition runs out (Game: everywhere but the proving ground)
var ammo_k := 1.0 ## how many loads its guns carry (a crew's: more)
var wet := 0.0 ## 0..1: the ground soaked by rain (Weather.wetness): what the wheels throw

var power_kw := 0.0
var total_mass := 0.0
var rated_kg := 0.0
var com := Vector3.ZERO
var frontal := 1.0 ## m2
var top_y := 0.0 ## m: the top of its highest part (machine space)
var wheels: Array[MachineWheel] = [] ## (a track's road wheels too)
var tracks: Array[MachineTrack] = []
var part_nodes: Array[Node3D] = [] ## each part's model, in the design's order
var capacity_kj := 0.0 ## the batteries hold
var energy_kj := 0.0
var alternator_kw := 0.0
var draw_kw := 0.0 ## drawn this moment
var charge_kw := 0.0 ## put in this moment
var powered := true ## (false: flat)
var shed := 0 ## 0 all on .. 3: lights, loaders, gun motors off
var consumers: Array[Dictionary] = [] ## [{name, kw, on, off_why}] (the HUD)
const SHED := [0.25, 0.12, 0.05] ## the charge each is shed under
const SHED_BACK := 0.06 ## and comes back this much above it
var _energy_frac := 1.0 ## (kept over a rebuild)
var speed := 0.0 ## m/s along its nose
var ground_label := ""

var _occ := {} ## Vector3i -> design index
var _root: Node3D
var _scenes := {}
var _lamps: Array[SpotLight3D] = []
var _glows: Array[Node3D] = []
var _engine_sound: EngineSound
var _roll_sound: AudioStreamPlayer3D
var _rpm := 0.0
var _fx: Node3D ## the wheels' spray (rebuilt with the parts)
var _catch: GPUParticlesCollisionHeightField3D ## the ground the clods fall onto, round it


func _ready() -> void:
	add_to_group(Hearing.GROUP) # (the terrain makes its soft ground's ruts round these)
	add_to_group("machines")
	collision_layer = 2
	collision_mask = 1 | 2 | 4 # (and what lies about: billets, wrecks' parts; they ride on a bed)
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_root = Node3D.new()
	_root.name = "Parts"
	add_child(_root)
	_catch = GPUParticlesCollisionHeightField3D.new()
	_catch.size = Vector3(40.0, 16.0, 40.0)
	_catch.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_catch.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_catch.top_level = true
	add_child(_catch)
	_engine_sound = EngineSound.new()
	add_child(_engine_sound)
	_roll_sound = _loop("res://assets/audio/dirt_roll_loop.ogg", -60.0)
	rebuild()


func _loop(path: String, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var s := load(path) as AudioStreamOggVorbis
	if s:
		s.loop = true
	p.stream = s
	p.volume_db = db
	p.unit_size = 8.0
	add_child(p)
	return p


# --- The design --------------------------------------------------------------------------------

func part_at(cell: Vector3i) -> int:
	return int(_occ.get(cell, -1))


func cab_index() -> int:
	for i in design.size():
		if Parts.is_cab(design[i].id):
			return i
	return -1


## Can `id` go at `at` turned `rot`: its cells free, and touching a part it can be bolted to
## (not a wheel's or a light's side), a second cab never.
func can_place(id: String, at: Vector3i, rot: int) -> bool:
	if Parts.is_cab(id) and cab_index() >= 0:
		return false
	if Parts.def(id).kind == "track" and rot % 2 == 1:
		return false # (a track runs fore and aft)
	if rot >= 4 and not Parts.can_tilt(id):
		return false # (a wheel, a track, the cab: upright only)
	var cells := Parts.cells_of(id, at, rot)
	for c in cells:
		if _occ.has(c):
			return false
	if design.is_empty():
		return true
	for c in cells:
		for n in _NEIGHBOURS:
			var other := part_at(c + n)
			if other >= 0 and _structural(design[other].id):
				return true
	return false


const _NEIGHBOURS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


static func _structural(id: String) -> bool:
	return Parts.def(id).kind in ["cab", "block", "wedge", "engine", "joint"] # (nothing bolts on through a wheel, a light or a gun)


func place(id: String, at: Vector3i, rot: int) -> bool:
	if not can_place(id, at, rot):
		return false
	design.append({"id": id, "at": at, "rot": rot, "hp": Parts.hp_of(id)})
	rebuild()
	_note_built()
	return true


## Off it comes, unless it's the cab or something would be left hanging by nothing.
func can_remove(i: int) -> bool:
	if i < 0 or i >= design.size() or Parts.is_cab(design[i].id):
		return false
	return _connected_without(i)


func remove(i: int) -> bool:
	if not can_remove(i):
		return false
	design.remove_at(i)
	rebuild()
	_note_built()
	return true


## Every part still reaches the cab through bolted faces with part `skip` gone.
func _connected_without(skip: int) -> bool:
	var cab := cab_index()
	if cab < 0:
		return true
	var occ := {}
	for i in design.size():
		if i != skip:
			for c in Parts.cells_of(design[i].id, design[i].at, design[i].rot):
				occ[c] = i
	var seen := {cab: true}
	var queue: Array[int] = [cab]
	while not queue.is_empty():
		var i: int = queue.pop_back()
		if i != cab and not _structural(design[i].id):
			continue # (nothing bolts on through a wheel or a light)
		for c in Parts.cells_of(design[i].id, design[i].at, design[i].rot):
			for n in _NEIGHBOURS:
				var j: int = occ.get(c + n, -1)
				if j >= 0 and not seen.has(j):
					seen[j] = true
					queue.append(j)
	return seen.size() == design.size() - (1 if skip >= 0 else 0)


## The design as rows [id, x, y, z, rot, (key), (wear)]; `wear`: a part not whole keeps what it has
## left of its hit points (0..1) seventh (the valley's machines keep their wear; elsewhere they're new).
func to_data(wear := false) -> Array:
	var out := []
	for p: Dictionary in design:
		var row := [p.id, p.at.x, p.at.y, p.at.z, p.rot]
		var frac := clampf(float(p.get("hp", 0.0)) / Parts.hp_of(p.id), 0.0, 1.0)
		if int(p.get("key", 0)) != 0 or (wear and frac < 0.995):
			row.append(int(p.get("key", 0))) # (the key it answers to)
		if wear and frac < 0.995:
			row.append(snappedf(frac, 0.01))
		out.append(row)
	return out


func from_data(data: Array) -> void:
	design.clear()
	for e: Variant in data:
		if e is Array and (e as Array).size() >= 5 and Parts.DEFS.has(str(e[0])):
			var pid := str(e[0])
			var p := {"id": pid, "at": Vector3i(int(e[1]), int(e[2]), int(e[3])), "rot": int(e[4]), "hp": Parts.hp_of(pid)}
			if (e as Array).size() >= 6 and int(e[5]) != 0:
				p.key = int(e[5])
			if (e as Array).size() >= 7: # (worn: what it has left)
				var frac := clampf(float(e[6]), 0.02, 1.0)
				p.hp = Parts.hp_of(pid) * frac
				if frac < TYRE_BURST and Parts.def(pid).kind == "wheel":
					p.flat = true
				if frac < TRACK_THROWN and Parts.def(pid).kind == "track":
					p.thrown = true
			design.append(p)
	rebuild()
	_note_built()
	set_down()


## The parts' models, boxes, mass, centre of mass, wheels and lamps, from the design.
func rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()
	_fx = null
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	_occ.clear()
	if capacity_kj > 0.0:
		_energy_frac = energy_kj / capacity_kj
	wheels.clear()
	part_nodes.clear()
	tracks.clear()
	guns.clear()
	flippers.clear()
	for h in hoists:
		h.free_fx()
	hoists.clear()
	for t in tools:
		t.free_fx()
	tools.clear()
	joints.clear()
	_chain.clear()
	_shapes.clear()
	_lamps.clear()
	_glows.clear()
	power_kw = 0.0
	total_mass = 0.0
	rated_kg = 0.0
	alternator_kw = 0.0
	capacity_kj = Parts.CAB_KWH * 3600.0 if cab_index() >= 0 else 0.0
	var moment := Vector3.ZERO
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in design.size():
		for c in Parts.cells_of(design[i].id, design[i].at, design[i].rot):
			_occ[c] = i # (all of it first: a gun asks what's beside it)
	for i in design.size():
		var p: Dictionary = design[i]
		var d := Parts.def(p.id)
		var xf := Parts.xform_of(p.id, p.at, p.rot)
		_cur = i
		var node := _instance(p.id)
		node.transform = xf
		_root.add_child(node)
		if Parts.is_cab(p.id) and DisplayServer.get_name() != "headless": # (TIKI's kind at the wheel: Mascot)
			var drv := Mascot.creature()
			drv.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * 0.85), DRIVER_AT.get(p.id, Vector3(0, -0.25, 0.1)))
			node.add_child(drv)
		part_nodes.append(node)
		var m: float = d.mass
		total_mass += m
		moment += xf.origin * m
		var ext := Vector3(Parts.size_of(p.id, p.rot)) * Parts.CELL
		lo = lo.min(xf.origin - ext * 0.5)
		hi = hi.max(xf.origin + ext * 0.5)
		match str(d.kind):
			"wheel":
				var mw := MachineWheel.make(self, node, p.id, xf)
				mw.part = i
				mw.flat = bool(p.get("flat", false))
				wheels.append(mw)
				rated_kg += float(d.rated)
			"track":
				var tr := MachineTrack.make(self, node, p.id, xf)
				for b in tr.bogies:
					b.unit = tracks.size()
					b.thrown = bool(p.get("thrown", false))
				tracks.append(tr)
				wheels.append_array(tr.bogies)
				rated_kg += float(d.rated) * tr.bogies.size()
				# (its fender and the top run: hits and walls; the road wheels are rays)
				var tsz := Vector3(Parts.size_of(p.id, p.rot)) * Parts.CELL
				_add_shape(Vector3(tsz.x * 0.9, tsz.y * 0.4, tsz.z * 0.95), xf.origin + Vector3.UP * tsz.y * 0.28)
			"battery":
				capacity_kj += float(d.kwh) * 3600.0 * (0.4 + 0.6 * clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0))
				_add_shape(ext - Vector3.ONE * 0.01, xf.origin)
			"engine":
				var ef := _engine_eff(p)
				power_kw += float(d.power) * ef
				alternator_kw += float(d.get("alternator", 0.0)) * ef
				_add_shape(Vector3(Parts.size_of(p.id, p.rot)) * Parts.CELL * Vector3(0.9, 0.75, 0.95), xf.origin)
			"weapon":
				var mg := MachineGun.make(self, node, p.id, mini(_beside(i, "ammo"), 2), mini(_beside(i, "barrel"), 2))
				mg.key = int(p.get("key", 0))
				mg.fiery = _beside(i, "pitch") > 0
				mg.supply(ammo_limited, ammo_k, p)
				mg.condition = clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0)
				guns.append(mg)
				_add_shape(Vector3(Parts.size_of(p.id, p.rot)) * Parts.CELL * Vector3(0.8, 0.9, 0.8), xf.origin)
			"light":
				_add_lamp(node, xf)
				_add_shape(Vector3(0.3, 0.3, 0.3), xf.origin)
			"wedge":
				_add_wedge(xf)
			"joint":
				var jt := MachineJoint.make(self, node, i, p.id, xf)
				jt.key = int(p.get("key", 0))
				joints.append(jt)
				_add_shape(ext * Vector3(0.95, 0.95, 0.95), xf.origin)
			"crane", "winch":
				var ho := MachineHoist.make(self, node, i, p.id)
				ho.key = int(p.get("key", 0))
				ho.condition = clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0)
				hoists.append(ho)
				_add_shape(ext * Vector3(0.9, 0.8, 0.9), xf.origin)
			"rail": # (a fence a metre high, a plank thick: what's on the bed stays on)
				var r := xf.basis.orthonormalized()
				var half := Vector3(0.24, 0.49, 0.05)
				var box := Vector3(absf(r.x.x) * half.x + absf(r.y.x) * half.y + absf(r.z.x) * half.z,
					absf(r.x.y) * half.x + absf(r.y.y) * half.y + absf(r.z.y) * half.z,
					absf(r.x.z) * half.x + absf(r.y.z) * half.y + absf(r.z.z) * half.z) * 2.0
				_add_shape(box, xf.origin)
			"saw":
				var tl := MachineTool.make(self, node, i, p.id)
				tl.key = int(p.get("key", 0))
				tl.condition = clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0)
				tools.append(tl)
				_add_shape(ext * Vector3(0.9, 0.8, 0.9), xf.origin)
			"flipper":
				var fl := MachineFlipper.make(self, node)
				fl.key = int(p.get("key", 0))
				fl.condition = clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0)
				flippers.append(fl)
				_add_shape(ext * Vector3(0.95, 0.8, 0.95), xf.origin)
			_:
				_add_shape(ext - Vector3.ONE * 0.01, xf.origin)
	_cur = -1
	# what the mouse works (picked on the bottom panel: kept on the part's row): a saw from the start,
	# a crane only if there's nothing else to work
	for t in tools:
		t.armed = bool(design[t.index].get("sel", true))
	for h in hoists:
		if h.kind == "crane":
			h.armed = bool(design[h.index].get("sel", tools.is_empty() and guns.is_empty()))
	_sections()
	if total_mass <= 0.0:
		return
	com = moment / total_mass
	mass = total_mass
	center_of_mass = com
	frontal = maxf((hi.x - lo.x) * (hi.y - lo.y), 0.25)
	top_y = hi.y
	for w in wheels:
		w.steers = w.rest.z < com.z - 0.4 and not w.track and not _chain.has(w.part) # (one on a joint turns with it)
		w.side = signf(w.rest.x - com.x)
	energy_kj = capacity_kj * _energy_frac
	_set_lamps()
	_smoke.clear() # (they went with the part nodes)
	_show_wear()
	changed.emit()


## How many parts of `kind` touch part `i` face to face.
func _beside(i: int, kind: String) -> int:
	var found := {}
	for c in Parts.cells_of(design[i].id, design[i].at, design[i].rot):
		for n in _NEIGHBOURS:
			var k: int = _occ.get(c + n, -1)
			if k >= 0 and k != i and str(Parts.def(design[k].id).kind) == kind:
				found[k] = true
	return found.size()


func _instance(id: String) -> Node3D:
	if not _scenes.has(id):
		_scenes[id] = load(Parts.model(id)) if ResourceLoader.exists(Parts.model(id)) else _stand_in(id)
	var n := (_scenes[id] as PackedScene).instantiate() as Node3D
	PaintedLook.apply(n)
	if TEAM_PAINT.has(team):
		_team_paint(n)
	return n


## A part whose model isn't built yet: a plain box its size (so a new part works before its model's made).
static func _stand_in(id: String) -> PackedScene:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(Parts.def(id).size) * Parts.CELL * 0.94
	mi.mesh = bm
	root.add_child(mi)
	mi.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps


## The other side's colours, on the parts' paint (yours stays the works yellow): the rivals oxide red.
const TEAM_PAINT := {1: Color(0.36, 0.06, 0.045)}
static var _team_mats := {} ## [team, painted material] -> that material in the team's colour


func _team_paint(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for k in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(k)
			if src == null or src.resource_name != "Paint":
				continue
			var painted := mi.get_surface_override_material(k) as ShaderMaterial
			if painted == null:
				continue
			var key := [team, painted]
			if not _team_mats.has(key):
				var m := painted.duplicate() as ShaderMaterial
				m.set_shader_parameter("albedo", TEAM_PAINT[team])
				_team_mats[key] = m
			mi.set_surface_override_material(k, _team_mats[key])


func _add_shape(size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = at
	add_child(cs)
	_note_shape(cs)


## (which part a box belongs to: a joint moves it with the part)
func _note_shape(cs: CollisionShape3D) -> void:
	if _cur >= 0:
		if not _shapes.has(_cur):
			_shapes[_cur] = []
		_shapes[_cur].append([cs, cs.transform])


## A wedge: high at its back (+z of the part, as the model: Blender -Y), down to its front edge.
func _add_wedge(xf: Transform3D) -> void:
	var h := Parts.CELL * 0.5
	var pts := PackedVector3Array()
	for x: float in [-h, h]:
		pts.append_array([Vector3(x, -h, h), Vector3(x, -h, -h), Vector3(x, h, h)])
	var cs := CollisionShape3D.new()
	var s := ConvexPolygonShape3D.new()
	s.points = pts
	cs.shape = s
	cs.transform = xf
	add_child(cs)
	_note_shape(cs)


func _add_lamp(node: Node3D, xf: Transform3D) -> void:
	var l := SpotLight3D.new()
	l.spot_range = 45.0
	l.spot_angle = 32.0
	l.light_energy = 6.0
	l.light_color = Color(1.0, 0.93, 0.8)
	l.shadow_enabled = false # (FPS: a machine with six lights would cost six shadow maps)
	l.position = Vector3(0.0, -0.03, -0.1)
	node.add_child(l)
	_lamps.append(l)
	var g := node.find_child("Glow", true, false) as Node3D
	if g:
		_glows.append(g)


func set_lights(on: bool) -> void:
	lights_on = on
	_set_lamps()


func _set_lamps() -> void:
	for l in _lamps:
		l.visible = lights_on and powered and shed < 1
	for g in _glows:
		g.visible = lights_on and powered and shed < 1


# --- Building ----------------------------------------------------------------------------------

## The cell a ray (world space) first hits and the face it came in through (machine grid):
## {cell, normal, index} or {}.
func pick(from: Vector3, dir: Vector3) -> Dictionary:
	if _occ.is_empty():
		return {}
	var inv := global_transform.affine_inverse()
	var o := inv * from / Parts.CELL
	var d := (inv.basis * dir).normalized()
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for c: Vector3i in _occ:
		lo = lo.min(c)
		hi = hi.max(c)
	# into the occupied box first (slabs), then cell by cell (Amanatides-Woo)
	var t0 := 0.0
	var t1 := 1e9
	for a in 3:
		if absf(d[a]) < 1e-9:
			if o[a] < lo[a] or o[a] > hi[a] + 1:
				return {}
			continue
		var ta := (lo[a] - o[a]) / d[a]
		var tb := (hi[a] + 1 - o[a]) / d[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t0 > t1:
		return {}
	var p := o + d * (t0 + 1e-4)
	var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var step := Vector3i(int(signf(d.x)), int(signf(d.y)), int(signf(d.z)))
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for a in 3:
		if step[a] == 0:
			t_max[a] = INF
			t_delta[a] = INF
		else:
			var edge := float(cell[a] + (1 if step[a] > 0 else 0))
			t_max[a] = t0 + (edge - p[a]) / d[a] + 1e-4
			t_delta[a] = absf(1.0 / d[a])
	# the face it entered through: the axis whose slab it crossed last (at the box: where it came in)
	var normal := Vector3i.ZERO
	var entry := Vector3(absf(p.x - lo.x), absf(p.y - lo.y), absf(p.z - lo.z))
	var near_hi := Vector3(absf(p.x - hi.x - 1), absf(p.y - hi.y - 1), absf(p.z - hi.z - 1))
	var best := INF
	for a in 3:
		if entry[a] < best:
			best = entry[a]
			normal = Vector3i.ZERO
			normal[a] = -1
		if near_hi[a] < best:
			best = near_hi[a]
			normal = Vector3i.ZERO
			normal[a] = 1
	for _i in 256:
		if _occ.has(cell):
			return {"cell": cell, "normal": normal, "index": _occ[cell]}
		var a := 0
		if t_max.y < t_max[a]:
			a = 1
		if t_max.z < t_max[a]:
			a = 2
		cell[a] += step[a]
		t_max[a] += t_delta[a]
		normal = Vector3i.ZERO
		normal[a] = -step[a]
		if cell[a] < lo[a] - 1 or cell[a] > hi[a] + 1:
			return {}
	return {}


## Where `id` (turned `rot`) would go against the face `normal` of `cell`: its footprint's low
## corner, flush against that face and centred on it.
## Wheels and tracks on a side hang down from it (their hub level with the bottom of what they're on).
static func anchor_for(id: String, rot: int, cell: Vector3i, normal: Vector3i) -> Vector3i:
	var s := Parts.size_of(id, rot)
	var t := cell + normal
	var at := Vector3i.ZERO
	var hangs := str(Parts.def(id).kind) in ["wheel", "track"] and normal.y == 0
	for a in 3:
		if normal[a] > 0:
			at[a] = t[a]
		elif normal[a] < 0:
			at[a] = t[a] - (s[a] - 1)
		elif a == 1 and hangs:
			at[a] = t[a] - s[a] / 2
		else:
			at[a] = t[a] - (s[a] - 1) / 2
	return at


## A wheel turned so its inner face is against the face it goes on (on a side, the front, the back).
static func wheel_rot_for(normal: Vector3i, rot: int) -> int:
	if normal.x > 0:
		return 0
	if normal.x < 0:
		return 2
	if normal.z < 0:
		return 1
	if normal.z > 0:
		return 3
	return rot


## Up for building: held still, level, high enough off the ground for its wheels.
func set_building(on: bool) -> void:
	building = on
	for jt in joints:
		jt.reset()
	_place_moving()
	if on:
		var yaw := global_basis.get_euler().y
		var at := global_position
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
		var g := at.y
		if terrain and terrain.has_method("height_at"):
			g = float(terrain.call("height_at", at.x, at.z))
		var low := 0.0
		for c: Vector3i in _occ:
			low = minf(low, c.y * Parts.CELL)
		global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, g + 0.6 - low, at.z))
	else:
		freeze = false
		set_down()
	_engine_sound.stream_paused = on


# --- Driving -----------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if building or total_mass <= 0.0 or not alive:
		return
	# nothing real throws it up faster than this or spins it faster: a guard against a bad contact
	if linear_velocity.y > MAX_RISE:
		linear_velocity.y = MAX_RISE
	if angular_velocity.length() > MAX_SPIN:
		angular_velocity = angular_velocity.normalized() * MAX_SPIN
	# the knocks felt last step (taken here, not in the middle of the physics step)
	if not _knocks.is_empty():
		var ks := _knocks
		_knocks = []
		var total := 0.0
		for e: Array in ks:
			total += float(e[1])
		last_hit_kind = "koç" if _rammed else "çarpışma"
		_rammed = false
		if is_instance_valid(_knock_by):
			last_hit_by = _knock_by
		_knock_by = null
		damaged.emit(total, _knock_at, "çarpışma")
		for e: Array in ks:
			var j := design.find(e[0])
			if j >= 0 and alive:
				damage_part(j, float(e[1]), _knock_at, last_hit_by)
		if not alive:
			return
	_power(dt)
	for g in guns:
		# (yours: a gun with a key of its own fires on that key, the rest on the mouse; a crew's on its own)
		var trig := g.key_down if keyed and g.key != 0 else firing
		g.update(dt, aim_point, trig and g.armed, powered)
	for f in flippers:
		f.update(dt, powered)
	for h in hoists:
		h.update(dt)
	for t in tools:
		t.update(dt)
	if not _burning.is_empty():
		_burn(dt)
	if not joints.is_empty():
		for jt in joints:
			jt.update(dt, powered)
		_place_moving()
		_turn_wheels()
		for k: Variant in _struck.keys():
			_struck[k] = float(_struck[k]) - dt
			if float(_struck[k]) <= 0.0 or not is_instance_valid(k):
				_struck.erase(k) # (its time's up, or it's gone)
	var fwd := -global_basis.z
	speed = linear_velocity.dot(fwd)
	var on_ground: Array[MachineWheel] = []
	for w in wheels:
		w.suspend(dt)
		if w.contact:
			on_ground.append(w)
	# The engines' push, shared by the wheels on the ground: P = F v, at a crawl as much as its lowest
	# gear gives (TRACTION of its weight: more would only stand it on its tail)
	var drive := 0.0
	if power_kw > 0.0 and not on_ground.is_empty():
		drive = minf(power_kw * 1000.0 / maxf(absf(speed), 2.5), TRACTION * total_mass * 9.8) / on_ground.size()
		if power_kw < _full_power * 0.55: # (badly hurt engines miss: the push comes and goes)
			_sputter_t -= dt
			if _sputter_t <= 0.0:
				_sputter_t = randf_range(0.08, 0.3)
				_sputter = randf_range(0.25, 1.0)
			drive *= _sputter
	var steer_angle := steer * MAX_STEER / (1.0 + absf(speed) / 10.0)
	var grip_sum := 0.0
	# a track drives through one belt: what its side gets goes to its road wheels by what each carries
	var unit_load := PackedFloat32Array()
	var unit_n := PackedInt32Array()
	unit_load.resize(tracks.size())
	unit_n.resize(tracks.size())
	for w in on_ground:
		if w.unit >= 0:
			unit_load[w.unit] += w.load
			unit_n[w.unit] += 1
	for w in on_ground:
		var push := throttle * drive
		if w.thrown:
			push = 0.0 # (its belt's off: it runs on nothing)
		elif w.track:
			# a track turns by its sides: the outside driven, the inside held back or run backwards
			# (on the spot with no throttle); slewing round, its belt slides sideways
			var k := 1.0 if absf(throttle) < 0.1 else 0.8
			push = clampf(throttle - steer * w.side * k, -1.0, 1.0) * drive * unit_n[w.unit] * w.load / maxf(unit_load[w.unit], 1.0)
			w.lat_scale = 0.35 if absf(steer) > 0.1 else 1.0
		else:
			# the outside of the turn pushes harder, the inside less (helps any machine round)
			push -= steer * w.side * drive * 0.35 * (1.0 if absf(throttle) > 0.05 else 0.8)
		w.tyre(dt, push, brake, steer_angle if w.steers else 0.0)
		grip_sum += w.mu
	ground_label = on_ground[0].surface_label if not on_ground.is_empty() else ""
	for t in tracks:
		t.step(dt, throttle)
	# The air on its front.
	var v := linear_velocity
	apply_central_force(-v * v.length() * 0.5 * AIR_DENSITY * CD * frontal)
	_update_sound(on_ground.size(), dt)


## Knocks: each contact's impulse this step, as a change in the machine's speed; past IMPACT_SAFE
## it hurts the part where it struck.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if building or not alive or total_mass <= 0.0:
		return
	if _grace > 0.0:
		_grace -= state.step
		return
	var worst := {}
	var sums := {} ## what it struck -> [its contacts' impulse summed (as dv), where the hardest was, that one's dv]
	for i in state.get_contact_count():
		if not joints.is_empty():
			_moving_blow(state, i)
		var dv := state.get_contact_impulse(i).length() / total_mass
		var at := state.get_contact_local_position(i)
		var other := state.get_contact_collider_object(i)
		if dv > 0.05:
			var sm: Array = sums.get(other, [0.0, at, 0.0])
			sm[0] = float(sm[0]) + dv
			if dv > float(sm[2]):
				sm[1] = at
				sm[2] = dv
			sums[other] = sm
		if dv <= IMPACT_SAFE:
			continue
		if other is RigidBody3D and not other is Machine and (other as RigidBody3D).mass < total_mass * 0.05:
			continue # (debris rattling on it)
		var felt_dv := dv
		if other is StructurePiece:
			# into a structure: the blow lands on it too (its weight times how hard it stopped)
			var bite := RAM_BITE if _part_near(at) >= 0 and design[_part_near(at)].id == "spike" else 1.0
			(other as StructurePiece).hit.call_deferred(dv * total_mass * 0.06 * bite, at, linear_velocity.normalized(), true) # (not mid-step)
		if other is Machine:
			_knock_by = other
			# struck by its ram's spikes: the blow lands on a few points, and tears
			var oi: int = (other as Machine)._part_near(at)
			if oi >= 0 and (other as Machine).design[oi].id == "spike":
				felt_dv *= RAM_BITE
				_rammed = true
		# what's round where it struck takes it, less further from it (a knock crumples a corner,
		# not one bolt)
		var local := global_transform.affine_inverse() * at
		for j in design.size():
			var c := part_xform(j).origin
			var ext := Vector3(Parts.size_of(design[j].id, design[j].rot)) * Parts.CELL * 0.5
			var d := ((local - c).abs() - ext).max(Vector3.ZERO).length() # (to its box, not its middle)
			if d < IMPACT_REACH:
				var felt := felt_dv * (1.0 - 0.6 * d / IMPACT_REACH)
				if felt > float(worst.get(j, 0.0)):
					worst[j] = felt
		_knock_at = at
	# the hardest knock this step, all its contacts together (debris rattling on it aside)
	var hardest := 0.0
	var hard_at := Vector3.ZERO
	var hard_on: Object = null
	for o: Object in sums:
		if is_instance_valid(o) and o is RigidBody3D and not o is Machine and (o as RigidBody3D).mass < total_mass * 0.05:
			continue
		if float(sums[o][0]) > hardest:
			hardest = float(sums[o][0])
			hard_at = sums[o][1]
			hard_on = o
	if hardest > IMPACT_SAFE:
		struck.emit(hard_at, hardest, hard_on)
	# cover driven into (a Breakable): the blow lands on it (its weight times how hard it stopped, all its
	# contacts together; more on a ram's spikes)
	for o: Object in sums:
		if o is Breakable and float(sums[o][0]) > IMPACT_SAFE:
			var pn := _part_near(sums[o][1])
			var bite := RAM_BITE if pn >= 0 and design[pn].id == "spike" else 1.0
			(o as Breakable).hit.call_deferred(float(sums[o][0]) * total_mass * 0.06 * bite, sums[o][1], linear_velocity.normalized(), false)
	if worst.is_empty():
		return
	for part: int in worst:
		var over := float(worst[part]) - IMPACT_SAFE
		if over > 0.0:
			_knocks.append([design[part], over * over * IMPACT_HURT])
	knocked.emit(_knock_at, float(worst.values().max()))


var _knocks := []
var _grace := 0.0
var _sputter := 1.0
var _sputter_t := 0.0 ## s knocks don't hurt (just set down: built, made anew, put back on its wheels)
var _knock_at := Vector3.ZERO
var _knock_by: Machine
var _rammed := false
signal knocked(at: Vector3, dv: float)
## The hardest knock this step and what it struck (HitFeel: sparks, the sound, the view).
signal struck(at: Vector3, dv: float, other: Object)
## Part `id` torn off at `at` (HitFeel).
signal torn(at: Vector3, id: String)


## Just put down somewhere (made, built, righted): for a moment it can land without harm.
func set_down() -> void:
	_grace = 1.5


## True with no engine left or nothing left to run on.
## Fires a flipper that's ready (throwing what's on it, or righting itself on its back). True if one did.
func flip() -> bool:
	for f in flippers:
		if f.fire():
			return true
	return false


## A flipper's ready and `m` is over it.
func can_flip(m: Machine) -> bool:
	for f in flippers:
		if f.ready() and m in f.over_it():
			return true
	return false


func immobile() -> bool:
	return alive and (power_kw <= 0.0 or wheels.is_empty())


## The cab's share of its hit points left (1 without one).
func cab_frac() -> float:
	var i := cab_index()
	return clampf(float(design[i].hp) / Parts.hp_of(design[i].id), 0.0, 1.0) if i >= 0 else 0.0


## The battery: the alternators in (with the engines' revs), the cab, the lights and the guns out.
func _power(dt: float) -> void:
	charge_kw = alternator_kw * (0.45 + 0.55 * _rpm) if power_kw > 0.0 else 0.0
	var lamps_kw := 0.15 * _lamps.size() if lights_on and powered and shed < 1 else 0.0
	var spin_kw := 0.0
	var turn_kw := 0.0
	var load_kw := 0.0
	var spins := false
	var loads := false
	for g in guns:
		var d: Array = MachineGun.DRAW[g.kind]
		spin_kw += float(d[0]) * g._spin
		turn_kw += float(d[1]) * g._slew
		load_kw += g.draw_kw() - float(d[0]) * g._spin - float(d[1]) * g._slew
		spins = spins or float(d[0]) > 0.0
		loads = loads or float(d[2]) > 0.0
	for f in flippers:
		load_kw += f.draw_kw()
	for jt in joints:
		load_kw += jt.draw_kw()
	for t in tools:
		load_kw += t.draw_kw()
	draw_kw = 0.1 + lamps_kw + spin_kw + turn_kw + load_kw
	energy_kj = clampf(energy_kj + (charge_kw - draw_kw) * dt, 0.0, capacity_kj)
	var was := powered
	var was_shed := shed
	if powered and energy_kj <= 0.0:
		powered = false
	elif not powered and energy_kj > minf(capacity_kj * 0.03, 10.0): # (a little back in before it all comes on again)
		powered = true
	var f := charge_frac()
	while shed < SHED.size() and f < SHED[shed]:
		shed += 1
	while shed > 0 and f > SHED[shed - 1] + SHED_BACK:
		shed -= 1
	for g in guns:
		g.can_spin = shed < 3
		g.can_load = shed < 2
	if powered != was or shed != was_shed:
		_set_lamps()
	consumers.clear()
	var low := "akü düşük"
	consumers.append({"name": "Kabin", "kw": 0.1, "on": true, "off_why": ""})
	if not _lamps.is_empty():
		consumers.append({"name": "Farlar", "kw": lamps_kw, "on": lights_on and powered and shed < 1,
			"off_why": "" if not lights_on else (low if shed >= 1 or not powered else "")})
	if loads:
		consumers.append({"name": "Doldurucular", "kw": load_kw, "on": powered and shed < 2,
			"off_why": low if shed >= 2 or not powered else ""})
	if spins:
		consumers.append({"name": "Minigun motoru", "kw": spin_kw, "on": powered and shed < 3,
			"off_why": low if shed >= 3 or not powered else ""})
	if not guns.is_empty():
		consumers.append({"name": "Kule dönüşü", "kw": turn_kw, "on": powered, "off_why": "" if powered else "akü bitti"})


## All its guns' ammunition taken up by `frac` of a full load; true if any took some.
func resupply(frac: float) -> bool:
	var any := false
	for g in guns:
		if g.limited and g.ammo < g.ammo_max - 0.01:
			g.refill(frac)
			any = true
	return any


## Every part given back `frac` of its hit points (a burst tyre or a thrown track mended once it's
## sound enough); a part that's gone stays gone.
func repair(frac: float) -> void:
	for p: Dictionary in design:
		var full := Parts.hp_of(p.id)
		p.hp = minf(float(p.hp) + full * frac, full)
		var f := float(p.hp) / full
		if f >= 0.5:
			p.erase("weak")
			p.erase("sputter")
		if f >= TYRE_BURST:
			p.erase("flat")
		if f >= TRACK_THROWN:
			p.erase("thrown")
	rebuild()


## Any of its guns can still fire.
func armed_any() -> bool:
	for g in guns:
		if g.has_ammo():
			return true
	return false


func charge_frac() -> float:
	return energy_kj / capacity_kj if capacity_kj > 0.0 else 0.0


func _process(dt: float) -> void:
	for p in _smoke:
		if is_instance_valid(p) and p.get_child_count() > 0:
			var fire := p.get_child(0) as Node3D
			if fire.visible:
				fire.scale = Vector3.ONE * randf_range(0.8, 1.25)
				(fire.get_child(1) as OmniLight3D).light_energy = randf_range(1.4, 2.6)
	for w in wheels:
		w.animate(dt)
	for t in tracks:
		t.animate(dt)
	# the clods' ground follows it (snapped to 4 m: it re-reads the ground only when it moves on)
	var p := global_position.snapped(Vector3(4.0, 4.0, 4.0))
	if _catch.global_position != p:
		_catch.global_position = p


func _update_sound(touching: int, dt: float) -> void:
	# the wheels on the ground (engine or none: a cart rolls downhill too)
	var roll := clampf(absf(speed) / 8.0, 0.0, 1.0) * (1.0 if touching > 0 else 0.0)
	if _roll_sound.stream:
		if roll > 0.02 and not _roll_sound.playing:
			_roll_sound.play()
		elif roll <= 0.02 and _roll_sound.playing:
			_roll_sound.stop()
		_roll_sound.volume_db = linear_to_db(maxf(roll * 0.5, 0.0001))
		_roll_sound.pitch_scale = 0.85 + roll * 0.3
	if power_kw <= 0.0:
		if _engine_sound.playing:
			_engine_sound.stop()
		return
	if not _engine_sound.playing:
		_engine_sound.play()
	var want := clampf(absf(speed) / 18.0, 0.0, 1.0) * 0.6 + absf(throttle) * 0.4
	_rpm = move_toward(_rpm, want, dt * 1.5)
	var hurt := clampf((0.7 - power_kw / maxf(_full_power, 1.0)) / 0.5, 0.0, 1.0) # (a badly hurt engine misses)
	_engine_sound.update(self, _rpm, absf(throttle), hurt, dt)


# --- Taking hits --------------------------------------------------------------------------------

## A round or a fragment at `at` going `dir`: the part there takes `damage`, the machine the push.
func hit(at: Vector3, dir: Vector3, damage: float, push: float, by: Machine = null) -> void:
	if not alive:
		return
	apply_impulse(dir * push, at - global_position)
	var i := _part_near(at + dir * 0.06)
	if i >= 0:
		last_hit_by = by
		last_hit_kind = "minigun"
		damaged.emit(damage, by.global_position if is_instance_valid(by) else at - dir * 20.0, "minigun")
		damage_part(i, damage, at, by)


## A burst at `at`: every part within `radius` takes damage falling off with the square of the
## distance (all of it at the middle, none at the edge), the machine is heaved away from it.
func blast(at: Vector3, radius: float, damage: float, push: float, by: Machine = null, kind := "patlama") -> void:
	if not alive:
		return
	var hurt := {}
	for i in design.size():
		var c := global_transform * Parts.xform_of(design[i].id, design[i].at, design[i].rot).origin
		var d := c.distance_to(at)
		if d < radius:
			var f := 1.0 - d / radius
			hurt[i] = damage * f * f # (the fragments thin out fast: a near miss scars, a hit tears)
	# the heave: away from it and a little up, through the centre of mass mostly (a burst shoves a
	# machine and can tip it; it doesn't throw a ton of steel into the air: at most BLAST_DV m/s)
	var away := com_global() - at
	var k := clampf(1.0 - away.length() / (radius * 2.5), 0.0, 1.0)
	var j := minf(push * k, BLAST_DV * total_mass)
	var heave := (away.normalized() * Vector3(1.0, 0.0, 1.0) + Vector3.UP * 0.25).normalized() * j
	apply_central_impulse(heave * 0.7)
	apply_impulse(heave * 0.3, at - global_position)
	if hurt.is_empty():
		return
	last_hit_by = by
	last_hit_kind = kind
	var total := 0.0
	for v: float in hurt.values():
		total += v
	if total > 0.0:
		damaged.emit(total, at, kind)
	# the worst first; indices shift as parts come off, so go by the part's dictionary
	var keys := hurt.keys()
	keys.sort_custom(func(a: int, b: int) -> bool: return hurt[a] > hurt[b])
	var parts := []
	for i: int in keys:
		parts.append([design[i], hurt[i]])
	for e: Array in parts:
		var at_i := design.find(e[0])
		if at_i >= 0 and alive:
			var wood := Parts.burns(str(e[0].id))
			if wood and kind == "alev": # (wood takes fire: it burns hotter and goes on burning)
				_alight(e[0])
			damage_part(at_i, float(e[1]) * (WOOD_HEAT if wood and kind == "alev" else 1.0), global_transform * part_xform(at_i).origin, by)


const WOOD_HEAT := 3.0 ## how much harder a flame takes a wooden part
const BURN_FOR := 6.0 ## s a wooden part burns on once it's caught
const BURN_DPS := 7.0 ## what burning takes off it a second
var _burning: Array[Dictionary] = [] ## the parts' rows alight (each its "burn": s it burns on)
var _burn_fx := 0.0


func _alight(row: Dictionary) -> void:
	if not row.has("burn") or float(row.burn) <= 0.0:
		_burning.append(row)
	row.burn = BURN_FOR


## Wooden parts alight: burning on, and catching what's beside them now and then.
func _burn(dt: float) -> void:
	_burn_fx -= dt
	var fx := _burn_fx <= 0.0
	if fx:
		_burn_fx = 0.3
	for row: Dictionary in _burning.duplicate():
		var i := design.find(row)
		row.burn = float(row.burn) - dt
		if i < 0 or float(row.burn) <= 0.0:
			row.erase("burn")
			_burning.erase(row)
			continue
		var at := global_transform * part_xform(i).origin
		if fx and Combat.current:
			Combat.current._burst(at + Vector3.UP * 0.2, "embers" if randf() < 0.5 else "explosion", 0.25, Vector3.UP)
		if randf() < dt * 0.35: # (it spreads to the wood touching it)
			for c in Parts.cells_of(row.id, row.at, row.rot):
				for d: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
					var j: int = _occ.get(c + d, -1)
					if j >= 0 and j != i and Parts.burns(design[j].id) and not burning(j):
						_alight(design[j])
		last_hit_kind = "yanık"
		damage_part(i, BURN_DPS * dt, at)


## Whether a part's alight.
func burning(i: int) -> bool:
	return i >= 0 and i < design.size() and float(design[i].get("burn", 0.0)) > 0.0


## Part `i` takes `amount` (at `at`, by `by`, for the HUD); at none it comes off; on the way, what it
## does gives (systems).
func damage_part(i: int, amount: float, at := Vector3.INF, by: Machine = null) -> void:
	if i < 0 or i >= design.size() or invulnerable:
		return
	var p: Dictionary = design[i]
	if at == Vector3.INF:
		at = global_transform * part_xform(i).origin
	p.hp = float(p.hp) - amount
	var broke := float(p.hp) <= 0.0
	if Combat.current:
		Combat.current.part_hit.emit(self, str(p.id), at, amount, by, broke)
	if broke:
		break_off(i)
	else:
		_systems(i, amount, at)
		_show_wear()
		_flash_part(i)


## What part `i`'s hurt does to the machine (once each: the flags stay on its design entry).
func _systems(i: int, amount: float, at: Vector3) -> void:
	var p: Dictionary = design[i]
	var frac := clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0)
	match str(Parts.def(p.id).kind):
		"engine":
			_refigure_power()
			if frac < 0.5 and not bool(p.get("weak", false)):
				p.weak = true
				system_hit.emit("MOTOR HASARLI  ·  GÜÇ %%%d" % int(power_kw / maxf(_full_power, 1.0) * 100.0), at)
			elif frac < 0.35 and not bool(p.get("sputter", false)):
				p.sputter = true
				system_hit.emit("MOTOR TEKLİYOR", at)
		"wheel":
			if frac < TYRE_BURST and not bool(p.get("flat", false)):
				p.flat = true
				for w in wheels:
					if w.node == part_nodes[i]:
						w.flat = true
				system_hit.emit("LASTİK PATLADI", at)
				if Combat.current:
					Combat.current.sound("res://assets/audio/impact/tyre_pop.wav", at, 2.0, randf_range(0.9, 1.1))
					Combat.current.backblast(at, Vector3.UP)
		"track":
			if frac < TRACK_THROWN and not bool(p.get("thrown", false)):
				p.thrown = true
				rebuild()
				system_hit.emit("PALET KOPTU", at)
				if Combat.current:
					Combat.current.sound("res://assets/audio/explosion/debris_metal_0%d.wav" % randi_range(1, 2), at, 2.0, 0.8)
		"battery":
			energy_kj = maxf(energy_kj - amount * 4.0, 0.0)
			var cap := capacity_kj
			rebuild()
			energy_kj = minf(energy_kj, capacity_kj)
			if capacity_kj < cap - 1.0 and not bool(p.get("hit", false)):
				p.hit = true
				system_hit.emit("AKÜ VURULDU  ·  ŞARJ %%%d" % int(charge_frac() * 100.0), at)
			if Combat.current:
				Combat.current.muzzle_flash(at, Vector3.UP, 0.8) # (sparks off its terminals)
		"flipper":
			for f in flippers:
				if f.node == part_nodes[i]:
					f.condition = frac
			if frac < 0.5 and not bool(p.get("weak", false)):
				p.weak = true
				system_hit.emit("ÇEVİRİCİ HAVA KAÇIRIYOR", at)
		"weapon":
			for g in guns:
				if g.node == part_nodes[i]:
					g.condition = frac
			if frac < 0.5 and not bool(p.get("weak", false)):
				p.weak = true
				system_hit.emit("SİLAH HASARLI", at)


## The engines' power and charge as hurt as they are (without making the whole machine anew).
func _refigure_power() -> void:
	power_kw = 0.0
	alternator_kw = 0.0
	for p: Dictionary in design:
		var d := Parts.def(p.id)
		if str(d.kind) == "engine":
			var ef := _engine_eff(p)
			power_kw += float(d.power) * ef
			alternator_kw += float(d.get("alternator", 0.0)) * ef


## An engine's share of its power, by its hit points: all of it whole, under a third at the end.
static func _engine_eff(p: Dictionary) -> float:
	var frac := clampf(float(p.hp) / Parts.hp_of(p.id), 0.0, 1.0)
	return 0.3 + 0.7 * frac


var _full_power := 1.0 ## (its engines' power as built: the HUD's share)


## A part just hit shows it: a flash of white over it for a moment.
func _flash_part(i: int) -> void:
	if DisplayServer.get_name() == "headless" or i >= part_nodes.size():
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.albedo_color = Color(1.0, 0.9, 0.7, 0.55)
	var node := part_nodes[i]
	if not is_instance_valid(node):
		return
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = _flash_mat
	# (held weakly: the part, or the whole machine, may be gone before the flash is over)
	var wn: WeakRef = weakref(node)
	var wm: WeakRef = weakref(self)
	get_tree().create_timer(0.07).timeout.connect(func() -> void:
		var n := wn.get_ref() as Node3D
		var me := wm.get_ref() as Machine
		if n == null or me == null:
			return
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			if mi.material_overlay == Machine._flash_mat:
				mi.material_overlay = null
		me._show_wear())


static var _flash_mat: StandardMaterial3D


## Soot and pocks on each hurt part; smoke from the worst (rebuilt with the parts).
func _show_wear() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _wear_mat == null:
		_wear_mat = ShaderMaterial.new()
		_wear_mat.shader = WEAR
	var worst: Array = []
	for i in mini(design.size(), part_nodes.size()):
		var frac := clampf(float(design[i].hp) / Parts.hp_of(design[i].id), 0.0, 1.0)
		var w := clampf((1.0 - frac) * 1.25, 0.0, 1.0)
		var node := part_nodes[i]
		if not is_instance_valid(node):
			continue
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			if w > 0.02:
				if mi.material_overlay != _wear_mat:
					mi.material_overlay = _wear_mat
				mi.set_instance_shader_parameter("wear", w)
			elif mi.material_overlay == _wear_mat:
				mi.material_overlay = null
		if frac < 0.45:
			worst.append([frac, i])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in SMOKERS:
		if k >= _smoke.size():
			_smoke.append(_make_smoke())
		var p := _smoke[k]
		if k < worst.size():
			var i: int = worst[k][1]
			var node := part_nodes[i]
			var engine := str(Parts.def(design[i].id).kind) == "engine"
			if p.get_parent() != node:
				if p.get_parent():
					p.get_parent().remove_child(p)
				node.add_child(p)
			var hurt := 1.0 - float(worst[k][0]) / 0.45
			p.amount_ratio = clampf(0.3 + hurt * 0.7, 0.1, 1.0)
			(p.process_material as ParticleProcessMaterial).color = Color(0.08, 0.075, 0.07, 0.8) if engine else Color(0.42, 0.4, 0.38, 0.55)
			p.get_child(0).visible = engine and hurt > 0.4 # (the fire)
			p.emitting = true
		else:
			p.emitting = false


## A part's smoke: puffs rising and spreading from it, and a flicker of fire (an engine's).
func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 20.0
	m.initial_velocity_min = 0.8
	m.initial_velocity_max = 1.8
	m.gravity = Vector3(0.0, 0.6, 0.0)
	m.damping_min = 0.4
	m.damping_max = 0.8
	m.scale_min = 0.6
	m.scale_max = 1.2
	var grow := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(1.0, 1.6))
	grow.curve = c
	m.scale_curve = grow
	var fade := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.12, Color(1, 1, 1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	fade.gradient = g
	m.color_ramp = fade
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = WheelSpray._puff()
	q.material = mat
	p.draw_pass_1 = q
	p.amount = 40
	p.lifetime = 3.0
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 14, 16))
	# the fire: a flickering orange billboard and a light
	var fire := Node3D.new()
	fire.visible = false
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = WheelSpray._puff()
	fm.albedo_color = Color(1.0, 0.5, 0.15)
	var fq := QuadMesh.new()
	fq.size = Vector2(0.8, 1.0)
	fq.material = fm
	var fmi := MeshInstance3D.new()
	fmi.mesh = fq
	fmi.position = Vector3(0, 0.35, 0)
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.add_child(fmi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 2.0
	l.omni_range = 4.0
	l.position = Vector3(0, 0.5, 0)
	fire.add_child(l)
	p.add_child(fire)
	fire.set_process(true)
	return p


const AMMO_RADIUS := 2.6 ## m: an ammo box going up
const AMMO_DAMAGE := 170.0
const AMMO_PUSH := 3200.0


## Part `i` off, and whatever hung on only through it; the cab: all of it (an ammo box goes up).
func break_off(i: int) -> void:
	var gone: Array[int] = []
	if Parts.is_cab(design[i].id):
		for j in design.size():
			gone.append(j)
	else:
		gone = _cut_off_by(i)
	var c := Combat.current
	var spin_scale := 3.0
	if design[i].id == "ammo" and c:
		# its rounds go up: a burst where it was, after this part's come away (what it takes with it, it takes then)
		var at := global_transform * part_xform(i).origin
		c.call_deferred("explode", at, AMMO_RADIUS, AMMO_DAMAGE, AMMO_PUSH, last_hit_by if is_instance_valid(last_hit_by) else null, true)
		system_hit.emit("CEPHANE PATLADI", at)
	if design[i].id == "pitch" and c: # (the pitch goes up in flames where it was, and catches what's by it)
		var at := global_transform * part_xform(i).origin
		c.call_deferred("oil_fire", at, 2.0, 7.0, last_hit_by if is_instance_valid(last_hit_by) else null)
		blast(at, 1.6, 20.0, 0.0, last_hit_by, "alev")
		system_hit.emit("KATRAN TUTUŞTU", at)
	torn.emit(global_transform * part_xform(i).origin, str(design[i].id))
	for j in gone:
		var p: Dictionary = design[j]
		var xf := global_transform * part_xform(j)
		if c:
			var v := velocity_at(xf.origin) + (xf.origin - com_global()).normalized() * randf_range(2.0, 6.0) + Vector3.UP * randf_range(2.0, 5.0)
			c.debris(p.id, xf, v, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spin_scale, _scenes[p.id], self,
				float(p.hp) > 0.0 and not Parts.is_cab(p.id)) # (whole: it came away with another, or the cab went)
	gone.sort()
	gone.reverse()
	for j in gone:
		design.remove_at(j)
	if cab_index() < 0:
		_die()
		return
	rebuild()


## The parts that come away with `i`: it, and those no longer reaching the cab without it.
func _cut_off_by(i: int) -> Array[int]:
	var cab := cab_index()
	var occ := {}
	for j in design.size():
		if j != i:
			for c in Parts.cells_of(design[j].id, design[j].at, design[j].rot):
				occ[c] = j
	var seen := {cab: true}
	var queue: Array[int] = [cab]
	while not queue.is_empty():
		var j: int = queue.pop_back()
		if j != cab and not _structural(design[j].id):
			continue
		for c in Parts.cells_of(design[j].id, design[j].at, design[j].rot):
			for n in _NEIGHBOURS:
				var k: int = occ.get(c + n, -1)
				if k >= 0 and not seen.has(k):
					seen[k] = true
					queue.append(k)
	var out: Array[int] = [i]
	for j in design.size():
		if j != i and not seen.has(j):
			out.append(j)
	return out


func _die() -> void:
	alive = false
	firing = false
	throttle = 0.0
	if not is_instance_valid(last_hit_by):
		last_hit_by = null # (what hit it last may be gone already)
	if Combat.current:
		Combat.current.explode(com_global(), 3.5, 0.0, 6000.0, last_hit_by, true)
	_engine_sound.stop()
	_roll_sound.stop()
	died.emit()
	queue_free()


## The part at (or nearest to) a world point, or -1.
func _part_near(p: Vector3) -> int:
	# a part a joint's moved: where it would be at rest
	var lm := global_transform.affine_inverse() * p
	for i: int in _chain:
		if not _moved(i):
			continue
		var r := _joint_xform(i).affine_inverse() * lm / Parts.CELL
		var rc := Vector3i(floori(r.x), floori(r.y), floori(r.z))
		if _occ.get(rc, -1) == i:
			return i
	var l := lm / Parts.CELL
	var cell := Vector3i(floori(l.x), floori(l.y), floori(l.z))
	if _occ.has(cell):
		return _occ[cell]
	var best := -1
	var best_d := 2.5
	for c: Vector3i in _occ:
		var d := (Vector3(c) + Vector3.ONE * 0.5).distance_to(l)
		if d < best_d:
			best_d = d
			best = _occ[c]
	return best


## How much is left of it, 0..1, against it as it was built (parts shot off count as nothing left;
## the cab's share counts double).
func health() -> float:
	var have := 0.0
	for p: Dictionary in design:
		have += maxf(float(p.hp), 0.0) * (2.0 if Parts.is_cab(p.id) else 1.0)
	return have / maxf(_built_hp, 1.0)


var _built_hp := 1.0 ## (all its parts' hit points as built: set when it's built, not as it's shot apart)


func _note_built() -> void:
	_full_power = maxf(power_kw, 1.0)
	_built_hp = 0.0
	for p: Dictionary in design:
		_built_hp += Parts.hp_of(p.id) * (2.0 if Parts.is_cab(p.id) else 1.0)


## Where the wheels' spray goes (freed with the parts on a rebuild).
func fx_root() -> Node3D:
	if _fx == null:
		_fx = Node3D.new()
		_fx.name = "Spray"
		_root.add_child(_fx)
	return _fx


## The world position of its centre of mass.
func com_global() -> Vector3:
	return global_transform * com


func velocity_at(p: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(p - com_global())


## Totals and what's wrong with it, for the build screen.
func report() -> Dictionary:
	var warn := PackedStringArray()
	if cab_index() < 0:
		warn.append("Kabin yok")
	if power_kw <= 0.0:
		warn.append("Motor yok: kımıldamaz")
	if wheels.is_empty():
		warn.append("Tekerlek ya da palet yok")
	elif total_mass > rated_kg:
		warn.append("Tekerlekler aşırı yüklü (%d / %d kg): yere oturur" % [int(total_mass), int(rated_kg)])
	var kw_t := power_kw / maxf(total_mass / 1000.0, 0.01)
	if power_kw > 0.0 and kw_t < 40.0:
		warn.append("Güç az (%d kW/ton): yokuşta zorlanır" % int(kw_t))
	var steerers := 0
	for w in wheels:
		if w.steers:
			steerers += 1
	if not wheels.is_empty() and steerers == 0 and tracks.is_empty():
		warn.append("Önde tekerlek yok: sadece paletli gibi döner")
	if tracks.size() == 1:
		warn.append("Tek palet: bir yana çeker")
	# the most the guns can draw at once (motors, traverse, loaders) and the lamps, against the charge
	var peak := 0.1 + 0.15 * _lamps.size()
	for g in guns:
		var dk: Array = MachineGun.DRAW[g.kind]
		peak += float(dk[0]) + float(dk[1]) + float(dk[2])
	if not guns.is_empty() and alternator_kw <= 0.0:
		warn.append("Alternatör yok: silahlar aküyle (%.1f kWh) idare eder" % (capacity_kj / 3600.0))
	elif peak > alternator_kw and capacity_kj > 0.0:
		var mins := capacity_kj / maxf(peak - alternator_kw, 0.01) / 60.0
		if mins < 10.0:
			warn.append("Silahlar alternatörden çok çeker: sürekli ateşte akü ~%d dk" % maxi(int(mins), 1))
	return {"mass": total_mass, "power": power_kw, "kw_t": kw_t, "rated": rated_kg,
		"wheels": wheels.size() - _track_wheels(), "tracks": tracks.size(),
		"parts": design.size(), "guns": guns.size(), "warn": warn,
		"kwh": capacity_kj / 3600.0, "alternator": alternator_kw, "peak": peak}


func _track_wheels() -> int:
	var n := 0
	for t in tracks:
		n += t.bogies.size()
	return n



# --- Joints -----------------------------------------------------------------------------------------

## What each joint carries: what's bolted to its top and doesn't reach the cab another way (then it
## can't move: it's locked); a joint within what another carries is carried by it too.
func _sections() -> void:
	var cab := cab_index()
	for jt in joints:
		jt.members.clear()
		jt.locked = false
		jt.carried_kg = 0.0
		var own := Parts.cells_of(design[jt.index].id, design[jt.index].at, design[jt.index].rot)
		var n := jt.out_normal()
		var seeds: Array[int] = []
		for c in own:
			var k: int = _occ.get(c + n, -1)
			if k >= 0 and k != jt.index and not k in seeds:
				seeds.append(k)
		if seeds.is_empty():
			continue
		var carried := _reach(seeds, jt.index)
		var main := _reach([cab] as Array[int], jt.index) if cab >= 0 and cab != jt.index else {}
		for k: int in carried:
			if main.has(k) and _structural(design[k].id):
				jt.locked = true # (bolted round it to the rest: it can't move)
				break
		if jt.locked:
			continue
		for k: int in carried:
			if not main.has(k): # (a light or a gun touching both stays with the rest)
				jt.members.append(k)
				jt.carried_kg += float(Parts.def(design[k].id).mass)
	# the chain of joints that carry each part, outermost (carrying most) first
	var order := joints.duplicate()
	order.sort_custom(func(a: MachineJoint, b: MachineJoint) -> bool: return a.members.size() > b.members.size())
	for jt: MachineJoint in order:
		for k in jt.members:
			if not _chain.has(k):
				_chain[k] = []
			_chain[k].append(jt)
	for jt in joints:
		jt.depth = (_chain.get(jt.index, []) as Array).size()


## Every part reached from `from` through bolted faces, not through `but`.
func _reach(from: Array[int], but: int) -> Dictionary:
	var seen := {}
	var queue: Array[int] = []
	for f in from:
		if f >= 0 and f != but and not seen.has(f):
			seen[f] = true
			queue.append(f)
	while not queue.is_empty():
		var i: int = queue.pop_back()
		if not _structural(design[i].id) and not i in from:
			continue
		for c in Parts.cells_of(design[i].id, design[i].at, design[i].rot):
			for nb in _NEIGHBOURS:
				var j: int = _occ.get(c + nb, -1)
				if j >= 0 and j != but and not seen.has(j):
					seen[j] = true
					queue.append(j)
	return seen


## The joints' motion that's on part `i` (machine space).
func _joint_xform(i: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	for jt: MachineJoint in _chain.get(i, []):
		t = t * jt.motion()
	return t


func _moved(i: int) -> bool:
	for jt: MachineJoint in _chain.get(i, []):
		if absf(jt.angle) > 1e-4:
			return true
	return false


## Where part `i` is now on the machine (a joint may have moved it).
func part_xform(i: int) -> Transform3D:
	var p: Dictionary = design[i]
	var rest := Parts.xform_of(p.id, p.at, p.rot)
	return _joint_xform(i) * rest if _chain.has(i) else rest


## The carried parts' models and boxes where their joints have them.
func _place_moving() -> void:
	for i: int in _chain:
		if i >= part_nodes.size() or not is_instance_valid(part_nodes[i]):
			continue
		var t := _joint_xform(i)
		part_nodes[i].transform = t * Parts.xform_of(design[i].id, design[i].at, design[i].rot)
		for e: Array in _shapes.get(i, []):
			if is_instance_valid(e[0]):
				(e[0] as CollisionShape3D).transform = t * (e[1] as Transform3D)


## The wheels a joint carries (a steering joint's, mostly) where it has them: their hubs and the way
## they roll turned with it.
func _turn_wheels() -> void:
	for w in wheels:
		if w.part < 0 or not _chain.has(w.part):
			continue
		var t := _joint_xform(w.part)
		w.rest = t * w.rest0
		w.roll_dir = (t.basis * w.roll0).normalized()
		w.axle = (t.basis * w.axle0).normalized()


## How fast a point on part `i` (machine space, now) is going from its joints.
func _joint_velocity(i: int, local: Vector3) -> Vector3:
	var v := Vector3.ZERO
	var t := Transform3D.IDENTITY
	for jt: MachineJoint in _chain.get(i, []):
		# (each joint's motion about where its carriers have put it)
		var rest := t.affine_inverse() * local
		v += t.basis * jt.velocity_at(rest)
		t = t * jt.motion()
	return v


## A moving part striking something: the blow by how fast that point's going and how much is moving
## (a spike or a blade on it bites the harder); what it strikes is thrown along, and this one pushed
## back a little. Once a moment per thing struck.
func _moving_blow(state: PhysicsDirectBodyState3D, c: int) -> void:
	var at := state.get_contact_local_position(c)
	var other := state.get_contact_collider_object(c)
	if other == null or _struck.has(other) or not (other is Machine or other is StructurePiece or other is Breakable or other is RigidBody3D):
		return
	var i := _part_near(at)
	if i < 0 or not _chain.has(i):
		return
	var local := global_transform.affine_inverse() * at
	var v := global_basis * _joint_velocity(i, local)
	var speed := v.length()
	if speed < 2.0:
		return
	var moving := 0.0
	for k: int in (_chain[i] as Array).back().members:
		moving += float(Parts.def(design[k].id).mass)
	var bite := RAM_BITE if str(Parts.def(design[i].id).kind) == "ram" else 1.0
	var blow := moving * speed * 0.035 * bite
	var push := v.normalized() * moving * speed * 0.6
	_struck[other] = 0.18
	if other is Machine:
		(other as Machine).hit.call_deferred(at, v.normalized(), blow, push.length(), self)
		(other as Machine).set_deferred("last_hit_kind", "koç" if bite > 1.0 else "çarpışma")
	elif other is StructurePiece:
		(other as StructurePiece).hit.call_deferred(blow * 1.5, at, v.normalized(), true)
	elif other is Breakable:
		(other as Breakable).hit.call_deferred(blow, at, v.normalized())
	elif other is RigidBody3D:
		(other as RigidBody3D).apply_impulse.call_deferred(push * 0.3, at - (other as RigidBody3D).global_position)
	apply_impulse.call_deferred(-push * 0.25, at - global_position)
	if Combat.current:
		Combat.current.call_deferred("_impact", at, -v.normalized(), "metal", clampf(speed / 10.0, 0.3, 1.0))
		Combat.current.call_deferred("sound", ("res://assets/audio/wood/log_drop_0%d.wav" % randi_range(1, 3)) if other is Node and (other as Node).is_in_group(Timber.GROUP) \
			else ("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3)), at, 4.0, randf_range(0.7, 0.9))


## The cranes and winches on `code` (Y a crane with no key of its own, N a winch): hooked on or let
## go. What they did, in words ("" if none answers to it).
## What the number keys pick, in order: the guns, then the saws, then the cranes (Game, DriveHud).
func controls() -> Array:
	var out: Array = []
	out.append_array(guns)
	for t in tools:
		if t.kind == "saw":
			out.append(t)
	for h in hoists:
		if h.kind == "crane":
			out.append(h)
	return out


## The tools on `code` (R for a saw with no key of its own) toggled: what's said, "" if none answers.
func tool_key(code: int) -> String:
	var said := ""
	for t in tools:
		if t.kind == "saw" and (t.key if t.key != 0 else KEY_R) == code:
			said = t.toggle()
	return said


func hoist_key(code: int) -> String:
	var said := ""
	for h in hoists:
		if (h.key if h.key != 0 else (KEY_Y if h.kind == "crane" else KEY_N)) == code:
			said = h.toggle()
	return said


## The joints on `code` (E for those with no key of their own) toggled. True if any answers to it.
func joint_key(code: int) -> bool:
	var any := false
	for jt in joints:
		if jt.kind == "steer":
			continue # (it turns while its key's held, or with the steering)
		if (jt.key if jt.key != 0 else (0 if jt.kind == "turret" else KEY_E)) == code: # (a turret with no key just follows the aim)
			jt.toggle()
			any = true
	return any
