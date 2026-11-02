class_name Villager
extends Node3D
## One of the village's people: walks the Nav grid (wearing the ground as it goes), carries what it's
## given to carry, works where it's sent. What it does is a plan, a list of steps the Village gives it:
##   {t: "go", to: Vector3}                       walk there
##   {t: "work", time, anim, face, tick?, done?}  work on the spot (`tick` says when to stop, else `time`)
##   {t: "do", f: Callable}                       do something at once; false calls the plan off
##   {t: "fight", foe: Villager, give_up?}         run it down and strike till one of them falls
##   {t: "step", to: Vector3}                     a few steps straight there (in through a door)
## An emptied plan and the village gives it the next one. Called off (`abort`), what it carried for a
## building site goes back into the store and what it had set aside (a tree) is let go.
##
## Raiders are these too (`team` 1, Raids gives them their plans): the same walk, the same blows.
## Struck, a fighter turns on whoever struck it; at no hit points it falls and lies a while.
##
## A carter pushes a handcart (`has_cart`): it carries three times what a back does, and is quick on
## a trodden path, but it wears the ground three times as hard, and on soft or rain-soaked ground
## it's slow and now and then sinks in and has to be heaved out.
## A drover leads an ox and its two-wheeled cart (`vehicle` "ox"): thirty to a load, slow and
## steady, the ruts it leaves deepest of all; mud stops it more often and for longer.

signal died(v: Villager)

const LANTERN_REACH := 7.0

const TUNICS := [Color(0.42, 0.24, 0.16), Color(0.3, 0.33, 0.22), Color(0.5, 0.42, 0.28), Color(0.26, 0.3, 0.38),
	Color(0.55, 0.3, 0.2), Color(0.38, 0.36, 0.33), Color(0.46, 0.19, 0.14)]
const SKIN := [Color(0.86, 0.67, 0.53), Color(0.74, 0.55, 0.42), Color(0.62, 0.45, 0.33)]

var village: Node
var nav: Nav
var plan: Array = []
var job := "Boşta"
var idle := false ## its plan is only standing about: anything else may have it
var workplace: Building
var home: Building
var sleeping := false
var carry_res := ""
var carry_n := 0
var owed := {} ## {site, res, n}: taken from the store for a building site, not yet delivered
var target: Node ## the building its plan is for
var team := 0 ## 0 the village's, 1 a raider
var hp := 50.0
var max_hp := 50.0
var attack := 9.0
var dead := false
var fighter := false ## turns on whoever strikes it (a guard, a raider), rather than running
var inside: Building ## the building it's in (asleep, hiding)
var hiding := false
var perched: Building ## the tower it's up on
var tunic_color := Color(0, 0, 0, 0) ## (unset: one of TUNICS)
var display_name := "Kasabalı"
var meal_key := "" ## the last meal it had ("<day>-<o|a>")
var is_child := false
var born_day := 0
var _hit_t := 0.0 ## s to the next blow's sound
var _sit := 0.0 ## 0 standing .. 1 sat on the ground
var _hip_y := 0.78
var ranged := 0.0 ## a rifle's reach (0: hand to hand)
var speed_mul := 1.0
var has_cart := false ## pushing or leading a cart of any kind
var vehicle := "" ## "", "hand", "ox"

var _path := PackedVector3Array()
var _path_i := 0
var _elapsed := 0.0
var _anim := ""
var _phase := 0.0
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _elbows: Array[Node3D] = [] ## the forearms' pivots (on a model built in two at the elbow)
var _knees: Array[Node3D] = [] ## the shins' pivots
var _torso: Node3D
var _load: Node3D
var _yaw := 0.0
var _weapon: Node3D
var _attack_t := 0.0
var _chase_at := Vector3.INF
var _tunic: StandardMaterial3D
var _cart: Node3D
var _wheels: Array[Node3D] = []
var _stuck := 0.0 ## seconds left heaving the cart out of the mud
var _bed: Node3D ## where a load sits
var _wheel_r := 0.36
var _ox_legs: Array[Node3D] = []
var _ox_head: Node3D
var _lantern: Node3D
var _tool: Node3D
var _tool_kind := ""
var _body: Townsfolk ## the rigged townsman (null: the old jointed figure)
var look_seed := 0 ## what its body was dressed from (Portraits builds it again from this)
var look_kind := "man"
# --- the defence
var militia := false ## takes a rifle from the armoury when the alarm goes
var drafted := false ## under the player's orders (skipped by Village._assign)
var armed := false ## has an armoury weapon in hand
var weapon := "" ## what it's trained to: "rifle", "bow" ("" marked by hand: whatever's on the rack)
var held := "" ## what it took from the rack this time
var ammo := 0 ## cartridges on it
var lantern_mode := "" ## "": lit at night, "off": kept dark
var revealed := 0.0 ## s it can be seen anywhere (the flash of its own shot)
var in_cover := false ## behind a wall or a fence: half as easy to hit
var focus: Villager ## (drafted) the one it's told to shoot
var down := false ## shot and lying wounded: bleeding out unless carried in
var bleed := 0.0 ## s left
var carried_by: Villager
var recovering := false ## abed till it's mended
var role := "" ## an outlaw's: "shooter", "torch", "looter"
# --- who it is
## What the town's work asks of hands and eyes, and the name each goes by.
const SKILLS := {"odun": "Odunculuk", "insa": "İnşaat", "tas": "Taşçılık", "tarim": "Tarım", "toplama": "Toplayıcılık",
	"tasima": "Taşıma", "zanaat": "Zanaat", "nisan": "Nişancılık", "okcu": "Okçuluk"}
var skills := {} ## skill -> 0..10, growing as it's done
var prio := {} ## skill -> 0 never, 1 as needed, 2 first
var family := "" ## the surname's stem ("Ivanov"): a family shares a house
var female := false


## Two things it's good at, one it's poor at, the rest middling (a child: nothing yet).
func roll_skills(rng: RandomNumberGenerator) -> void:
	var keys := SKILLS.keys()
	for k: String in keys:
		skills[k] = 0.0 if is_child else rng.randf_range(1.0, 3.5)
		prio[k] = 1
	if is_child:
		return
	keys.shuffle()
	skills[keys[0]] = rng.randf_range(5.5, 7.5)
	skills[keys[1]] = rng.randf_range(4.0, 6.0)
	skills[keys[keys.size() - 1]] = rng.randf_range(0.0, 0.8)


func skill(k: String) -> float:
	return float(skills.get(k, 2.0))


## How quick at `k` it is: 0.7 at nothing, 1 at middling (5), 1.3 at the best (10).
func knack(k: String) -> float:
	return 0.7 + skill(k) * 0.06 if k != "" else 1.0


## Better at `k` for `secs` s of doing it (slower the better it already is).
func learn(k: String, secs: float) -> void:
	if k == "" or is_child:
		return
	skills[k] = minf(skill(k) + secs * 0.004 * (1.0 - skill(k) / 12.0), 10.0)


## What its work just now draws on.
func work_skill() -> String:
	var j := str(job)
	if j.begins_with("İnşa") or j.begins_with("Sur") or j.begins_with("Onarıyor"):
		return "insa"
	if j.begins_with("Taşıyor") or j.begins_with("Yakacak") or j.begins_with("Trenden yük"):
		return "tasima"
	if workplace:
		return Villager.skill_of(workplace)
	return ""


static func skill_of(b: Building) -> String:
	match b.kind:
		"oduncu", "ormanci":
			return "odun"
		"tasci":
			return "tas"
		"tarla":
			return "tarim"
		"toplayici":
			return "toplama"
		"arabaci", "ahir":
			return "tasima"
		"yayci":
			return "zanaat"
		"insaatci":
			return "insa"
		"kisla", "kule":
			return "nisan"
	return ""


