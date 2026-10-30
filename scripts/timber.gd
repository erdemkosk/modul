class_name Timber
extends RefCounted
## The valley's wood: trees felled with a saw (MachineTool), the logs and stumps lying in the forest
## cut up, all of it left on the ground as billets (bodies of their own, group GROUP, solid to a
## machine and its wheels) for a crane to lift onto a bed and carry home (Workshop takes them in). A felled tree goes over away from the saw, hinged at the cut (what it comes down on
## it strikes), its stump left standing, and where it lies its trunk is billets (as many as its height
## gives, as thick as its trunk; the crown's left); a log on the ground or a stump is cut up where it lies. Billets lie LIFE s if no one takes
## them (not while one's by a machine: on its bed, say). What's felled stays felled (WorldProps.cut_tree:
## RutStore keeps it).
## A tree's cut where the blade meets it: at that height (KERF_H, from the ground up), the kerf opening
## from the side the blade came in, sawdust heaping at its foot; through, it shivers, cracks and goes
## over from there, away from the cut, and its stump stands that tall.

const GROUP := "timber"
const BILLET := 1.0 ## m long
const DENSITY := 700.0 ## kg/m3, green wood
const LIFE := 900.0 ## s
const MAX := 60 ## billets lying at once (the oldest go first)
const KERF_H := Vector2(0.2, 1.6) ## m over the ground a trunk's cut, at most and least
const SHIVER := 0.55 ## s it stands, cut through, before it goes

static var _bark: StandardMaterial3D
static var _end: StandardMaterial3D
static var _lying: Array[RigidBody3D] = []


static func props_of(n: Node) -> WorldProps:
	return n.get_tree().get_first_node_in_group("anchor_index") as WorldProps


## Prop `i` cut through by `by`'s saw: a tree goes over `away`, a log or a stump is billets.
static func cut(by: Machine, props: WorldProps, i: int, away: Vector3, cut_h := 0.3) -> void:
	var info := props.prop_info(i)
	props.cut_tree(i)
	var tree := by.get_tree()
	if Combat.current:
		Combat.current.sound("res://assets/audio/wood/knock_0%d.wav" % randi_range(1, 4), info.origin + Vector3.UP, 2.0, 0.7) # (the last of the wood parting)
	match str(info.kind):
		"tree":
			_fall(tree, props, i, info, away, cut_h)
		"log":
			var o: Vector3 = info.origin
			var ax: Vector3 = info.axis
			_lay_along(tree, o - ax * float(info.length) * 0.5, ax, float(info.length), float(info.radius))
		_:
			_lay_along(tree, info.origin + Vector3.UP * 0.25, Vector3.RIGHT, 1.0, float(info.radius))


## The tree going over: its model hinged at the cut, tipping `away` as a felled tree does (slow at
## first, faster and faster: a rod falling about its foot), till its top meets the ground; what's
## under it is struck. A moment after, its trunk lies as billets and its stump's left.
static func _fall(tree: SceneTree, props: WorldProps, i: int, info: Dictionary, away: Vector3, cut_h := 0.3) -> void:
	var h := float(info.height)
	var r := float(info.radius)
	var ground: Vector3 = info.origin
	var base := ground + Vector3.UP * cut_h # (the hinge: the cut; what was below it is the stump)
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
	_stump(root, ground, r, cut_h)
	var st := {"a": 0.0, "w": 0.12, "down": false, "left": 0.7, "shiver": SHIVER} # (it stands a moment, then the cut opens)
	var terrain := props.terrain
	st.cb = func() -> void:
		if not is_instance_valid(t):
			tree.physics_frame.disconnect(st.cb)
			return
		var dt := 1.0 / Engine.physics_ticks_per_second
		if float(st.shiver) > 0.0: # (cut through, it shivers on the last fibres, leaning a hair)
			st.shiver = float(st.shiver) - dt
			var k := 1.0 - float(st.shiver) / SHIVER
			var wob := sin(float(st.shiver) * 55.0) * 0.006 * (1.0 - k) + 0.035 * k * k
			t.global_transform = Transform3D(Basis(axis, wob) * start, base)
			if float(st.shiver) <= 0.0:
				st.a = 0.04
				if Combat.current:
					Combat.current._burst(base, "chips", 0.8, away + Vector3.UP * 0.3)
					Combat.current._burst(base, "sawdust", 1.0, -away + Vector3.UP * 0.2)
			return
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
		Combat.current.sound("res://assets/audio/wood/tree_fall.wav", mid, 8.0, clampf(1.15 - h * 0.015, 0.85, 1.05)) # (the crown's crash, the trunk's thud: deeper the taller)
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


