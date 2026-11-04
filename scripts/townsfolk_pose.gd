class_name TownsfolkPose
extends SkeletonModifier3D
## The work no clip has (felling, the pick, the sickle, the saw, the hammer, the scaffold...),
## turned onto the townsman's bones over the clip playing: Villager._animate's numbers as they
## swung the old jointed figure, each a turn in the body's own frame (it faces -z):
## arm_l / arm_r raise an arm forward (negative up), el / er bend an elbow, lean bends the back
## forward, twist turns the chest, kn bends the knees. Eased in and out.

const KEYS := ["arm_l", "arm_r", "el", "er", "lean", "twist", "kn"]
## (what the old figure stood at doing nothing: the clip's own pose is that)
const REST := {"arm_l": 0.0, "arm_r": 0.0, "el": 0.15, "er": 0.15, "lean": 0.0, "twist": 0.0, "kn": 0.05}

var _want := {}
var _now := {}
var _ease := 1.0 ## the game's speed: the easing keeps up with it
var _bones := {}
var lost: Array[String] = [] ## bones gone (a lost arm or leg): shrunk to nothing, whatever the clip does
## Laid over whatever the body's doing (Villager sets them each frame):
var look_at := Vector3.INF ## a point to turn the head to (INF: straight ahead)
var limp := 0.0 ## a hurt or lost leg: the hips dip and the body rolls over the good one
var shiver := 0.0 ## cold to the bone: a shudder through the shoulders
var slump := 0.0 ## low: the back bent, the head down
var walking := false
var nod := 0.0 ## listening: a nod now and then
var bow := 0.0 ## the head bowed and the shoulders a little forward (at prayer)
var _look := Vector2.ZERO ## the head's turn now (yaw, pitch)
var _t := 0.0
var _nod_at := 0.0 ## (when the next nod starts)
## Sat down (Townsfolk.sit, a villager at its ease): the hips let down onto a seat `seat` m over
## the ground under the feet (0: on the ground itself, the knees drawn up), and each leg solved as
## a two-bone chain to its foot set flat on the ground in front. Only the hips and legs: whatever
## clip plays carries on above them (talking, eating, a pipe, a rifle across the knees...).
var seat := -1.0 ## (-1: on its feet)
var _sit := 0.0 ## eased in and out
var _seat_now := 0.0
## Feet on uneven ground: `ground` says where the ground is under a world point; each foot is set on
## it and the hips let down as far as the lower foot needs. `plant` fades it in and out (off far
## from the view, on a floor or a porch, where the ground under it isn't the land's).
var ground := Callable()
var plant := 0.0
var _plant_off := Vector2.ZERO ## the left and right foot's lift (+) or drop (-), skeleton m


func _ready() -> void:
	for k: String in KEYS:
		_now[k] = 0.0
		_want[k] = 0.0


## The numbers to move to ({} back to the clip alone).
func want(v: Dictionary, rate: float) -> void:
	_ease = maxf(rate, 1.0)
	for k: String in KEYS:
		_want[k] = float(v.get(k, REST[k])) - float(REST[k]) if not v.is_empty() else 0.0


func _bone(name: String) -> int:
	if not _bones.has(name):
		_bones[name] = get_skeleton().find_bone(name)
	return _bones[name]


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b: String in lost:
		var i := _bone(b)
		if i >= 0:
			sk.set_bone_pose_scale(i, Vector3.ONE * 0.001)
	var k := 1.0 - exp(-10.0 * delta * _ease)
	var any := false
	for key: String in KEYS:
		_now[key] = lerpf(_now[key], _want[key], k)
		any = any or absf(_now[key]) > 0.002
	_t += delta
	_legs(sk, delta)
	_overlays(sk, delta)
	if not any:
		return
	var x := Vector3.RIGHT
	_turn(sk, "Spine", x, -_now.lean * 0.5)
	_turn(sk, "Chest", x, -_now.lean * 0.5)
	_turn(sk, "UpperChest", Vector3.UP, _now.twist)
	_turn(sk, "LeftUpperArm", x, -_now.arm_l)
	_turn(sk, "LeftLowerArm", x, _now.el)
	_turn(sk, "RightUpperArm", x, -_now.arm_r)
	_turn(sk, "RightLowerArm", x, _now.er)
	for side in ["Left", "Right"]:
		_turn(sk, side + "UpperLeg", x, _now.kn * 0.5)
		_turn(sk, side + "LowerLeg", x, -_now.kn)


