extends SceneTree
## The starting cart (Designs.logger_cart) with TIKI at the wheel, from the front corner, the side and
## behind, to see how much of the driver shows: user://cab_shot.png (or --out=<file>).
##   godot --path . --resolution 1920x400 -s res://tools/cab_shot.gd -- --out=<file>

const SIZE := Vector2i(640, 400)
## (from where, how far, looking at): the cab and the crane from the front corner and the side, the driver close.
const VIEWS := [[Vector3(0.75, 0.45, -1.0), 4.0, Vector3(0.5, 1.5, -0.5)], [Vector3(1.0, 0.3, 0.0), 4.0, Vector3(0.5, 1.5, -0.5)],
	[Vector3(0.9, 0.2, -0.6), 2.2, Vector3(0.5, 1.1, -0.5)]]

var _vp: SubViewport
var _cam: Camera3D
var _k := 0
var _wait := 6
var _imgs: Array[Image] = []
var _out := "user://cab_shot.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.62, 0.66)
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
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for e: Array in Designs.logger_cart():
		var id := str(e[0])
		var at := Vector3i(int(e[1]), int(e[2]), int(e[3]))
		var n := (load(Parts.model(id)) as PackedScene).instantiate() as Node3D
		PaintedLook.apply(n)
		n.transform = Parts.xform_of(id, at, int(e[4]))
		_vp.add_child(n)
		if Parts.is_cab(id):
			var drv := Mascot.creature()
			drv.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * Machine.DRIVER_SCALE), Machine.DRIVER_AT.get(id, Vector3(0, -0.25, 0.1)))
			n.add_child(drv)
			Mascot.pose(drv, Mascot.MOODS.happy, Vector2.ZERO, 0.0, Vector3.ZERO, Vector2.ZERO, 1.0)
		lo = lo.min(Vector3(at) * Parts.CELL)
		hi = hi.max((Vector3(at) + Vector3(Parts.size_of(id, int(e[4])))) * Parts.CELL)


func _process(_d: float) -> bool:
	if _k >= VIEWS.size():
		var sheet := Image.create(SIZE.x * VIEWS.size(), SIZE.y, false, Image.FORMAT_RGBA8)
		for i in _imgs.size():
			sheet.blit_rect(_imgs[i], Rect2i(Vector2i.ZERO, SIZE), Vector2i(i * SIZE.x, 0))
		sheet.save_png(_out)
		print("saved ", _out)
		return true
	var v: Array = VIEWS[_k]
	_cam.position = (v[2] as Vector3) + (v[0] as Vector3).normalized() * float(v[1])
	_cam.look_at(v[2], Vector3.UP)
	_wait -= 1
	if _wait > 0:
		return false
	_wait = 4
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_imgs.append(img)
	_k += 1
	return false
