class_name Mascot
extends CanvasLayer
## TIKI, who drives: a small fuzzy forest creature in a leather driving cap and goggles, big eyes, long
## floppy ears. It sits in your machine's cab (`creature()`, put there by Machine for every cab: the
## other side's are driven by its kind too) and its face is at the bottom left of the screen, live:
## it blinks and looks about, looks where you aim, its head is thrown about by the machine's pull (as
## it brakes, turns, lands) and its ears swing. And it feels what happens (`mood`, each held a while):
##   hurt      a knock or a hit: it screws its eyes shut and grimaces, its head jolts
##   scared    in the air, a part torn off, a giant near: eyes wide, mouth open
##   dizzy     on its back: eyes rolling
##   happy     going well (fast on good ground), wood brought home: a grin, ears up
##   focus     sawing: brows down, the tip of its tongue out
##   effort    a load on the crane: cheeks puffed, eyes squeezed half
##   wow       a tree coming down: eyes and mouth round
##   worried   badly hurt: brows up, a wobbly mouth
##   dead      its machine gone: crosses for eyes
## The face is made of plain shapes (spheres, boxes) moved by a handful of numbers (`_face`) eased
## toward the mood's every frame.

const PORTRAIT := Vector2i(210, 210)
const NAME := "TIKI"
const FUR := Color(0.72, 0.46, 0.24)
const FUR_DARK := Color(0.5, 0.3, 0.15)
const FACE := Color(0.93, 0.8, 0.62)
const CAP := Color(0.3, 0.18, 0.1)
const LENS := Color(0.55, 0.75, 0.8, 0.5)

## The faces: lid (0 open, 1 shut), brow (up +), tilt (worried + / angry -), open (mouth), smile (+ up,
## - down), round (an "o"), puff (cheeks), tongue, x (dead eyes).
const MOODS := {
	"idle": {"lid": 0.1, "brow": 0.0, "tilt": 0.0, "open": 0.05, "smile": 0.3, "round": 0.0, "puff": 0.0, "tongue": 0.0, "x": 0.0},
	"happy": {"lid": 0.25, "brow": 0.3, "tilt": 0.0, "open": 0.45, "smile": 1.0, "round": 0.0, "puff": 0.2, "tongue": 0.0, "x": 0.0},
	"hurt": {"lid": 0.95, "brow": -0.4, "tilt": -0.6, "open": 0.35, "smile": -0.8, "round": 0.0, "puff": 0.0, "tongue": 0.0, "x": 0.0},
	"scared": {"lid": 0.0, "brow": 0.9, "tilt": 0.6, "open": 0.9, "smile": -0.3, "round": 0.6, "puff": 0.0, "tongue": 0.0, "x": 0.0},
	"dizzy": {"lid": 0.35, "brow": 0.3, "tilt": 0.3, "open": 0.3, "smile": -0.4, "round": 0.4, "puff": 0.0, "tongue": 0.3, "x": 0.0},
	"focus": {"lid": 0.4, "brow": -0.3, "tilt": -0.5, "open": 0.15, "smile": 0.1, "round": 0.0, "puff": 0.0, "tongue": 1.0, "x": 0.0},
	"effort": {"lid": 0.6, "brow": -0.2, "tilt": -0.3, "open": 0.0, "smile": -0.2, "round": 0.0, "puff": 1.0, "tongue": 0.0, "x": 0.0},
	"wow": {"lid": 0.0, "brow": 1.0, "tilt": 0.2, "open": 0.7, "smile": 0.2, "round": 1.0, "puff": 0.0, "tongue": 0.0, "x": 0.0},
	"worried": {"lid": 0.2, "brow": 0.5, "tilt": 0.9, "open": 0.15, "smile": -0.6, "round": 0.0, "puff": 0.0, "tongue": 0.0, "x": 0.0},
	"dead": {"lid": 0.0, "brow": -0.2, "tilt": 0.4, "open": 0.4, "smile": -0.5, "round": 0.3, "puff": 0.0, "tongue": 0.8, "x": 1.0},
}