## The head turned to what it's looking at, the limp, the shiver, the slump.
func _overlays(sk: Skeleton3D, delta: float) -> void:
	var want := Vector2.ZERO
	if look_at != Vector3.INF:
		var d := sk.global_transform.affine_inverse() * look_at
		var hb := _bone("Head")
		if hb >= 0:
			d -= sk.get_bone_global_pose(hb).origin
		var flat := Vector2(d.x, d.z).length()
		if flat > 0.05:
			want = Vector2(clampf(atan2(-d.x, -d.z), -1.1, 1.1), clampf(atan2(d.y, flat), -0.45, 0.35))
			if absf(atan2(-d.x, -d.z)) > 1.9:
				want = Vector2.ZERO # (behind it: it doesn't screw its head round)
	_look = _look.lerp(want, 1.0 - exp(-4.0 * delta))
	var x := Vector3.RIGHT
	if _look.length() > 0.01:
		_turn(sk, "Neck", Vector3.UP, _look.x * 0.4)
		_turn(sk, "Head", Vector3.UP, _look.x * 0.6)
		_turn(sk, "Head", x, _look.y)
	if limp > 0.01 and walking:
		var ph := sin(_t * 6.5)
		_turn(sk, "Hips", Vector3.BACK, ph * 0.09 * limp)
		_turn(sk, "Spine", Vector3.BACK, -ph * 0.06 * limp)
		_turn(sk, "Spine", x, -0.08 * limp)
	if shiver > 0.01:
		_turn(sk, "UpperChest", Vector3.UP, sin(_t * 38.0) * 0.025 * shiver)
		_turn(sk, "Neck", x, 0.12 * shiver) # (the chin tucked into the collar)
	if slump > 0.01:
		_turn(sk, "Spine", x, -0.12 * slump)
		_turn(sk, "Neck", x, 0.2 * slump)
	if nod > 0.01:
		# a nod every few seconds, as one does listening: down, and up again
		if _t > _nod_at + 0.7:
			_nod_at = _t + randf_range(1.6, 4.2)
		var u := clampf((_t - _nod_at) / 0.7, 0.0, 1.0)
		if u > 0.0 and u < 1.0:
			_turn(sk, "Head", x, sin(u * PI) * 0.26 * nod)
	if bow > 0.01:
		_turn(sk, "UpperChest", x, -0.12 * bow)
		_turn(sk, "Neck", x, 0.3 * bow)
		_turn(sk, "Head", x, 0.25 * bow)