## Its aim with what it holds (a rifle: nişancılık, a bow: okçuluk).
func aim() -> float:
	if team != 0:
		return 1.0
	return 0.75 + skill("okcu" if held == "bow" else "nisan") * 0.05
var _speed_now := 0.0 ## m/s over the ground this frame
var _rifle := false

## The tool in the right hand for each kind of work.
const TOOLS := {"mow": "scythe", "eat": "bowl", "chop": "axe", "limb": "axe", "mine": "pick", "build": "hammer", "reap": "sickle", "hoe": "hoe", "dig": "spade", "saw": "saw", "chisel": "mallet"}


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_look()
	if is_child:
		scale = Vector3.ONE * 0.62


## Grown up: full size, and fit to work.
func grow_up() -> void:
	is_child = false
	scale = Vector3.ONE


## The townsfolk as built in Blender (tools/blender/build_villagers.py): a body and four limbs.
const FOLK := ["man_cap", "man_hat", "man_fur", "woman_scarf", "woman_shawl", "man_cap", "man_hat", "woman_scarf"]
static var _folk := {} ## variant -> {Torso, ArmL, ArmR, LegL, LegR: [mesh, position]}


static func _parts(variant: String) -> Dictionary:
	if _folk.has(variant):
		return _folk[variant]
	var path := "res://assets/villagers/%s.glb" % variant
	var out := {}
	if ResourceLoader.exists(path):
		var root := (load(path) as PackedScene).instantiate()
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			out[String(mi.name)] = [mi.mesh, mi.position]
		root.free()
	_folk[variant] = out
	return out


func _build_look() -> void:
	if Townsfolk.available():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		look_seed = rng.seed if rng.seed != 0 else 1
		rng.seed = look_seed
		look_kind = "outlaw" if team == 1 else ("child" if is_child else "man")
		_body = Townsfolk.new()
		add_child(_body)
		_body.build(look_kind, rng)
		_tunic = _body.coat_material
		return
	var parts := _parts("outlaw" if team == 1 else FOLK[randi() % FOLK.size()])
	if parts.has("Torso") and parts.has("ArmL"):
		_build_model(parts)
		return
	var tunic := StandardMaterial3D.new()
	tunic.albedo_color = TUNICS[randi() % TUNICS.size()] if tunic_color.a == 0.0 else tunic_color
	tunic.roughness = 0.95
	_tunic = tunic
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN[randi() % SKIN.size()]
	skin.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.17, 0.13, 0.1)
	dark.roughness = 0.95
	_torso = Node3D.new()
	add_child(_torso)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.21
	cap.height = 0.95
	cap.radial_segments = 10
	cap.rings = 3
	body.mesh = cap
	body.material_override = tunic
	body.position = Vector3(0, 1.17, 0)
	_torso.add_child(body)
	var skirt := MeshInstance3D.new()
	var sk := CylinderMesh.new()
	sk.top_radius = 0.2
	sk.bottom_radius = 0.27
	sk.height = 0.35
	sk.radial_segments = 10
	skirt.mesh = sk
	skirt.material_override = tunic
	skirt.position = Vector3(0, 0.82, 0)
	_torso.add_child(skirt)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.13
	hs.height = 0.27
	hs.radial_segments = 10
	hs.rings = 6
	head.mesh = hs
	head.material_override = skin
	head.position = Vector3(0, 1.74, 0)
	_torso.add_child(head)
	var hat := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	if randf() < 0.5:
		hm.top_radius = 0.02
		hm.bottom_radius = 0.16
		hm.height = 0.18
	else:
		hm.top_radius = 0.13
		hm.bottom_radius = 0.15
		hm.height = 0.1
	hm.radial_segments = 8
	hat.mesh = hm
	hat.material_override = dark if randf() < 0.6 else tunic
	hat.position = Vector3(0, 1.88, 0)
	_torso.add_child(hat)
	for s in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(s * 0.1, 0.78, 0)
		add_child(hip)
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.12, 0.76, 0.14)
		leg.mesh = lm
		leg.material_override = dark
		leg.position = Vector3(0, -0.38, 0)
		hip.add_child(leg)
		_legs.append(hip)
		_hip_y = hip.position.y
		var sh := Node3D.new()
		sh.position = Vector3(s * 0.28, 1.47, 0)
		_torso.add_child(sh)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.1, 0.62, 0.11)
		arm.mesh = am
		arm.material_override = tunic
		arm.position = Vector3(0, -0.3, 0)
		sh.add_child(arm)
		_arms.append(sh)


## The model's body and limbs, turned to face -Z (it was built facing +Z), each limb on a pivot
## at its shoulder or hip for _animate to swing.
func _build_model(parts: Dictionary) -> void:
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.roughness = 0.9
	look.albedo_color = Color(randf_range(0.86, 1.08), randf_range(0.86, 1.08), randf_range(0.86, 1.08)) # (no two dyed quite alike)
	_tunic = look
	var turn := Basis(Vector3.UP, PI)
	_torso = Node3D.new()
	add_child(_torso)
	_torso.add_child(_part_mesh(parts.Torso[0], look, turn))
	for name: String in ["LegL", "LegR"]:
		var hip := Node3D.new()
		hip.position = turn * (parts[name][1] as Vector3)
		add_child(hip)
		hip.add_child(_part_mesh(parts[name][0], look, turn))
		_legs.append(hip)
		_hip_y = hip.position.y
		if parts.has(name + "2"):
			_knees.append(_joint(hip, parts, name, look, turn))
	for name: String in ["ArmR", "ArmL"]: # (turned round, the model's left arm is on +x: the right hand, the one that holds things, goes second)
		var sh := Node3D.new()
		sh.position = turn * (parts[name][1] as Vector3)
		_torso.add_child(sh)
		sh.add_child(_part_mesh(parts[name][0], look, turn))
		_arms.append(sh)
		if parts.has(name + "2"):
			_elbows.append(_joint(sh, parts, name, look, turn))


## The lower half of a limb on its own pivot (the elbow, the knee), hung from the upper half's.
static func _joint(upper: Node3D, parts: Dictionary, name: String, look: Material, turn: Basis) -> Node3D:
	var j := Node3D.new()
	j.position = turn * ((parts[name + "2"][1] as Vector3) - (parts[name][1] as Vector3))
	upper.add_child(j)
	j.add_child(_part_mesh(parts[name + "2"][0], look, turn))
	return j


## What a hand holds hangs from: the forearm, or the whole arm on a model with no elbow.
func _hand(i: int) -> Node3D:
	if _body:
		return _body.hand(i)
	return _elbows[i] if i < _elbows.size() else _arms[i]


## How far down that is to the palm.
func _palm() -> float:
	if _body:
		return 0.0
	return -0.27 if not _elbows.is_empty() else -0.6


static func _part_mesh(mesh: Mesh, mat: Material, turn: Basis) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.basis = turn
	return mi


## What it holds, shown: a log over the shoulder, a stone in its arms, a basket, a bucket.
func set_carry(res: String, n: int) -> void:
	carry_res = res
	carry_n = n
	if _load:
		_load.queue_free()
		_load = null
	if res == "" or n <= 0:
		return
	if has_cart and _bed and res != "su":
		_load = _cart_load(res, n)
		_bed.add_child(_load)
		return
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	match res:
		"odun":
			var c := CylinderMesh.new()
			c.top_radius = 0.11
			c.bottom_radius = 0.12
			c.height = 1.5
			c.radial_segments = 8
			mi.mesh = c
			m.albedo_color = Color(0.36, 0.25, 0.15)
			mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, 0.25), Vector3(0.2, 1.5 if _body else 1.62, 0.0))
		"tas":
			var b := BoxMesh.new()
			b.size = Vector3(0.36, 0.28, 0.3)
			mi.mesh = b
			m.albedo_color = Color(0.5, 0.49, 0.46)
			mi.position = Vector3(0, 1.08, -0.3)
		"yiyecek":
			var c := CylinderMesh.new()
			c.top_radius = 0.2
			c.bottom_radius = 0.15
			c.height = 0.28
			c.radial_segments = 10
			mi.mesh = c
			m.albedo_color = Color(0.55, 0.42, 0.22)
			mi.position = Vector3(0, 1.0, -0.3)
		"su":
			var c := CylinderMesh.new()
			c.top_radius = 0.14
			c.bottom_radius = 0.11
			c.height = 0.26
			c.radial_segments = 8
			mi.mesh = c
			m.albedo_color = Color(0.3, 0.22, 0.14)
			mi.position = Vector3(0, 1.0, -0.32)
	mi.material_override = m
	_load = mi
	add_child(mi)


