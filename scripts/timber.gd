class_name Timber
extends RefCounted
## The valley's wood: trees felled with a saw (MachineTool), the logs and stumps lying in the forest
## cut up, all of it left on the ground as billets (bodies of their own, group GROUP) for a collector
## to take in. A felled tree goes over away from the saw, hinged at the cut (what it comes down on
## it strikes), its stump left standing, and where it lies its trunk is billets (as many as its height
## gives, as thick as its trunk; the crown's left); a log on the ground or a stump is cut up where it lies. Billets lie LIFE s if no one takes
## them. What's felled stays felled (WorldProps.cut_tree: RutStore keeps it).

const GROUP := "timber"
const BILLET := 1.0 ## m long
const DENSITY := 700.0 ## kg/m3, green wood
const LIFE := 900.0 ## s
const MAX := 60 ## billets lying at once (the oldest go first)

static var _bark: StandardMaterial3D
static var _end: StandardMaterial3D
static var _lying: Array[RigidBody3D] = []


static func props_of(n: Node) -> WorldProps:
	return n.get_tree().get_first_node_in_group("anchor_index") as WorldProps


## Prop `i` cut through by `by`'s saw: a tree goes over `away`, a log or a stump is billets.
static func cut(by: Machine, props: WorldProps, i: int, away: Vector3) -> void:
	var info := props.prop_info(i)
	props.cut_tree(i)
	var tree := by.get_tree()
	if Combat.current:
		Combat.current.sound("res://assets/audio/impact/dirt_0%d.wav" % randi_range(1, 3), info.origin + Vector3.UP, 4.0, 0.6)
	match str(info.kind):
		"tree":
			_fall(tree, props, i, info, away)
		"log":
			var o: Vector3 = info.origin
			var ax: Vector3 = info.axis
			_lay_along(tree, o - ax * float(info.length) * 0.5, ax, float(info.length), float(info.radius))
		_:
			_lay_along(tree, info.origin + Vector3.UP * 0.25, Vector3.RIGHT, 1.0, float(info.radius))


## The tree going over: its model hinged at the cut, tipping `away` as a felled tree does (slow at
## first, faster and faster: a rod falling about its foot), till its top meets the ground; what's
## under it is struck. A moment after, its trunk lies as billets and its stump's left.
static func _fall(tree: SceneTree, props: WorldProps, i: int, info: Dictionary, away: Vector3) -> void:
	var h := float(info.height)
	var r := float(info.radius)
	var base: Vector3 = info.origin
	var root := tree.current_scene if tree.current_scene else tree.root
	var t := Node3D.new()
	t.name = "Felled"
	var mi := MeshInstance3D.new()
	mi.mesh = props.felled_mesh(i)
	t.add_child(mi)
	root.add_child(t)
	var start: Basis = info.basis
	var axis := away.cross(Vector3.UP).normalized() * -1.0 # (about this, up turns toward `away`)
	t.global_transform = Transform3D(start, base)
	_stump(root, base, r)
	var st := {"a": 0.1, "w": 0.2, "down": false, "left": 0.7} # (the cut opening, the saw's shove)
	var terrain := props.terrain
	st.cb = func() -> void:
		if not is_instance_valid(t):
			tree.physics_frame.disconnect(st.cb)
			return
		var dt := 1.0 / Engine.physics_ticks_per_second
		if not bool(st.down):
			st.w = float(st.w) + 2.5 * 9.8 / maxf(h, 2.0) * sin(float(st.a)) * dt # (a rod going over about its foot, a crown that pulls it on)
			st.a = float(st.a) + float(st.w) * dt
			var rot := Basis(axis, float(st.a))
			t.global_transform = Transform3D(rot * start, base)
			var up := rot * Vector3.UP
			# where it meets the ground: its top (two thirds up: the crown gives) at the ground there
			var top := base + up * h * 0.66
			if top.y <= terrain.height_at(top.x, top.z) + r or float(st.a) > PI * 0.55:
				st.down = true
				_landed(tree, base, up, h, r)
			return
		st.left = float(st.left) - dt
		if float(st.left) <= 0.0:
			tree.physics_frame.disconnect(st.cb)
			var up := t.global_basis.orthonormalized() * Vector3.UP
			t.queue_free()
			_lay_along(tree, base + up * 0.45, up, minf(h * 0.55, 9.0), r) # (the bole, not the crown)
	tree.physics_frame.connect(st.cb)


## It's down: the thump and the dust, and what it fell on struck.
static func _landed(tree: SceneTree, base: Vector3, up: Vector3, h: float, r: float) -> void:
	var mid := base + up * h * 0.45
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/heavy_01.wav", mid, 6.0, 0.55)
		Combat.current._burst(mid, "smoke", 0.9)
		Combat.current._burst(base + up * h * 0.75, "dirt", 1.0, Vector3.UP)
	for n: Node in tree.get_nodes_in_group("machines"):
		var m := n as Machine
		if not m.alive:
			continue
		var c := m.com_global()
		var k := clampf((c - base).dot(up) / h, 0.0, 1.0)
		var on := base + up * h * k
		if c.distance_to(on) < 2.0 and k > 0.15:
			m.blast(on + Vector3.UP * 0.5, 2.5, 140.0 * clampf(r / 0.3, 0.5, 2.0) * (1.0 - k * 0.6), m.total_mass * 2.0, null, "ağaç")


