class_name Workshop
extends Node
## The valley has no base: the workshop is a truck (Designs.workshop: six big wheels, a V8, a shop
## of plate walls on its bed, a crane), and it's where you left it. Only beside it (within REACH) can
## a machine be built on or mended; nowhere else. V gets you out of your machine and into it (within
## SWAP of it), and back: it's slow and heavy (3 t), it sinks where your machine wouldn't, and it
## carries what your machine can't (Expeditions). Left, it's braked.
##
## What's brought home is taken in: billets (Timber) and wrecks' parts (Salvage) set down within YARD of
## it, or riding on your machine's bed stopped within REACH, go into the store one at a time (TAKE_EVERY
## s): wood into Inventory.wood, parts into what you hold. The wood age's weapons are stocked again
## there (bolts, stones, oil: a quarter of a load for a billet, ARM_EVERY s).
## Mending: your machine stopped beside it, its hurt parts are put right a little at a time, the steel
## paid in scrap (Inventory.scrap: SCRAP_PER for each whole part's worth), the wooden in wood
## (Inventory.wood: WOOD_PER); what there's nothing to pay for waits; a part that's gone stays gone.
## Where it stands is kept (`path`); a machine lost is built anew beside it.

const REACH := 25.0 ## m: building and mending
const SWAP := 12.0 ## m: getting in and out
const MEND := 0.05 ## of a part's hit points a step
const MEND_EVERY := 0.5 ## s
const SCRAP_PER := 10.0 ## scrap a whole part's worth of mending costs
const WOOD_PER := 2.0 ## billets a whole wooden part's worth of mending costs
const YARD := 12.0 ## m round the truck what's set down is taken in
const TAKE_EVERY := 0.35 ## s

static var path := "user://valley_workshop.cfg" ## (tests point it elsewhere)

var game: Node
var terrain: Node
var truck: Machine
var own: Machine ## your machine, while you drive the truck
var mending := false
var _mend_t := 0.0
var _save_t := 0.0
var _owe := 0.0
var _owe_wood := 0.0
var _arm_t := 0.0
var _take_t := 0.0
var _brought := 0 ## (wood taken in this time: said once it's all in)
var _brought_t := 0.0
const ARM_EVERY := 1.0 ## s


## Where it was left (or beside the valley's start): its transform.
static func saved_at(terrain_: Node) -> Transform3D:
	var cf := ConfigFile.new()
	if cf.load(path) == OK and cf.has_section_key("truck", "at"):
		var p: Vector3 = cf.get_value("truck", "at")
		return Transform3D(Basis(Vector3.UP, float(cf.get_value("truck", "yaw", 0.0))), p)
	var s: Transform3D = terrain_.get("spawn") if terrain_.get("spawn") != null else Transform3D.IDENTITY
	var p := s.origin + s.basis.x * 9.0
	p.y = float(terrain_.call("height_at", p.x, p.z))
	return Transform3D(s.basis, p)


## Where your machine's put (beside the truck).
static func beside(terrain_: Node) -> Transform3D:
	var at := saved_at(terrain_)
	var p := at.origin - at.basis.x * 8.0
	p.y = float(terrain_.call("height_at", p.x, p.z)) + 1.5
	return Transform3D(at.basis, p)


func _ready() -> void:
	name = "Workshop"
	var at := saved_at(terrain)
	at.origin.y = float(terrain.call("height_at", at.origin.x, at.origin.z)) + 2.2
	truck = game.call("_spawn", Designs.workshop(), at, 0)
	truck.label = "ATÖLYE"
	truck.invulnerable = true # (the shop itself: knocked about, never broken)
	truck.ammo_limited = false
	truck.brake = 1.0


func _exit_tree() -> void:
	save()


func save() -> void:
	if not is_instance_valid(truck) or not truck.is_inside_tree():
		return
	var cf := ConfigFile.new()
	cf.set_value("truck", "at", truck.global_position)
	cf.set_value("truck", "yaw", truck.global_basis.get_euler().y)
	cf.save(path)


