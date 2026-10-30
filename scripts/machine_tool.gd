class_name MachineTool
extends RefCounted
## A working tool on a Machine: what the valley's wood is got with.
##
##   saw        (the part "saw": R) a flat circular blade out in front, low, as a feller's head has.
##              R starts it (it runs up over a second, drawing SAW_KW off the battery) and stops it.
##              Spinning, driven into a tree it cuts through the trunk (the thicker the longer:
##              CUT_BASE + CUT_PER_M of trunk radius), and the tree goes over away from you and lies
##              as billets (Timber); a log lying in the forest or a stump it cuts into billets too.
##              What else it meets it cuts: a crate or a log in pieces quickly, stone and steel
##              slowly and in sparks, and another machine's parts.
##   collector  (the part "collector") an open steel bin with a small grab: billets lying within
##              GATHER of it are taken in, up to its `holds`; it's emptied into the workshop's store
##              beside the workshop truck (Workshop). What it holds is kept with what you hold
##              (Inventory.bin) and shows in it as a pile.
##   rack       (the part "wood_rack") a wooden cradle: the collector's bin holds its `holds` more,
##              piled in it (it takes nothing in itself).
## A bin's pile shows the billets held past those its machine's earlier bins show.

const BLADE := Vector3(0.0, -0.4, -0.95) ## the blade's middle, in the part's space (low: under the bed, as a feller's is)
const BLADE_R := 0.55 ## m
const SAW_KW := 3.0
const CUT_BASE := 0.6 ## s to cut through the thinnest trunk
const CUT_PER_M := 7.0 ## s more for each m of trunk radius
const GATHER := 4.0 ## m from the bin a billet's taken in
const BIN_AT := Vector3(0.0, 0.1, 0.0)

var machine: Machine
var node: Node3D
var index := -1
var kind := "saw"
var key := 0
var condition := 1.0
var on := false
var spin := 0.0 ## 0..1 of the blade's speed
var cutting := -1 ## (the prop the blade's in, or -1)
var _progress := {} ## prop index -> s cut so far
var _blade: Node3D
var _hum: AudioStreamPlayer3D
var _dust_t := 0.0
var _gather_t := 0.0
var _full_said := false
var _pile: Array[MeshInstance3D] = []


static func make(m: Machine, part: Node3D, i: int, id: String) -> MachineTool:
	var t := MachineTool.new()
	t.machine = m
	t.node = part
	t.index = i
	t.kind = str(Parts.def(id).kind)
	t._blade = part.find_child("Blade", true, false) as Node3D
	var p: Dictionary = m.design[i]
	t.on = bool(p.get("tool_on", false))
	if t.kind in ["collector", "rack"]:
		t._make_pile(int(Parts.def(id).holds))
	return t


func holds() -> int:
	return machine.bin_holds()


## Of what's to cut, how far through (0..1; 0 when it's not cutting).
func cut_frac() -> float:
	if cutting < 0:
		return 0.0
	var props := Timber.props_of(machine)
	if props == null:
		return 0.0
	var info := props.prop_info(cutting)
	var need := CUT_BASE + CUT_PER_M * float(info.radius) * (0.7 if info.kind != "tree" else 1.0)
	return clampf(float(_progress.get(cutting, 0.0)) / need, 0.0, 1.0)


## R: the saw started or stopped. Says what happened.
func toggle() -> String:
	if kind != "saw":
		return ""
	on = not on
	machine.design[index].tool_on = on
	if on and not machine.powered:
		return "Akü bitti: testere dönmüyor"
	return "Testere çalışıyor" if on else "Testere durdu"


func draw_kw() -> float:
	return SAW_KW * spin if kind == "saw" and on else 0.0


