class_name TownsfolkPose
extends SkeletonModifier3D
## The work no clip has (felling, the pick, the sickle, the saw, the hammer, the scaffold...),
## turned onto the townsman's bones over the clip playing: Villager._animate's numbers as they
## swung the old jointed figure, each a turn in the body's own frame (it faces -z):
## arm_l / arm_r raise an arm forward (negative up), el / er bend an elbow, lean bends the back
## forward, twist turns the chest, kn bends the knees. Eased in and out.
##
## ---- The API (for anyone laying moves over the townsman: combat, the daily round...) ----------
## Everything here is the body's own frame: x its right, y up, -z the way it faces; metres, radians.
##
## want(v, rate)        the numbers to move to, eased ({} back to the clip alone). Keys left out go
##                      to rest. Keys: arm_l arm_r el er lean twist kn (above), and
##                        roll   the back bent to the side (+ toward its right)
##                        hip_y  the hips let down (m, + down), the feet kept where they stand
##                        hip_z  the hips shifted back (m, +) or forward (-), the feet kept
##                        sh_l / sh_r  a shoulder raised (+, a shrug) or dropped (-)
##                        abd_l / abd_r  an arm held out from the side (+)
##                        head   the head bowed (+) or lifted (-)
##                      (kn, hip_y and hip_z bend the legs over the feet where they stand: two-bone
##                      legs, so the feet don't leave the ground.)
##                      Townsfolk.POSES holds named sets of these (Townsfolk.pose_preset(name),
##                      Townsfolk.register_pose(name, v)).
## reach(i, at, bone, w) hand i (0 left, 1 right) brought to `at` and held there (two-bone arm,
##                      the elbow kept in the plane the clip gives it): `at` a world point if
##                      `bone` is "", else an offset from that bone in the body's frame (it goes
##                      with the bone as it moves: "UpperChest", "Cargo", "Hips", "LeftLowerLeg"...).
##                      w 0..1, eased. release(i) lets go. An "occupied hand": whatever holds it.
## frame(bone)          the bone's frame in skeleton space, turned so that at rest it's the body's
##                      own (x right, y up, -z ahead): offsets given in the body's terms go through it.
## The walk, read from who it is and where it walks (Townsfolk / Villager set these):
##   age (0..1, the old stooped and short-stepped), female (a sway in the hips, a shorter step),
##   child (a skip in it), tired (0..1 the shoulders dropped, the head down), snow (0..1 deep snow:
##   the knees lifted high, the arms out, slower), mud (0..1: careful short steps, now and then a
##   slip), limp, stride (the step's length, 1 the clip's: set by Townsfolk from the above).
##   phase (0..1 through the walking clip's cycle, 0 the left heel down) is set by Townsfolk.
## lean_kick (+ forward) a lean thrown in starting off and pulled back stopping (Townsfolk).
## turn_lead (+ to its left) the chest and head turned ahead into a turn on the spot (Townsfolk).
## Sitting down and getting up (seat) go through a lean with the hands on the knees, the push up
## off them; standing up from the ground the same.

const KEYS := ["arm_l", "arm_r", "el", "er", "lean", "twist", "kn", "roll", "hip_y", "hip_z", "sh_l", "sh_r",
	"abd_l", "abd_r", "head"]
## (what the old figure stood at doing nothing: the clip's own pose is that)
const REST := {"arm_l": 0.0, "arm_r": 0.0, "el": 0.15, "er": 0.15, "lean": 0.0, "twist": 0.0, "kn": 0.05,
	"roll": 0.0, "hip_y": 0.0, "hip_z": 0.0, "sh_l": 0.0, "sh_r": 0.0, "abd_l": 0.0, "abd_r": 0.0, "head": 0.0}

