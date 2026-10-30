class_name MachineWheel
extends RefCounted
## One wheel of a Machine: a ray down its travel, a spring and damper, the tyre on the ground.
##
## Its spring is as stiff as its rated load asks (rated kg sit it a little past the middle of its
## travel); past the travel's top a bump stop. The tyre's grip is the ground's (Surface.grip) times
## the tyre's own there: lugs bite in soft and wet ground and give a little on hard, a road tyre the
## other way round. On soft ground it sinks by how hard it presses on its footprint (load over
## width x radius, against a road wheel at its rated load), digs in spinning, eases out rolling, and
## being down in it drags (Surface.sink_drag) and, for a road tyre, loses grip; its rut goes into the
## ground (SoftPatch.stamp).
##
## A track's road wheels are these too (MachineTrack makes them): each presses on its share of the
## belt's length (`patch`) rather than a tyre's footprint, so it sinks about half as deep; its grousers
## bite hard in soft ground; and slewing it round (`lat_scale` below 1) lets it slide sideways.

const REF_PRESSURE := 450.0 / (0.26 * 0.38) ## kg per m of width x radius: a road wheel at its rated load
const DAMPING := 0.35 ## of critical, at the rated load

var machine: Machine
var node: Node3D ## the part
var spinner: Node3D ## its Wheel node (spins, steers, rides the travel)
var id := ""
var rest := Vector3.ZERO ## the hub at the middle of its travel (machine space)
var axle := Vector3.RIGHT ## (machine space)
var roll_dir := Vector3.FORWARD ## which way it rolls (machine space, the nose's way)
var radius := 0.38
var width := 0.26
var rated := 450.0
var travel := 0.16 ## half the travel either side of rest
var lugs := 0.0
var k := 1.0
var c := 1.0
var steers := false
var side := 0.0 ## -1 left of the centre of mass, +1 right
var track := false ## a track's road wheel
var unit := -1 ## (a track's road wheel) which of the machine's tracks
var patch := 0.0 ## (a track's) m of belt on the ground it presses through
var lat_scale := 1.0 ## how much of the sideways hold it has this step (a track slewing: less)
var flat := false ## its tyre's burst: it sits lower, grips half, drags and wobbles
var thrown := false ## (a track's road wheel) its belt's off: it drives nothing and slides
var tread_speed := 0.0 ## m/s its tread runs over the ground (+ forward)

var contact := false
var point := Vector3.ZERO
var normal := Vector3.UP
var load := 0.0 ## N
var mu := 0.0
var sink := 0.0
var slip := 0.0 ## m/s of wheelspin
var surface_label := ""
var steer_angle := 0.0
var _comp := 0.0
var _hub_drop := 0.0 ## how far below the travel's top the hub is
var _spin := 0.0
var _spin_speed := 0.0
var _stamp_d := 0.0
var _spinner_rest := Transform3D.IDENTITY
var spray: WheelSpray
var part := -1 ## (its part in the design: a joint may carry it)
var iron := false ## (a wooden wheel's iron tyre: it slides on hard ground and finds little in soft)
var rest0 := Vector3.ZERO ## (where it is, the way it rolls and its axle, with every joint at rest)
var roll0 := Vector3.FORWARD
var axle0 := Vector3.RIGHT


static func make(m: Machine, part: Node3D, p_id: String, xf: Transform3D, spinner_name := "Wheel", sprays := true) -> MachineWheel:
	var w := MachineWheel.new()
	w.machine = m
	w.node = part
	w.id = p_id
	var d := Parts.def(p_id)
	w.radius = d.radius
	w.width = d.width
	w.rated = d.rated
	w.travel = d.travel
	w.lugs = d.lugs
	w.iron = bool(d.get("iron", false))
	var g := 9.8
	w.k = w.rated * g / (w.travel * 1.2) # rated load: 1.2 x half travel compressed of the 2 x half travel
	w.c = 2.0 * DAMPING * sqrt(w.k * w.rated)
	w.track = str(d.kind) == "track"
	w.patch = float(d.get("patch", 0.0))
	w.spinner = part.find_child(spinner_name, true, false) as Node3D
	if w.spinner:
		w._spinner_rest = w.spinner.transform
		w.rest = xf * w.spinner.position
	else:
		var s := Vector3(Parts.size_of(p_id, 0)) * Parts.CELL
		w.rest = xf * Vector3(s.x * 0.5 - w.width * 0.5 - 0.02, 0.0, 0.0)
	w.axle = xf.basis * Vector3.RIGHT
	w.roll_dir = Vector3.UP.cross(w.axle).normalized()
	if w.roll_dir.dot(Vector3.FORWARD) < 0.0:
		w.roll_dir = -w.roll_dir
	w._hub_drop = w.travel
	w.rest0 = w.rest
	w.roll0 = w.roll_dir
	w.axle0 = w.axle
	if sprays:
		w.spray = WheelSpray.new()
		m.fx_root().add_child(w.spray)
	return w


