class_name MachineHoist
extends RefCounted
## A crane or a winch on a Machine: a wire rope from its tip to something hooked on (a load, a
## wreck, another machine), pulling as a stiff spring when it's drawn tight and never pushing, so
## what hangs swings, what's dragged slides and bumps along behind, and what's too heavy stays where
## it is (or tips the machine over).
##
##   crane  (the part "crane": Y) slews round to where you look, its rope from a trolley that runs
##          out along its jib to as far as you look (REACH: so it sets a load down on your own bed as
##          well as picking one up beside you). Y with the hook over a load (within GRAB of the tip, below or beside it):
##          hooked, and the drum winds it up till it hangs HANG under the tip; Y again pays the rope out
##          till the load rests on something (LOWER m/s; LOWER_MAX s at most), and then lets it go.
##          So: hook it, look round over your bed, set it down there. It lifts its `lift` (1.5 t) at
##          most: heavier, the rope's as tight as it'll go and the load stays on the ground. And no
##          more than its machine stands up to (a load moment limiter, as a real one has): the load's
##          pull times how far out past the wheels it hangs against the machine's weight times how far
##          in from them its middle is. Bring the hook in closer, or build it heavier and wider.
##   winch  (the part "winch": N) from the fairlead at its back: N hooks the nearest load or machine
##          within GRAB_WINCH behind, the rope as long as it is, and winds it in to TOW; it pulls
##          `lift` (4 t) at most. Dragging a load, or pulling a machine (yours, sunk) out of the mud.
##
## On the mouse (your crane picked, `armed`: its number on the bottom panel, as a gun's): it slews and
## luffs to where the cross is; the left button held pays the rope out (`lower_held`) and the hook goes
## down there, and whatever it touches it takes hold of (HOOK_R round it: a billet, a part off a wreck,
## a load), where it touched; the right held winds it in (`raise_held`), with or without a load; let
## go, the drum holds. Q lets go of it (`release()`): set it down where you like, or drag it along
## behind you on the rope as far as you like.
## Y is the old way still: the nearest load to the hook (`pick()`) taken and wound up to `hang`; Y again
## pays out till it rests and lets go.
## The wood age's crane ("wood_crane") is the same, smaller: a short pole jib that luffs (its model's
## node Jib, hinged at `jib_pivot`: up to reach in close, down to reach out, LUFF), 450 kg. What a crane takes hold of: a load, a billet lying
## (Timber), a part off a wreck (Salvage): set on your own bed, it rides there (rails keep it on) and
## it's taken into the store beside the workshop (Workshop).
##
## The rope is drawn between the two (a thin line); the hook hangs at its end.

const GRAB := 6.0 ## m from the crane's tip a load can be hooked
const GRAB_WINCH := 12.0
const HANG := 1.4 ## m the crane winds the rope in to
const TOW := 3.0 ## m the winch winds the rope in to
const WIND := 0.9 ## m/s the drum winds
const LOWER := 1.2 ## m/s it pays out, setting a load down
const LOWER_MAX := 4.0 ## s
const AIM_PICK := 2.0 ## m from where you look a load's taken as the one meant
const ROPE_MAX := 9.0 ## m of rope on the drum
const SLEW := 1.4 ## rad/s the crane turns
const TIP := Vector3(0.0, 1.85, -2.5) ## the crane's sheave, in the part's space with the boom straight ahead
const ROOT := Vector3(0.0, 1.5, -0.1) ## where its jib leaves the post
const REACH := Vector2(0.8, 2.5) ## m out from the post the trolley runs
const TROLLEY := 1.2 ## m/s
const FAIRLEAD := Vector3(0.0, -0.05, 0.55) ## the winch's, at its back
const HOOK_R := 0.4 ## m round the hook it takes hold of what it touches
const HOOK_LEN := 1.0 ## m of rope the empty hook hangs on at first
const LUFF := Vector2(-0.3, 1.0) ## rad the jib tips down / up from where it's built
const LUFF_RATE := 0.9 ## rad/s

