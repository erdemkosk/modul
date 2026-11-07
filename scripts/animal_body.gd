class_name AnimalBody
extends Node3D
## An animal's body made in Blender (assets/animals, tools/blender/build_animals.py): its trunk, and the
## head, tail, legs (and a hen's wings) each hung from the joint it swings at, read from the model's
## "pivot_<tag>" empties. Whoever keeps the beast moves this node over the ground and calls step() with
## its speed: the legs go in the gait for that speed (a walk, a trot, a gallop or bound; a hare's hop,
## a hen's strut), each foot swept back as far as the body goes forward over it while it's planted, so
## nothing slides; the trunk pitched to the lie of the ground, so the feet stay on a slope.
##
## The coat: one material for every animal (the colours in the vertices), each beast's own coat colour
## (and its winter one) as instance parameters; what's painted to keep its colour (a white belly, a
## comb, black ear tips) isn't tinted.

const PATH := "res://assets/animals/%s.glb"

## Per kind: `leg` the hip height (m), the stride (m a full cycle) of each gait and the speeds (m/s)
## it takes up the trot and the run at, how far a shin folds lifting, how long it is nose to tail.
const SPEC := {
	"wolf": {"leg": 0.68, "walk": 1.0, "trot": 1.55, "run": 2.7, "trot_at": 1.9, "run_at": 4.6, "fold": 0.9, "len": 1.1, "graze": 0.55},
	"dog": {"leg": 0.49, "walk": 0.72, "trot": 1.1, "run": 1.9, "trot_at": 1.5, "run_at": 3.6, "fold": 0.9, "len": 0.8, "graze": 0.55},
	"deer": {"leg": 0.78, "walk": 1.1, "trot": 1.7, "run": 3.3, "trot_at": 2.0, "run_at": 4.0, "fold": 1.2, "len": 1.1, "graze": 1.15},
	"hare": {"leg": 0.15, "walk": 0.7, "trot": 0.45, "run": 1.5, "trot_at": 99.0, "run_at": 3.5, "fold": 0.6, "len": 0.4, "graze": 0.35},
	"hen": {"leg": 0.15, "walk": 0.2, "trot": 0.2, "run": 0.32, "trot_at": 99.0, "run_at": 1.6, "fold": 0.0, "len": 0.3, "graze": 1.1},
}

## The gaits: where in the cycle each foot comes down (0..1), and the share of it the foot is down.
const GAITS := {
	"walk": {"duty": 0.64, "fl": 0.25, "fr": 0.75, "hl": 0.0, "hr": 0.5, "l": 0.0, "r": 0.5},
	"trot": {"duty": 0.45, "fl": 0.0, "fr": 0.5, "hl": 0.5, "hr": 0.0, "l": 0.0, "r": 0.5},
	"run": {"duty": 0.32, "fl": 0.55, "fr": 0.62, "hl": 0.0, "hr": 0.08, "l": 0.0, "r": 0.5},
	"hop": {"duty": 0.38, "fl": 0.5, "fr": 0.56, "hl": 0.0, "hr": 0.03, "l": 0.0, "r": 0.5},
}

const SHADER := "
shader_type spatial;
render_mode diffuse_burley;

global uniform float weather_wetness;

instance uniform vec3 coat = vec3(1.0);
instance uniform vec3 coat_winter = vec3(1.0);
instance uniform float winter = 0.0;
instance uniform float flash = 0.0;

varying vec3 lp;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 tint = mix(coat, coat_winter, winter);
	vec3 c = mix(COLOR.rgb, COLOR.rgb * tint, COLOR.a);
	// (the lie of the hair: fine streaks along the body, flecks)
	float g = vnoise(lp * vec3(60.0, 60.0, 14.0)) * 0.55 + vnoise(lp * 140.0) * 0.45;
	c *= 0.88 + 0.24 * g;
	c *= mix(1.0, 0.72, weather_wetness);
	c = mix(c, vec3(0.85, 0.16, 0.12), flash * 0.75);
	ALBEDO = c;
	ROUGHNESS = 0.96;
	SPECULAR = 0.25;
	RIM = 0.3;
	RIM_TINT = 0.7;
}
"