## How much it carries of `res` in one go.
func capacity(res: String) -> int:
	match vehicle:
		"ox":
			return 30
		"hand":
			return 12
	return {"odun": 6, "tas": 4, "yiyecek": 6}.get(res, 5)


func _drop_vehicle() -> void:
	has_cart = false
	vehicle = ""
	if _cart:
		_cart.queue_free()
		_cart = null
	_bed = null
	_wheels.clear()
	_ox_legs.clear()
	_ox_head = null
	_wheel_r = 0.36


## The handcart, pushed in front: a plank bed on two wheels, two handles back to the hands.
func give_cart(on: bool) -> void:
	_drop_vehicle()
	if not on:
		return
	has_cart = true
	vehicle = "hand"
	_cart = Node3D.new()
	_cart.position = Vector3(0, 0, -1.25)
	add_child(_cart)
	var wood := Building.material("plank")
	var dark := Building.material("dark")
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.95, 0.12, 1.15)
	bed.mesh = bm
	bed.material_override = wood
	bed.position = Vector3(0, 0.55, 0)
	_cart.add_child(bed)
	for s in [-1.0, 1.0]:
		var side := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.05, 0.3, 1.15)
		side.mesh = sm
		side.material_override = wood
		side.position = Vector3(s * 0.47, 0.72, 0)
		_cart.add_child(side)
		var handle := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.05, 0.05, 0.9)
		handle.mesh = hm
		handle.material_override = dark
		handle.transform = Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(s * 0.3, 0.75, 0.85))
		_cart.add_child(handle)
		var hub := Node3D.new()
		hub.position = Vector3(s * 0.55, 0.36, -0.15)
		_cart.add_child(hub)
		var wheel := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.36
		wm.bottom_radius = 0.36
		wm.height = 0.07
		wm.radial_segments = 10
		wheel.mesh = wm
		wheel.material_override = dark
		wheel.rotation.z = PI * 0.5
		hub.add_child(wheel)
		var spoke := MeshInstance3D.new()
		var spm := BoxMesh.new()
		spm.size = Vector3(0.09, 0.66, 0.05)
		spoke.mesh = spm
		spoke.material_override = wood
		hub.add_child(spoke)
		_wheels.append(hub)
	_bed = Node3D.new()
	_cart.add_child(_bed)


## An ox and its cart, led from its left: the ox ahead, yoked to the shafts of a two-wheeled
## cart with high plank sides behind it.
func give_ox(on: bool) -> void:
	_drop_vehicle()
	if not on:
		return
	has_cart = true
	vehicle = "ox"
	_wheel_r = 0.62
	_cart = Node3D.new()
	add_child(_cart)
	var hide := StandardMaterial3D.new()
	hide.albedo_color = [Color(0.42, 0.3, 0.2), Color(0.55, 0.45, 0.33), Color(0.3, 0.22, 0.16), Color(0.72, 0.66, 0.56)][randi() % 4]
	hide.roughness = 0.95
	var horn := StandardMaterial3D.new()
	horn.albedo_color = Color(0.85, 0.8, 0.68)
	var wood := Building.material("plank")
	var dark := Building.material("dark")
	# The ox.
	var ox := Node3D.new()
	ox.position = Vector3(0.95, 0, -1.7)
	_cart.add_child(ox)
	_mesh_box(ox, Vector3(0.85, 0.85, 1.9), Vector3(0, 1.15, 0), hide)
	_mesh_box(ox, Vector3(0.7, 0.35, 0.5), Vector3(0, 1.45, -0.75), hide) # (the hump of its shoulders)
	_ox_head = Node3D.new()
	_ox_head.position = Vector3(0, 1.25, -1.0)
	ox.add_child(_ox_head)
	_mesh_box(_ox_head, Vector3(0.45, 0.5, 0.65), Vector3(0, 0, -0.3), hide)
	_mesh_box(_ox_head, Vector3(0.36, 0.3, 0.25), Vector3(0, -0.1, -0.7), Building.material("dark"))
	for s in [-1.0, 1.0]:
		var h := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.01
		hm.bottom_radius = 0.05
		hm.height = 0.45
		hm.radial_segments = 6
		h.mesh = hm
		h.material_override = horn
		h.transform = Transform3D(Basis(Vector3.BACK, -s * 1.1).rotated(Vector3.RIGHT, -0.3), Vector3(s * 0.3, 0.3, -0.25))
		_ox_head.add_child(h)
		for z in [-0.7, 0.75]:
			var hip := Node3D.new()
			hip.position = Vector3(s * 0.3, 0.8, z)
			ox.add_child(hip)
			_mesh_box(hip, Vector3(0.18, 0.8, 0.2), Vector3(0, -0.4, 0), hide)
			_ox_legs.append(hip)
	_mesh_box(ox, Vector3(0.08, 0.7, 0.08), Vector3(0, 1.0, 1.0), hide) # (its tail)
	_mesh_box(ox, Vector3(1.3, 0.12, 0.14), Vector3(0, 1.62, -0.6), dark) # (the yoke)
	# The cart.
	var cart := Node3D.new()
	cart.position = Vector3(0.95, 0, 1.0)
	_cart.add_child(cart)
	_mesh_box(cart, Vector3(1.5, 0.14, 2.2), Vector3(0, 0.95, 0), wood)
	for s in [-1.0, 1.0]:
		_mesh_box(cart, Vector3(0.06, 0.5, 2.2), Vector3(s * 0.74, 1.25, 0), wood)
		_mesh_box(cart, Vector3(0.09, 0.09, 2.4), Vector3(s * 0.45, 1.05, -1.9), dark) # (the shafts)
		var hub := Node3D.new()
		hub.position = Vector3(s * 0.88, _wheel_r, 0.1)
		cart.add_child(hub)
		var wheel := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = _wheel_r
		wm.bottom_radius = _wheel_r
		wm.height = 0.1
		wm.radial_segments = 12
		wheel.mesh = wm
		wheel.material_override = dark
		wheel.rotation.z = PI * 0.5
		hub.add_child(wheel)
		for k in 2:
			var spoke := MeshInstance3D.new()
			var spm := BoxMesh.new()
			spm.size = Vector3(0.12, _wheel_r * 1.9, 0.07)
			spoke.mesh = spm
			spoke.material_override = wood
			spoke.rotation.x = k * PI * 0.5
			hub.add_child(spoke)
		_wheels.append(hub)
	_mesh_box(cart, Vector3(1.5, 0.5, 0.06), Vector3(0, 1.25, 1.1), wood)
	_bed = Node3D.new()
	_bed.position = Vector3(0, 0.4, 0)
	cart.add_child(_bed)


func _mesh_box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)