var _want := {}
var _now := {}
var _ease := 1.0 ## the game's speed: the easing keeps up with it
var _bones := {}
var _rest_inv := {} ## bone -> its rest basis undone (frame())
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
## The walk (see above).
var age := 0.0
var female := false
var child := false
var tired := 0.0
var snow := 0.0
var mud := 0.0
var stride := 1.0
var phase := 0.0
var lean_kick := 0.0
var turn_lead := 0.0
var _gait_w := 0.0 ## (walking, eased: the walk's ways fade in and out with it)
var _slip_t := -1.0 ## s into a slip in the mud (-1: none)
var _slip_side := 1.0
var _kick := 0.0
var _lead := 0.0
## The hands (reach): [spec, weight wanted, weight now]; a spec is [world point] or [bone, offset].
var _reach_at: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _reach_bone: Array[String] = ["", ""]
var _reach_want: Array[float] = [0.0, 0.0]
var _reach_now: Array[float] = [0.0, 0.0]
var _knee_at: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO] ## (the knees, skeleton space, for the push up)
var _push := 0.0 ## sitting down or getting up: 0..1..0 through it


func _ready() -> void:
	for k: String in KEYS:
		_now[k] = 0.0
		_want[k] = 0.0


## The numbers to move to ({} back to the clip alone).
func want(v: Dictionary, rate: float) -> void:
	_ease = maxf(rate, 1.0)
	for k: String in KEYS:
		_want[k] = float(v.get(k, REST[k])) - float(REST[k]) if not v.is_empty() else 0.0


## Hand `i` (0 left, 1 right) brought to `at`: a world point (`bone` ""), or an offset in the body's
## frame from `bone` (frame()). `w` how far (0..1), eased in.
func reach(i: int, at: Vector3, bone := "", w := 1.0) -> void:
	_reach_at[i] = at
	_reach_bone[i] = bone
	_reach_want[i] = clampf(w, 0.0, 1.0)


func release(i: int) -> void:
	_reach_want[i] = 0.0


func reaching(i: int) -> bool:
	return _reach_want[i] > 0.0


func _bone(name: String) -> int:
	if not _bones.has(name):
		_bones[name] = get_skeleton().find_bone(name)
	return _bones[name]


## Bone `name`'s frame (skeleton space), turned so that at rest it lies as the body does.
func frame(name: String) -> Transform3D:
	var sk := get_skeleton()
	var b := _bone(name)
	if sk == null or b < 0:
		return Transform3D.IDENTITY
	if not _rest_inv.has(b):
		_rest_inv[b] = sk.get_bone_global_rest(b).basis.orthonormalized().inverse()
	var g := sk.get_bone_global_pose(b)
	return Transform3D(g.basis.orthonormalized() * (_rest_inv[b] as Basis), g.origin)


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
	_gait_w = move_toward(_gait_w, 1.0 if walking else 0.0, delta * 4.0)
	if _gait_w > 0.01 and absf(stride - 1.0) > 0.01:
		_shorten(sk, lerpf(1.0, stride, _gait_w))
	_legs(sk, delta)
	if any:
		var x := Vector3.RIGHT
		_turn(sk, "Spine", x, -_now.lean * 0.5)
		_turn(sk, "Chest", x, -_now.lean * 0.5)
		_turn(sk, "Spine", Vector3.FORWARD, _now.roll * 0.6)
		_turn(sk, "Chest", Vector3.FORWARD, _now.roll * 0.4)
		_turn(sk, "UpperChest", Vector3.UP, _now.twist)
		_turn(sk, "LeftShoulder", Vector3.FORWARD, _now.sh_l)
		_turn(sk, "RightShoulder", Vector3.FORWARD, -_now.sh_r)
		_turn(sk, "LeftUpperArm", x, -_now.arm_l)
		_turn(sk, "LeftUpperArm", Vector3.FORWARD, _now.abd_l)
		_turn(sk, "LeftLowerArm", x, _now.el)
		_turn(sk, "RightUpperArm", x, -_now.arm_r)
		_turn(sk, "RightUpperArm", Vector3.FORWARD, -_now.abd_r)
		_turn(sk, "RightLowerArm", x, _now.er)
		_turn(sk, "Head", x, _now.head)
	_gait(sk, delta)
	_overlays(sk, delta)
	_hands(sk, delta)


