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
##          hooked, and the drum winds it up till it hangs HANG under the tip; Y again lets it go.
##          So: hook it, look round over your bed, set it down there. It lifts its `lift` (1.5 t) at
##          most: heavier, the rope's as tight as it'll go and the load stays on the ground. And no
##          more than its machine stands up to (a load moment limiter, as a real one has): the load's
##          pull times how far out past the wheels it hangs against the machine's weight times how far
##          in from them its middle is. Bring the hook in closer, or build it heavier and wider.
##   winch  (the part "winch": N) from the fairlead at its back: N hooks the nearest load or machine
##          within GRAB_WINCH behind, the rope as long as it is, and winds it in to TOW; it pulls
##          `lift` (4 t) at most. Dragging a load, or pulling a machine (yours, sunk) out of the mud.
##
## The rope is drawn between the two (a thin line); the hook hangs at its end.

const GRAB := 6.0 ## m from the crane's tip a load can be hooked
const GRAB_WINCH := 12.0
const HANG := 1.4 ## m the crane winds the rope in to
const TOW := 3.0 ## m the winch winds the rope in to
const WIND := 0.9 ## m/s the drum winds
const SLEW := 1.4 ## rad/s the crane turns
const TIP := Vector3(0.0, 1.85, -2.5) ## the crane's sheave, in the part's space with the boom straight ahead
const ROOT := Vector3(0.0, 1.5, -0.1) ## where its jib leaves the post
const REACH := Vector2(0.8, 2.5) ## m out from the post the trolley runs
const TROLLEY := 1.2 ## m/s
const FAIRLEAD := Vector3(0.0, -0.05, 0.55) ## the winch's, at its back

var machine: Machine
var node: Node3D
var index := -1 ## its part in the design
var kind := "crane"
var key := 0
var lift := 1500.0 ## kg
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
	var p: Dictionary = m.design[i]
	h.slew = float(p.get("slew", 0.0))
	h.reach = float(p.get("reach", REACH.y))
	return h


## What it's hooked to (kept on the part's row: a rebuild keeps it).
func hooked() -> PhysicsBody3D:
	var b: Variant = machine.design[index].get("rope_to") if index < machine.design.size() else null
	return b as PhysicsBody3D if is_instance_valid(b) else null


## Where the rope leaves it (world).
func tip() -> Vector3:
	if kind == "crane":
		var f := (reach - absf(ROOT.z)) / (absf(TIP.z) - absf(ROOT.z))
		return node.global_transform * (Basis(Vector3.UP, slew) * ROOT.lerp(TIP, f))
	return node.global_transform * FAIRLEAD


## Where the rope's made fast on `b` (world): a load's top, a machine's middle.
static func eye(b: PhysicsBody3D) -> Vector3:
	if b is Machine:
		return (b as Machine).com_global()
	var size: Vector3 = b.get_meta("size", Vector3.ONE)
	return b.global_transform * Vector3(0.0, size.y * 0.5, 0.0)


## Y / N: hook on, or let go. Says what happened (for the screen); "" if nothing.
func toggle() -> String:
	if hooked():
		_let_go()
		return "%s bıraktı" % ("Vinç" if kind == "crane" else "Halat")
	var t := tip()
	var best: PhysicsBody3D = null
	var bd := GRAB if kind == "crane" else GRAB_WINCH
	for n: Node in machine.get_tree().get_nodes_in_group("loads"):
		var b := n as PhysicsBody3D
		var d := eye(b).distance_to(t)
		if d < bd:
			bd = d
			best = b
	if kind == "winch": # (or a machine: one stuck, a wreck to drag)
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
	p.rope_len = maxf(eye(best).distance_to(t), HANG if kind == "crane" else TOW)
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), eye(best), 0.0, 0.8)
	var what := str(best.get_meta("title", "")) if not best is Machine else (best as Machine).label
	return "Kancada: %s" % what if what != "" else "Kancada"


func _let_go() -> void:
	var p: Dictionary = machine.design[index]
	p.erase("rope_to")
	p.erase("rope_len")


## Every physics step: the crane slews to the aim; the rope winds in and pulls.
func update(dt: float) -> void:
	if not is_instance_valid(node):
		return
	if kind == "crane" and boom:
		if machine.keyed or machine.firing:
			var to := node.global_transform.affine_inverse() * machine.aim_point
			var want := atan2(-to.x, -to.z)
			var turn := clampf(angle_difference(slew, want), -SLEW * dt, SLEW * dt) * (1.0 if machine.powered else 0.0)
			slew = wrapf(slew + turn, -PI, PI)
			machine.design[index].slew = slew
			var out := clampf(Vector2(to.x, to.z).length(), REACH.x, REACH.y)
			reach = move_toward(reach, out, TROLLEY * dt)
			machine.design[index].reach = reach
		boom.transform = Transform3D(Basis(Vector3.UP, slew), Vector3.ZERO)
	var b := hooked()
	if b == null:
		_show(Vector3.INF)
		return
	var p: Dictionary = machine.design[index]
	var len := float(p.rope_len)
	p.rope_len = maxf(len - WIND * dt * (1.0 if machine.powered else 0.0), HANG if kind == "crane" else TOW)
	var t := tip()
	var e := eye(b)
	var d := e - t
	var l := d.length()
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
	return absf(held) * 0.85 / absf(per)


## The rope drawn from the tip to `e` (INF: none), the hook at its end.
func _show(e: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if e == Vector3.INF:
		if _rope:
			_rope.visible = false
			_hook.visible = false
		elif kind == "crane" and is_instance_valid(node):
			_make()
			_rope.visible = true
			_hook.visible = true
			_line(tip(), tip() + Vector3.DOWN * 1.0) # (the hook hangs empty under the tip)
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
