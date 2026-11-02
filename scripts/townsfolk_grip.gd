class_name TownsfolkGrip
extends SkeletonModifier3D
## The second hand on a long tool's haft (a hoe, an axe, a pick, a spade, a scythe): the left arm
## re-solved each frame as a two-bone chain so the left hand comes to the haft wherever the right
## hand has swung it (after TownsfolkPose). The elbow stays in the plane the pose gave it. (After
## Mud Run's SurvivorHandIK.)

## Where the left hand goes, in the right hand bone's own frame (null-ish when nothing's held).
var hold := Transform3D.IDENTITY
var on := false

var _ua := -1
var _la := -1
var _hand := -1
var _rhand := -1
var _w := 0.0 ## eased in and out


func _ready() -> void:
	var sk := get_skeleton()
	_ua = sk.find_bone("LeftUpperArm")
	_la = sk.find_bone("LeftLowerArm")
	_hand = sk.find_bone("LeftHand")
	_rhand = sk.find_bone("RightHand")


func _process_modification_with_delta(delta: float) -> void:
	_w = move_toward(_w, 1.0 if on else 0.0, delta * 6.0)
	var sk := get_skeleton()
	if sk == null or _w <= 0.001 or _ua < 0 or _rhand < 0:
		return
	var sh := sk.get_bone_global_pose(_ua).origin
	var el := sk.get_bone_global_pose(_la).origin
	var wr := sk.get_bone_global_pose(_hand).origin
	var goal := (sk.get_bone_global_pose(_rhand) * hold).origin
	goal = wr.lerp(goal, _w)
	var l1 := sh.distance_to(el)
	var l2 := el.distance_to(wr)
	var d := goal - sh
	var c := clampf(d.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dn := d.normalized()
	var bend := (el - sh) - dn * (el - sh).dot(dn) # (the elbow's plane as posed)
	if bend.length_squared() < 1e-8:
		bend = Vector3(0, -1, 0) - dn * dn.y
	bend = bend.normalized()
	var cos_a := clampf((l1 * l1 + c * c - l2 * l2) / (2.0 * l1 * c), -1.0, 1.0)
	var new_el := sh + (dn * cos_a + bend * sqrt(1.0 - cos_a * cos_a)) * l1
	var up := sk.get_bone_global_pose(_ua)
	up.basis = Basis(Quaternion((el - sh).normalized(), (new_el - sh).normalized())) * up.basis
	sk.set_bone_global_pose(_ua, up)
	el = sk.get_bone_global_pose(_la).origin
	wr = sk.get_bone_global_pose(_hand).origin
	var reach := sh + dn * c
	var lo := sk.get_bone_global_pose(_la)
	lo.basis = Basis(Quaternion((wr - el).normalized(), (reach - el).normalized())) * lo.basis
	sk.set_bone_global_pose(_la, lo)