func update(dt: float) -> void:
	if not is_instance_valid(node):
		return
	if kind == "rack":
		return
	if kind == "collector":
		_gather_t -= dt
		if _gather_t <= 0.0:
			_gather_t = 0.2
			_gather()
		return
	var run := on and machine.powered
	spin = move_toward(spin, 1.0 if run else 0.0, dt * (1.0 if run else 0.5))
	if _blade:
		_blade.rotate_object_local(Vector3.UP, spin * 45.0 * dt)
	_sound()
	cutting = -1
	if spin < 0.5:
		return
	var c := node.global_transform * BLADE
	var bite := spin * maxf(condition, 0.3) # (a worn one cuts slower)
	_dust_t -= dt
	var props := Timber.props_of(machine)
	if props:
		var i := props.prop_near(Vector2(c.x, c.z), BLADE_R, ["tree", "log", "stump"])
		if i >= 0:
			var info := props.prop_info(i)
			var base: Vector3 = info.origin
			var low := base.y - (1.0 if info.kind == "log" else 0.6)
			var high := base.y + (float(info.radius) + 0.6 if info.kind == "log" else (0.5 if info.kind == "stump" else 3.0))
			if c.y > low and c.y < high:
				cutting = i
				var need := CUT_BASE + CUT_PER_M * float(info.radius) * (0.7 if info.kind != "tree" else 1.0)
				_progress[i] = float(_progress.get(i, 0.0)) + dt * bite
				# the wood holds the machine back as it bites
				machine.apply_central_force(-machine.linear_velocity * machine.total_mass * 1.5)
				if _dust_t <= 0.0:
					_dust_t = 0.12
					Timber.sawdust(c)
				if float(_progress[i]) >= need:
					_progress.erase(i)
					var away := Vector3(base.x - machine.global_position.x, 0.0, base.z - machine.global_position.z)
					Timber.cut(machine, props, i, away.normalized() if away.length() > 0.1 else -machine.global_basis.z)
				return
	# crates, logs and the like lying about; another machine
	for n: Node in machine.get_tree().get_nodes_in_group(Breakable.GROUP):
		var b := n as Breakable
		if b.broken:
			continue
		var l := b.global_transform.affine_inverse() * c
		var h := b.size * 0.5
		var near := Vector3(clampf(l.x, -h.x, h.x), clampf(l.y, 0.0, b.size.y), clampf(l.z, -h.z, h.z))
		if near.distance_to(l) < BLADE_R * 0.6:
			var soft := b.kind in ["log", "crate"]
			b.hit((220.0 if soft else 35.0) * bite * dt, c, -machine.global_basis.z)
			if _dust_t <= 0.0:
				_dust_t = 0.12
				if soft:
					Timber.sawdust(c)
				elif Combat.current:
					Combat.current._burst(c, "metal", 0.5, Vector3.UP)
			return
	for n: Node in machine.get_tree().get_nodes_in_group("machines"):
		var m := n as Machine
		if m == machine or not m.alive or m.global_position.distance_squared_to(c) > 64.0:
			continue
		var j := m._part_near(c)
		if j >= 0 and (m.global_transform * m.part_xform(j).origin).distance_to(c) < BLADE_R + 0.35:
			m.damage_part(j, 70.0 * (2.5 if Parts.burns(m.design[j].id) else 1.0) * bite * dt, c, machine) # (wood's cut through)
			if _dust_t <= 0.0:
				_dust_t = 0.1
				if Combat.current:
					Combat.current._burst(c, "metal", 0.6, Vector3.UP)
			return


func _sound() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _hum == null:
		_hum = AudioStreamPlayer3D.new()
		_hum.stream = load("res://assets/audio/weapons/minigun_motor_loop.wav")
		_hum.unit_size = 6.0
		node.add_child(_hum)
	if spin < 0.02:
		if _hum.playing:
			_hum.stop()
		return
	if not _hum.playing:
		_hum.play()
	_hum.pitch_scale = 0.5 + spin * (0.9 if cutting < 0 else 0.6) # (it labours in the wood)
	_hum.volume_db = linear_to_db(clampf(spin, 0.05, 1.0)) + (4.0 if cutting >= 0 else 0.0)


## The collector: billets within reach taken in.
func _gather() -> void:
	var at := node.global_transform * BIN_AT
	for n: Node in machine.get_tree().get_nodes_in_group(Timber.GROUP):
		var b := n as RigidBody3D
		if b.has_meta("taken") or b.global_position.distance_to(at) > GATHER:
			continue
		if Inventory.bin >= holds():
			if not _full_said:
				_full_said = true
				machine.system_hit.emit("Kasa dolu (%d kütük): atölyeye götür" % holds(), at)
			break
		Timber.take(b, node, at)
		Inventory.bin += 1
		Inventory.save_all()
	if Inventory.bin < holds():
		_full_said = false
	for t in machine.tools:
		t.show_pile()


## The pile in the bin: one billet showing for each held, past what the bins before it show.
func show_pile() -> void:
	var before := 0
	for t in machine.tools:
		if t == self:
			break
		before += t._pile.size()
	for k in _pile.size():
		_pile[k].visible = k < Inventory.bin - before


func _make_pile(n: int) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.1
	cm.height = 0.8
	cm.radial_segments = 10
	cm.material = Timber.bark()
	var per := 4 if kind == "collector" else 3
	for k in n:
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		var row := k % per
		var layer := k / per
		mi.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, randf_range(-0.1, 0.1)),
			Vector3(0.0, -0.3 + layer * 0.17, -0.3 + row * 0.2 + layer * 0.1) if kind == "collector" \
				else Vector3(0.0, -0.32 + layer * 0.19, -0.2 + row * 0.2 + layer * 0.1))
		mi.visible = false
		node.add_child(mi)
		_pile.append(mi)


func free_fx() -> void:
	if is_instance_valid(_hum):
		_hum.queue_free()
