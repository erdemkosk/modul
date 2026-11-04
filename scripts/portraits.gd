class_name Portraits
extends Node
## Each villager's face, for the lists: its own body built again from the same seed (Townsfolk is
## dressed by the seed alone) in a little studio of its own (a SubViewport with its own world: a
## key light, a fill, a dark ground), framed head and shoulders and taken once. Asked for one that
## isn't taken yet, `of` gives null and puts it in line; they're taken one a frame or two apart.

const SIZE := Vector2i(330, 400) ## (head and shoulders, then painted: shaders/portrait_paint.gdshader)
const DIST := 1.02 ## m the camera stands off the face

static var _me: Portraits

var _vp: SubViewport
var _canvas: SubViewport ## the studio's picture painted over
var _cam: Camera3D
var _stage: Node3D
var _taken := {} ## "<seed>:<kind>" -> ImageTexture
var _line: Array = [] ## [seed, kind] still to be taken
var _busy := false


func _ready() -> void:
	_me = self
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#7d6f60")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffdcae")
	key.light_energy = 1.05
	key.rotation_degrees = Vector3(-34, 208, 0) # (a window high to the left: half the face in shade)
	key.shadow_enabled = true
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#9fb4d0")
	fill.light_energy = 0.16
	fill.rotation_degrees = Vector3(-6, 130, 0)
	_vp.add_child(fill)
	var rim := DirectionalLight3D.new() # (the edge of the far cheek and shoulder caught)
	rim.light_color = Color("#ffcf96")
	rim.light_energy = 0.5
	rim.rotation_degrees = Vector3(-18, 25, 0)
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_vp.add_child(_cam)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	_canvas = SubViewport.new()
	_canvas.size = SIZE
	_canvas.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_canvas)
	var sheet := ColorRect.new()
	sheet.size = Vector2(SIZE)
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://shaders/portrait_paint.gdshader")
	paint.set_shader_parameter("src", _vp.get_texture())
	sheet.material = paint
	_canvas.add_child(sheet)


## `v`'s face, or null while it's still to be taken.
static func of(v: Villager) -> Texture2D:
	if v == null or not is_instance_valid(v):
		return null
	return of_look(v.look_seed, v.look_kind)


## The face a body dressed from `seed` (`kind`: "man", "child", "outlaw") has: a settler not yet in
## the valley too (the title screen's choosing).
static func of_look(seed: int, kind := "man") -> Texture2D:
	if _me == null or seed == 0:
		return null
	var key := "%d:%s" % [seed, kind]
	if _me._taken.has(key):
		return _me._taken[key]
	if not _me._line.any(func(e: Array) -> bool: return e[0] == seed and e[1] == kind):
		_me._line.append([seed, kind])
	return null


func _process(_dt: float) -> void:
	if _busy or _line.is_empty():
		return
	var e: Array = _line.pop_front()
	_take(int(e[0]), str(e[1]))


func _take(seed: int, kind: String) -> void:
	_busy = true
	var body := Townsfolk.new()
	_stage.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	body.build(kind, rng)
	body.player.seek(0.0, true) # (stood square to the camera, not mid-step)
	await get_tree().process_frame # (the skeleton posed)
	var face := _head(body)
	_cam.look_at_from_position(face + Vector3(0.3, 0.06, -DIST), face + Vector3(0, -0.09, 0)) # (three-quarters on)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_canvas.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _canvas.get_texture().get_image()
	if img and not img.is_empty():
		img.generate_mipmaps()
		_taken["%d:%s" % [seed, kind]] = ImageTexture.create_from_image(img)
	body.queue_free()
	_busy = false


## Where the face is: the head bone (a little up from it, to the eyes), or a man's height.
func _head(body: Townsfolk) -> Vector3:
	var sk := body.skeleton
	var b := sk.find_bone("Head")
	if b < 0:
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).to_lower().contains("head"):
				b = i
				break
	if b < 0:
		return body.global_position + Vector3.UP * 1.6
	return (sk.global_transform * sk.get_bone_global_pose(b)).origin + Vector3.UP * 0.08
