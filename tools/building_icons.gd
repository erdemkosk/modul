extends SceneTree
## The build bar's pictures: every building put up whole in a little studio of its own and taken
## from the front right, a little above, on a clear background (its buried plinth left out).
##
##   godot --path . -s res://tools/building_icons.gd [-- --only=ev,ambar]
##
## Output: assets/ui/icons/<kind>.png (the HUD shows them if they're there).

const OUT := "res://assets/ui/icons/"
const SIZE := Vector2i(256, 176)

var _vp: SubViewport
var _cam: Camera3D
var _kinds: Array = []


func _initialize() -> void:
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	for k: String in BuildingDefs.DEFS:
		if only.is_empty() or k in only:
			_kinds.append(k)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b8b0a0")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe6c4")
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-42, 30, 0)
	sun.shadow_enabled = true
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 28.0
	_vp.add_child(_cam)
	_take_all.call_deferred()


func _take_all() -> void:
	for k: String in _kinds:
		await _take(k)
	quit()


func _take(kind: String) -> void:
	var b := Building.new()
	b.setup(kind)
	_vp.add_child(b)
	b.complete_now()
	b.set_ghost(false)
	var box := AABB()
	var first := true
	for p in b.pieces:
		if p.tag == "plinth":
			if is_instance_valid(p.mesh):
				p.mesh.visible = false
			continue
		box = p.aabb if first else box.merge(p.aabb)
		first = false
	if first:
		print("icons: %s has nothing to show" % kind)
		b.queue_free()
		return
	var centre := box.get_center()
	var dir := Vector3(0.78, 0.62, 1.0).normalized()
	var radius := box.size.length() * 0.5
	var dist := radius / tan(deg_to_rad(_cam.fov * 0.5)) * 0.92
	_cam.look_at_from_position(centre + dir * dist, centre)
	await process_frame
	await process_frame
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + kind + ".png"))
	print("icons: wrote %s" % kind)
	b.queue_free()
	await process_frame
