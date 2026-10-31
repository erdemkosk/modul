class_name Mascot
extends CanvasLayer
## Budak Usta, who drives: a stocky bearded woodsman in a green wool hood, his felling axe across his
## back (a dwarf's build: four heads tall, 0.6 m seated, which is what a 1 m cab on half-metre cells
## fits). He sits in your machine's cab (`creature()`, put there by Machine for every cab: the other
## side's are driven by his kind too), his hands on the wheel, and his face is at the bottom left of the
## screen, live: he blinks and looks about, looks where you aim, his head is thrown about by the
## machine's pull (as it brakes, turns, lands). And he feels what happens (`mood`, each held a while):
##   hurt      a knock or a hit: eyes screwed shut, a grimace, his head jolts
##   scared    in the air, a part torn off, a giant near: eyes wide, brows up, mouth open
##   dizzy     on his back: eyes rolling
##   happy     going well (fast on good ground), wood brought home: a grin under the moustache
##   focus     sawing: brows down, eyes narrowed, lips pressed
##   effort    a load on the crane: cheeks puffed, eyes squeezed half
##   wow       a tree coming down: eyes and mouth round
##   worried   badly hurt: brows up and in, the moustache down
##   dead      his machine gone: eyes shut, head fallen to one side
## The model's moving parts (brows, lids, irises, cheeks, the moustache's halves, the mouth, the jaw
## with the beard on it) are moved by a handful of numbers (`_face`) eased toward the mood's every frame.

const PORTRAIT := Vector2i(210, 210)
const NAME := "BUDAK USTA"

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
	_cam.fov = PORTRAIT_FOV
	_vp.add_child(_cam)
	_cam.transform = Transform3D(Basis.looking_at(PORTRAIT_LOOK - PORTRAIT_AT), PORTRAIT_AT)
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


# --- The man ----------------------------------------------------------------------------------------

const MODEL := "res://assets/mascot/budak.glb"
## The portrait's camera: on his face, a little from his left, the beard and the hood's edge in.
const PORTRAIT_FOV := 30.0
const PORTRAIT_AT := Vector3(0.1, 0.5, 0.7)
const PORTRAIT_LOOK := Vector3(0.0, 0.435, 0.0)


## Budak Usta, seated (his origin where he sits; he faces +Z): the model (tools/blender/build_mascot.py,
## assets/mascot/budak.glb) in a node called Driver, his face's moving parts noted where they rest.
static func creature() -> Node3D:
	var root := Node3D.new()
	root.name = "Driver"
	var m := (load(MODEL) as PackedScene).instantiate() as Node3D
	PaintedLook.apply(m)
	root.add_child(m)
	for n: String in ["Head", "Jaw", "Mouth", "TeethTop", "EyeL", "EyeR", "IrisL", "IrisR", "LidL", "LidR", "BrowL", "BrowR",
			"CheekL", "CheekR", "StacheL", "StacheR"]:
		var part := m.find_child(n, true, false) as Node3D
		if part:
			part.set_meta("rest", part.transform)
			root.set_meta(n, part)
	return root


## The man `c` set to the face `f` (MOODS' numbers), his eyes on `look`, blinking `blink` (s left of it),
## his head thrown `jolt` (`ears`: unused, his are under the hood).
static func pose(c: Node3D, f: Dictionary, look: Vector2, blink: float, jolt: Vector3, _ears: Vector2, t: float) -> void:
	if not c.has_meta("Head"):
		return
	var head := c.get_meta("Head") as Node3D
	var rest: Transform3D = head.get_meta("rest")
	var breathe := sin(t * 2.0) * 0.003
	var dead := float(f.x)
	head.transform = Transform3D(Basis.from_euler(Vector3(-jolt.y * 1.0 + look.y * 0.12 + dead * 0.35, look.x * 0.3,
		-jolt.x * 1.2 + float(f.tilt) * 0.03 + dead * 0.25)), rest.origin + Vector3(jolt.x, jolt.y * 0.4 + breathe, jolt.z) * 0.4)
	var lid := clampf(maxf(maxf(float(f.lid), 1.0 if blink > 0.0 else 0.0), dead), 0.0, 1.0)
	for k in 2:
		var s := -1.0 if k == 0 else 1.0
		var n := "L" if k == 0 else "R"
		var eye := c.get_meta("Eye" + n) as Node3D
		var wide := 1.0 + float(f.round) * 0.2
		eye.scale = Vector3(wide, wide, 1.0)
		var iris := c.get_meta("Iris" + n) as Node3D
		var ir: Transform3D = iris.get_meta("rest")
		iris.position = ir.origin + Vector3(look.x * 0.006, look.y * 0.005, 0.0)
		var l := c.get_meta("Lid" + n) as Node3D # (the upper lid: up under the brow, down over the eye)
		var lr: Transform3D = l.get_meta("rest")
		l.position = lr.origin + Vector3(0.0, lerpf(0.013, 0.0, lid), lerpf(-0.002, 0.0, lid))
		l.scale = Vector3(1.0, lerpf(0.45, 1.0, lid), 1.0)
		var brow := c.get_meta("Brow" + n) as Node3D
		var br: Transform3D = brow.get_meta("rest")
		brow.position = br.origin + Vector3(0.0, float(f.brow) * 0.009 - lid * 0.003, 0.0)
		brow.rotation = br.basis.get_euler() + Vector3(0.0, 0.0, -s * float(f.tilt) * 0.4)
		var cheek := c.get_meta("Cheek" + n) as Node3D
		var cr: Transform3D = cheek.get_meta("rest")
		cheek.scale = cr.basis.get_scale() * (1.0 + float(f.puff) * 0.5 + maxf(float(f.smile), 0.0) * 0.12)
		cheek.position = cr.origin + Vector3(0.0, maxf(float(f.smile), 0.0) * 0.004, float(f.puff) * 0.006)
		var st := c.get_meta("Stache" + n) as Node3D
		var sr: Transform3D = st.get_meta("rest")
		st.rotation = sr.basis.get_euler() + Vector3(0.0, 0.0, s * float(f.smile) * 0.4)
	var open := float(f.open)
	var smile := float(f.smile)
	var rnd := float(f.round)
	var mouth := c.get_meta("Mouth") as Node3D
	var mr: Transform3D = mouth.get_meta("rest")
	mouth.scale = mr.basis.get_scale() * Vector3(lerpf(1.0 + smile * 0.3, 0.6, rnd), 0.35 + open * 1.5 + rnd * 0.5, 1.0)
	mouth.position = mr.origin + Vector3(0.0, -open * 0.006, 0.0)
	var jaw := c.get_meta("Jaw") as Node3D
	var jr: Transform3D = jaw.get_meta("rest")
	jaw.transform = Transform3D(Basis(Vector3.RIGHT, open * 0.16 + rnd * 0.06), jr.origin)
	(c.get_meta("TeethTop") as Node3D).visible = smile > 0.5 and open > 0.2
