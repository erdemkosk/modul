extends SceneTree
## Every face of TIKI's (Mascot.MOODS), side by side: res://../mascot_sheet.png (or --out=<file>).
##   godot --path . --resolution 1600x400 -s res://tools/mascot_sheet.gd -- --out=<file>

var _vp: SubViewport
var _c: Node3D
var _k := 0
var _wait := 0
var _imgs: Array[Image] = []
var _out := "user://mascot_sheet.png"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_vp = SubViewport.new()
	_vp.size = Vector2i(220, 220)
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.26, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.82, 0.78)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0.0)
	sun.light_energy = 1.3
	_vp.add_child(sun)
	_c = Mascot.creature()
	_vp.add_child(_c)
	var cam := Camera3D.new()
	cam.fov = 32.0
	_vp.add_child(cam)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, -0.06, -1.25)), Vector3(0.0, 0.42, 1.25))


func _process(_d: float) -> bool:
	var keys: Array = Mascot.MOODS.keys()
	if _k >= keys.size():
		var w := 220 * keys.size()
		var sheet := Image.create(w, 220, false, Image.FORMAT_RGBA8)
		for i in _imgs.size():
			sheet.blit_rect(_imgs[i], Rect2i(0, 0, 220, 220), Vector2i(i * 220, 0))
		sheet.save_png(_out)
		print("saved ", _out, " ", keys)
		return true
	Mascot.pose(_c, Mascot.MOODS[keys[_k]], Vector2(0.2, 0.0), 0.0, Vector3.ZERO, Vector2.ZERO, 1.0)
	_wait += 1
	if _wait < 4:
		return false
	_wait = 0
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	_imgs.append(img)
	_k += 1
	return false