func _cart_load(res: String, n: int) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, 0.62, 0)
	var big := vehicle == "ox"
	var k := mini(ceili(n / (3.0 if big else 2.0)), 10 if big else 8)
	if big:
		root.scale = Vector3(1.4, 1.2, 1.5)
	for i in k:
		var mi := MeshInstance3D.new()
		match res:
			"odun":
				var c := CylinderMesh.new()
				c.top_radius = 0.1
				c.bottom_radius = 0.11
				c.height = 1.3
				c.radial_segments = 7
				mi.mesh = c
				mi.material_override = Building.material("wood")
				mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3((i % 4) * 0.21 - 0.31, 0.11 + (i / 4) * 0.2, 0))
			"tas":
				var b := BoxMesh.new()
				b.size = Vector3(0.3, 0.22, 0.3)
				mi.mesh = b
				mi.material_override = Building.material("stone")
				mi.position = Vector3((i % 3) * 0.3 - 0.3, 0.11 + (i / 3) * 0.22, ((i / 3) % 2) * 0.3 - 0.15)
			_:
				var c := CylinderMesh.new()
				c.top_radius = 0.17
				c.bottom_radius = 0.13
				c.height = 0.25
				c.radial_segments = 8
				mi.mesh = c
				mi.material_override = Building.material("thatch")
				mi.position = Vector3((i % 2) * 0.38 - 0.19, 0.13 + (i / 4) * 0.25, ((i / 2) % 2) * 0.4 - 0.2)
		root.add_child(mi)
	return root


func give(new_plan: Array, what: String, for_node: Node = null, is_idle := false) -> void:
	plan = new_plan
	job = what
	target = for_node
	idle = is_idle
	_path = PackedVector3Array()
	_elapsed = 0.0


## The plan's called off: what was owed goes back, what was set aside is let go.
func abort() -> void:
	plan.clear()
	_path = PackedVector3Array()
	_elapsed = 0.0
	if not owed.is_empty():
		village.give_back(owed)
		owed = {}
	set_carry("", 0)
	village.release(self)
	if perched:
		get_down()
	job = "Boşta"
	target = null
	idle = false
	_anim = ""


func sleep_in(h: Building, hide := false) -> void:
	if down:
		down = false
		recovering = true
		carried_by = null
		hp = maxf(hp, 5.0)
		if _body:
			_body.stand()
	sleeping = true
	hiding = hide
	inside = h
	visible = false


## Asleep out of doors (no roof of its own): curled up on its side in a blanket at `at`, its feet
## to the fire at `fire`.
var _blanket: Node3D
var _rough := false


func sleep_rough(cover: Building, at: Vector3, fire: Vector3) -> void:
	sleeping = true
	hiding = false
	inside = cover
	_rough = true
	if _lantern:
		_lantern.visible = false
	position = at
	_face(fire, 1.0)
	rotation.y = _yaw + PI * 0.5
	_blanket = MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(1.8, 0.1, 0.75)
	(_blanket as MeshInstance3D).mesh = m
	var wool := StandardMaterial3D.new()
	wool.albedo_color = [Color(0.36, 0.2, 0.15), Color(0.3, 0.3, 0.27), Color(0.42, 0.36, 0.24)][get_instance_id() % 3]
	wool.roughness = 1.0
	(_blanket as MeshInstance3D).material_override = wool
	_blanket.position = Vector3(-0.55, 0.05, 0)
	add_child(_blanket)
	if _body:
		_body.play("CrouchIdle", 0.08)
		_body.rotation = Vector3(0, 0, PI * 0.5)
		_body.position = Vector3(0.1, 0.28, 0)
	else:
		visible = false


func wake() -> void:
	recovering = false
	sleeping = false
	hiding = false
	visible = true
	job = "Boşta"
	if _rough:
		_rough = false
		inside = null
		if _blanket:
			_blanket.queue_free()
			_blanket = null
		if _body:
			_body.rotation = Vector3.ZERO
			_body.position = Vector3.ZERO
		return
	var from: Building = inside if is_instance_valid(inside) else (home if is_instance_valid(home) else null)
	inside = null
	if from:
		# Out the way it came in: the door opens, a few steps out.
		position = from.inside()
		var b := from
		give([{"t": "do", "f": func() -> bool:
			if is_instance_valid(b):
				b.open_door()
			return true}, {"t": "step", "to": b.door()}], "Dışarı çıkıyor")


## Up (or down) the scaffold to `y`, hand over hand.
func climb(y: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "position:y", y, 0.8).set_trans(Tween.TRANS_SINE)


## Up onto a tower's platform (an archer).
func perch_on(t: Building) -> void:
	perched = t
	position = t.global_transform * Vector3(0, 9.58, 0)


func get_down() -> void:
	if is_instance_valid(perched):
		position = perched.door()
	perched = null
	position.y = village.ground_at(position) if village.has_method("ground_at") else nav.height(position.x, position.z)


## A weapon in its right hand: "spear", "axe", "torch", "bow".
func arm_with(kind: String) -> void:
	if _weapon:
		_weapon.queue_free()
	_weapon = Node3D.new()
	_rifle = kind == "rifle" and _body != null
	if _rifle:
		# Held as the rifle clips hold it: the grip in the right hand, the barrel out along -z.
		_body.weapon_mount().add_child(_weapon)
	else:
		_weapon.position = Vector3(0, _palm() + 0.02, -0.04)
		_hand(1).add_child(_weapon)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.13)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.35, 0.36, 0.38)
	iron.metallic = 0.6
	iron.roughness = 0.45
	match kind:
		"spear":
			_rod(Vector3(0, 0.25, 0), 0.03, 2.1, wood)
			var tip := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.0
			tm.bottom_radius = 0.06
			tm.height = 0.3
			tip.mesh = tm
			tip.material_override = iron
			tip.position = Vector3(0, 1.45, 0)
			_weapon.add_child(tip)
		"axe":
			_rod(Vector3(0, -0.1, 0), 0.03, 0.8, wood)
			var head := MeshInstance3D.new()
			var hm := BoxMesh.new()
			hm.size = Vector3(0.04, 0.2, 0.24)
			head.mesh = hm
			head.material_override = iron
			head.position = Vector3(0, -0.42, -0.1)
			_weapon.add_child(head)
		"torch":
			_rod(Vector3(0, -0.15, 0), 0.035, 0.7, wood)
			var fire := MeshInstance3D.new()
			var fm := SphereMesh.new()
			fm.radius = 0.11
			fm.height = 0.26
			fire.mesh = fm
			var glow := StandardMaterial3D.new()
			glow.albedo_color = Color(1.0, 0.6, 0.2)
			glow.emission_enabled = true
			glow.emission = Color(1.0, 0.5, 0.15)
			glow.emission_energy_multiplier = 4.0
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fire.material_override = glow
			fire.position = Vector3(0, -0.55, 0)
			_weapon.add_child(fire)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.55, 0.2)
			light.light_energy = 1.6
			light.omni_range = 7.0
			light.position = Vector3(0, -0.6, 0)
			_weapon.add_child(light)
		"bow":
			var limb := StandardMaterial3D.new()
			limb.albedo_color = Color(0.5, 0.33, 0.17)
			for k in 3:
				var seg := _rod(Vector3(0, -0.45 + k * 0.45, -0.08 * float(k == 1)), 0.018, 0.48, limb)
				seg.rotation.x = [0.28, 0.0, -0.28][k]
			var cord := StandardMaterial3D.new()
			cord.albedo_color = Color(0.85, 0.82, 0.72)
			_rod(Vector3(0, 0.0, 0.06), 0.004, 1.3, cord)
		"rifle":
			if _rifle:
				_rod(Vector3(0, 0.06, -0.55), 0.016, 0.8, iron).rotation.x = PI * 0.5
				_rod(Vector3(0, 0.03, -0.3), 0.03, 0.55, wood).rotation.x = PI * 0.5
				_rod(Vector3(0, -0.02, 0.2), 0.04, 0.35, wood).rotation.x = PI * 0.5 + 0.2
			else:
				_rod(Vector3(0, 0.1, 0), 0.025, 1.2, iron)
				_rod(Vector3(0, -0.35, 0.02), 0.04, 0.45, wood)