## The spring: down its travel to the ground; the force up along the machine's up at the hub.
func suspend(dt: float) -> void:
	var t := machine.global_transform
	var up := t.basis.y.normalized()
	var top := t * (rest + Vector3.UP * travel)
	var r := radius * (0.8 if flat else 1.0)
	var reach := 2.0 * travel + r
	var q := PhysicsRayQueryParameters3D.create(top + up * 0.05, top - up * (reach + sink + 0.05), Machine.RAY_MASK)
	q.exclude = [machine.get_rid()]
	var hit := machine.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		contact = false
		if spray:
			spray.spray(top, Vector3.ZERO, 0.0, 0.0, "", 0.0)
		load = 0.0
		_comp = 0.0
		_hub_drop = move_toward(_hub_drop, 2.0 * travel, dt * 2.0)
		sink = move_toward(sink, 0.0, dt * 0.5)
		return
	var dist := top.distance_to(hit.position) + sink # (sunk in: the ground's that much lower)
	var drop := dist - r
	if drop > 2.0 * travel:
		contact = false
		load = 0.0
		_comp = 0.0
		_hub_drop = 2.0 * travel
		return
	contact = true
	point = (hit.position as Vector3) - up * sink
	normal = hit.normal
	var comp := 2.0 * travel - maxf(drop, 0.0)
	var rate := (comp - _comp) / dt
	_comp = comp
	_hub_drop = maxf(drop, 0.0)
	var f := k * comp + c * rate
	if drop < 0.0: # past the top: the bump stop
		f += k * BUMP * -drop + c * rate
	load = maxf(f, 0.0)
	machine.apply_force(up * load, (t * (rest + Vector3.UP * (travel - _hub_drop))) - machine.global_position)


const BUMP := 8.0