var game: Node
var mood := "idle"
var _mood_t := 0.0 ## s the mood's held still
var _face := {}
var _vp: SubViewport
var _head: Node3D ## (the portrait's)
var _cam: Camera3D
var _frame: Control
var _label: Label
var _blink := 0.0
var _blink_t := 2.0
var _look := Vector2.ZERO
var _look_t := 0.0
var _look_to := Vector2.ZERO
var _jolt := Vector3.ZERO ## (the head thrown about: an offset, springing back)
var _jolt_v := Vector3.ZERO
var _vel := Vector3.ZERO ## (the machine's last step: its pull)
var _ears := Vector2.ZERO
var _bound: Machine
var _lying := 0
var _brought := 0
var _t := 0.0


func _ready() -> void:
	layer = 5
	_face = (MOODS.idle as Dictionary).duplicate()
	if DisplayServer.get_name() == "headless":
		return
	_vp = SubViewport.new()
	_vp.size = PORTRAIT
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.82, 0.78)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0.0)
	sun.light_energy = 1.3
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.2, -2.4, 0.0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.7, 0.8, 1.0)
	_vp.add_child(fill)
	_head = creature()
	_vp.add_child(_head)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	_vp.add_child(_cam)
	_cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, -0.06, -1.25)), Vector3(0.0, 0.42, 1.25))
	# the plate, bottom left: the face in a frame, its name under it
	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel", Ui.glass(false, 6.0))
	_frame.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_frame.offset_left = 24
	_frame.offset_bottom = -22
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(col)
	var pic := TextureRect.new()
	pic.texture = _vp.get_texture()
	pic.custom_minimum_size = Vector2(150, 150)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	_label = Ui.label(col, NAME, 13, Ui.ACCENT, "head")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Feel `m` for a moment: `hold` s at least (a stronger one breaks in).
func feel(m: String, hold := 1.2) -> void:
	if mood == "dead" and m != "idle":
		return
	var rank := {"idle": 0, "happy": 1, "focus": 1, "effort": 1, "worried": 2, "wow": 3, "dizzy": 3, "scared": 4, "hurt": 5, "dead": 6}
	if _mood_t > 0.0 and int(rank.get(m, 0)) < int(rank.get(mood, 0)):
		return
	mood = m
	_mood_t = hold


func _bind(m: Machine) -> void:
	if _bound == m:
		return
	_bound = m
	mood = "idle"
	_mood_t = 0.0
	if not is_instance_valid(m):
		return
	m.struck.connect(func(_at: Vector3, dv: float, _o: Object) -> void:
		if dv > 2.5:
			feel("hurt", 0.4 + minf(dv * 0.05, 0.8))
			jolt(Vector3(randf_range(-1, 1), 0.6, 0.0) * minf(dv * 0.03, 0.25)))
	m.damaged.connect(func(amount: float, _from: Vector3, _kind: String) -> void:
		if amount > 6.0:
			feel("hurt", 0.6)
			jolt(Vector3(randf_range(-1, 1), randf_range(-0.3, 0.6), 0.0) * 0.12))
	m.torn.connect(func(_at: Vector3, _id: String) -> void: feel("scared", 1.5))
	m.died.connect(func() -> void: feel("dead", 9999.0))


## The head thrown (portrait units: m of the head's own size).
func jolt(v: Vector3) -> void:
	_jolt_v += v * 12.0