func _rod(at: Vector3, r: float, length: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = length
	m.radial_segments = 6
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	_weapon.add_child(mi)
	return mi


## Lying wounded: bleeding out where it fell, or carried on someone's shoulders.
func _downed(dt: float) -> void:
	if is_instance_valid(carried_by) and not carried_by.dead and not carried_by.down and carried_by.carry_res == "yarali":
		position = carried_by.position + carried_by.global_basis * Vector3(0.0, 1.05, 0.25)
		rotation.y = carried_by.rotation.y + PI * 0.5
		return
	if carried_by != null:
		carried_by = null # (put down, or the one carrying it fell)
		position.y = village.ground_at(position)
	bleed -= dt
	if bleed <= 0.0:
		die()


func _go_down() -> void:
	abort()
	down = true
	hp = 1.0
	bleed = 120.0
	job = "Yaralı, yerde"
	drafted = false
	if _lantern:
		_lantern.visible = false
	_hold("")
	if _body:
		_body.lie()


## A blow (an arrow) of `dmg` from `by`.
func hurt(dmg: float, by: Villager = null) -> void:
	if dead:
		return
	if down:
		die() # (struck again where it lies)
		return
	hp -= dmg
	if _tunic:
		var c := _tunic.albedo_color
		_tunic.albedo_color = Color(1.0, 0.3, 0.25)
		var tw := create_tween()
		tw.tween_interval(0.12)
		tw.tween_callback(func() -> void: _tunic.albedo_color = c)
	if hp <= 0.0:
		# One of the town shot or cut down mostly lies wounded, not dead: it can still be saved.
		if team == 0 and _body and randf() < 0.75:
			_go_down()
			return
		die()
		return
	if fighter and not armed and by and is_instance_valid(by) and not by.dead and (plan.is_empty() or str(plan[0].t) != "fight"):
		abort()
		give([{"t": "fight", "foe": by, "give_up": 40.0}], "Savaşıyor")


func die() -> void:
	if dead:
		return
	abort()
	dead = true
	hp = 0.0
	if perched:
		get_down()
	died.emit(self)
	var tw := create_tween()
	if _body:
		_body.die() # (the knees go, and it falls)
		tw.tween_interval(1.4)
	else:
		tw.tween_property(self, "rotation:x", -PI * 0.5, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(self, "position:y", position.y + 0.2, 0.45)
	tw.tween_interval(30.0)
	tw.tween_property(self, "position:y", position.y - 1.0, 4.0)
	tw.tween_callback(queue_free)


func _process(dt: float) -> void:
	if dead:
		return
	if revealed > 0.0:
		revealed -= dt
	if down:
		_downed(dt)
		return
	if hp < max_hp:
		hp = minf(hp + dt * (0.35 if sleeping else 0.12), max_hp) # (mending, quicker asleep)
	if sleeping:
		return
	_lantern_check()
	if plan.is_empty():
		_anim = "idle"
		_animate(dt, false)
		return
	var step: Dictionary = plan[0]
	match str(step.t):
		"go":
			if _path.is_empty():
				_path = nav.path_for(self, position, step.to)
				_path_i = 0
			if _path.is_empty(): # (the way's still being found)
				_anim = "idle"
				_animate(dt, false)
			elif _walk(dt):
				plan.pop_front()
				_path = PackedVector3Array()
		"work":
			_anim = str(step.get("anim", "build"))
			_hold(TOOLS.get(_anim, ""))
			# The blows heard: an axe on wood, a pick and a chisel on stone, the hammer on a site.
			var period: float = {"chop": 1.37, "limb": 1.2, "mine": 1.57, "chisel": 0.45, "build": 0.9}.get(_anim, 0.0)
			if period > 0.0:
				_hit_t -= delta_safe(dt)
				if _hit_t <= 0.0:
					_hit_t = period
					var pitch: float = {"chop": 1.0, "limb": 1.2, "mine": 1.7, "chisel": 2.0, "build": 1.4}[_anim]
					Ambience.knock(global_position + Vector3.UP * 1.0 - global_basis.z * 0.6, pitch)
			if step.has("face"):
				_face(step.face, dt)
			var sk := work_skill()
			var pace := knack(sk)
			learn(sk, dt)
			_elapsed += dt * pace
			var over := false
			if step.has("tick"):
				over = not bool((step.tick as Callable).call(dt * _rate() * pace))
			elif _elapsed * _rate() >= float(step.time):
				over = true
			if over:
				_elapsed = 0.0
				plan.pop_front()
				if step.has("done"):
					(step.done as Callable).call()
			_animate(dt, false)
		"do":
			plan.pop_front()
			var r: Variant = (step.f as Callable).call()
			if r is bool and not r:
				abort()
		"fight":
			_fight(step, dt)
		"hold":
			_hold_post(step, dt)
		"step":
			var to: Vector3 = step.to
			var d := Vector2(to.x - position.x, to.z - position.z)
			var len := d.length()
			var move := 1.7 * dt
			_speed_now = 1.7
			if len <= move:
				position = to
				position.y = village.ground_at(position)
				plan.pop_front()
			else:
				position.x += d.x / len * move
				position.z += d.y / len * move
				position.y = village.ground_at(position)
				_face(to, dt)
			_anim = "walk"
			_hold("")
			_phase += dt * 5.0
			_animate(dt, true)
		_:
			plan.pop_front()


## A stretch of its walk; true once it's there.
func _walk(dt: float) -> bool:
	in_cover = false
	if _path_i >= _path.size():
		return true
	if team == 1 and village.has_method("barrier_at"):
		var bar: Dictionary = village.barrier_at(position, _path[_path_i])
		if not bar.is_empty():
			# A shut gate or the stakes in the way: hacked at till it gives.
			var at: Vector3 = (bar.gate as Node3D).global_position if bar.has("gate") else bar.at
			_face(at, dt)
			_anim = "strike"
			_attack_t -= dt
			if _attack_t <= 0.0:
				_attack_t = randf_range(1.0, 1.4)
				if bar.has("gate"):
					(bar.gate as Gate).hit(attack)
				else:
					if role == "torch" and randf() < 0.35:
						(bar.wall as Wall).ignite(at) # (a torch to it as well: it takes, slowly)
					(bar.wall as Wall).hit(at, attack)
			job = "Suru kırıyor"
			_animate(dt, false)
			return false
	var worn := nav.worn(position)
	var speed := 2.9 * (1.0 + 0.5 * worn * (1.0 - 0.75 * Weather.wet_now))
	speed *= 0.82 if carry_n > 0 else 1.0
	# A trodden way in the wet is mud underfoot; deep snow is slow going everywhere; planks are neither.
	var planks := nav.on_road(position)
	if planks:
		speed = 2.9 * 1.5 * (0.82 if carry_n > 0 else 1.0)
	else:
		speed *= 1.0 - 0.35 * smoothstep(0.3, 0.9, Weather.wet_now) * worn - 0.3 * Weather.snow_cover_now
	var mud := 0.0
	if has_cart:
		# Quick on a hard path, slow off it; in the wet the path is mud, and soft ground is worse.
		speed = 2.4 * (1.0 + 0.9 * worn * (1.0 - 0.8 * Weather.wet_now))
		mud = 0.0 if planks else clampf(Weather.wet_now * (0.4 + worn * 0.6) + nav.terrain.soft_at(position.x, position.z).x * 1.5 + Weather.snow_cover_now * 0.5, 0.0, 1.0)
		speed *= 1.0 - 0.6 * mud
		if _stuck > 0.0:
			_stuck -= dt
			_anim = "push"
			_animate(dt, false)
			return false
		if vehicle == "ox":
			# Slow and steady, but heavy: the mud has it more often and for longer.
			speed = 1.9 * (1.0 + 0.55 * worn * (1.0 - 0.8 * Weather.wet_now)) * (1.0 - 0.45 * mud)
		if mud > 0.35 and randf() < dt * (0.1 if vehicle == "ox" else 0.06) * mud:
			_stuck = randf_range(5.0, 9.0) if vehicle == "ox" else randf_range(2.5, 5.0)
			job = job if job.ends_with("(çamura saplandı)") else job + " (çamura saplandı)"
	speed *= _rate() * (1.1 if team == 1 else 1.0) * speed_mul
	_speed_now = speed
	var left := speed * dt
	var moved := 0.0
	while left > 0.0 and _path_i < _path.size():
		var to := _path[_path_i]
		var d := Vector2(to.x - position.x, to.z - position.z)
		var len := d.length()
		if len <= left:
			position.x = to.x
			position.z = to.z
			left -= len
			moved += len
			_path_i += 1
		else:
			var step := d / len * left
			position.x += step.x
			position.z += step.y
			_face(to, dt)
			moved += left
			left = 0.0
	position.y = village.ground_at(position) if village.has_method("ground_at") else nav.height(position.x, position.z)
	if vehicle == "ox":
		# (the hooves and the wheels, a little to the right of the drover: a broad pair of ruts)
		nav.tread(global_transform * Vector3(0.95, 0, -1.7), dt, 2.0)
		nav.tread(global_transform * Vector3(0.95, 0, 1.0), dt, 4.0)
		nav.tread(position, dt, 1.0)
	else:
		nav.tread(position, dt, 3.0 if has_cart else (1.6 if carry_n > 0 else 1.0))
	for w in _wheels:
		w.rotation.x -= moved / _wheel_r
	for k in _ox_legs.size():
		_ox_legs[k].rotation.x = sin(_phase * 0.8 + (PI if k % 3 == 0 else 0.0)) * 0.4
	if _ox_head:
		_ox_head.rotation.x = sin(_phase * 0.8) * 0.06
	if _cart and vehicle == "hand":
		# (the bed follows the lie of the ground a little)
		var ahead := global_transform * Vector3(0, 0, -1.25)
		_cart.rotation.x = clampf(atan2(nav.height(ahead.x, ahead.z) - position.y, 1.25), -0.4, 0.4)
	if job.ends_with(" (çamura saplandı)") and _stuck <= 0.0:
		job = job.trim_suffix(" (çamura saplandı)")
	_anim = "walk"
	_hold("")
	_phase += dt * speed * 3.2
	_animate(dt, true)
	return _path_i >= _path.size()


## Out at night, one of the town's carries a lantern in its left hand.
func lantern_on() -> bool:
	return _lantern != null and _lantern.visible


func _lantern_check() -> void:
	if team != 0 or Engine.get_process_frames() % 20 != get_instance_id() % 20:
		return
	var want: bool = village.weather.is_night() and not perched and not down and lantern_mode != "off"
	if want and _lantern == null:
		_lantern = Node3D.new()
		_lantern.position = Vector3(0, _palm() - 0.02, -0.05)
		_hand(0).add_child(_lantern)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.2, 0.14)
		box.mesh = bm
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.75, 0.4)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.62, 0.25)
		glow.emission_energy_multiplier = 3.0
		box.material_override = glow
		_lantern.add_child(box)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.66, 0.32)
		l.omni_range = LANTERN_REACH
		l.light_energy = 0.9
		l.shadow_enabled = false
		_lantern.add_child(l)
	if _lantern:
		_lantern.visible = want


