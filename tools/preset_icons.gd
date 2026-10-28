extends SceneTree
## Renders a picture of each of the builder's ready designs (Designs.PRESETS) for its button:
## assets/ui/presets/<function>.png, the machine from a front corner on a clear background.
##   godot --path . --resolution 640x400 -s res://tools/preset_icons.gd

const OUT := "res://assets/ui/presets"
const SIZE := Vector2i(256, 150)

var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _i := -1
var _wait := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.7, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_vp.add_child(_cam)
	_holder = Node3D.new()
	_vp.add_child(_holder)


func _process(_dt: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var img := _vp.get_texture().get_image()
			var fn: String = Designs.PRESETS[_i][2]
			img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, fn]))
			print("icon ", fn)
		return false
	_i += 1
	if _i >= Designs.PRESETS.size():
		return true
	_build(Designs.preset(_i))
	_wait = 6
	return false


## The design's parts as they'd sit on the machine, and the camera framing them.
func _build(rows: Array) -> void:
	for c in _holder.get_children():
		c.free()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for e: Array in rows:
		var id := str(e[0])
		var at := Vector3i(int(e[1]), int(e[2]), int(e[3]))
		var rot := int(e[4])
		var n := (load(Parts.model(id)) as PackedScene).instantiate() as Node3D
		PaintedLook.apply(n)
		n.transform = Parts.xform_of(id, at, rot)
		_holder.add_child(n)
		var s := Vector3(Parts.size_of(id, rot))
		lo = lo.min(Vector3(at) * Parts.CELL)
		hi = hi.max((Vector3(at) + s) * Parts.CELL)
	var mid := (lo + hi) * 0.5
	var r := (hi - lo).length() * 0.5
	var dir := Vector3(0.75, 0.55, -1.0).normalized() # (from in front, a little to the side, above)
	_cam.position = mid + dir * (r / sin(deg_to_rad(_cam.fov * 0.5)) * 0.82)
	_cam.look_at(mid, Vector3.UP)