## The step shortened (or lengthened): each leg's swing in the clip drawn toward the leg standing
## straight under the body.
func _shorten(sk: Skeleton3D, f: float) -> void:
	for n: String in ["LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"]:
		var b := _bone(n)
		if b < 0:
			continue
		var rest := sk.get_bone_rest(b).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(b, rest.slerp(sk.get_bone_pose_rotation(b), f))


## Who it is and where it walks, in the walk: the old stooped, a woman's sway, a child's skip, the
## tired slumped, the knees lifted high through deep snow, the arms out in the mud and a slip now
## and then; and on its feet or not, the lean starting off and stopping, the chest led into a turn.
func _gait(sk: Skeleton3D, delta: float) -> void:
	var x := Vector3.RIGHT
	var fwd := Vector3.FORWARD
	var w := _gait_w
	var old := smoothstep(0.6, 1.0, age)
	# (the stoop and the slump are there standing too, less so)
	var stoop := old * (0.55 + 0.45 * w)
	if stoop > 0.01:
		_turn(sk, "Spine", x, -0.2 * stoop)
		_turn(sk, "Chest", x, -0.16 * stoop)
		_turn(sk, "LeftShoulder", fwd, -0.06 * stoop)
		_turn(sk, "RightShoulder", fwd, 0.06 * stoop)
		_turn(sk, "Neck", x, 0.16 * stoop)
		_turn(sk, "Head", x, -0.12 * stoop)
	if tired > 0.01:
		var t := tired * (0.6 + 0.4 * w)
		_turn(sk, "LeftShoulder", fwd, -0.16 * t)
		_turn(sk, "RightShoulder", fwd, 0.16 * t)
		_turn(sk, "LeftShoulder", Vector3.UP, -0.1 * t) # (rounded forward)
		_turn(sk, "RightShoulder", Vector3.UP, 0.1 * t)
		_turn(sk, "Spine", x, -0.12 * t)
		_turn(sk, "Neck", x, 0.12 * t)
		_turn(sk, "Head", x, 0.16 * t)
	_kick = lerpf(_kick, lean_kick, 1.0 - exp(-8.0 * delta))
	if absf(_kick) > 0.003:
		_turn(sk, "Spine", x, -_kick)
	_lead = lerpf(_lead, turn_lead, 1.0 - exp(-8.0 * delta))
	if absf(_lead) > 0.003:
		_turn(sk, "UpperChest", Vector3.UP, _lead * 0.5)
		_turn(sk, "Head", Vector3.UP, _lead * 0.45)
	if w < 0.01:
		_slip_t = -1.0
		return
	var ph := phase * TAU
	if female:
		# the hips roll over the foot that's down, the shoulders holding level
		var s := sin(ph) * 0.045 * w
		_turn(sk, "Hips", fwd, s)
		_turn(sk, "Spine", fwd, -s * 1.1)
		_turn(sk, "Hips", Vector3.UP, sin(ph) * 0.05 * w)
	if child:
		# a skip: a little hop off each foot
		var hb := _bone("Hips")
		if hb >= 0:
			var g := sk.get_bone_global_pose(hb)
			g.origin.y += maxf(sin(ph * 2.0), 0.0) * 0.035 * w
			sk.set_bone_global_pose(hb, g)
	# Deep snow: the swinging leg lifted high out of it (as high as the clip already lifts it, and
	# more), the arms out for the balance, the body into it.
	var deep := snow * w
	var lf := _bone("LeftFoot")
	var rf := _bone("RightFoot")
	if deep > 0.01 and lf >= 0 and rf >= 0:
		var yl := sk.get_bone_global_pose(lf).origin.y
		var yr := sk.get_bone_global_pose(rf).origin.y
		var low := minf(yl, yr)
		for i in 2:
			var lift := clampf(((yl if i == 0 else yr) - low) / 0.06, 0.0, 1.0)
			var a := deep * smoothstep(0.0, 1.0, lift) * 0.85
			var side := "Left" if i == 0 else "Right"
			_turn(sk, side + "UpperLeg", x, a)
			_turn(sk, side + "LowerLeg", x, -a * 1.5)
		_turn(sk, "Spine", x, -0.1 * deep)
		_turn(sk, "LeftUpperArm", fwd, 0.3 * deep)
		_turn(sk, "RightUpperArm", fwd, -0.3 * deep)
	# Mud: the arms a little out, and now and then a foot goes: a lurch to the side, the arms
	# thrown out, caught again.
	var wet := mud * w
	if wet > 0.01:
		_turn(sk, "LeftUpperArm", fwd, 0.12 * wet)
		_turn(sk, "RightUpperArm", fwd, -0.12 * wet)
		_turn(sk, "Spine", x, -0.05 * wet)
		if _slip_t < 0.0 and wet > 0.35 and randf() < delta * 0.12 * wet:
			_slip_t = 0.0
			_slip_side = -1.0 if randf() < 0.5 else 1.0
	if _slip_t >= 0.0:
		_slip_t += delta
		var u := _slip_t / 0.7
		if u >= 1.0:
			_slip_t = -1.0
		else:
			var e := sin(u * PI) * (1.0 - u * 0.4)
			var wob := sin(u * TAU * 2.0) * 0.4
			_turn(sk, "Hips", fwd, _slip_side * 0.08 * e)
			_turn(sk, "Spine", fwd, -_slip_side * (0.16 + wob * 0.1) * e)
			_turn(sk, "LeftUpperArm", fwd, (0.7 + wob) * e)
			_turn(sk, "RightUpperArm", fwd, -(0.7 - wob) * e)
			_turn(sk, "Spine", x, 0.1 * e) # (thrown back, catching itself)


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
		_turn(sk, "LeftShoulder", Vector3.FORWARD, -0.07 * slump)
		_turn(sk, "RightShoulder", Vector3.FORWARD, 0.07 * slump)
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
## hip, knee and ankle; the foot keeps the clip's set, flat to the body); the hips let down or
## shifted with the feet kept where they are (hip_y, hip_z, the old folk's bent knees).
func _legs(sk: Skeleton3D, delta: float) -> void:
	var was := _sit
	_sit = move_toward(_sit, 1.0 if seat >= 0.0 else 0.0, delta * (1.6 if _seat_now < 0.2 else 2.0) * _ease)
	_push = sin(_sit * PI) if absf(_sit - was) > 0.00001 else move_toward(_push, 0.0, delta * 4.0)
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
	var bend := smoothstep(0.6, 1.0, age) * 0.045 * (1.0 - _sit) # (the old: the knees never quite straight)
	# (bent knees: the hips let down and the knees solved over the feet, not the feet lifted off)
	var drop := maxf(-minf(_plant_off.x, _plant_off.y), 0.0) + maxf(float(_now.hip_y), 0.0) + bend + maxf(float(_now.kn), 0.0) * 0.1
	var shift := float(_now.hip_z)
	var s := smoothstep(0.0, 1.0, _sit)
	if s < 0.001 and drop < 0.004 and absf(shift) < 0.004 and absf(_plant_off.x) < 0.004 and absf(_plant_off.y) < 0.004:
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
	hp.origin.z += 0.05 * s + shift * (1.0 - s) # (the seat under the thighs, not the small of the back)
	# going down or coming up the weight's over the feet: the hips back, the chest forward over them
	hp.origin.z += 0.06 * _push
	sk.set_bone_global_pose(hips, hp)
	if _push > 0.01:
		_turn(sk, "Spine", Vector3.RIGHT, -0.3 * _push)
		_turn(sk, "Chest", Vector3.RIGHT, -0.2 * _push)
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
		_knee_at[i] = sk.get_bone_global_pose(lo).origin


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
	var reach_at := hip + dn * c
	var gl := sk.get_bone_global_pose(lo)
	if (ank - knee).length_squared() > 1e-6 and (reach_at - knee).length_squared() > 1e-6:
		gl.basis = Basis(Quaternion((ank - knee).normalized(), (reach_at - knee).normalized())) * gl.basis
		sk.set_bone_global_pose(lo, gl)
	var gf := sk.get_bone_global_pose(foot)
	gf.basis = foot_basis
	sk.set_bone_global_pose(foot, gf)


