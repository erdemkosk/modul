class_name Details
extends RefCounted
## The town's small made things (assets/details, tools/blender/build_details.py): palisade stakes and
## their rails, the gate, the telegraph poles, the graveyard's crosses, what lies about. Each model's
## pieces kept once; put down as pieces (each can be baked with MeshBake), or as one mesh of a
## surface to a stuff (for a MultiMesh).

const PATH := "res://assets/details/%s.glb"

static var _kinds := {} ## kind -> [{mesh, stuff, tag, xf}]
static var _meshes := {} ## kind -> ArrayMesh
static var _looks := {} ## stuff -> Material (those not the buildings')


## `kind`'s pieces, each at its place in the model.
static func pieces(kind: String) -> Array:
	if _kinds.has(kind):
		return _kinds[kind]
	var out: Array = []
	var scene := load(PATH % kind) as PackedScene
	if scene == null:
		push_warning("Details: no model %s" % kind)
		_kinds[kind] = out
		return out
	var root := scene.instantiate()
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


## The material for a piece of `stuff` (its colours in its vertices; snow and wet on it, as on the
## buildings), but glass and a lamp's lens, which are their own.
static func look(stuff: String) -> Material:
	if _looks.has(stuff):
		return _looks[stuff]
	var m: Material
	match stuff:
		"glass":
			var g := StandardMaterial3D.new()
			g.vertex_color_use_as_albedo = true
			g.roughness = 0.12
			g.metallic_specular = 0.9
			m = g
		"lamp":
			var l := StandardMaterial3D.new()
			l.vertex_color_use_as_albedo = true
			l.emission_enabled = true
			l.emission = Color(0.4, 0.95, 0.45)
			l.emission_energy_multiplier = 1.6
			m = l
		"water": # (still water in a trough or a tub: dark, the sky only dimly in it)
			var w := StandardMaterial3D.new()
			w.albedo_color = Color(0.07, 0.07, 0.05)
			w.roughness = 0.3
			w.metallic_specular = 0.35
			m = w
		_:
			m = Building.material(stuff + "+")
	_looks[stuff] = m
	return m


## `kind` put down under `parent` at `xf` (in `parent`'s terms): its pieces as children. Returns them.
static func place(parent: Node3D, kind: String, xf := Transform3D.IDENTITY, shadow := true) -> Array[MeshInstance3D]:
	var made: Array[MeshInstance3D] = []
	for p: Dictionary in pieces(kind):
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.material_override = look(str(p.stuff))
		mi.transform = xf * (p.xf as Transform3D)
		mi.set_meta("tag", p.tag)
		if not shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		made.append(mi)
	return made


## `kind` as one mesh (its pieces at their places, a surface to each stuff, each with its material):
## for a MultiMesh.
static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var by := {} ## stuff -> SurfaceTool
	for p: Dictionary in pieces(kind):
		var stuff := str(p.stuff)
		if not by.has(stuff):
			by[stuff] = SurfaceTool.new()
		var m: Mesh = p.mesh
		for s in m.get_surface_count():
			(by[stuff] as SurfaceTool).append_from(m, s, p.xf)
	var out := ArrayMesh.new()
	for stuff: String in by:
		(by[stuff] as SurfaceTool).commit(out)
		out.surface_set_material(out.get_surface_count() - 1, look(stuff))
	_meshes[kind] = out
	return out