var machine: Machine
var node: Node3D
var index := -1 ## its part in the design
var kind := "crane"
var key := 0
var lift := 1500.0 ## kg
var tip_at := TIP ## (its own, if its part says: the wood age's is shorter)
var root_at := ROOT
var reach_range := REACH
var hang := HANG
var wind := WIND
var _lower_t := 0.0
var armed := true ## (picked: it follows the cross and the mouse works it)
var lower_held := false ## (the left button, this step)
var raise_held := false ## (the right)
var luff := 0.0 ## rad the jib's tipped up from where it's built (the wood crane's)
var _jib: Node3D
var _jib_pivot := Vector3.ZERO
var _tip_local := Vector3.ZERO
var condition := 1.0
var boom: Node3D ## (the crane's: what slews)
var slew := 0.0 ## rad, the boom turned from straight ahead (left +)
var reach := 2.5 ## m out along the jib the hook hangs from
var limited := false ## (the crane: held back from tipping its machine over this moment)
var _held := 0.0
var _warned := false
var _rope: MeshInstance3D
var _hook: MeshInstance3D


static func make(m: Machine, part: Node3D, i: int, id: String) -> MachineHoist:
	var h := MachineHoist.new()
	h.machine = m
	h.node = part
	h.index = i
	h.kind = str(Parts.def(id).kind)
	h.lift = float(Parts.def(id).get("lift", 1500.0))
	h.boom = part.find_child("Top", true, false) as Node3D
	var d := Parts.def(id)
	h.tip_at = d.get("tip", TIP)
	h.root_at = d.get("root", ROOT)
	h.reach_range = d.get("reach", REACH)
	h.hang = float(d.get("hang", HANG))
	h.wind = float(d.get("wind", WIND))
	var p: Dictionary = m.design[i]
	h.slew = float(p.get("slew", 0.0))
	h.reach = clampf(float(p.get("reach", h.reach_range.y)), h.reach_range.x, h.reach_range.y)
	h.luff = float(p.get("luff", 0.0))
	h._jib = part.find_child("Jib", true, false) as Node3D
	if h._jib and h.boom: # (it slews with the top: hung under it, where it was built)
		h._jib_pivot = h._jib.position
		h._jib.reparent(h.boom, false)
		h._jib.transform = Transform3D(Basis.IDENTITY, h._jib_pivot)
		h._tip_local = h.tip_at - h._jib_pivot
	return h


## What it's hooked to (kept on the part's row: a rebuild keeps it).
func hooked() -> PhysicsBody3D:
	var b: Variant = machine.design[index].get("rope_to") if index < machine.design.size() else null
	return b as PhysicsBody3D if is_instance_valid(b) else null


## Where the rope leaves it (world).
func tip() -> Vector3:
	if kind == "crane" and _jib:
		return node.global_transform * (Basis(Vector3.UP, slew) * (_jib_pivot + Basis(Vector3.RIGHT, luff) * _tip_local))
	if kind == "crane":
		var f := (reach - absf(root_at.z)) / (absf(tip_at.z) - absf(root_at.z))
		return node.global_transform * (Basis(Vector3.UP, slew) * root_at.lerp(tip_at, f))
	return node.global_transform * FAIRLEAD


## Where the rope's made fast on `b` (world): a load's top, a machine's middle.
static func eye(b: PhysicsBody3D) -> Vector3:
	if b is Machine:
		return (b as Machine).com_global()
	if b.has_meta("hook_at"): # (where the hook took it)
		return b.global_transform * (b.get_meta("hook_at") as Vector3)
	if not b.has_meta("size"): # (a billet, a part off a wreck: by its middle)
		return b.global_position + Vector3.UP * 0.12
	var size: Vector3 = b.get_meta("size", Vector3.ONE)
	return b.global_transform * Vector3(0.0, size.y * 0.5, 0.0)