func driving() -> bool:
	return is_instance_valid(truck) and game.get("machine") == truck


## Your machine (not the truck), wherever you are.
func yours() -> Machine:
	if driving():
		return own if is_instance_valid(own) else null
	var mv: Variant = game.get("machine")
	return mv as Machine if is_instance_valid(mv) else null


## How far `m` is from the truck.
func dist(m: Machine) -> float:
	if not is_instance_valid(truck) or not is_instance_valid(m):
		return INF
	return m.global_position.distance_to(truck.global_position)


func near(m: Machine) -> bool:
	return dist(m) <= REACH


## V: into the truck from beside it, or back into your machine from beside that.
func swap() -> bool:
	if driving():
		if not is_instance_valid(own):
			game.call("say", "Aracın yok")
			return false
		if dist(own) > SWAP:
			game.call("say", "Aracına geçmek için yanına sür (%d m)" % roundi(dist(own)))
			return false
		game.call("drive", own)
		own = null
		game.call("say", "Aracındasın")
		return true
	var me: Machine = game.get("machine")
	if dist(me) > SWAP:
		game.call("say", "Atölyeye binmek için yanına git (%d m)" % roundi(dist(me)))
		return false
	own = me
	game.call("drive", truck)
	game.call("say", "ATÖLYE kamyonundasın: yavaş, ağır, çok taşır  ·  V: aracına dön")
	return true


func _physics_process(dt: float) -> void:
	if not is_instance_valid(truck):
		return
	if not driving():
		truck.throttle = 0.0
		truck.steer = 0.0
		truck.brake = 1.0
	_save_t -= dt
	if _save_t <= 0.0:
		_save_t = 10.0
		save()
	# mending: your machine, stopped beside it, not being built on
	var m := yours()
	_take_t -= dt
	if _take_t <= 0.0:
		_take_t = TAKE_EVERY
		_take_in(m)
	if _brought > 0:
		_brought_t -= dt
		if _brought_t <= 0.0:
			game.call("say", "+%d odun  ·  depoda %d" % [_brought, Inventory.wood])
			_brought = 0
	if m and near(m) and not driving():
		_arm_t += dt
		if _arm_t >= ARM_EVERY:
			_arm_t = 0.0
			_stock(m)
	mending = false
	if m == null or driving() or m.building or not near(m) or absf(m.speed) > 0.5:
		_mend_t = 0.0
		return
	# what's hurt that can be paid for: steel with scrap, wood with wood
	var can := func(p: Dictionary) -> bool:
		if float(p.hp) >= Parts.hp_of(p.id) * 0.995:
			return false
		return Inventory.wood > 0 if Parts.burns(p.id) else Inventory.scrap > 0
	var hurt := m.design.filter(can)
	if hurt.is_empty():
		mending = false
		return
	mending = true
	_mend_t += dt
	if _mend_t < MEND_EVERY:
		return
	_mend_t = 0.0
	for p: Dictionary in hurt:
		var full := Parts.hp_of(p.id)
		var gain := minf(MEND, 1.0 - float(p.hp) / full)
		if Parts.burns(p.id):
			_owe_wood += gain * WOOD_PER
		else:
			_owe += gain * SCRAP_PER
		p.hp = float(p.hp) + gain * full
		var f := float(p.hp) / full
		if f >= 0.5:
			p.erase("weak")
			p.erase("sputter")
		if f >= Machine.TYRE_BURST:
			p.erase("flat")
		if f >= Machine.TRACK_THROWN:
			p.erase("thrown")
	m.rebuild()
	var pay := floori(_owe)
	if pay > 0:
		_owe -= pay
		Inventory.add_scrap(-pay)
	var pay_w := floori(_owe_wood)
	if pay_w > 0:
		_owe_wood -= pay_w
		Inventory.add_wood(-pay_w)
	if Combat.current and randf() < 0.5:
		Combat.current.sound("res://assets/audio/build/bolt_on_0%d.wav" % randi_range(1, 3), m.global_position, -8.0, randf_range(0.9, 1.1))