## The tyre on the ground: driving `push` N, braking 0..1, steered `angle` rad.
func tyre(dt: float, push: float, braking: float, angle: float) -> void:
	steer_angle = angle
	var t := machine.global_transform
	var dir := t.basis * (Basis(Vector3.UP, -angle) * roll_dir)
	var fwd := (dir - normal * dir.dot(normal)).normalized()
	var lat := normal.cross(fwd).normalized()
	var v := machine.velocity_at(point)
	var v_long := v.dot(fwd)
	var v_lat := v.dot(lat)
	var surf: Surface = _surface()
	surface_label = surf.label
	mu = surf.grip * _tyre_factor(surf) * (0.5 if flat else 1.0) * (0.4 if thrown else 1.0)
	var share := load / 9.8 # kg on this wheel
	# Soft ground: how deep, and what that costs.
	var drag := surf.rolling_resistance * load * (1.5 if track else 1.0) # (a track's pins and wheels: more to turn)
	if flat:
		drag += 0.12 * load # (a flat drags like a brake on)
		# and thumps round: the rim's flat spot coming down each turn
		machine.apply_force(normal * load * 0.18 * sin(_spin * 2.0), point - machine.global_position)
	if surf.is_soft():
		var pressure := share / maxf(width * (patch if track else radius), 0.01) / REF_PRESSURE
		var settle := surf.static_sink * clampf(pressure, 0.0, 3.0)
		if absf(v_long) > 0.6 and slip < 0.5:
			sink = move_toward(sink, settle, dt * 0.25) # rolling on, it climbs out of its hole
		else:
			sink = maxf(sink, minf(settle, sink + dt * 0.4))
		sink += (surf.sink_rate * pressure + surf.dig_rate * slip * pressure) * dt
		sink = clampf(sink, 0.0, surf.max_depth)
		# down in it, it pushes the ground ahead of it: a wheel's rim against its hole, a track's long
		# belt climbing its own (as gentle as a wheel twice its length on the ground)
		drag += surf.sink_drag * (sink / (maxf(radius, patch * 2.0) if track else radius)) * load
		mu *= 1.0 - 0.35 * (sink / maxf(surf.max_depth, 0.01)) * (1.0 - lugs)
		_rut(fwd, dt, v_long)
	else:
		sink = move_toward(sink, 0.0, dt * 0.6)
	var cap := mu * load
	# Along: the engine, the brake, rolling (and sinking) resistance.
	var f_long := push
	if braking > 0.0:
		f_long -= signf(v_long) * minf(absf(v_long) * share / dt, cap) * braking
	if absf(v_long) > 0.05:
		f_long -= signf(v_long) * drag
	else:
		f_long -= v_long * share / dt * 0.5 # (holds it still)
	# Across: as much as it takes to stop sliding sideways this step, if the ground gives it.
	var f_lat := -v_lat * share / dt * 0.5 * lat_scale
	var f := Vector2(f_long, f_lat)
	slip = 0.0
	if f.length() > cap:
		var over := f.length() / maxf(cap, 0.001)
		slip = clampf((absf(push) - cap) / maxf(share * 4.0, 1.0), 0.0, 8.0) if absf(push) > cap else 0.0
		f /= over
	machine.apply_force(fwd * f.x + lat * f.y, point - machine.global_position)
	_spin_speed = (v_long + signf(push) * slip) / radius
	var tread := v_long + signf(push) * slip # (which way the tread runs over the ground)
	tread_speed = tread
	if spray:
		spray.spray(point + Vector3.UP * 0.05 - fwd * signf(tread) * radius * 0.4, -fwd * signf(tread), v_long, slip,
			surface_label, machine.wet)


func _surface() -> Surface:
	var tr := machine.terrain
	if tr and tr.has_method("surface_at"):
		var s: Variant = tr.call("surface_at", point)
		if s is Surface:
			return s
	return Surface.preset("dirt")


## The tyre's own grip on this ground: lugs in the soft, rubber on the hard.
func _tyre_factor(s: Surface) -> float:
	var soft := s.is_soft() or s.label in ["wet", "grass", "snowpack", "snow"]
	if track:
		return 1.4 if soft else (0.7 if s.label == "ice" else 0.95) # (grousers; steel on ice slides)
	if iron:
		return 0.6 if soft else 0.75
	if soft:
		return lerpf(0.85, 1.3, lugs)
	return lerpf(1.05, 0.92, lugs)


## Its rut in the soft ground, every STAMP_STEP rolled.
func _rut(fwd: Vector3, dt: float, v_long: float) -> void:
	_stamp_d += absf(v_long) * dt + slip * dt
	if _stamp_d < Machine.STAMP_STEP or sink < 0.01:
		return
	_stamp_d = 0.0
	var tr := machine.terrain
	if tr == null or not tr.has_method("patch_at"):
		return
	var patch: Variant = tr.call("patch_at", point)
	if patch is SoftPatch:
		(patch as SoftPatch).stamp(point, fwd, width * 0.5, radius * 0.35, sink)


## The wheel's node: down its travel, steered, spinning (rolling forward turns it about up x its
## rolling direction, the top going forward), in the part's own space (it may be turned round).
func animate(dt: float) -> void:
	if spinner == null:
		return
	_spin = fmod(_spin + _spin_speed * dt, TAU)
	var hub := _spinner_rest.origin + Vector3.UP * (travel - _hub_drop)
	var spin_axis := (node.transform.basis.inverse() * Vector3.UP.cross(roll_dir)).normalized()
	spinner.transform = Transform3D(Basis(Vector3.UP, -steer_angle) * Basis(spin_axis, _spin) * _spinner_rest.basis, hub)