## Y / N: hook on, or let go. Says what happened (for the screen); "" if nothing.
func toggle() -> String:
	if hooked():
		if kind == "crane" and not machine.design[index].has("lowering"):
			machine.design[index].erase("drum")
			machine.design[index].lowering = true # (set down first, then let go: update())
			_lower_t = 0.0
			return "İndiriyor"
		_let_go()
		return "%s bıraktı" % ("Vinç" if kind == "crane" else "Halat")
	var t := tip()
	var best: PhysicsBody3D = pick() if kind == "crane" else null
	var bd := GRAB if kind == "crane" else GRAB_WINCH
	if kind == "winch":
		for n: Node in liftable(machine.get_tree()):
			var b := n as PhysicsBody3D
			if b == null or b.has_meta("taken"):
				continue
			var d := eye(b).distance_to(t)
			if d < bd:
				bd = d
				best = b # (or a machine: one stuck, a wreck to drag)
		for n: Node in machine.get_tree().get_nodes_in_group("machines"):
			var m := n as Machine
			if m == machine or not m.alive:
				continue
			var d := m.com_global().distance_to(t) - 1.5
			if d < bd:
				bd = d
				best = m
	if best == null:
		return "Kancanın yakınında yük yok" if kind == "crane" else "Halatın ulaşacağı yerde yük ya da araç yok"
	var p: Dictionary = machine.design[index]
	_warned = false
	p.rope_to = best
	p.erase("lowering")
	p.erase("drum")
	p.rope_len = maxf(eye(best).distance_to(t), hang if kind == "crane" else TOW)
	if best is RigidBody3D and not best is Machine: # (it swings less, hung on a hook)
		(best as RigidBody3D).angular_damp = maxf((best as RigidBody3D).angular_damp, 3.0)
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), eye(best), -3.0 if best.is_in_group(Timber.GROUP) else 0.0, 0.8)
		if best.is_in_group(Timber.GROUP): # (the hook's iron on the chain, and the log knocked as it takes)
			Combat.current.sound("res://assets/audio/wood/knock_0%d.wav" % randi_range(1, 4), eye(best), 0.0, randf_range(0.8, 0.95))
	var what := (best as Machine).label if best is Machine else what_is(best)
	return "Kancada: %s" % what if what != "" else "Kancada"


## What the crane would take hold of now: of what's within GRAB of its tip, the one nearest where you
## look (within AIM_PICK of it), or failing that the nearest the tip; null if nothing.
func pick() -> PhysicsBody3D:
	if kind != "crane" or not is_instance_valid(node):
		return null
	var t := tip()
	var best: PhysicsBody3D = null
	var bd := INF
	var aim := machine.aim_point
	for n: Node in liftable(machine.get_tree()):
		var b := n as PhysicsBody3D
		if b == null or b.has_meta("taken") or b == hooked():
			continue
		var e := eye(b)
		var dt := e.distance_to(t)
		if dt > GRAB:
			continue
		var da := e.distance_to(aim)
		var score := da if da < AIM_PICK else 100.0 + dt
		if score < bd:
			bd = score
			best = b
	return best


## What there is to take hold of: loads, billets lying, parts off wrecks.
static func liftable(tree: SceneTree) -> Array[Node]:
	var out := tree.get_nodes_in_group("loads")
	out.append_array(tree.get_nodes_in_group(Timber.GROUP))
	for n: Node in tree.get_nodes_in_group("salvage"):
		if not n.has_meta("plan"):
			out.append(n)
	return out


## A load's name, in a word or two.
static func what_is(b: Node) -> String:
	if b.is_in_group(Timber.GROUP):
		return "kütük"
	if b.has_meta("salvage"):
		return Parts.def(str(b.get_meta("salvage"))).get("name", "parça")
	return str(b.get_meta("title", ""))


## Where the empty hook hangs (world): under the tip on its rope, resting on the ground if it's down.
func hook_at() -> Vector3:
	var t := tip()
	var p: Dictionary = machine.design[index]
	var h := t + Vector3.DOWN * float(p.get("hook_len", HOOK_LEN))
	var props := Timber.props_of(machine)
	if props and props.terrain:
		h.y = maxf(h.y, props.terrain.height_at(h.x, h.z) + 0.12)
	return h


## Q: let go of what it holds, where it is. Says what happened ("" if it held nothing).
func release() -> String:
	var b := hooked()
	if b == null:
		return ""
	var p: Dictionary = machine.design[index]
	p.hook_len = minf(eye(b).distance_to(tip()), ROPE_MAX)
	_let_go()
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), tip(), -6.0, 1.1)
	return "Bıraktı: %s" % what_is(b)


