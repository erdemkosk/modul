class_name OrbitCamera
extends Camera3D
## Round the machine: the mouse turns it (captured while driving; with the right button held
## while building), the wheel brings it in and out; it follows the machine's centre of mass and
## never goes under the ground.
##
## Driving it's a shooter's camera: it stands behind and above the machine but looks where you aim
## (a little over the line to the machine), so the crosshair is out where your rounds go and the
## machine sits low in the picture. `mode` (C): CHASE that; HIGH further back and up, looking down
## over the fight to see where everything lands; TURRET from on top of the machine, along the aim.
## The right button held narrows the view to aim at range. `iso` (building): an isometric view, orthographic, looking down at
## 35° from one of the four corners (the right drag turns it a corner at a time), the wheel zooming.

var target: Machine
var terrain: Node
var yaw := PI
var pitch := -0.3
var dist := 11.0
var free_mouse := false ## building: the mouse is a pointer, the right button drags the view
var dragging := false
var drag_moved := 0.0
var shift := 0.0 ## m the view looks off to the machine's right of it (the menu's picture: the machine to one side)
var iso := false
enum { CHASE, HIGH, TURRET }
const MODE_NAMES := ["Takip", "Yüksek", "Kule"]
var mode := CHASE
var zoom := false ## (the right button held while driving)
var _fov := 70.0
var trauma := 0.0 ## 0..1: the view shakes by its square, and it dies away
var _punch := 0.0 ## degrees the view's widened by a big gun going off, springing back
var _noise := FastNoiseLite.new()
var _nt := 0.0

const SENS := 0.004
const ISO_PITCH := -0.6155 ## atan(1 / sqrt(2)): the true isometric angle
const ISO_BACK := 80.0 ## m the orthographic camera stands off (it sees the same at any distance)

var _yaw_shown := PI
var _iso_drag := 0.0
var _reach := -1.0 ## m out from the pivot it's let go this moment (pulled in at once by what's in the way, let out slowly)


func _ready() -> void:
	# it moves every frame itself, after the machine's drawn where it is between physics steps: it's
	# not interpolated, and it follows the machine as drawn (not as the last step left it), or the
	# machine shudders in the picture, the more the further out the view
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	far = 6000.0
	near = 0.08
	fov = 70.0
	_yaw_shown = yaw


func cycle_mode() -> String:
	mode = (mode + 1) % 3
	return MODE_NAMES[mode]


## A shake (`amount` 0..1, adding up to 1) and a punch of the field of view (degrees).
func add_trauma(amount: float, punch := 0.0) -> void:
	var k := float(Settings.get_value("shake"))
	trauma = minf(trauma + amount * k, 1.0)
	_punch = maxf(_punch, punch * k)


