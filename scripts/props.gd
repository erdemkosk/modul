class_name Props
extends RefCounted
## The things made in Blender that aren't buildings (assets/props, tools/blender/build_props.py):
## each model's pieces, kept once, set down wherever they're wanted.

const PATH := "res://assets/props/%s.glb"

static var _kinds := {} ## kind -> [{mesh, stuff, tag, xf}]


## `kind`'s pieces, each at its place in the model.
static func pieces(kind: String) -> Array:
	if _kinds.has(kind):
		return _kinds[kind]
	var root := (load(PATH % kind) as PackedScene).instantiate()
	var out: Array = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var parts := String(mi.name).split("-")
		var xf := Transform3D.IDENTITY
		var at: Node = mi
		while at != root and at is Node3D:
			xf = (at as Node3D).transform * xf
			at = at.get_parent()
		out.append({"mesh": mi.mesh, "stuff": parts[0], "tag": parts[1] if parts.size() >= 3 else "", "xf": xf})
	root.free()
	_kinds[kind] = out
	return out


## The material for a piece of `stuff` (its colours are in its vertices).
static func look(stuff: String) -> Material:
	return Building.material(stuff + "+")


## `kind` put down under `parent` at `xf`: its pieces as children (each can be baked with MeshBake).
## `hide`: what's made of "hide" wears this instead. Returns them.
static func place(parent: Node3D, kind: String, xf := Transform3D.IDENTITY, hide: Material = null) -> Array[MeshInstance3D]:
	var made: Array[MeshInstance3D] = []
	for p: Dictionary in pieces(kind):
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.material_override = hide if p.stuff == "hide" and hide != null else look(str(p.stuff))
		mi.transform = xf * (p.xf as Transform3D)
		mi.set_meta("tag", p.tag)
		parent.add_child(mi)
		made.append(mi)
	return made