## A tool in the right hand ("" puts it away): only while working, and never over a weapon.
func _hold(kind: String) -> void:
	if _weapon and _weapon.get_child_count() > 0:
		kind = ""
	if kind == _tool_kind:
		return
	_tool_kind = kind
	if _tool:
		_tool.queue_free()
		_tool = null
	if _body:
		_body.grip(null)
	if kind == "" or (_arms.size() < 2 and _body == null):
		return
	_tool = Node3D.new()
	_tool.position = Vector3(0, _palm(), -0.04)
	_hand(0 if kind == "bowl" else 1).add_child(_tool)
	var wood := Building.material("wood")
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.32, 0.33, 0.35)
	iron.metallic = 0.7
	iron.roughness = 0.4
	# The haft runs along the forearm and out past the fist, the head at its far end (-y, then
	# forward once the arm swings up).
	if kind == "bowl":
		var bw := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.09
		bm.bottom_radius = 0.05
		bm.height = 0.07
		bm.radial_segments = 10
		bw.mesh = bm
		bw.material_override = wood
		bw.position = Vector3(0, -0.06, -0.06)
		_tool.add_child(bw)
		return
	if kind == "scythe":
		# the snath, long and bent, held by its two grips; the blade out at its foot
		_tool_part(Vector3(0.035, 1.6, 0.035), Vector3(0, -0.55, -0.1), wood, Vector3(-0.15, 0, 0))
		_tool_part(Vector3(0.03, 0.03, 0.2), Vector3(0, -0.45, -0.2), wood)
		_tool_part(Vector3(0.012, 0.08, 0.75), Vector3(0.0, -1.32, -0.42), iron, Vector3(0, 0.25, 0))
		_second_hand(Vector3(0, -0.45, -0.28))
		return
	var haft: float = {"axe": 0.85, "pick": 0.85, "hammer": 0.38, "sickle": 0.18, "hoe": 1.3, "spade": 1.1, "saw": 0.16, "mallet": 0.3}[kind]
	_tool_part(Vector3(0.035, haft, 0.035), Vector3(0, -haft * 0.35, 0), wood)
	var tip := Vector3(0, -haft * 0.85, 0)
	match kind:
		"axe":
			_tool_part(Vector3(0.04, 0.16, 0.22), tip + Vector3(0, 0, -0.1), iron)
		"pick":
			_tool_part(Vector3(0.05, 0.05, 0.6), tip, iron)
		"hammer":
			_tool_part(Vector3(0.09, 0.09, 0.2), tip, iron)
		"sickle":
			for k in 4:
				var a := k * 0.45
				_tool_part(Vector3(0.02, 0.12, 0.03), tip + Vector3(0, -cos(a) * 0.12 - 0.05, -sin(a) * 0.14), iron, Vector3(a, 0, 0))
		"hoe":
			_tool_part(Vector3(0.18, 0.04, 0.16), tip + Vector3(0, 0, -0.08), iron)
		"spade":
			_tool_part(Vector3(0.2, 0.26, 0.03), tip + Vector3(0, -0.1, 0), iron)
		"saw":
			_tool_part(Vector3(0.012, 0.13, 0.8), tip + Vector3(0, -0.02, -0.4), iron)
			_tool_part(Vector3(0.03, 0.03, 0.8), tip + Vector3(0, 0.22, -0.4), wood)
		"mallet":
			_tool_part(Vector3(0.12, 0.12, 0.2), tip, wood)
	# A long haft's held in both hands: the left one further down it.
	var other: float = {"axe": 0.3, "pick": 0.36, "hoe": 0.5, "spade": 0.5}.get(kind, 0.0)
	if other > 0.0:
		_second_hand(Vector3(0, -other, 0))


## Where the left hand takes hold of the tool (Townsfolk.grip).
func _second_hand(at: Vector3) -> void:
	if _body == null or _tool == null:
		return
	var m := Node3D.new()
	m.position = at
	_tool.add_child(m)
	_body.grip(m)


