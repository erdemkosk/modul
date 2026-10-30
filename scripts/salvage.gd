class_name Salvage
extends Node
## Wrecks you can take from (the valley): a part that comes off the other side's
## machine whole lies where it falls with a light over it; drive up to it (within REACH) and it's
## yours (Inventory). Parts shot to nothing leave nothing to take. They lie LIFE s, then they're
## gone (the oldest first past MAX).
##
## Nothing taken off a wreck is new: each comes with what's left of it (WORN: rusted, bent, burnt),
## less than a cache's or a job's pay; what it has is said when it's taken (Inventory keeps it).

const REACH := 4.5 ## m
const LIFE := 240.0 ## s
const MAX := 40
const WORN := Vector2(0.3, 0.85) ## what a wreck's part has left: between these

static var current: Salvage

var game: Node
var _items: Array[RigidBody3D] = []


func _ready() -> void:
	current = self
	name = "Salvage"


func _exit_tree() -> void:
	if current == self:
		current = null


## A piece of debris (`b`, part `id`) to take: lit, kept out of the debris pool's culling; `cond` what
## it has left (a wreck's own if not said).
func mark(b: RigidBody3D, id: String, cond := -1.0) -> void:
	b.set_meta("salvage", id)
	b.set_meta("cond", cond if cond >= 0.0 else randf_range(WORN.x, WORN.y))
	b.set_meta("age", 0.0)
	b.add_to_group("salvage")
	if Combat.current:
		Combat.current._debris.erase(b)
	if DisplayServer.get_name() != "headless":
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.18
		cm.height = 3.5
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.6, 0.15, 0.35)
		cm.material = m
		beam.mesh = cm
		beam.top_level = true
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(beam)
		b.set_meta("beam", beam)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.2)
		l.light_energy = 1.2
		l.omni_range = 3.5
		beam.add_child(l)
	_items.append(b)
	while _items.size() > MAX:
		var old: RigidBody3D = _items.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## A plan (Parts.PLANS key) left at `at` to be taken: a leather tube of drawings, lit as a part is.
## Taken, it's known (Inventory.learn): its metal parts can be made from then on.
func drop_plan(plan: String, at: Vector3) -> void:
	var c := Combat.current
	if c == null or plan == "":
		return
	var b := RigidBody3D.new()
	b.collision_layer = 4
	b.collision_mask = 1 | 2 | 4
	b.mass = 3.0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.09
	cyl.height = 0.7
	cs.shape = cyl
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.09
	cm.height = 0.7
	cm.radial_segments = 12
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.2, 0.1)
	m.roughness = 0.7
	cm.material = m
	mi.mesh = cm
	b.add_child(mi)
	for e in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var capm := CylinderMesh.new()
		capm.top_radius = 0.1
		capm.bottom_radius = 0.1
		capm.height = 0.06
		capm.radial_segments = 12
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.7, 0.55, 0.25)
		brass.metallic = 0.8
		capm.material = brass
		cap.mesh = capm
		cap.position = Vector3.UP * 0.35 * e
		b.add_child(cap)
	c.add_child(b)
	b.global_transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), at + Vector3.UP * 0.8)
	b.linear_velocity = Vector3(randf_range(-1, 1), 3.0, randf_range(-1, 1))
	b.set_meta("plan", plan)
	mark(b, "", 1.0)


## A whole part `id` left at `at` to be taken (a robot's wreck, a site's cache): tossed up a little.
func drop(id: String, at: Vector3, cond := -1.0) -> void:
	var c := Combat.current
	if c == null or not ResourceLoader.exists(Parts.model(id)):
		return
	var v := Vector3(randf_range(-1.5, 1.5), randf_range(2.0, 4.0), randf_range(-1.5, 1.5))
	var b := c.debris(id, Transform3D(Basis(Vector3.UP, randf() * TAU), at + Vector3.UP * 0.8), v,
		Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 2.0, load(Parts.model(id)) as PackedScene)
	mark(b, id, cond)


func _physics_process(dt: float) -> void:
	var mv: Variant = game.get("machine")
	var me: Machine = mv if is_instance_valid(mv) else null
	for k in range(_items.size() - 1, -1, -1):
		var b := _items[k]
		if not is_instance_valid(b):
			_items.remove_at(k)
			continue
		var age := float(b.get_meta("age", 0.0)) + dt
		b.set_meta("age", age)
		var beam := b.get_meta("beam") as MeshInstance3D if b.has_meta("beam") else null
		if beam:
			beam.global_position = b.global_position + Vector3.UP * 1.9
			beam.scale = Vector3.ONE * (1.0 + 0.12 * sin(age * 4.0))
		if age > LIFE and not b.has_meta("plan"): # (a plan lies till it's taken)
			b.queue_free()
			_items.remove_at(k)
			continue
		if me and me.alive and not me.building and me.global_position.distance_to(b.global_position) < REACH:
			_take(b)
			_items.remove_at(k)


func _take(b: RigidBody3D) -> void:
	if b.has_meta("plan"):
		_take_plan(b)
		return
	var id := str(b.get_meta("salvage"))
	var c := float(b.get_meta("cond", 1.0))
	Inventory.add(id, 1, c)
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/bolt_on_0%d.wav" % randi_range(1, 3), b.global_position, 2.0, 1.1)
	if game.has_method("say"):
		game.call("say", "+ %s %s  ·  elde %d" % [Parts.def(id).name, cond_word(c), Inventory.count(id)])
	b.queue_free()


## A plan taken: known from now on; the first one opens the metal age.
func _take_plan(b: RigidBody3D) -> void:
	var plan := str(b.get_meta("plan"))
	var first := Inventory.age() == 1
	var fresh := Inventory.learn(plan)
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/ratchet_0%d.wav" % randi_range(1, 3), b.global_position, 0.0, 0.8)
	b.queue_free()
	if not fresh or not game.has_method("say"):
		return
	var names := []
	for id: String in Parts.PLANS[plan].parts:
		names.append(Parts.def(id).name)
	if first:
		game.call("say", "METAL ÇAĞI  ·  ilk plan bulundu: %s. Artık hurdayla yapılır: %s" % [Parts.PLANS[plan].name, ", ".join(names)])
	else:
		game.call("say", "PLAN: %s  ·  hurdayla yapılır: %s" % [Parts.PLANS[plan].name, ", ".join(names)])


## How a part is, in a word and its share (%): what's said when it's taken, the builder's note.
static func cond_word(c: float) -> String:
	var w := "sağlam" if c >= 0.85 else ("kullanılmış" if c >= 0.6 else ("yıpranmış" if c >= 0.4 else "hurda gibi"))
	return "(%s %%%d)" % [w, roundi(c * 100.0)]


func count() -> int:
	return _items.size()