func _process(dt: float) -> void:
	_t += dt
	var mv: Variant = game.get("machine") if game else null
	var m: Machine = mv as Machine if is_instance_valid(mv) else null
	if m != _bound:
		_bind(m)
	var building: bool = (game.get("builder") as Builder).active if game and game.get("builder") else false
	if _frame:
		_frame.visible = m != null and not building
	_mood_t -= dt
	if m and m.alive:
		_sense(m, dt)
	if _mood_t <= 0.0 and mood != "dead":
		mood = "idle"
	# the face eased toward the mood's
	var want: Dictionary = MOODS.get(mood, MOODS.idle)
	for k: String in want:
		_face[k] = lerpf(float(_face.get(k, 0.0)), float(want[k]), 1.0 - exp(-10.0 * dt))
	# blinking, looking about
	_blink_t -= dt
	if _blink_t <= 0.0:
		_blink_t = randf_range(1.5, 4.5)
		_blink = 0.14
	_blink = maxf(_blink - dt, 0.0)
	_look_t -= dt
	if _look_t <= 0.0:
		_look_t = randf_range(0.6, 2.2)
		_look_to = Vector2(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3))
	if m and m.alive and game and game.get("cam"):
		var c := game.get("cam") as Camera3D # (it looks where you aim, now and then)
		var to := c.global_basis.inverse() * (m.aim_point - c.global_position)
		if fmod(_t, 5.0) < 3.0:
			_look_to = Vector2(clampf(to.x / maxf(-to.z, 1.0) * 2.0, -0.8, 0.8), clampf(to.y / maxf(-to.z, 1.0) * 2.0, -0.4, 0.4))
	if mood == "dizzy":
		_look_to = Vector2(cos(_t * 9.0), sin(_t * 9.0)) * 0.7
	_look = _look.lerp(_look_to, 1.0 - exp(-12.0 * dt))
	# the head on its neck: a spring, thrown by the machine's pull
	_jolt_v += (-_jolt * 140.0 - _jolt_v * 9.0) * dt
	_jolt += _jolt_v * dt
	_jolt = _jolt.limit_length(0.18)
	_ears = _ears.lerp(Vector2(-_jolt.x * 4.0, clampf(_jolt.y * 3.0 + float(_face.brow) * 0.3, -0.6, 0.8)), 1.0 - exp(-6.0 * dt))
	if _head:
		pose(_head, _face, _look, _blink, _jolt, _ears, _t)
	if m:
		var d := m.get_node_or_null("Parts")
		if d:
			for n: Node in d.find_children("Driver", "Node3D", true, false):
				pose(n as Node3D, _face, _look, _blink, _jolt * 0.5, _ears, _t)


## What's going on round it, felt.
func _sense(m: Machine, dt: float) -> void:
	var acc := (m.linear_velocity - _vel) / maxf(dt, 0.001)
	_vel = m.linear_velocity
	var local := m.global_basis.inverse() * acc
	if local.length() < 200.0: # (not a teleport)
		jolt(Vector3(-local.x * 0.0012, -local.y * 0.0008, 0.0) * dt * 60.0)
	var touching := 0
	for w in m.wheels:
		touching += int(w.contact)
	if m.global_basis.y.y < -0.2:
		feel("dizzy", 0.5)
	elif touching == 0 and m.wheels.size() > 0 and m.linear_velocity.y < -2.0:
		feel("scared", 0.4)
	elif m.health() < 0.35:
		feel("worried", 0.5)
	for t in m.tools:
		if t.cutting >= 0:
			feel("focus", 0.4)
	for h in m.hoists:
		if h.hooked() and h.hooked() is RigidBody3D and (h.hooked() as RigidBody3D).mass > 120.0:
			feel("effort", 0.3)
	var lying := Timber.lying()
	if lying > _lying + 1: # (a tree's come down)
		feel("wow", 1.6)
	_lying = lying
	if Inventory.delivered > _brought:
		if _brought > 0 or Inventory.delivered - _brought < 20:
			feel("happy", 2.0)
		_brought = Inventory.delivered
	if absf(m.speed) > 9.0 and touching > 0 and mood == "idle":
		feel("happy", 0.3)


# --- The creature ------------------------------------------------------------------------------------