## What's left standing where it was cut: a stump, its cut face pale.
static func _stump(root: Node, at: Vector3, r: float) -> void:
	var s := MeshInstance3D.new()
	s.name = "Stump"
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 1.25
	cm.height = 0.5
	cm.radial_segments = 14
	cm.material = bark()
	s.mesh = cm
	var top := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = r * 0.95
	tm.bottom_radius = r * 0.95
	tm.height = 0.01
	tm.radial_segments = 14
	tm.material = _end_mat()
	top.mesh = tm
	top.position = Vector3.UP * 0.25
	s.add_child(top)
	root.add_child(s)
	s.global_position = at + Vector3.UP * 0.15


## Billets along `ax` from `from`, `length` m of it, `radius` thick.
static func _lay_along(tree: SceneTree, from: Vector3, ax: Vector3, length: float, radius: float) -> void:
	var n := clampi(floori(length / BILLET), 1, 9)
	var flat := Vector3(ax.x, 0.0, ax.z)
	var lie := flat.normalized() if flat.length() > 0.1 else Vector3.RIGHT
	for k in n:
		var at := from + ax * (k + 0.5) * (length / n)
		var props := tree.get_first_node_in_group("anchor_index") as WorldProps
		if props and props.terrain:
			at.y = maxf(at.y, props.terrain.height_at(at.x, at.z) + radius + 0.05)
		billet(tree, at, lie, clampf(radius, 0.1, 0.35))


## One billet lying at `at` along `lie`.
static func billet(tree: SceneTree, at: Vector3, lie: Vector3, radius: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = "Billet"
	b.collision_layer = 4
	b.collision_mask = 1 | 2 | 4
	b.mass = PI * radius * radius * BILLET * DENSITY
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	b.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = BILLET * 0.96
	cs.shape = cyl
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * randf_range(0.9, 1.0)
	cm.bottom_radius = radius
	cm.height = BILLET * 0.96
	cm.radial_segments = 12
	cm.material = bark()
	mi.mesh = cm
	b.add_child(mi)
	for e in [-1.0, 1.0]: # (the sawn ends: pale)
		var end := MeshInstance3D.new()
		var em := CylinderMesh.new()
		em.top_radius = radius * 0.94
		em.bottom_radius = radius * 0.94
		em.height = 0.01
		em.radial_segments = 12
		em.material = _end_mat()
		end.mesh = em
		end.position = Vector3.UP * e * BILLET * 0.481
		b.add_child(end)
	b.add_to_group(GROUP)
	b.set_meta("age", 0.0)
	var root := tree.current_scene if tree.current_scene else tree.root
	root.add_child(b)
	var y := lie.normalized()
	var x := Vector3.UP.cross(y)
	if x.length() < 0.1:
		x = Vector3.RIGHT
	x = x.normalized()
	b.global_transform = Transform3D(Basis(x, y, x.cross(y)), at) # (the cylinder's axis: along `lie`)
	b.angular_velocity = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	_lying.append(b)
	var gone := func() -> void:
		if is_instance_valid(b) and not b.has_meta("taken"):
			b.queue_free()
	tree.create_timer(LIFE, false, true).timeout.connect(gone)
	while _lying.size() > MAX:
		var old: RigidBody3D = _lying.pop_front()
		if is_instance_valid(old) and not old.has_meta("taken"):
			old.queue_free()
	return b


## A billet taken into a bin (`into` at `at`): lifted over and dropped in, then gone (the bin shows it).
static func take(b: RigidBody3D, into: Node3D, at: Vector3) -> void:
	b.set_meta("taken", true)
	b.remove_from_group(GROUP)
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	_lying.erase(b)
	var tw := b.create_tween()
	var from := b.global_position
	var top := (from + at) * 0.5 + Vector3.UP * 1.6
	tw.tween_method(func(f: float) -> void:
		if is_instance_valid(into):
			var to := into.global_transform * MachineTool.BIN_AT
			b.global_position = from.lerp(top, f).lerp(top.lerp(to, f), f), 0.0, 1.0, 0.45)
	tw.tween_callback(b.queue_free)
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), at, -4.0, 0.7)


## Chips flying where the blade bites.
static func sawdust(at: Vector3) -> void:
	if Combat.current:
		Combat.current._burst(at, "sawdust", 0.7, Vector3.UP)


static func bark() -> StandardMaterial3D:
	if _bark == null:
		_bark = StandardMaterial3D.new()
		_bark.albedo_color = Color(0.2, 0.14, 0.09)
		_bark.roughness = 0.95
	return _bark


static func _end_mat() -> StandardMaterial3D:
	if _end == null:
		_end = StandardMaterial3D.new()
		_end.albedo_color = Color(0.62, 0.47, 0.3)
		_end.roughness = 0.8
	return _end


## How many billets lie about.
static func lying() -> int:
	var n := 0
	for b in _lying:
		if is_instance_valid(b) and not b.has_meta("taken"):
			n += 1
	return n