func set_iso(on: bool) -> void:
	iso = on
	if on:
		yaw = snappedf(yaw - PI * 0.25, PI * 0.5) + PI * 0.25 # (to the nearest corner)
		size = dist * 1.15


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		dist = maxf(dist * 0.9, 3.0)
	elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		dist = minf(dist * 1.1, 40.0)
	elif mb and mb.button_index == MOUSE_BUTTON_RIGHT:
		dragging = mb.pressed
		if mb.pressed:
			drag_moved = 0.0
			_iso_drag = 0.0
	var mm := event as InputEventMouseMotion
	if mm and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (free_mouse and dragging)):
		drag_moved += mm.relative.length()
		if iso:
			# a quarter turn for every so far dragged
			_iso_drag += mm.relative.x
			if absf(_iso_drag) > 90.0:
				yaw -= signf(_iso_drag) * PI * 0.5
				_iso_drag = 0.0
		else:
			var sens := SENS * float(Settings.get_value("sensitivity")) * (_fov / 70.0) # (zoomed in, the mouse moves the view less)
			yaw -= mm.relative.x * sens
			pitch = clampf(pitch - mm.relative.y * sens, -1.35, 0.6 if free_mouse else 0.45)


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var k := 1.0 - exp(-14.0 * dt)
	_yaw_shown = lerp_angle(_yaw_shown, yaw, 1.0 - exp(-10.0 * dt)) if iso or free_mouse else yaw
	var p := ISO_PITCH if iso else pitch
	var dir := Basis(Vector3.UP, _yaw_shown) * Basis(Vector3.RIGHT, p) * Vector3(0.0, 0.0, 1.0)
	var c := _anchor() + Vector3.UP * 0.6 - Basis(Vector3.UP, _yaw_shown) * Vector3.RIGHT * shift
	if iso:
		projection = Camera3D.PROJECTION_ORTHOGONAL
		size = lerpf(size, dist * 1.15, k)
		global_position = c + dir * ISO_BACK
	elif free_mouse:
		projection = Camera3D.PROJECTION_PERSPECTIVE
		var want := c + dir * dist
		if terrain and terrain.has_method("height_at"):
			want.y = maxf(want.y, float(terrain.call("height_at", want.x, want.z)) + 0.6)
		global_position = global_position.lerp(want, 1.0 - exp(-20.0 * dt))
	else:
		projection = Camera3D.PROJECTION_PERSPECTIVE
		_drive_view(dt, k)
	if iso or free_mouse:
		look_at(c, Vector3.UP)
	# the shake: a jolt and a tremor, sideways, up and a roll, by the square of the trauma
	_nt += dt * 40.0
	trauma = maxf(trauma - dt * (0.6 + 2.5 * trauma), 0.0) # (a steady fire holds it at a tremor)
	_punch = move_toward(_punch, 0.0, dt * 30.0)
	var k2 := trauma * trauma
	if k2 > 0.0001 and not free_mouse:
		_noise.frequency = 0.5
		h_offset = _noise.get_noise_2d(_nt, 0.0) * 0.35 * k2
		v_offset = _noise.get_noise_2d(0.0, _nt) * 0.3 * k2
		rotate_object_local(Vector3.BACK, _noise.get_noise_2d(_nt, 50.0) * 0.06 * k2)
	else:
		h_offset = 0.0
		v_offset = 0.0
	zoom = not free_mouse and not iso and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var base := float(Settings.get_value("fov"))
	_fov = lerpf(_fov, base * 0.43 if zoom else base, 1.0 - exp(-12.0 * dt))
	fov = _fov + _punch


## The machine's centre of mass as it's drawn this frame (between physics steps).
func _anchor() -> Vector3:
	return target.get_global_transform_interpolated() * target.com


## The driving views: placed behind and above, looking out along the aim.
func _drive_view(dt: float, k: float) -> void:
	var aim := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD # (where you look)
	var want: Vector3
	var look := aim
	match mode:
		TURRET:
			# on top of it, a little behind its middle
			want = target.get_global_transform_interpolated() * Vector3(target.com.x, target.top_y + 0.9, target.com.z) \
				- Basis(Vector3.UP, yaw) * Vector3.FORWARD * 0.6
		HIGH:
			var d := dist * 1.7 + 8.0
			var back := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, minf(pitch, -0.25) - 0.45) * Vector3.BACK
			want = _anchor() + Vector3.UP * 1.0 + back * d
			# looking down over the ground ahead to where the aim comes down
			look = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch - 0.22) * Vector3.FORWARD
		_:
			# behind and above: the line back to the camera is the aim's, tipped up 0.15 rad more
			var back := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch - 0.15) * Vector3.BACK
			want = _anchor() + Vector3.UP * (1.0 + dist * 0.06) + back * dist
	if zoom and mode != TURRET:
		want = want.lerp(_anchor() + Vector3.UP * (target.top_y + 1.2), 0.35) # (in closer, over it)
	if terrain and terrain.has_method("height_at"):
		want.y = maxf(want.y, float(terrain.call("height_at", want.x, want.z)) + 0.6)
	# not through walls: from over the machine out to where it wants to be, it stops short of what's
	# in the way (the ground, the arena, its cover; not machines or what's flying about)
	var pivot := _anchor() + Vector3.UP * 1.2
	var out := want - pivot
	var full := out.length()
	var q := PhysicsRayQueryParameters3D.create(pivot, want + out.normalized() * 0.4, 1)
	q.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var room := full if hit.is_empty() or mode == TURRET else maxf(pivot.distance_to(hit.position) - 0.4, 0.5)
	# pulled in at once when something's in the way, let back out slowly: a far view over rough ground
	# (a bump, a tree, in and out of the line every frame) doesn't jump in and out with it
	if _reach < 0.0 or room < _reach:
		_reach = room
	else:
		_reach = minf(lerpf(_reach, room, 1.0 - exp(-2.5 * dt)), room)
	var blocked := _reach < full - 0.05
	want = pivot + out.normalized() * _reach if full > 0.001 else want
	global_position = global_position.lerp(want, 1.0 if blocked else (k if mode != TURRET else 1.0 - exp(-30.0 * dt)))
	look_at(global_position + look, Vector3.UP)