## The hands where they're held (reach), and going down onto a seat or up off it, onto the knees.
func _hands(sk: Skeleton3D, delta: float) -> void:
	var names := ["Left", "Right"]
	for i in 2:
		_reach_now[i] = move_toward(_reach_now[i], _reach_want[i], delta * 5.0 * _ease)
		var w := _reach_now[i]
		var goal := Vector3.INF
		if w > 0.001:
			if _reach_bone[i] == "":
				goal = sk.global_transform.affine_inverse() * _reach_at[i]
			else:
				goal = frame(_reach_bone[i]) * _reach_at[i]
		elif _push > 0.02 and seat < 0.0 or _push > 0.02 and _seat_now < 0.2:
			# getting up (or down to the ground): a hand on the knee, pushing off it (the right one
			# more, both going down to the ground)
			w = _push * (1.0 if i == 1 else (0.9 if _seat_now < 0.2 else 0.5))
			goal = _knee_at[i] + Vector3(0.03 * (1.0 if i == 1 else -1.0), 0.06, -0.06)
		if goal != Vector3.INF and w > 0.001:
			_arm(sk, names[i], goal, w)


## A two-bone arm: shoulder, elbow, wrist brought to `goal` (skeleton space) by `w`, the elbow
## kept in the plane the pose gives it (or hanging down and out).
func _arm(sk: Skeleton3D, side: String, goal: Vector3, w: float) -> void:
	var ua := _bone(side + "UpperArm")
	var la := _bone(side + "LowerArm")
	var hd := _bone(side + "Hand")
	if ua < 0 or la < 0 or hd < 0:
		return
	var sh := sk.get_bone_global_pose(ua).origin
	var el := sk.get_bone_global_pose(la).origin
	var wr := sk.get_bone_global_pose(hd).origin
	goal = wr.lerp(goal, w)
	var l1 := sh.distance_to(el)
	var l2 := el.distance_to(wr)
	var d := goal - sh
	var c := clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dn := d.normalized()
	var bend := (el - sh) - dn * (el - sh).dot(dn)
	if bend.length_squared() < 1e-6:
		bend = Vector3(0.4 if side == "Right" else -0.4, -1.0, 0.3)
		bend = bend - dn * bend.dot(dn)
	if bend.length_squared() < 1e-8:
		return
	bend = bend.normalized()
	var cos_a := clampf((l1 * l1 + c * c - l2 * l2) / (2.0 * l1 * c), -1.0, 1.0)
	var new_el := sh + (dn * cos_a + bend * sqrt(1.0 - cos_a * cos_a)) * l1
	var up := sk.get_bone_global_pose(ua)
	up.basis = Basis(Quaternion((el - sh).normalized(), (new_el - sh).normalized())) * up.basis
	sk.set_bone_global_pose(ua, up)
	el = sk.get_bone_global_pose(la).origin
	wr = sk.get_bone_global_pose(hd).origin
	var to := sh + dn * c
	if (wr - el).length_squared() > 1e-8 and (to - el).length_squared() > 1e-8:
		var lo := sk.get_bone_global_pose(la)
		lo.basis = Basis(Quaternion((wr - el).normalized(), (to - el).normalized())) * lo.basis
		sk.set_bone_global_pose(la, lo)


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