## What's left standing where it was cut: a stump `cut_h` tall, its cut face pale, a splinter of the
## last fibres torn up at one edge.
static func _stump(root: Node, at: Vector3, r: float, cut_h := 0.3) -> void:
	var s := MeshInstance3D.new()
	s.name = "Stump"
	var hh := cut_h + 0.2
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 1.25
	cm.height = hh
	cm.radial_segments = 14
	cm.material = bark()
	s.mesh = cm
	var sp := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(r * 0.7, 0.12, 0.05)
	sm.material = _end_mat()
	sp.mesh = sm
	sp.position = Vector3(0.0, hh * 0.5 + 0.05, -r * 0.45)
	sp.rotation = Vector3(0.25, 0.0, 0.0)
	s.add_child(sp)
	var top := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = r * 0.95
	tm.bottom_radius = r * 0.95
	tm.height = 0.01
	tm.radial_segments = 14
	tm.material = _end_mat()
	top.mesh = tm
	top.position = Vector3.UP * hh * 0.5
	s.add_child(top)
	root.add_child(s)
	s.global_position = at + Vector3.UP * (hh * 0.5 - 0.2)


## The cut opening in a trunk (its ground at `base`, `r` thick) where the blade at `blade` went in: a
## dark slot at that height from the blade's side, and a heap of sawdust at the foot. {node, heap, h, dir, r}.
static func kerf(tree: SceneTree, base: Vector3, blade: Vector3, r: float) -> Dictionary:
	var root := tree.current_scene if tree.current_scene else tree.root
	var h := clampf(blade.y - base.y, KERF_H.x, KERF_H.y)
	var from := Vector3(blade.x - base.x, 0.0, blade.z - base.z)
	var dir := (-from).normalized() if from.length() > 0.05 else Vector3.FORWARD # (into the trunk)
	var n := Node3D.new()
	n.name = "Kerf"
	root.add_child(n)
	n.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), base + Vector3.UP * h)
	var slot := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(r * 2.05, 0.04, 1.0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.05, 0.035)
	dark.roughness = 1.0
	bm.material = dark
	slot.mesh = bm
	slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(slot)
	var heap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 10
	var dust := StandardMaterial3D.new()
	dust.albedo_color = Color(0.72, 0.58, 0.38)
	dust.roughness = 1.0
	cm.material = dust
	heap.mesh = cm
	root.add_child(heap)
	var foot := base - dir * (r + 0.25)
	var props := tree.get_first_node_in_group("anchor_index") as WorldProps
	if props and props.terrain:
		foot.y = props.terrain.height_at(foot.x, foot.z)
	heap.global_position = foot
	var k := {"node": n, "slot": slot, "heap": heap, "h": h, "dir": dir, "r": r}
	kerf_grow(k, 0.0)
	return k


## The kerf `frac` (0..1) of the way through: the slot that deep from its side, the heap that big.
static func kerf_grow(k: Dictionary, frac: float) -> void:
	var slot := k.slot as MeshInstance3D
	if not is_instance_valid(slot):
		return
	var r := float(k.r)
	var depth := maxf(frac, 0.04) * r * 2.0
	slot.scale = Vector3(1.0, 1.0 + frac * 0.6, depth) # (it opens a little as the trunk settles on it)
	slot.position = Vector3(0.0, 0.0, r - depth * 0.5 + 0.01) # (+z is the blade's side; it goes in along -z)
	var heap := k.heap as MeshInstance3D
	if is_instance_valid(heap):
		var s := 0.08 + 0.3 * frac
		heap.scale = Vector3(s, s * 0.35, s)