## The hook going down touched something it can take: it takes it, where it touched. True if it did.
func _touch(at: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = HOOK_R
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = 4
	q.exclude = [machine.get_rid()]
	var can := liftable(machine.get_tree())
	for hit: Dictionary in machine.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var b := hit.collider as PhysicsBody3D
		if b == null or b.has_meta("taken") or not b in can:
			continue
		b.set_meta("hook_at", b.to_local(at))
		var p: Dictionary = machine.design[index]
		p.rope_to = b
		p.drum = "hold"
		p.erase("lowering")
		p.rope_len = maxf(eye(b).distance_to(tip()), 0.3)
		_warned = false
		if b is RigidBody3D:
			(b as RigidBody3D).angular_damp = maxf((b as RigidBody3D).angular_damp, 3.0)
		if Combat.current:
			Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), at, -3.0, 0.85)
			if b.is_in_group(Timber.GROUP):
				Combat.current.sound("res://assets/audio/wood/knock_0%d.wav" % randi_range(1, 4), at, 0.0, randf_range(0.8, 0.95))
		return true
	return false


func _let_go() -> void:
	var p: Dictionary = machine.design[index]
	var was := hooked()
	if was and was.has_meta("hook_at"):
		was.remove_meta("hook_at")
	p.erase("rope_to")
	p.erase("rope_len")
	p.erase("lowering")
	p.erase("drum")


## Every physics step: the crane slews to the aim; the rope winds in and pulls.
func update(dt: float) -> void:
	if not is_instance_valid(node):
		return
	if kind == "crane" and boom:
		if (machine.keyed and armed) or (not machine.keyed and machine.firing):
			var to := node.global_transform.affine_inverse() * machine.aim_point
			var want := atan2(-to.x, -to.z)
			var turn := clampf(angle_difference(slew, want), -SLEW * dt, SLEW * dt) * (1.0 if machine.powered else 0.0)
			slew = wrapf(slew + turn, -PI, PI)
			machine.design[index].slew = slew
			var out := clampf(Vector2(to.x, to.z).length(), reach_range.x, reach_range.y)
			reach = move_toward(reach, out, TROLLEY * dt)
			machine.design[index].reach = reach
			if _jib: # (luffed: down to reach out to the cross, up to reach in close)
				var j := Basis(Vector3.UP, slew) * _jib_pivot
				var far := Vector2(to.x - j.x, to.z - j.z).length()
				var l := Vector2(_tip_local.y, _tip_local.z).length()
				var e0 := atan2(_tip_local.y, -_tip_local.z)
				var e := acos(clampf(far / l, 0.0, 1.0))
				var want_luff := clampf(e - e0, LUFF.x, LUFF.y)
				luff = move_toward(luff, want_luff, LUFF_RATE * dt * (1.0 if machine.powered else 0.0))
				machine.design[index].luff = luff
		boom.transform = Transform3D(Basis(Vector3.UP, slew), Vector3.ZERO)
		if _jib:
			_jib.transform = Transform3D(Basis(Vector3.RIGHT, luff), _jib_pivot)
	var b := hooked()
	if b == null:
		if kind == "crane": # (the empty hook: down on the left button till it touches something, up on the right)
			var p0: Dictionary = machine.design[index]
			var hl := float(p0.get("hook_len", HOOK_LEN))
			var run := 1.0 if machine.powered else 0.0
			if lower_held and armed:
				hl = minf(hl + LOWER * dt * run, ROPE_MAX)
				p0.hook_len = hl
				if _touch(hook_at()):
					_show(eye(hooked()))
					return
			elif raise_held and armed:
				p0.hook_len = maxf(hl - wind * dt * run, 0.35)
		_show(Vector3.INF)
		return
	var p: Dictionary = machine.design[index]
	var len := float(p.rope_len)
	var t := tip()
	var e := eye(b)
	var d := e - t
	var l := d.length()
	if armed and kind == "crane" and (lower_held or raise_held): # (the mouse on the drum)
		p.drum = "pay" if lower_held else "haul"
		p.erase("lowering")
	elif armed and kind == "crane" and str(p.get("drum", "")) in ["pay", "haul"]:
		p.drum = "hold"
	if p.has("lowering"): # (paying out: once the rope's gone slack under it, it's down)
		_lower_t += dt
		p.rope_len = len + LOWER * dt
		var still := (b as RigidBody3D).linear_velocity.length() < 0.5 if b is RigidBody3D else true
		if (l < float(p.rope_len) - 0.25 and still) or _lower_t > LOWER_MAX:
			_let_go()
			_show(Vector3.INF)
			return
	else:
		var run := 1.0 if machine.powered else 0.0
		match str(p.get("drum", "")):
			"pay":
				p.rope_len = minf(len + LOWER * dt * run, ROPE_MAX)
				if l < len - 0.3: # (it's resting on something: the rope'd only go slack)
					p.rope_len = l + 0.3
			"haul":
				p.rope_len = maxf(len - wind * dt * run, hang)
			"hold":
				pass
			_:
				p.rope_len = maxf(len - wind * dt * run, hang if kind == "crane" else TOW)
	if l > 30.0: # (torn away: the rope parts)
		_let_go()
		return
	if l > float(p.rope_len) and l > 0.001:
		var dir := d / l
		var other_mass := (b as RigidBody3D).mass if b is RigidBody3D else 1000.0
		var k := other_mass * 400.0
		var rel := (b as RigidBody3D).linear_velocity - machine.velocity_at(t) if b is RigidBody3D else -machine.velocity_at(t)
		var pull := k * (l - float(p.rope_len)) + other_mass * 20.0 * rel.dot(dir)
		pull = clampf(pull, 0.0, lift * 9.8 * 1.25 * maxf(condition, 0.3))
		if kind == "crane":
			var most := _steady(t, dir)
			limited = pull > most
			pull = minf(pull, most)
			_held = _held + dt if limited else 0.0
			if _held > 1.0 and not _warned:
				_warned = true
				machine.system_hit.emit("Vinç sınırda: bu yük aracını devirir. Kancayı yaklaştır ya da aracı ağırlaştır", t)
		var f := -dir * pull
		if b is RigidBody3D:
			(b as RigidBody3D).apply_force(f, e - b.global_position)
			(b as RigidBody3D).sleeping = false
		machine.apply_force(-f, t - machine.global_position)
	_show(e)