static var _kinds := {} ## kind -> {meshes: {tag: ArrayMesh}, pivots: {tag: Vector3}}
static var _mat: ShaderMaterial

var kind := ""
var body: Node3D ## the trunk and all that hangs from it: pitched to the ground, bobbed with the gait
var head: Node3D
var tail: Node3D
var legs := {} ## "fl" ... -> the thigh's pivot
var shins := {} ## "fl" ... -> the shin's pivot, under the thigh
var wings := {} ## "l", "r" -> pivot

## What the keeper asks of it, each 0..1 unless said: the head down grazing or pecking, sat (a dog),
## reared up on its haunches (a hare), the tail wagging, the wings beating, the head turned (radians),
## lunging (a bite).
var graze := 0.0
var sit := 0.0
var rear := 0.0
var wag := 0.0
var flap := 0.0
var look := 0.0
var lunge := 0.0

var phase := 0.0
var _off := {} ## leg -> where in the cycle it comes down now (eased toward the gait's)
var _duty := 0.64
var _w := {"walk": 1.0, "trot": 0.0, "run": 0.0} ## how much each gait it's in
var _move := 0.0
var _speed := 0.0
var _pitch := 0.0
var _rest := {} ## node -> its rest position
var _t := 0.0
var _meshes: Array[MeshInstance3D] = []


## A `kind` (wolf, dog, deer, hare, hen) in its `coat` (and `winter_coat` when winter() is set);
## `antlers`: a roe buck's. `far`: m beyond which it isn't drawn.
static func make(kind_: String, coat: Color, winter_coat := Color(-1, 0, 0), antlers := false, far := 150.0) -> AnimalBody:
	var a := AnimalBody.new()
	a.kind = kind_
	a.name = kind_.capitalize()
	a._build(antlers, far)
	a.set_coat(coat, winter_coat if winter_coat.r >= 0.0 else coat)
	return a


static func _material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat


## The model's parts, each tag's pieces made into one mesh about its pivot (kept once a kind).
static func _load(kind_: String) -> Dictionary:
	if _kinds.has(kind_):
		return _kinds[kind_]
	var root := (load(PATH % kind_) as PackedScene).instantiate()
	var pivots := {}
	for n: Node in root.find_children("pivot_*", "Node3D", true, false):
		pivots[String(n.name).trim_prefix("pivot_")] = _to_root(n as Node3D, root).origin
	var by_tag := {}
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var parts := String(mi.name).split("-")
		var tag := parts[1] if parts.size() >= 3 else "body"
		if not by_tag.has(tag):
			by_tag[tag] = []
		var at: Vector3 = pivots.get(_pivot_of(tag), Vector3.ZERO)
		by_tag[tag].append([mi.mesh, Transform3D(Basis(), -at) * _to_root(mi, root)])
	root.free()
	var meshes := {}
	for tag: String in by_tag:
		meshes[tag] = _merge(by_tag[tag])
	_kinds[kind_] = {"meshes": meshes, "pivots": pivots}
	return _kinds[kind_]


static func _pivot_of(tag: String) -> String:
	return "head" if tag == "antler" else tag


