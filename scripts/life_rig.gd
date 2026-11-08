class_name LifeRig
extends SkeletonModifier3D
## The daily round's hands and feet, laid over the townsman after everything else (TownsfolkPose,
## TownsfolkGrip): each hand brought to a point (a yoke, a shovel's haft, a neighbour's hand in the
## round dance, the brow and the shoulders for the sign of the cross), solved as a two-bone arm
## with the elbow hanging the way it's told; a foot lifted and stamped down, the hips bobbed with
## the feet kept where they stand; and the props of the work (LifePoses, LifeProps) kept on the
## body where they belong: hung from the chest, held between the two hands.
## Everything is in the skeleton's own space (metres, the body facing -z, its left -x). Set by
## LifePoses each frame; idle (inactive) when nothing's asked of it.

const CHEST := "UpperChest"

var t := 0.0 ## s of its own time (the game's: it runs fast when the game does)
## Each hand's goal (skeleton space; INF: the clip's own), whether it's given in the chest's frame
## (it goes with the body as it leans and turns), and how far toward it (eased in and out).
var goal: Array[Vector3] = [Vector3.INF, Vector3.INF]
var chest_rel: Array[bool] = [false, false]
var reach: Array[float] = [0.0, 0.0] ## 0..1 wanted
var elbow: Array[Vector3] = [Vector3(-0.6, -1.0, 0.35), Vector3(0.6, -1.0, 0.35)] ## which way each elbow points
var foot_lift := Vector2.ZERO ## m each foot is raised off where the clip has it (left, right)
var hips := Vector3.ZERO ## m the hips are moved (a bob, a dip), the feet staying put
var roll := 0.0 ## the back bent to the side (+ to the body's right)
var head_tilt := 0.0 ## the head bent down (+) or back
var head_yaw := 0.0 ## the head turned (+ to its left): a shake of the head
## (LifePoses' own: what it's doing, its props by name, those used this frame, the last beat seen)
var anim := ""
var skel: Skeleton3D ## (the body's: what the props hang in)
var props := {}
var used := {}
var prev_u := 0.0
var ease := 1.0 ## (how quick it eases: the game's speed)
## Props kept on the body: [node, bone ("" the skeleton itself), offset]: placed every frame.
var attached: Array = []
## A thing held in both hands (a crate, a bucket, a sack): kept between them, upright (null: none).
var held: Node3D
var held_off := Vector3.ZERO ## (from the hands' middle, in the chest's frame)
## Things hung from a point on the chest-frame (a yoke's buckets): [node, offset from the chest]
## each swinging as `swing` (fore and aft, side to side) says.
var hung: Array = []
var swing := Vector2.ZERO

var _w: Array[float] = [0.0, 0.0]
var _lift := Vector2.ZERO
var _hips := Vector3.ZERO
var _roll := 0.0
var _tilt := 0.0
var _yaw := 0.0
var _bones := {}
var _last_used := 0.0


func _bone(name: String) -> int:
	if not _bones.has(name):
		_bones[name] = get_skeleton().find_bone(name)
	return _bones[name]


## Nothing asked of it any more: everything let go (eased out), then idle.
func release() -> void:
	reach[0] = 0.0
	reach[1] = 0.0
	foot_lift = Vector2.ZERO
	hips = Vector3.ZERO
	roll = 0.0
	head_tilt = 0.0
	head_yaw = 0.0


## Whether it's still doing anything at all (once everything's eased out it can go idle).
func busy() -> bool:
	return _w[0] > 0.001 or _w[1] > 0.001 or reach[0] > 0.0 or reach[1] > 0.0 or _lift.length() > 0.002 \
		or foot_lift.length() > 0.0 or _hips.length() > 0.002 or hips.length() > 0.0 or absf(_roll) > 0.002 \
		or absf(_tilt) > 0.002 or absf(_yaw) > 0.002 or not attached.is_empty() or held != null or not hung.is_empty()


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	t += delta
	if not busy():
		return # (nothing asked of it: the clip's own)
	var k := 1.0 - exp(-12.0 * delta * ease)
	for i in 2:
		_w[i] = move_toward(_w[i], reach[i], delta * 3.5 * ease)
	_lift = _lift.lerp(foot_lift, 1.0 - exp(-22.0 * delta * ease))
	_hips = _hips.lerp(hips, k)
	_roll = lerpf(_roll, roll, k)
	_tilt = lerpf(_tilt, head_tilt, k)
	_yaw = lerpf(_yaw, head_yaw, k)
	_legs(sk)
	if absf(_roll) > 0.001:
		_turn(sk, "Spine", Vector3.BACK, -_roll * 0.6)
		_turn(sk, "Chest", Vector3.BACK, -_roll * 0.4)
	if absf(_tilt) > 0.001:
		_turn(sk, "Neck", Vector3.RIGHT, -_tilt * 0.4)
		_turn(sk, "Head", Vector3.RIGHT, -_tilt * 0.6)
	if absf(_yaw) > 0.001:
		_turn(sk, "Neck", Vector3.UP, _yaw * 0.4)
		_turn(sk, "Head", Vector3.UP, _yaw * 0.6)
	var cb := _bone(CHEST)
	var chest := sk.get_bone_global_pose(cb) * sk.get_bone_global_rest(cb).affine_inverse() if cb >= 0 else Transform3D.IDENTITY
	var names := ["Left", "Right"]
	for i in 2:
		if _w[i] <= 0.001 or goal[i] == Vector3.INF:
			continue
		var g := chest * goal[i] if chest_rel[i] else goal[i]
		_arm(sk, names[i], g, chest.basis * elbow[i], _w[i])
	for a: Array in attached:
		var n := a[0] as Node3D
		if not is_instance_valid(n):
			continue
		var b: String = a[1]
		var at: Transform3D = a[2]
		if b == CHEST:
			n.transform = chest * at
		elif b != "":
			var bi := _bone(b)
			if bi >= 0:
				n.transform = sk.get_bone_global_pose(bi) * at
		else:
			n.transform = at
	for h: Array in hung:
		var n := h[0] as Node3D
		if not is_instance_valid(n):
			continue
		var p: Vector3 = chest * (h[1] as Vector3)
		var yaw := atan2(-chest.basis.z.x, -chest.basis.z.z) + PI
		n.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, swing.x) * Basis(Vector3.BACK, swing.y), p)
	if held and is_instance_valid(held):
		var lh := _bone("LeftHand")
		var rh := _bone("RightHand")
		if lh >= 0 and rh >= 0:
			var gl := sk.get_bone_global_pose(lh)
			var gr := sk.get_bone_global_pose(rh)
			# (the fists' middles: a little down the fingers from the wrists)
			var mid := (gl.origin + gl.basis.y.normalized() * 0.08 + gr.origin + gr.basis.y.normalized() * 0.08) * 0.5
			var across := gr.origin - gl.origin
			across.y = 0.0
			var yaw := atan2(across.z, -across.x) if across.length() > 0.05 else 0.0
			var b := Basis(Vector3.UP, yaw + PI)
			held.transform = Transform3D(b, mid + b * held_off)


