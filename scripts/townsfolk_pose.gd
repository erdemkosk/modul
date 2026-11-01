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
	var k := 1.0 - exp(-10.0 * delta * _ease)
	var any := false
	for key: String in KEYS:
		_now[key] = lerpf(_now[key], _want[key], k)
		any = any or absf(_now[key]) > 0.002
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
