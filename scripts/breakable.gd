class_name Breakable
extends StaticBody3D
## Something in the arena that rounds chip, bursts break and a machine driven into it batters (its
## weight times how hard it stopped, more on a ram's spikes: Machine): a concrete block, a jersey barrier, a
## shipping container, a crate, a sandbag wall, an oil drum. Solid ground to everything (layer 1:
## wheels drive up on it, rounds stop on it) until its hit points run out; then it comes apart into
## chunks the size and stuff it was made of (concrete lumps, steel panels, planks, bags), flung away
## from what broke it, and a drum goes up in a burst of its own.

const GROUP := "breakables"
## kind -> hit points, chunk colour, how many chunks, what its chips look like (Combat's impacts), mass kg/m3.
const KINDS := {
	"block": {"hp": 420.0, "color": Color(0.52, 0.5, 0.46), "chunks": 12, "chip": "dirt", "density": 2300.0},
	"barrier": {"hp": 380.0, "color": Color(0.52, 0.5, 0.46), "chunks": 7, "chip": "dirt", "density": 2300.0},
	"container": {"hp": 800.0, "color": Color(0.12, 0.25, 0.38), "chunks": 8, "chip": "metal", "density": 60.0},
	"crate": {"hp": 60.0, "color": Color(0.42, 0.3, 0.17), "chunks": 10, "chip": "dirt", "density": 160.0},
	"sandbags": {"hp": 320.0, "color": Color(0.5, 0.43, 0.29), "chunks": 10, "chip": "dirt", "density": 1500.0},
	"drum": {"hp": 30.0, "color": Color(0.45, 0.08, 0.05), "chunks": 4, "chip": "metal", "density": 200.0},
	"boulder": {"hp": 520.0, "color": Color(0.4, 0.38, 0.35), "chunks": 10, "chip": "dirt", "density": 2600.0},
	"log": {"hp": 160.0, "color": Color(0.33, 0.24, 0.16), "chunks": 6, "chip": "dirt", "density": 600.0},
}
## The valley's: a model of its own (the props'), fitted to the box.
const MODELS := {"boulder": "res://assets/nature/rock_a.glb", "log": "res://assets/nature/log.glb"}
## The models' boxes (Godot axes: x across, y up, z along), their feet at the origin.
const SIZES := {"block": Vector3(2.0, 1.2, 2.0), "barrier": Vector3(3.0, 0.8, 0.6), "container": Vector3(6.06, 2.59, 2.44),
	"crate": Vector3(1.2, 1.2, 1.2), "sandbags": Vector3(3.0, 0.62, 0.8), "drum": Vector3(0.6, 0.88, 0.6),
	"boulder": Vector3(2.4, 1.7, 2.2), "log": Vector3(7.0, 0.7, 0.7)}

var kind := "block"
var hp := 100.0
var size := Vector3.ONE
var broken := false


static func make(p_kind: String, xf: Transform3D) -> Breakable:
	var b := Breakable.new()
	b.kind = p_kind
	b.hp = float(KINDS[p_kind].hp)
	b.size = SIZES[p_kind]
	b.transform = xf
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = b.size
	cs.shape = box
	cs.position = Vector3.UP * b.size.y * 0.5
	b.add_child(cs)
	var model := (load(MODELS.get(p_kind, "res://assets/arena/%s.glb" % p_kind)) as PackedScene).instantiate() as Node3D
	PaintedLook.apply(model)
	b.add_child(model)
	if MODELS.has(p_kind):
		_fit(model, b.size)
	b.add_to_group(GROUP)
	return b


## A round or a fragment: chips off it.
func hit(damage: float, _at: Vector3, _dir: Vector3, from_burst := false) -> void:
	if broken:
		return
	hp -= damage
	if hp <= 0.0:
		broken = true
		var c := Combat.current
		if c:
			c.shatter.call_deferred(self, _dir, from_burst)
		else:
			queue_free()


## `model` (a prop's: only its nearest detail kept) scaled and moved to fill a box of `box` standing on the origin.
static func _fit(model: Node3D, box: Vector3) -> void:
	for n: Node in model.get_children():
		if n.name.begins_with("LOD") and n.name != "LOD0":
			n.free()
	var aabb := AABB()
	var first := true
	for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a := _rel(model, m) * m.mesh.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	if first or aabb.size.x <= 0.0:
		return
	var k := box / aabb.size
	model.scale = k
	model.position = Vector3(-(aabb.position.x + aabb.size.x * 0.5) * k.x, -aabb.position.y * k.y, -(aabb.position.z + aabb.size.z * 0.5) * k.z)


static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent() as Node3D
	while p and p != root:
		t = p.transform * t
		p = p.get_parent() as Node3D
	return t


func chip_kind() -> String:
	return str(KINDS[kind].chip)


## Its middle (world).
func center() -> Vector3:
	return global_transform * (Vector3.UP * size.y * 0.5)
