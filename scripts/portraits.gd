class_name Portraits
extends Node
## Each villager's face, for the lists: its own body built again from the same seed (Townsfolk is
## dressed by the seed alone) in a little studio of its own (a SubViewport with its own world: a
## key light, a fill, a dark ground), framed head and shoulders and taken once. Asked for one that
## isn't taken yet, `of` gives null and puts it in line; they're taken one a frame or two apart.

const SIZE := 96
const DIST := 0.75 ## m the camera stands off the face

static var _me: Portraits

var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D
var _taken := {} ## villager instance id -> ImageTexture
var _line: Array[Villager] = []
var _busy := false


func _ready() -> void:
	_me = self
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1d1a17")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8a8070")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffe2b8")
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-28, -35, 0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#9fb4d0")
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-10, 140, 0)
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_vp.add_child(_cam)
	_stage = Node3D.new()
	_vp.add_child(_stage)


## `v`'s face, or null while it's still to be taken.
static func of(v: Villager) -> Texture2D:
	if _me == null or v == null or not is_instance_valid(v) or v.look_seed == 0:
		return null
	var id := v.get_instance_id()
	if _me._taken.has(id):
		return _me._taken[id]
	if not v in _me._line:
		_me._line.append(v)
	return null


func _process(_dt: float) -> void:
	if _busy or _line.is_empty():
		return
	var v: Villager = _line.pop_front()
	if is_instance_valid(v) and not v.dead:
		_take(v)


func _take(v: Villager) -> void:
	_busy = true
	var body := Townsfolk.new()
	_stage.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = v.look_seed
	body.build(v.look_kind, rng)
	body.player.seek(0.0, true) # (stood square to the camera, not mid-step)
	await get_tree().process_frame # (the skeleton posed)
	var face := _head(body)
	_cam.look_at_from_position(face + Vector3(0.14, 0.03, -DIST), face + Vector3(0, -0.04, 0))
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img and not img.is_empty():
		_taken[v.get_instance_id()] = ImageTexture.create_from_image(img)
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