## The line for the HUD: where it is from you, and what it's doing.
func status() -> String:
	if not is_instance_valid(truck):
		return ""
	if driving():
		var o := yours()
		return "ATÖLYEDESİN  ·  aracın %d m  ·  V: geç" % roundi(dist(o)) if o else "ATÖLYEDESİN"
	var me := yours()
	if me == null:
		return ""
	var d := dist(me)
	if d <= REACH:
		var s := "Atölye yanında  ·  B: inşa"
		if mending:
			s += "  ·  ONARILIYOR"
		elif Inventory.scrap <= 0 or Inventory.wood <= 0:
			s += "  ·  onarım için %s yok" % ("hurda" if Inventory.scrap <= 0 else "odun")
		return s
	var to := truck.global_position - me.global_position
	return "Atölye %d m %s" % [roundi(d), compass(atan2(to.x, -to.z))]


## A bearing (rad, 0 = north = -z, clockwise) in words.
static func compass(a: float) -> String:
	var names := ["kuzey", "kuzeydoğu", "doğu", "güneydoğu", "güney", "güneybatı", "batı", "kuzeybatı"]
	return names[posmod(roundi(a / (TAU / 8.0)), 8)]


## One thing brought home taken in: set down in the yard, or riding on `m` stopped near.
func _take_in(m: Machine) -> void:
	var shop := truck.global_position
	var on_bed := m != null and near(m) and absf(m.speed) < 0.6 and not m.building
	for n: Node in get_tree().get_nodes_in_group(Timber.GROUP) + get_tree().get_nodes_in_group("salvage"):
		var b := n as RigidBody3D
		if b == null or b.has_meta("taken") or b.has_meta("plan") or b.linear_velocity.length() > 1.2:
			continue
		var in_yard := b.global_position.distance_to(shop) < YARD
		if not in_yard and not (on_bed and _riding(b, m)):
			continue
		var to := truck.global_transform * Vector3(0.0, 1.6, 1.5)
		if b.is_in_group(Timber.GROUP):
			var w := Timber.worth(b)
			Inventory.bring_wood(w)
			_brought += w
			_brought_t = 1.2
			Timber.take(b, to)
		else:
			var id := str(b.get_meta("salvage"))
			var c := float(b.get_meta("cond", 1.0))
			Inventory.add(id, 1, c)
			b.remove_from_group("salvage")
			Timber.take(b, to)
			game.call("say", "+ %s %s" % [Parts.def(id).name, Salvage.cond_word(c)])
		return


## Is `b` on `m` (over its bed, within its outline and a little above it)?
static func _riding(b: Node3D, m: Machine) -> bool:
	var l := m.global_transform.affine_inverse() * b.global_position
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p: Dictionary in m.design:
		var xf := Parts.xform_of(p.id, p.at, p.rot)
		var ext := Vector3(Parts.size_of(p.id, p.rot)) * Parts.CELL * 0.5
		lo = lo.min(xf.origin - ext)
		hi = hi.max(xf.origin + ext)
	return l.x > lo.x - 0.2 and l.x < hi.x + 0.2 and l.z > lo.z - 0.2 and l.z < hi.z + 0.2 and l.y > lo.y and l.y < hi.y + 1.5


## The wood age's weapons stocked from the store: a quarter of a load each, a billet for it.
func _stock(m: Machine) -> void:
	for g in m.guns:
		if g.kind in MachineGun.MANUAL and g.limited and g.ammo < g.ammo_max - 0.5 and Inventory.wood > 0:
			g.refill(0.25)
			Inventory.add_wood(-1)
			if Combat.current:
				Combat.current.sound("res://assets/audio/build/ratchet_0%d.wav" % randi_range(1, 3), m.global_position, -8.0, 0.9)