static func _to_root(n: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = n
	while at != root and at is Node3D:
		xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


static func _merge(list: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	for e: Array in list:
		var m: Mesh = e[0]
		var xf: Transform3D = e[1]
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var base := verts.size()
			var vv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for k in vv.size():
				verts.append(xf * vv[k])
				normals.append((xf.basis * nn[k]).normalized())
			var cc = a[Mesh.ARRAY_COLOR]
			if cc is PackedColorArray and (cc as PackedColorArray).size() == vv.size():
				colors.append_array(cc)
			else:
				for k in vv.size():
					colors.append(Color(1, 1, 1, 0))
			var ii = a[Mesh.ARRAY_INDEX]
			if ii is PackedInt32Array and not (ii as PackedInt32Array).is_empty():
				for i in ii:
					idx.append(base + i)
			else:
				for k in vv.size():
					idx.append(base + k)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


func _build(antlers: bool, far: float) -> void:
	var d := _load(kind)
	var meshes: Dictionary = d.meshes
	var pivots: Dictionary = d.pivots
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	var nodes := {"body": body}
	# the joints: the shins under their thighs, all else under the trunk
	var order: Array = pivots.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return not a.begins_with("shin") and b.begins_with("shin"))
	for tag: String in order:
		var p := Node3D.new()
		p.name = tag
		var parent: Node3D = body
		var at: Vector3 = pivots[tag]
		if tag.begins_with("shin_") and nodes.has("leg_" + tag.substr(5)):
			parent = nodes["leg_" + tag.substr(5)]
			at -= pivots["leg_" + tag.substr(5)]
		p.position = at
		parent.add_child(p)
		_rest[p] = at
		nodes[tag] = p
		if tag.begins_with("leg_"):
			legs[tag.substr(4)] = p
		elif tag.begins_with("shin_"):
			shins[tag.substr(5)] = p
		elif tag.begins_with("wing_"):
			wings[tag.substr(5)] = p
	head = nodes.get("head")
	tail = nodes.get("tail")
	for tag: String in meshes:
		if tag == "antler" and not antlers:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[tag]
		mi.material_override = _material()
		mi.visibility_range_end = far
		mi.visibility_range_end_margin = far * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if kind in ["hen", "hare"] and tag != "body":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(nodes.get(_pivot_of(tag), body) as Node3D).add_child(mi)
		_meshes.append(mi)
	_rest[body] = Vector3.ZERO
	for k: String in legs:
		_off[k] = float(GAITS.walk.get(k, 0.0))
	phase = randf()


## Its coat, and the one it turns to in winter (as they look: sRGB).
func set_coat(coat: Color, winter_coat: Color) -> void:
	coat = coat.srgb_to_linear() # (given as one sees it; the vertices' colours are linear)
	winter_coat = winter_coat.srgb_to_linear()
	for mi in _meshes:
		mi.set_instance_shader_parameter("coat", Vector3(coat.r, coat.g, coat.b))
		mi.set_instance_shader_parameter("coat_winter", Vector3(winter_coat.r, winter_coat.g, winter_coat.b))


var _winter := -1.0
## How far into its winter coat (0..1).
func set_winter(w: float) -> void:
	if absf(w - _winter) < 0.01:
		return
	_winter = w
	for mi in _meshes:
		mi.set_instance_shader_parameter("winter", w)


var _flash := 0.0
## Struck: a red flash on it (0..1).
func set_flash(f: float) -> void:
	if f == _flash:
		return
	_flash = f
	for mi in _meshes:
		mi.set_instance_shader_parameter("flash", f)


## The trunk pitched to the ground under it: `ground` gives the height at a point (a Vector3).
func fit_ground(ground: Callable, dt: float) -> void:
	var half: float = SPEC[kind].len * 0.5
	var f := global_transform * Vector3(0, 0, -half)
	var b := global_transform * Vector3(0, 0, half)
	var want := clampf(atan2(float(ground.call(f)) - float(ground.call(b)), half * 2.0), -0.5, 0.5)
	_pitch = lerpf(_pitch, want, 1.0 - exp(-8.0 * dt))


## One frame of it going at `speed` m/s (0: standing).
func step(dt: float, speed: float) -> void:
	_t += dt
	var sp: Dictionary = SPEC[kind]
	_speed = speed
	var g := "walk"
	if kind == "hare":
		g = "run" if speed >= float(sp.run_at) * 0.6 else "walk"
	elif speed >= float(sp.run_at):
		g = "run"
	elif speed >= float(sp.trot_at):
		g = "trot"
	for k: String in _w:
		_w[k] = move_toward(float(_w[k]), 1.0 if k == g else 0.0, dt * 3.0)
	var stride: float = float(sp.walk) * _w.walk + float(sp.trot) * _w.trot + float(sp.run) * _w.run
	var gait: Dictionary = GAITS["hop" if kind == "hare" else g]
	phase = fposmod(phase + speed * dt / maxf(stride, 0.05), 1.0)
	_move = move_toward(_move, 1.0 if speed > 0.06 else 0.0, dt * 3.0)
	_duty = lerpf(_duty, float(gait.duty), 1.0 - exp(-4.0 * dt))
	var leg_len: float = sp.leg
	var amp := asin(clampf(stride * _duty / (2.0 * leg_len), 0.0, 0.8))
	var fold: float = sp.fold
	var run_w: float = _w.run
	# the trunk: bobbing with the footfalls, rocking at a gallop, arcing through a hop
	var bob := 0.0
	var rock := 0.0
	var tau_ph := TAU * phase
	if kind == "hare":
		var h := clampf(stride * speed * 0.03, 0.03, 0.22)
		bob = maxf(sin(tau_ph + 0.6), 0.0) * h * _move
		rock = -sin(tau_ph + 0.6) * 0.22 * _move
	elif kind == "hen":
		bob = absf(sin(tau_ph)) * 0.012 * _move
	else:
		bob = (cos(tau_ph * 2.0) * 0.012 * _w.walk + absf(sin(tau_ph * 2.0)) * 0.035 * _w.trot
			+ maxf(sin(tau_ph + 1.0), 0.0) * 0.1 * run_w) * leg_len * _move
		rock = sin(tau_ph + 2.0) * 0.1 * run_w * _move
	var sit_pitch := sit * 0.55 + rear * 0.75
	body.rotation.x = _pitch + rock + sit_pitch
	body.position = Vector3(0, bob - sit * leg_len * 0.06 + rear * leg_len * 0.15, -lunge * leg_len * 0.35)
	# the legs
	for k: String in legs:
		var target := float(gait.get(k, 0.0))
		var o := float(_off[k])
		o += wrapf(target - o, -0.5, 0.5) * minf(dt * 3.0, 1.0)
		_off[k] = o
		var u := fposmod(phase + o, 1.0)
		var th: float
		var lift: float
		if u < _duty:
			th = lerpf(amp, -amp, u / _duty)
			lift = 0.0
		else:
			var s := (u - _duty) / (1.0 - _duty)
			th = lerpf(-amp, amp, smoothstep(0.0, 1.0, s))
			lift = sin(PI * s)
		var front := k.begins_with("f")
		var thigh := th * _move - (body.rotation.x)
		var shin := lift * fold * _move * (-1.0 if front or kind == "hare" else 1.0)
		if kind == "hare" and not front:
			thigh = th * 0.6 * _move - body.rotation.x * 0.4
		if sit > 0.0 and not front:
			thigh = lerpf(thigh, 0.75, sit)
			shin = lerpf(shin, -1.25, sit)
		if rear > 0.0:
			# (up on its haunches: the forepaws hung under the chest, the long hind feet flat on the ground)
			thigh = lerpf(thigh, -body.rotation.x + 0.25 if front else 0.0, rear)
			if not front:
				shin = lerpf(shin, -body.rotation.x, rear)
		(legs[k] as Node3D).rotation.x = thigh
		if shins.has(k):
			(shins[k] as Node3D).rotation.x = shin
	# the head: nodding with the walk, down to graze or peck, turned to look
	if head:
		var nod := sin(tau_ph * 2.0) * 0.05 * _move * (1.0 - run_w)
		var down := graze * float(sp.graze)
		if kind == "hen":
			var bob_h := sin(tau_ph * 2.0) * 0.025 * _move # (a hen's head thrust forward and drawn back, step by step)
			head.position = (_rest[head] as Vector3) + Vector3(0, 0, -bob_h)
		head.rotation = Vector3(-down + nod - rock * 0.5 - sit_pitch * 0.6 + run_w * 0.15 * _move, look, 0)
	if tail:
		var swing := sin(_t * (14.0 if wag > 0.5 else 6.0)) * (0.15 + wag * 0.5)
		var lifted := -run_w * _move * 0.7 if kind == "wolf" or kind == "deer" else 0.0
		tail.rotation = Vector3(lifted + sin(tau_ph * 2.0) * 0.08 * _move, swing, 0)
	for k: String in wings:
		var beat := (sin(_t * 32.0) * 0.5 + 0.6) * flap
		(wings[k] as Node3D).rotation.z = beat * (-1.0 if k == "l" else 1.0)