static func _mat(c: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _ball(parent: Node3D, n: String, r: float, at: Vector3, mat: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 24
	s.rings = 12
	s.material = mat
	mi.mesh = s
	mi.position = at
	mi.scale = scale
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, n: String, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = at
	parent.add_child(mi)
	return mi


## TIKI, about 0.75 m tall sitting (its origin at its seat): a round fuzzy body, a big head with a pale
## face, eyes with lids and brows, a wide mouth (and a tongue), a nose, long ears, a cap and goggles.
static func creature() -> Node3D:
	var root := Node3D.new()
	root.name = "Driver"
	var fur := _mat(FUR, 0.95)
	var dark := _mat(FUR_DARK, 0.95)
	var face := _mat(FACE, 0.9)
	var white := _mat(Color(0.97, 0.96, 0.92), 0.4)
	var black := _mat(Color(0.05, 0.04, 0.04), 0.3)
	var mouth_m := _mat(Color(0.35, 0.08, 0.08), 0.7)
	_ball(root, "Body", 0.17, Vector3(0, 0.15, 0), fur, Vector3(1.0, 1.0, 0.85))
	_ball(root, "Belly", 0.12, Vector3(0, 0.13, 0.08), face, Vector3(1.0, 1.1, 0.6))
	for s in [-1.0, 1.0]:
		_ball(root, "Hand%d" % s, 0.045, Vector3(s * 0.13, 0.18, 0.15), dark)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.38, 0)
	root.add_child(head)
	_ball(head, "Skull", 0.2, Vector3.ZERO, fur, Vector3(1.12, 0.95, 1.0))
	_ball(head, "Face", 0.15, Vector3(0, -0.03, 0.08), face, Vector3(1.15, 0.9, 0.7))
	_ball(head, "Nose", 0.03, Vector3(0, 0.0, 0.205), _mat(Color(0.75, 0.35, 0.2), 0.5), Vector3(1.3, 1.0, 1.0))
	for s in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.name = "Eye%d" % s
		eye.position = Vector3(s * 0.08, 0.045, 0.15)
		head.add_child(eye)
		_ball(eye, "White", 0.06, Vector3.ZERO, white, Vector3(1.0, 1.15, 0.7))
		_ball(eye, "Pupil", 0.029, Vector3(0, 0, 0.038), black)
		_ball(eye, "Glint", 0.009, Vector3(0.012, 0.015, 0.06), _mat(Color(1, 1, 1), 0.1))
		var lid := _ball(eye, "Lid", 0.066, Vector3(0, 0.0, 0.004), fur, Vector3(1.05, 1.0, 0.75))
		lid.set_meta("s", s)
		var x1 := _box(eye, "X1", Vector3(0.07, 0.012, 0.01), Vector3(0, 0, 0.04), black)
		x1.rotation.z = 0.785
		var x2 := _box(eye, "X2", Vector3(0.07, 0.012, 0.01), Vector3(0, 0, 0.04), black)
		x2.rotation.z = -0.785
		_box(head, "Brow%d" % s, Vector3(0.075, 0.018, 0.02), Vector3(s * 0.08, 0.135, 0.19), dark)
		_ball(head, "Cheek%d" % s, 0.045, Vector3(s * 0.1, -0.05, 0.13), _mat(Color(0.95, 0.68, 0.55), 0.9))
		var ear := Node3D.new()
		ear.name = "Ear%d" % s
		ear.position = Vector3(s * 0.17, 0.08, -0.02)
		head.add_child(ear)
		_ball(ear, "Flap", 0.05, Vector3(s * 0.09, -0.05, 0), fur, Vector3(2.0, 0.6, 0.45))
		_ball(ear, "Inner", 0.035, Vector3(s * 0.095, -0.05, 0.015), _mat(Color(0.9, 0.62, 0.52), 0.9), Vector3(2.0, 0.5, 0.3))
	var mouth := _ball(head, "Mouth", 0.06, Vector3(0, -0.075, 0.17), mouth_m, Vector3(1.0, 0.25, 0.4))
	mouth.set_meta("y0", -0.075)
	_ball(head, "Tongue", 0.025, Vector3(0.02, -0.09, 0.19), _mat(Color(0.9, 0.4, 0.45), 0.6), Vector3(1.0, 0.6, 1.2))
	_ball(head, "Teeth", 0.03, Vector3(0, -0.06, 0.195), white, Vector3(1.4, 0.35, 0.4))
	# the driving cap, and goggles pushed up on it
	_ball(head, "Cap", 0.2, Vector3(0, 0.12, -0.05), _mat(CAP, 0.7), Vector3(1.12, 0.62, 1.0))
	_box(head, "Peak", Vector3(0.15, 0.012, 0.07), Vector3(0, 0.17, 0.15), _mat(CAP, 0.7))
	_box(head, "Strap", Vector3(0.43, 0.028, 0.02), Vector3(0, 0.19, 0.08), _mat(Color(0.18, 0.12, 0.08), 0.8))
	for s in [-1.0, 1.0]:
		var g := _ball(head, "Goggle%d" % s, 0.04, Vector3(s * 0.06, 0.21, 0.1), _mat(Color(0.55, 0.45, 0.3), 0.4), Vector3(1.0, 1.0, 0.5))
		_ball(g, "Glass", 0.032, Vector3(0, 0, 0.02), _mat(LENS, 0.05), Vector3(1.0, 1.0, 0.4))
	return root


## The creature `c` set to the face `f` (MOODS' numbers), its eyes on `look`, blinking `blink` (s left of
## it), its head thrown `jolt`, its ears `ears`.
static func pose(c: Node3D, f: Dictionary, look: Vector2, blink: float, jolt: Vector3, ears: Vector2, t: float) -> void:
	var head := c.get_node_or_null("Head") as Node3D
	if head == null:
		return
	var breathe := sin(t * 2.2) * 0.006
	head.position = Vector3(jolt.x, 0.38 + jolt.y * 0.5 + breathe, jolt.z)
	head.rotation = Vector3(-jolt.y * 1.2 + look.y * 0.15, look.x * 0.25, -jolt.x * 1.5 + float(f.tilt) * 0.04)
	var lid := clampf(maxf(float(f.lid), 1.0 if blink > 0.0 else 0.0), 0.0, 1.0)
	for s in [-1.0, 1.0]:
		var eye := head.get_node("Eye%d" % s) as Node3D
		var wide := 1.0 + float(f.round) * 0.25
		eye.scale = Vector3(wide, wide, 1.0)
		var pupil := eye.get_node("Pupil") as Node3D
		pupil.position = Vector3(look.x * 0.026, look.y * 0.026, 0.038)
		pupil.scale = Vector3.ONE * (1.0 - float(f.round) * 0.3)
		pupil.visible = float(f.x) < 0.5
		(eye.get_node("Glint") as Node3D).visible = float(f.x) < 0.5
		for xn: String in ["X1", "X2"]:
			(eye.get_node(xn) as Node3D).visible = float(f.x) >= 0.5
		var l := eye.get_node("Lid") as Node3D # (the lid comes down over the top: a fur cap shrinking out of sight up)
		l.position = Vector3(0, lerpf(0.09, 0.0, lid), 0.006)
		l.scale = Vector3(1.05, lerpf(0.15, 1.0, lid), 0.78)
		var brow := head.get_node("Brow%d" % s) as Node3D
		brow.position = Vector3(s * 0.08, 0.125 + float(f.brow) * 0.025 - lid * 0.01, 0.19)
		brow.rotation = Vector3(0, 0, -s * float(f.tilt) * 0.45)
		var cheek := head.get_node("Cheek%d" % s) as Node3D
		cheek.scale = Vector3.ONE * (1.0 + float(f.puff) * 0.6 + maxf(float(f.smile), 0.0) * 0.15)
		var ear := head.get_node("Ear%d" % s) as Node3D
		ear.rotation = Vector3(0, 0, s * (ears.y * 0.8 + 0.1 * sin(t * 1.3 + s)) + ears.x * 0.6)
	var mouth := head.get_node("Mouth") as Node3D
	var open := float(f.open)
	var smile := float(f.smile)
	var rnd := float(f.round)
	mouth.scale = Vector3(lerpf(1.0 + smile * 0.35, 0.55, rnd), 0.18 + open * 0.75 + rnd * 0.2, 0.4)
	mouth.position = Vector3(0, -0.075 - open * 0.02 + smile * 0.008, 0.17)
	mouth.rotation = Vector3(0, 0, 0)
	var teeth := head.get_node("Teeth") as Node3D
	teeth.visible = smile > 0.5 and open > 0.2
	var tongue := head.get_node("Tongue") as Node3D
	tongue.visible = float(f.tongue) > 0.3
	tongue.position = Vector3(0.025, -0.085, 0.17 + float(f.tongue) * 0.03)
