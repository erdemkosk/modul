class_name PaintedLook
extends Node
## The art direction (painted miniature) for imported models: vehicles, props, gear.
##
## Each surface's plain StandardMaterial3D becomes a painted_prop.gdshader material: the
## colour a little richer and warmer, soft light, a darker edge toward the silhouette, and
## no mirror gloss. Textured materials and lamps are left alone. A few named materials are
## remade outright: cling-film and water packs become one milky, opaque shrink-wrap, and
## camouflage collapses to two muted tones.
##
## As an autoload it repaints every model from assets/props or the truck upgrades as it enters
## the tree, so nothing that loads them has to know (`apply` also works on any node).

const AUTO_DIRS := ["res://assets/props/", "res://assets/truck/upgrades/"]
const SHADER := preload("res://shaders/painted_prop.gdshader")

## Named materials remade outright: name -> [colour, roughness].
const REMAKE := {
	"WaterPack": [Color(0.7, 0.8, 0.88), 0.3], "Wrap": [Color(0.8, 0.86, 0.9), 0.25],
	"CamoGreen": [Color(0.34, 0.37, 0.24), 0.95], "CamoDark": [Color(0.34, 0.37, 0.24), 0.95],
	"CamoBrown": [Color(0.46, 0.41, 0.3), 0.95], "CamoSand": [Color(0.46, 0.41, 0.3), 0.95],
}

static var _cache := {} ## source material -> painted one (shared between instances)
static var _camo: ShaderMaterial


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if not node is MeshInstance3D:
		return
	var owner_scene := node.owner.scene_file_path if node.owner else ""
	for d: String in AUTO_DIRS:
		if owner_scene.begins_with(d):
			_paint_mesh.call_deferred(node)
			return


## Repaints every mesh under `root`.
static func apply(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		_paint_mesh(node as MeshInstance3D)


static func _paint_mesh(mi: MeshInstance3D) -> void:
	if not is_instance_valid(mi) or mi.mesh == null or mi.has_meta("painted"):
		return
	mi.set_meta("painted", true)
	for s in mi.mesh.get_surface_count():
		var src := mi.get_surface_override_material(s)
		if src == null:
			src = mi.mesh.surface_get_material(s)
		if not src is StandardMaterial3D:
			continue
		var out: Material = _cache.get(src)
		if out == null:
			out = _repaint(src as StandardMaterial3D)
			_cache[src] = out
		mi.set_surface_override_material(s, out)


static func _repaint(src: StandardMaterial3D) -> Material:
	var name := src.resource_name
	if name == "Collision":
		return src # helper boxes (hidden anyway)
	if name.begins_with("Camo"):
		# Every patch of a camo net shares one material that paints the two tones itself:
		# the patches overlap, and patches of different colours flickered against each other
		# at a distance.
		if _camo == null:
			_camo = ShaderMaterial.new()
			_camo.shader = SHADER
			_camo.set_shader_parameter("albedo", REMAKE.CamoGreen[0])
			_camo.set_shader_parameter("albedo_b", REMAKE.CamoBrown[0])
			_camo.set_shader_parameter("roughness", 0.95)
			_camo.set_shader_parameter("camo", true)
		return _camo
	var col := src.albedo_color
	var rough := src.roughness
	if REMAKE.has(name):
		col = REMAKE[name][0]
		rough = REMAKE[name][1]
	elif src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or src.emission_enabled or src.albedo_texture:
		var m := src.duplicate() as StandardMaterial3D
		m.roughness = maxf(m.roughness, 0.45)
		return m # glass, lamps, textured: as they are
	var l := col.r * 0.3 + col.g * 0.59 + col.b * 0.11
	var rich := Color(l, l, l).lerp(col, 1.2)
	rich = Color(clampf(rich.r * 1.04, 0.0, 1.0), clampf(rich.g, 0.0, 1.0), clampf(rich.b * 0.95, 0.0, 1.0))
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo", rich)
	m.set_shader_parameter("roughness", maxf(rough, 0.45))
	m.set_shader_parameter("metallic", src.metallic)
	m.set_shader_parameter("use_vertex_color", src.vertex_color_use_as_albedo)
	return m