func _tool_part(size: Vector3, at: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	_tool.add_child(mi)


static func delta_safe(dt: float) -> float:
	return minf(dt, 0.1)


func _rate() -> float:
	return village.work_rate if team == 0 else 1.0


## At its post: the foe it's told to shoot, or else the nearest it can see in reach; out of cartridges
## it only watches.
func _hold_post(step: Dictionary, dt: float) -> void:
	_path = PackedVector3Array()
	var raids: Raids = village.raids
	var foe: Villager = null
	if is_instance_valid(focus) and not focus.dead and focus.position.distance_to(position) <= ranged * 1.25 and raids.can_see(position, focus):
		foe = focus
	elif raids and ranged > 0.0:
		foe = raids.nearest_raider(position, ranged, true)
	if foe and (ammo > 0 or not armed):
		_face(foe.position, dt * 3.0)
		_anim = "aim"
		_attack_t = _attack_t - dt if _aimed_at(foe.position) else maxf(_attack_t, 0.5) # (turned to it, the gun up, then the shot)
		if _attack_t <= 0.0:
			_attack_t = randf_range(2.2, 3.0)
			if armed:
				ammo -= 1
			var d := foe.position.distance_to(position)
			if held == "bow":
				_attack_t = randf_range(1.4, 1.9) # (a bow's quicker than a bolt)
				raids.arrow(muzzle(), foe, attack * randf_range(0.8, 1.2), clampf(1.0 - d / (ranged * 1.4), 0.3, 0.8), self)
			else:
				raids.shoot(muzzle(), foe, attack * randf_range(0.8, 1.2), clampf(1.0 - d / (ranged * 1.6), 0.3, 0.85), self)
	else:
		_anim = "idle"
		if step.has("face"):
			_face(step.face, dt)
	if armed and ammo <= 0:
		job = "Oku bitti" if held == "bow" else "Fişeği bitti"
	_animate(dt, false)


## Where a shot leaves from: the rifle's muzzle, the bow in the hand (or about the shoulder).
func muzzle() -> Vector3:
	if _weapon and is_instance_valid(_weapon) and _weapon.get_child_count() > 0:
		if _rifle:
			return _weapon.global_transform * Vector3(0, 0.06, -0.96)
		return _weapon.global_position
	return global_position + Vector3.UP * 1.45


## Turned to `p` near enough to shoot at it.
func _aimed_at(p: Vector3) -> bool:
	var to := Vector2(p.x - position.x, p.z - position.z)
	var fwd := Vector2(-global_basis.z.x, -global_basis.z.z)
	if to.length() < 0.1 or fwd.length() < 0.1:
		return true
	return to.normalized().dot(fwd.normalized()) > 0.985


func _fight(step: Dictionary, dt: float) -> void:
	var foe: Variant = step.foe
	if not is_instance_valid(foe) or (foe as Villager).dead or (foe as Villager).down or (foe as Villager).sleeping or (foe as Villager).perched:
		plan.pop_front()
		_path = PackedVector3Array()
		return
	var f := foe as Villager
	var d := Vector2(f.position.x - position.x, f.position.z - position.z).length()
	if d > float(step.get("give_up", 60.0)):
		plan.pop_front()
		_path = PackedVector3Array()
		return
	if ranged > 0.0 and d <= ranged and village.raids and village.raids.can_see(position, f):
		# A rifle: stand, aim, fire.
		_path = PackedVector3Array()
		_face(f.position, dt * 3.0)
		_anim = "aim"
		_attack_t = _attack_t - dt if _aimed_at(f.position) else maxf(_attack_t, 0.5)
		if _attack_t <= 0.0:
			_attack_t = randf_range(2.0, 2.8)
			village.raids.shoot(muzzle(), f, attack * randf_range(0.8, 1.2), clampf(1.0 - d / (ranged * 1.6), 0.3, 0.85), self)
		_animate(dt, false)
		return
	if role == "shooter" or (armed and ranged > 0.0):
		plan.pop_front() # (a rifleman doesn't run in: out of sight or reach, it lets it go)
		_path = PackedVector3Array()
		return
	if d > 1.4:
		if _path.is_empty() or f.position.distance_to(_chase_at) > 2.5 or _path_i >= _path.size():
			var way := nav.path_for(self, position, f.position)
			if not way.is_empty():
				_path = way
				_path_i = 0
				_chase_at = f.position
		_walk(dt)
		return
	_path = PackedVector3Array()
	_face(f.position, dt * 3.0)
	_anim = "strike"
	_attack_t -= dt
	if _attack_t <= 0.0:
		_attack_t = randf_range(0.9, 1.3)
		if randf() < 0.7:
			f.hurt(attack * randf_range(0.7, 1.3), self)
	_animate(dt, false)


func _face(p: Vector3, dt: float) -> void:
	var d := Vector2(p.x - position.x, p.z - position.z)
	if d.length() < 0.05:
		return
	var want := atan2(-d.x, -d.y)
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-10.0 * dt))
	rotation.y = _yaw