## The most the crane may pull at `t` (world), the rope going `u` (unit, toward the load), before its
## machine would tip over its wheels: the rope's turning moment about the line its outermost wheels
## that way stand on, against its weight's about the same line.
func _steady(t: Vector3, u: Vector3) -> float:
	var c := machine.com_global()
	var out := Vector3(t.x - c.x, 0.0, t.z - c.z)
	if out.length() < 0.05:
		return INF
	var dir := out.normalized()
	var edge := 0.3 # (how far out its wheels stand that way from its middle)
	var low := c.y
	for w in machine.wheels:
		var p := machine.global_transform * w.rest
		edge = maxf(edge, Vector3(p.x - c.x, 0.0, p.z - c.z).dot(dir))
		low = minf(low, p.y - w.radius)
	var e := c + dir * edge
	e.y = low
	var axis := Vector3.UP.cross(dir)
	var held := ((c - e).cross(Vector3.DOWN * machine.total_mass * 9.8)).dot(axis)
	var per := ((t - e).cross(u)).dot(axis)
	if signf(per) == signf(held) or absf(per) < 0.001:
		return INF
	return absf(held) * 0.7 / absf(per)


## The rope drawn from the tip to `e` (INF: none), the hook at its end.
func _show(e: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if e == Vector3.INF:
		if kind == "crane" and is_instance_valid(node): # (the hook hangs empty under the tip)
			if _rope == null:
				_make()
			_rope.visible = true
			_hook.visible = true
			_line(tip(), hook_at())
		elif _rope:
			_rope.visible = false
			_hook.visible = false
		return
	if _rope == null:
		_make()
	_rope.visible = true
	_hook.visible = true
	_line(tip(), e)


func _make() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.12, 0.12)
	m.metallic = 0.6
	m.roughness = 0.5
	_rope = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = 1.0
	cm.radial_segments = 6
	cm.material = m
	_rope.mesh = cm
	_rope.top_level = true
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(_rope)
	_hook = MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.14, 0.22, 0.1)
	var y := StandardMaterial3D.new()
	y.albedo_color = Color(0.62, 0.35, 0.04)
	y.metallic = 0.4
	hm.material = y
	_hook.mesh = hm
	_hook.top_level = true
	node.add_child(_hook)


func _line(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := maxf(d.length(), 0.01)
	var up := d / l
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up * l, side.cross(up)) # (the cylinder stretched along the rope)
	_rope.global_transform = Transform3D(basis, a + d * 0.5)
	_hook.global_transform = Transform3D(Basis(side, up, side.cross(up)), b + up * -0.05)


func free_fx() -> void:
	for n: Node3D in [_rope, _hook]:
		if is_instance_valid(n):
			n.queue_free()