## The hips and legs: let down onto a seat, or a foot set on a slope (a two-bone chain each,
## hip, knee and ankle; the foot keeps the clip's set, flat to the body).
func _legs(sk: Skeleton3D, delta: float) -> void:
	_sit = move_toward(_sit, 1.0 if seat >= 0.0 else 0.0, delta * 2.4 * _ease)
	if seat >= 0.0:
		_seat_now = seat
	var hips := _bone("Hips")
	if hips < 0:
		return
	var inv := 1.0 / maxf(sk.global_basis.get_scale().y, 0.01) # (world m into the skeleton's)
	var want := Vector2.ZERO
	var names := ["Left", "Right"]
	if plant > 0.01 and ground.is_valid() and _sit < 0.98:
		var xf := sk.global_transform
		for i in 2:
			var f := _bone(names[i] + "Foot")
			if f < 0:
				continue
			var at := xf * sk.get_bone_global_pose(f).origin
			want[i] = clampf((float(ground.call(at)) - xf.origin.y) * inv, -0.3, 0.3) * plant
	_plant_off = _plant_off.lerp(want, 1.0 - exp(-12.0 * delta))
	var drop := maxf(-minf(_plant_off.x, _plant_off.y), 0.0)
	var s := smoothstep(0.0, 1.0, _sit)
	if s < 0.001 and drop < 0.004 and absf(_plant_off.x) < 0.004 and absf(_plant_off.y) < 0.004:
		return
	# the clip's ankles and feet, before anything's moved
	var ankle: Array[Vector3] = []
	var foot_basis: Array[Basis] = []
	for i in 2:
		var f := _bone(names[i] + "Foot")
		var g := sk.get_bone_global_pose(f) if f >= 0 else Transform3D.IDENTITY
		ankle.append(g.origin)
		foot_basis.append(g.basis)
	var hp := sk.get_bone_global_pose(hips)
	var stand_y := hp.origin.y - drop
	var low := _seat_now < 0.2 # (on the ground: the knees drawn up, the feet further out)
	var sit_y := _seat_now * inv + (0.2 if low else 0.11)
	hp.origin.y = lerpf(stand_y, sit_y, s)
	hp.origin.z += 0.05 * s # (the seat under the thighs, not the small of the back)
	sk.set_bone_global_pose(hips, hp)
	for i in 2:
		var up := _bone(names[i] + "UpperLeg")
		var lo := _bone(names[i] + "LowerLeg")
		var f := _bone(names[i] + "Foot")
		if up < 0 or lo < 0 or f < 0:
			continue
		var side := -1.0 if i == 0 else 1.0
		var stand := ankle[i] + Vector3(0, _plant_off[i], 0)
		var sat := Vector3(side * (0.17 if low else 0.13), 0.1, -0.56 if low else -0.44)
		_leg(sk, up, lo, f, stand.lerp(sat, s), s, foot_basis[i])


## One leg: hip `up`, knee `lo`, ankle `foot` brought to `goal` (skeleton space), the knee bending
## forward (up and forward when sat), the foot left as the clip set it.
func _leg(sk: Skeleton3D, up: int, lo: int, foot: int, goal: Vector3, sat: float, foot_basis: Basis) -> void:
	var hip := sk.get_bone_global_pose(up).origin
	var knee := sk.get_bone_global_pose(lo).origin
	var ank := sk.get_bone_global_pose(foot).origin
	var l1 := hip.distance_to(knee)
	var l2 := knee.distance_to(ank)
	var d := goal - hip
	var c := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.002)
	var dn := d.normalized()
	var pole := (knee - hip) - dn * (knee - hip).dot(dn) # (the knee's way as the clip has it)
	var fwd := Vector3(0, 0.6 * sat, -1.0)
	fwd = fwd - dn * fwd.dot(dn)
	var w := sat if pole.length_squared() >= 0.0004 else 1.0 # (a leg straight as the clip has it: forward)
	pole = pole.normalized().lerp(fwd.normalized(), w)
	if pole.length_squared() < 1e-6:
		return
	pole = pole.normalized()
	var cos_a := clampf((l1 * l1 + c * c - l2 * l2) / (2.0 * l1 * c), -1.0, 1.0)
	var new_knee := hip + (dn * cos_a + pole * sqrt(1.0 - cos_a * cos_a)) * l1
	var g := sk.get_bone_global_pose(up)
	g.basis = Basis(Quaternion((knee - hip).normalized(), (new_knee - hip).normalized())) * g.basis
	sk.set_bone_global_pose(up, g)
	knee = sk.get_bone_global_pose(lo).origin
	ank = sk.get_bone_global_pose(foot).origin
	var reach := hip + dn * c
	var gl := sk.get_bone_global_pose(lo)
	if (ank - knee).length_squared() > 1e-6 and (reach - knee).length_squared() > 1e-6:
		gl.basis = Basis(Quaternion((ank - knee).normalized(), (reach - knee).normalized())) * gl.basis
		sk.set_bone_global_pose(lo, gl)
	var gf := sk.get_bone_global_pose(foot)
	gf.basis = foot_basis
	sk.set_bone_global_pose(foot, gf)


## Bone `name` turned by `angle` about `axis` (in the body's frame), at its joint.
func _turn(sk: Skeleton3D, name: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.001:
		return
	var b := _bone(name)
	if b < 0:
		return
	var g := sk.get_bone_global_pose(b)
	g.basis = Basis(axis, angle) * g.basis
	sk.set_bone_global_pose(b, g)