func _animate(dt: float, walking: bool) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var leg := 0.0
	var arm_l := 0.0
	var arm_r := 0.0
	var bob := 0.0
	var lean := 0.0
	var twist := 0.0
	var el := 0.15 ## elbows bent (forearm forward and up as it grows)
	var er := 0.15
	var kn := 0.05 ## knees bent
	match _anim:
		"walk":
			leg = sin(_phase) * 0.55
			arm_l = -leg * 0.6
			arm_r = leg * 0.6
			bob = absf(sin(_phase)) * 0.05
			el = 0.35 + maxf(-arm_l, 0.0) * 0.4
			er = 0.35 + maxf(-arm_r, 0.0) * 0.4
		"chop":
			# Both hands on the haft, swung in flat at the trunk from over the right shoulder.
			var s := sin(t * 4.6)
			arm_l = -1.3
			arm_r = -1.3
			twist = s * 0.75
			lean = 0.1
			el = 0.5 - s * 0.25
			er = 0.35 + s * 0.25
			kn = 0.2
		"mine":
			# Overhead and down.
			var s := sin(t * 4.0)
			arm_l = -1.6 - s * 1.0
			arm_r = arm_l
			lean = -s * 0.2 + 0.1
			el = 0.3 + maxf(s, 0.0) * 0.6
			er = el
			kn = 0.25
		"mow":
			# The scythe: a long flat sweep from right to left, the body turning from the hips into it,
			# the knees soft; then lifted round to the right again.
			var u := fmod(t + (get_instance_id() % 5) * 0.25, 1.7) / 1.7
			var sweep := smoothstep(0.0, 0.55, u)
			var back := smoothstep(0.6, 1.0, u)
			twist = 0.85 - sweep * 1.6 + back * 1.6
			arm_l = -0.75 + (1.0 - absf(sweep - back)) * 0.1
			arm_r = -0.55
			lean = 0.32
			el = 0.75
			er = 0.45
			kn = 0.35
		"reap":
			# Bent to the stalks, the sickle drawn round low.
			var s := sin(t * 5.0)
			arm_r = -0.7 + s * 0.3
			arm_l = -0.9
			twist = s * 0.5
			lean = 0.55
			el = 0.9
			er = 0.4
			kn = 0.5
		"hoe":
			# Raised high, brought down hard into the ground (body behind it), drawn back toward the feet.
			var u := fmod(t + (get_instance_id() % 7) * 0.2, 1.6) / 1.6
			var up := smoothstep(0.0, 0.5, u) * (1.0 - smoothstep(0.55, 0.66, u))
			var pull := smoothstep(0.68, 1.0, u)
			arm_r = -0.35 - up * 0.95 + pull * 0.15
			arm_l = arm_r
			lean = 0.38 - up * 0.18 + pull * 0.06
			er = 0.25 + up * 0.75 + pull * 0.3
			el = er
			kn = 0.3 + (1.0 - up) * 0.1
			twist = -0.2
		"dig":
			var s := sin(t * 3.0)
			arm_l = -0.8 + s * 0.4
			arm_r = arm_l
			lean = 0.35 + s * 0.2
			el = 0.6
			er = 0.6
			kn = 0.4
		"limb":
			# Down at the trunk, lopping the branches off it.
			var s := sin(t * 5.2)
			arm_l = -1.1 - s * 0.6
			arm_r = arm_l
			lean = 0.5
			twist = s * 0.3
			el = 0.5 + maxf(s, 0.0) * 0.5
			er = el
			kn = 0.45
		"saw":
			# Both hands on the saw, drawn back and forth across the log: the arms pumping at the elbow.
			var s := sin(t * 5.0)
			arm_l = -0.75 + s * 0.3
			arm_r = -0.85 + s * 0.35
			lean = 0.3 - s * 0.06
			el = 1.1 - s * 0.5
			er = 1.2 - s * 0.6
			kn = 0.25
		"chisel":
			# The chisel held to the block, the mallet coming down on it.
			var s := absf(sin(t * 7.0))
			arm_l = -0.7
			arm_r = -1.2 - s * 0.5
			lean = 0.35
			el = 0.8
			er = 0.5 + s * 1.0
		"sit":
			arm_l = -0.5
			arm_r = -0.45
			lean = 0.15
			el = 0.9 # (hands on the knees)
			er = 0.9
		"eat":
			# Sat, the bowl in the left hand, the spoon going up to the mouth.
			var s := sin(t * 2.2)
			arm_l = -0.6
			arm_r = -0.6 - maxf(s, 0.0) * 0.5
			lean = 0.2
			el = 1.3 # (the bowl held up)
			er = 1.2 + maxf(s, 0.0) * 1.2 # (the spoon to the mouth)
		"stretch":
			var s := sin(t * 1.6)
			arm_l = -2.6 - s * 0.3
			arm_r = arm_l
			lean = -0.15
			el = 0.05
			er = 0.05
		"look":
			twist = sin(t * 0.7 + get_instance_id() % 5) * 0.7
			arm_l = 0.1
			arm_r = 0.1
		"chat":
			var s := sin(t * 2.8 + get_instance_id() % 7)
			arm_r = -0.5 + s * 0.45
			arm_l = -0.15
			twist = sin(t * 0.9) * 0.2
			er = 1.1 + s * 0.4 # (a hand going as it talks)
			el = 0.25
		"sow":
			# The seed taken from the bag on the left arm, then flung out in a wide fan as the body turns.
			var u := fmod(t + (get_instance_id() % 5) * 0.3, 1.3) / 1.3
			var cast := smoothstep(0.35, 0.6, u) * (1.0 - smoothstep(0.75, 1.0, u))
			arm_l = -0.65
			arm_r = -0.5 - cast * 0.9
			twist = 0.35 - cast * 0.8
			lean = 0.12
			el = 1.35 # (the seed bag held up against the chest)
			er = 1.3 - cast * 1.1
			kn = 0.1
		"gather", "draw":
			arm_l = -0.9 + sin(t * 3.0) * 0.3
			arm_r = -0.9 - sin(t * 3.0) * 0.3
			lean = 0.35
		"throw":
			var s := sin(t * 4.5)
			arm_l = -1.2 - s * 0.8
			arm_r = arm_l
			lean = -s * 0.1
		"strike":
			var s := sin(t * 6.0 + get_instance_id() % 7)
			arm_r = -1.0 - s * 1.2
			arm_l = -0.4
			lean = -s * 0.15
		"aim":
			arm_l = -1.5
			arm_r = -1.4 + sin(t * 2.0) * 0.1
		"torch":
			var s := sin(t * 3.0)
			arm_r = -1.3 - s * 0.4
			arm_l = -0.3
			lean = 0.2
		"climb":
			var s := sin(t * 6.0)
			arm_l = -2.4 - s * 0.4
			arm_r = -2.4 + s * 0.4
			el = 0.6 + s * 0.4
			er = 0.6 - s * 0.4
			kn = 0.5 + s * 0.4
		"aim":
			arm_l = -1.3
			arm_r = -1.2
			el = 0.5
			er = 1.7 # (the butt to the shoulder)
		"build":
			var s := sin(t * 7.0)
			el = 0.8
			er = 0.5 + maxf(s, 0.0) * 0.9
			arm_r = -1.3 - s * 0.6
			arm_l = -0.6
			lean = 0.1
		_:
			arm_l = sin(t * 1.3) * 0.04
			arm_r = -arm_l
	if _anim == "push":
		arm_l = -0.7 + sin(t * 5.0) * 0.15
		arm_r = arm_l
		lean = 0.45
	if _anim == "push":
		el = 0.5
		er = 0.5
		kn = 0.4
	if vehicle == "hand" and _anim == "walk":
		arm_l = -0.7
		arm_r = -0.7
		lean = 0.15
		el = 0.45
		er = 0.45
	elif vehicle == "ox" and _anim == "walk":
		arm_r = -0.9 # (a hand on the halter)
	elif carry_n > 0 and carry_res in ["tas", "yiyecek", "su"] and _anim == "walk":
		arm_l = -0.5
		arm_r = -0.5
		el = 1.0 # (the load held in both arms)
		er = 1.0
	elif carry_n > 0 and carry_res == "odun" and _anim == "walk":
		arm_r = -2.6
		er = 1.8 # (the hand over on the log)
	if _body:
		if _lantern and _lantern.visible:
			_lantern.global_basis = Basis.IDENTITY # (it hangs from the hand, upright)
		_body.drive(_anim, walking, _speed_now, _rate(), carry_res if carry_n > 0 else "", vehicle, _rifle,
			{"arm_l": arm_l, "arm_r": arm_r, "el": el, "er": er, "lean": lean, "twist": twist, "kn": kn})
		return
	var k := 1.0 - exp(-14.0 * dt)
	# Sitting: down on the ground, the knees up a little.
	_sit = move_toward(_sit, 1.0 if _anim in ["sit", "eat"] else 0.0, dt * 2.5)
	var drop := (0.4 if not _knees.is_empty() else 0.52) * _sit
	for hip in _legs:
		hip.position.y = _hip_y - drop
	var thigh := 1.25 if not _knees.is_empty() else 1.45
	_legs[0].rotation.x = lerpf(_legs[0].rotation.x, (leg if walking else 0.0) + thigh * _sit, k)
	_legs[1].rotation.x = lerpf(_legs[1].rotation.x, (-leg if walking else 0.0) + thigh * _sit, k)
	if _knees.size() == 2:
		# A knee bends as its leg swings through, and when sitting, bending over, working low.
		var swing_l := maxf(sin(_phase + 1.3), 0.0) * 0.95 if walking else 0.0
		var swing_r := maxf(sin(_phase + 1.3 + PI), 0.0) * 0.95 if walking else 0.0
		_knees[0].rotation.x = lerpf(_knees[0].rotation.x, -(kn + swing_l + 0.5 * _sit), k)
		_knees[1].rotation.x = lerpf(_knees[1].rotation.x, -(kn + swing_r + 0.5 * _sit), k)
	if _elbows.size() == 2:
		_elbows[0].rotation.x = lerpf(_elbows[0].rotation.x, el, k)
		_elbows[1].rotation.x = lerpf(_elbows[1].rotation.x, er, k)
	# (the numbers above raise an arm forward and lean forward as they grow; the model faces -z)
	_arms[0].rotation.x = lerpf(_arms[0].rotation.x, -arm_l, k)
	_arms[1].rotation.x = lerpf(_arms[1].rotation.x, -arm_r, k)
	_torso.position.y = bob - drop
	_torso.rotation.x = lerpf(_torso.rotation.x, -lean, k)
	_torso.rotation.y = lerpf(_torso.rotation.y, twist, k)