## The hips moved by `_hips` and a foot lifted by `_lift`, each leg solved back to its foot.
func _legs(sk: Skeleton3D) -> void:
	if _hips.length() < 0.002 and _lift.length() < 0.002:
		return
	var hb := _bone("Hips")
	if hb < 0:
		return
	var names := ["Left", "Right"]
	var ankle: Array[Vector3] = []
	var fb: Array[Basis] = []
	for i in 2:
		var f := _bone(names[i] + "Foot")
		var g := sk.get_bone_global_pose(f)
		ankle.append(g.origin)
		fb.append(g.basis)
	var hp := sk.get_bone_global_pose(hb)
	hp.origin += _hips
	sk.set_bone_global_pose(hb, hp)
	for i in 2:
		var lift: float = _lift[i]
		var goal_at := ankle[i] + Vector3(0, lift, -lift * 0.35)
		var foot := fb[i]
		if lift > 0.01:
			foot = Basis(Vector3.RIGHT, lift * 1.2) * foot # (the toe lifted with it, then slapped down flat)
		_leg(sk, _bone(names[i] + "UpperLeg"), _bone(names[i] + "LowerLeg"), _bone(names[i] + "Foot"), goal_at, foot)


func _leg(sk: Skeleton3D, up: int, lo: int, foot: int, goal_at: Vector3, foot_basis: Basis) -> void:
	if up < 0 or lo < 0 or foot < 0:
		return
	_chain(sk, up, lo, foot, goal_at, Vector3(0, 0.15, -1.0), 1.0)
	var gf := sk.get_bone_global_pose(foot)
	gf.basis = foot_basis
	sk.set_bone_global_pose(foot, gf)


## One arm (`side` "Left"/"Right") brought to `g`, the elbow toward `hint`, `w` of the way.
func _arm(sk: Skeleton3D, side: String, g: Vector3, hint: Vector3, w: float) -> void:
	var up := _bone(side + "UpperArm")
	var lo := _bone(side + "LowerArm")
	var hand := _bone(side + "Hand")
	if up < 0 or lo < 0 or hand < 0:
		return
	var now := sk.get_bone_global_pose(hand).origin
	_chain(sk, up, lo, hand, now.lerp(g, smoothstep(0.0, 1.0, w)), hint, 1.0)


## A two-bone chain: `up` (the root joint), `lo` (the middle), `end` brought to `goal_at`, the middle
## joint bending out toward `hint`.
func _chain(sk: Skeleton3D, up: int, lo: int, end: int, goal_at: Vector3, hint: Vector3, _w: float) -> void:
	var a := sk.get_bone_global_pose(up).origin
	var b := sk.get_bone_global_pose(lo).origin
	var c := sk.get_bone_global_pose(end).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 0.01 or l2 < 0.01:
		return
	var d := goal_at - a
	var len := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.003)
	if d.length() < 0.001:
		return
	var dn := d.normalized()
	var pole := hint - dn * hint.dot(dn)
	if pole.length_squared() < 1e-6:
		pole = (b - a) - dn * (b - a).dot(dn)
		if pole.length_squared() < 1e-6:
			return
	pole = pole.normalized()
	var cos_a := clampf((l1 * l1 + len * len - l2 * l2) / (2.0 * l1 * len), -1.0, 1.0)
	var new_b := a + (dn * cos_a + pole * sqrt(1.0 - cos_a * cos_a)) * l1
	var gu := sk.get_bone_global_pose(up)
	gu.basis = Basis(Quaternion((b - a).normalized(), (new_b - a).normalized())) * gu.basis
	sk.set_bone_global_pose(up, gu)
	b = sk.get_bone_global_pose(lo).origin
	c = sk.get_bone_global_pose(end).origin
	var reach_at := a + dn * len
	if (c - b).length_squared() > 1e-6 and (reach_at - b).length_squared() > 1e-6:
		var gl := sk.get_bone_global_pose(lo)
		gl.basis = Basis(Quaternion((c - b).normalized(), (reach_at - b).normalized())) * gl.basis
		sk.set_bone_global_pose(lo, gl)


func _turn(sk: Skeleton3D, name: String, axis: Vector3, angle: float) -> void:
	var b := _bone(name)
	if b < 0:
		return
	var g := sk.get_bone_global_pose(b)
	g.basis = Basis(axis, angle) * g.basis
	sk.set_bone_global_pose(b, g)