static func kerf_free(k: Dictionary) -> void:
	var n := k.node as Node
	if is_instance_valid(n):
		n.queue_free()
	# (the heap stays: the sawdust lies where it fell)


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
	b.collision_layer = 1 | 4 # (ground to wheels: driven over, it's a bump; on a bed, it rides)
	b.collision_mask = 1 | 2 | 4
	b.mass = PI * radius * radius * BILLET * DENSITY
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	b.physics_material_override = pm
	b.angular_damp = 1.5 # (bark and stubs: it rolls a little way, not off down the hill)
	b.contact_monitor = true # (the knock of it landing on something)
	b.max_contacts_reported = 1
	b.body_entered.connect(_knocked.bind(b))
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
	_expire(tree, b, LIFE)
	var k := 0
	while _lying.size() > MAX and k < _lying.size():
		var old: RigidBody3D = _lying[k]
		if is_instance_valid(old) and not old.has_meta("taken") and _by_machine(old):
			k += 1 # (one on a bed, or being lifted, stays)
			continue
		_lying.remove_at(k)
		if is_instance_valid(old) and not old.has_meta("taken"):
			old.queue_free()
	return b


static var _knock_ms := 0


## A billet `b` coming down on something: a wooden knock, a heavier thud the faster it came.
static func _knocked(_on: Node, b: RigidBody3D) -> void:
	if Combat.current == null or not is_instance_valid(b) or b.has_meta("taken"):
		return
	var t := Time.get_ticks_msec()
	if t - _knock_ms < 70 or t - int(b.get_meta("knock_ms", -1000)) < 300:
		return
	_knock_ms = t
	b.set_meta("knock_ms", t)
	var v := b.linear_velocity.length() + b.angular_velocity.length() * 0.2
	var path := "res://assets/audio/wood/log_drop_0%d.wav" % randi_range(1, 3) if v > 2.5 \
		else "res://assets/audio/wood/knock_0%d.wav" % randi_range(1, 4)
	Combat.current.sound(path, b.global_position, clampf(-10.0 + v * 2.5, -10.0, 3.0), randf_range(0.75, 0.95) * clampf(1.25 - b.mass / 200.0, 0.8, 1.15))


## `b` gone in `t` s, unless it's by a machine then (it's asked again later).
static func _expire(tree: SceneTree, b: RigidBody3D, t: float) -> void:
	tree.create_timer(t, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(b) or b.has_meta("taken"):
			return
		if _by_machine(b):
			_expire(tree, b, 60.0)
		else:
			_lying.erase(b)
			b.queue_free())


static func _by_machine(b: Node3D) -> bool:
	for n: Node in b.get_tree().get_nodes_in_group("machines"):
		if (n as Node3D).global_position.distance_squared_to(b.global_position) < 36.0:
			return true
	return false


## What a billet's worth in the store (its weight: a thin one one, a thick one up to three).
static func worth(b: RigidBody3D) -> int:
	return clampi(roundi(b.mass / 90.0), 1, 3)


## Something brought home (a billet, a wreck's part) taken in at `to`: lifted over in an arc and gone.
static func take(b: RigidBody3D, to: Vector3) -> void:
	b.set_meta("taken", true)
	b.remove_from_group(GROUP)
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	_lying.erase(b)
	var tw := b.create_tween()
	var from := b.global_position
	var top := (from + to) * 0.5 + Vector3.UP * 2.0
	tw.tween_method(func(f: float) -> void:
		b.global_position = from.lerp(top, f).lerp(top.lerp(to, f), f), 0.0, 1.0, 0.6)
	tw.tween_callback(b.queue_free)
	if Combat.current:
		Combat.current.sound(("res://assets/audio/wood/knock_0%d.wav" % randi_range(1, 4)) if str(b.name).begins_with("Billet") \
			else ("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3)), from, -4.0, randf_range(0.8, 0.95))


## Sawdust flying where the blade bites (thrown `dir`).
static func sawdust(at: Vector3, dir := Vector3.UP) -> void:
	if Combat.current:
		Combat.current._burst(at, "sawdust", 0.8, dir)


static func bark() -> StandardMaterial3D:
	if _bark == null:
		_bark = StandardMaterial3D.new()
		_bark.albedo_color = WorldProps.BARK # (the standing trees' own)
		_bark.roughness = 0.95
	return _bark


static func _end_mat() -> StandardMaterial3D:
	if _end == null:
		_end = StandardMaterial3D.new()
		_end.albedo_color = WorldProps.CUT_WOOD
		_end.roughness = 0.8
	return _end


## How many billets lie about.
static func lying() -> int:
	var n := 0
	for b in _lying:
		if is_instance_valid(b) and not b.has_meta("taken"):
			n += 1
	return n
