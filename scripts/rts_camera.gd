class_name RtsCamera
extends Camera3D
## The village from above: a point on the ground it looks at (`focus`), turned round it (`yaw`) and
## stood back from it (`dist`), tipping down further the higher it goes. WASD, the arrows or the
## window's edge pan (Shift faster), Q / E or the middle button held turn it, the wheel brings it in
## and out. It never goes under the ground.

const MIN_DIST := 16.0
const MAX_DIST := 460.0
const EDGE := 4.0 ## px from the window's edge that pans
const LIMIT := 960.0 ## how far from the map's middle the focus may go, m

var hold_keys := false ## (something being placed: Q and E are its, not the view's)
var terrain: WorldTerrain
var focus := Vector3.ZERO
var yaw := 0.6
var dist := 70.0
var edge_pan := true

var _dist_to := 70.0
var _tilt := 0.0 ## the middle drag's own say in the pitch
var _turning := false


func _ready() -> void:
	near = 0.25
	far = 7000.0
	fov = 50.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_dist_to = dist


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist_to = maxf(MIN_DIST, _dist_to * 0.86)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist_to = minf(MAX_DIST, _dist_to / 0.86)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_turning = mb.pressed
	elif e is InputEventMouseMotion and _turning:
		var mm := e as InputEventMouseMotion
		yaw -= mm.relative.x * 0.006
		_tilt = clampf(_tilt + mm.relative.y * 0.004, -0.4, 0.4)


## Down from the horizon, rad: low and looking along the ground close in, steeper far out.
func pitch() -> float:
	var t := clampf(inverse_lerp(MIN_DIST, MAX_DIST, dist), 0.0, 1.0)
	return clampf(lerpf(0.5, 1.12, sqrt(t)) + _tilt, 0.25, 1.45)


func jump_to(p: Vector3) -> void:
	focus = p


## A blast felt: the view jolts, `amount` (0..1) the harder the nearer, and settles.
var _shake := 0.0


func shake(at: Vector3, power: float) -> void:
	var d := at.distance_to(global_position)
	_shake = maxf(_shake, clampf(power * (1.0 - d / 140.0), 0.0, 1.0))


func _process(dt: float) -> void:
	var real_dt := dt / maxf(Engine.time_scale, 0.01) # (it pans as fast at any game speed)
	if _shake > 0.001:
		_shake = maxf(_shake - real_dt * 2.2, 0.0)
		var k := _shake * _shake * 0.35
		h_offset = randf_range(-k, k)
		v_offset = randf_range(-k, k)
	elif h_offset != 0.0 or v_offset != 0.0:
		h_offset = 0.0
		v_offset = 0.0
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if edge_pan and DisplayServer.window_is_focused():
		var vp := get_viewport()
		var m := vp.get_mouse_position()
		var r := vp.get_visible_rect().size
		if m.x >= 0.0 and m.y >= 0.0 and m.x <= r.x and m.y <= r.y:
			if m.x < EDGE:
				move.x -= 1.0
			elif m.x > r.x - EDGE:
				move.x += 1.0
			if m.y < EDGE:
				move.y += 1.0
			elif m.y > r.y - EDGE:
				move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_Q) and not hold_keys:
		yaw += real_dt * 1.5
	if Input.is_physical_key_pressed(KEY_E) and not hold_keys:
		yaw -= real_dt * 1.5
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := fwd.cross(Vector3.UP)
	var speed := (12.0 + dist * 1.1) * (2.2 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	if move != Vector2.ZERO:
		move = move.normalized()
		focus += (fwd * move.y + right * move.x) * speed * real_dt
	focus.x = clampf(focus.x, -LIMIT, LIMIT)
	focus.z = clampf(focus.z, -LIMIT, LIMIT)
	var ground := terrain.height_at(focus.x, focus.z) if terrain else 0.0
	focus.y = lerpf(focus.y, ground, 1.0 - exp(-8.0 * real_dt)) if absf(focus.y - ground) < 40.0 else ground
	dist = lerpf(dist, _dist_to, 1.0 - exp(-10.0 * real_dt))
	var p := pitch()
	var pos := focus + Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * dist
	if terrain:
		pos.y = maxf(pos.y, terrain.height_at(pos.x, pos.z) + 3.0)
	global_position = pos
	look_at(focus + Vector3.UP * 0.5, Vector3.UP)
	# (the trees between the view and the town dissolve round the line of sight: nature.gdshader)
	RenderingServer.global_shader_parameter_set(&"view_focus", Vector4(focus.x, focus.y + 1.0, focus.z, 1.0))


## Where a ray from the camera through a point on the screen meets the ground (marched along the
## heightmap, then narrowed), or null off the map / into the sky.
func ground_under(screen: Vector2) -> Variant:
	var o := project_ray_origin(screen)
	var d := project_ray_normal(screen)
	var t := 0.0
	var step := 2.0
	var prev := 0.0
	var above := o.y - terrain.height_at(o.x, o.z)
	if above < 0.0:
		return null
	while t < 4000.0:
		t += step
		var p := o + d * t
		if absf(p.x) > 1024.0 or absf(p.z) > 1024.0:
			return null
		if p.y < terrain.height_at(p.x, p.z):
			var a := prev
			var b := t
			for k in 12:
				var mid := (a + b) * 0.5
				var q := o + d * mid
				if q.y < terrain.height_at(q.x, q.z):
					b = mid
				else:
					a = mid
			var hit := o + d * b
			hit.y = terrain.height_at(hit.x, hit.z)
			return hit
		prev = t
		step = minf(step * 1.08, 12.0)
	return null
