class_name LifePoses
extends RefCounted
## How the townsfolk move at the daily round, the work scenes and the evenings (what LifeScenes
## and Village set them to): water fetched home on the yoke, snow shovelled off the line and from
## before the door, the feet stamped and the coat brushed at the door, crates and pails passed hand
## to hand down a line (from a wagon, from a well to a fire), a wave at the train, an embrace and a
## handshake, an argument with the hands, the pot stirred over a yard fire, linen scrubbed at the
## river and hung on the line, a doorstep swept, the round dance (khorovod) on the square with the
## garmon or the balalaika and the clapping, the sign of the cross at a grave (right to left, as
## the Orthodox make it), snowballs, the sled, a hen chased.
## Each is a clip under it (a walk, the stand, the kneel) and over it the TownsfolkPose numbers for
## the back and knees, and LifeRig's hands (on the props: LifeProps) and feet. All in the body's
## own frame: metres, facing -z, its left -x; the shoulders at about (±0.18, 1.4, 0), the hips 0.97.
## Cheap: a handful of sums a frame for those doing any of it, nothing at all for the rest.

## The moves this knows (Villager._anim, or a step's "life").
const ANIMS := ["yoke", "shovel", "stamp", "pass", "wave", "embrace", "handshake", "argue", "argue_listen",
	"stir", "scrub", "hang", "sweep", "dance", "garmon", "balalaika", "clap", "cross", "kneel_cross", "mourn",
	"snowball", "sled_pull", "sled_ride", "grab", "hen", "basket", "set_down", "pail_walk"]
## The chain's beat: s a piece takes from one pair of hands to the next (LifeScenes keeps the line).
const PASS_T := 2.0
## When, through its beat, a member of the chain holds the piece (from taking it to handing it on).
const PASS_HOLD := 0.62
## The music's beat (s): the dance's stamps, the clapping, the player's foot.
const BEAT := 0.5


## The body's LifeRig (made the first time, after its other modifiers, so it has the last word).
static func rig_of(body: Townsfolk) -> LifeRig:
	if body.has_meta("life_rig"):
		var r: Variant = body.get_meta("life_rig")
		if is_instance_valid(r):
			return r
	var rig := LifeRig.new()
	rig.name = "LifeRig"
	rig.skel = body.skeleton
	body.skeleton.add_child(rig)
	body.set_meta("life_rig", rig)
	return rig


## Villager._animate's hook: if what `v` is doing is one of these, its body is moved here (true);
## else false and Townsfolk.drive does it (and anything left of these is let go).
static func drive(v: Villager, walking: bool) -> bool:
	var body := v._body
	if body == null:
		return false
	var step: Dictionary = v.plan[0] if not v.plan.is_empty() else {}
	var anim := _anim_of(v, walking, step)
	if anim == "":
		if body.has_meta("life_rig"):
			stop(body)
		return false
	var life: Variant = step.get("life", null)
	var k := {
		"walking": walking, "speed": v._speed_now, "seat": v.seat, "seed": v.look_seed % 97 + v.get_instance_id() % 13,
		"beat": float(v.village.clock), "child": v.is_child, "female": v.female, "life": life if life is Dictionary else {},
		"v": v,
	}
	play(body, anim, k, v._rate())
	return true


static func _anim_of(v: Villager, walking: bool, step: Dictionary) -> String:
	var life: Variant = step.get("life", null)
	if walking or str(step.get("t", "")) == "go":
		if life is String and str(life) in ANIMS:
			return str(life)
		if life is Dictionary and str((life as Dictionary).get("walk", "")) in ANIMS:
			return str(life.walk)
		return ""
	if v._anim in ANIMS:
		return v._anim
	if v._anim in ["chat", "listen"] and step.has("talk") and str((step.talk as Dictionary).get("mood", "")) == "argue":
		return "argue" if v._anim == "chat" else "argue_listen"
	if v._anim == "idle" and v.job == "Cenazede":
		return "mourn"
	return ""


## Let go of whatever it was doing: the hands and feet eased back to the clip, the props put away.
static func stop(body: Townsfolk) -> void:
	if not body.has_meta("life_rig"):
		return
	var r: Variant = body.get_meta("life_rig")
	if not is_instance_valid(r):
		return
	var rig := r as LifeRig
	if rig.anim == "":
		return
	rig.anim = ""
	rig.release()
	rig.attached.clear()
	rig.hung.clear()
	rig.held = null
	for p: Node3D in rig.props.values():
		p.visible = false
	body.rotation.y = 0.0


## One frame of `anim` on `body`: `k` says how (walking, speed, beat, seed, the scene's own...),
## `rate` the game's speed.
static func play(body: Townsfolk, anim: String, k: Dictionary, rate: float) -> void:
	if body._lying or body._dead or Time.get_ticks_msec() < body._flinch_t:
		return
	var rig := rig_of(body)
	rig.ease = maxf(rate, 1.0)
	if rig.anim != anim:
		rig.anim = anim
		rig.prev_u = 0.0
	rig.used.clear()
	rig.attached.clear()
	rig.hung.clear()
	rig.held = null
	rig.reach[0] = 0.0
	rig.reach[1] = 0.0
	rig.foot_lift = Vector2.ZERO
	rig.hips = Vector3.ZERO
	rig.roll = 0.0
	rig.head_tilt = 0.0
	rig.head_yaw = 0.0
	var o := {"clip": "Idle", "pace": rate, "pose": {}, "nod": 0.0, "bow": 0.0, "spin": 0.0}
	var t := rig.t + float(k.get("seed", 0)) * 0.37
	match anim:
		"yoke": _yoke(rig, k, o, t)
		"pail_walk": _pail_walk(rig, k, o, t)
		"basket": _basket_walk(rig, k, o, t)
		"set_down": _set_down(rig, k, o, t)
		"shovel": _shovel(rig, k, o, t)
		"stamp": _stamp(rig, k, o, t)
		"pass": _pass(rig, k, o, body)
		"wave": _wave(rig, k, o, t)
		"embrace": _embrace(rig, k, o, t)
		"handshake": _handshake(rig, k, o, t)
		"argue": _argue(rig, k, o, t)
		"argue_listen": _argue_listen(rig, k, o, t)
		"stir": _stir(rig, k, o, t)
		"scrub": _scrub(rig, k, o, t)
		"hang": _hang(rig, k, o, t)
		"sweep": _sweep(rig, k, o, t)
		"dance": _dance(rig, k, o, body)
		"garmon": _garmon(rig, k, o, t)
		"balalaika": _balalaika(rig, k, o, t)
		"clap": _clap(rig, k, o, t)
		"cross", "mourn": _cross(rig, k, o, t, false)
		"kneel_cross": _cross(rig, k, o, t, true)
		"snowball": _snowball(rig, k, o, t, body)
		"sled_pull": _sled_pull(rig, k, o, t)
		"sled_ride": _sled_ride(rig, k, o, t)
		"grab", "hen": _grab(rig, k, o, t, anim == "hen")
	for key: String in rig.props:
		if not rig.used.has(key):
			(rig.props[key] as Node3D).visible = false
	body.play(str(o.clip), float(o.pace), float(o.get("blend", 0.25)))
	body.pose.want(o.pose, rate * float(o.get("snap", 1.0)))
	if o.has("seat"):
		body.pose.seat = float(o.seat)
	body.pose.nod = float(o.nod)
	body.pose.bow = float(o.bow)
	body.rotation.y = lerp_angle(body.rotation.y, float(o.spin), 0.25)


# --- helpers ---------------------------------------------------------------------------------------

## Where loose things (a puff of snow, a thrown ball) go: the scene.
static func _world(n: Node) -> Node:
	var sc := n.get_tree().current_scene
	return sc if sc != null else n.get_tree().root


## The prop `key` (made as `kind` the first time) on the body, shown this frame.
static func _prop(rig: LifeRig, key: String, kind := "") -> Node3D:
	var p: Node3D = rig.props.get(key)
	if p == null or not is_instance_valid(p):
		p = LifeProps.make(kind if kind != "" else key)
		rig.skel.add_child(p)
		rig.props[key] = p
	p.visible = true
	rig.used[key] = true
	return p


## Prop `key` kept at `xf` (skeleton space; on `bone` if given, in its frame).
static func _put(rig: LifeRig, key: String, xf: Transform3D, bone := "", kind := "") -> Node3D:
	var p := _prop(rig, key, kind)
	rig.attached.append([p, bone, xf])
	return p


## Hand `i` (0 left, 1 right) to `at`, its elbow toward `elbow` (Vector3.ZERO: the usual).
static func _hand(rig: LifeRig, i: int, at: Vector3, chest := false, elbow := Vector3.ZERO, w := 1.0) -> void:
	rig.goal[i] = at
	rig.chest_rel[i] = chest
	rig.reach[i] = w
	rig.elbow[i] = elbow if elbow != Vector3.ZERO else (Vector3(-0.6, -1.0, 0.35) if i == 0 else Vector3(0.6, -1.0, 0.35))


## A basis looking down `down` (its -y), its face (+z) as near `face` as it can be.
static func _along(down: Vector3, face: Vector3) -> Basis:
	var y := -down.normalized()
	var z := (face - y * face.dot(y))
	z = z.normalized() if z.length() > 0.01 else y.cross(Vector3.RIGHT).normalized()
	return Basis(y.cross(z), y, z).orthonormalized()


## Smooth from a to b as u goes 0..1 (eased at both ends).
static func _s(a: Variant, b: Variant, u: float) -> Variant:
	return lerp(a, b, smoothstep(0.0, 1.0, clampf(u, 0.0, 1.0)))


## Keyframes [[u, value], ...] (u rising 0..1, the last back to the first), eased between.
static func _keys(keys: Array, u: float) -> Variant:
	var n := keys.size()
	for i in n:
		var a: Array = keys[i]
		var b: Array = keys[(i + 1) % n]
		var u1: float = 1.0 if i == n - 1 else float(b[0])
		if u >= float(a[0]) and u < u1:
			return _s(a[1], b[1], (u - float(a[0])) / maxf(u1 - float(a[0]), 0.0001))
	return (keys[0] as Array)[1]


## Hands on the hips (the backs of the wrists there, the elbows out).
static func _hips_hands(rig: LifeRig, which := 3) -> void:
	if which & 1:
		_hand(rig, 0, Vector3(-0.19, 1.0, 0.0), true, Vector3(-1.0, -0.1, 0.4))
	if which & 2:
		_hand(rig, 1, Vector3(0.19, 1.0, 0.0), true, Vector3(1.0, -0.1, 0.4))


## The walk's clip and pace at `k`'s speed.
static func _walk(k: Dictionary, o: Dictionary) -> void:
	var sp := float(k.get("speed", 1.4))
	if sp > 2.6:
		o.clip = "Jog"
		o.pace = sp / Townsfolk.JOG_SPEED
	else:
		o.clip = "Walk"
		o.pace = maxf(sp, 0.3) / Townsfolk.WALK_SPEED


## The walk's phase (radians, a stride a turn) from the clip's own time, so what swings keeps step.
static func _stride(rig: LifeRig, k: Dictionary) -> float:
	return rig.t * maxf(float(k.get("speed", 1.4)), 0.3) * 3.9


# --- water ---------------------------------------------------------------------------------------

## The yoke over the right shoulder, front to back, a full pail at each end swinging with the step;
## the right hand forward on the yoke steadying it, the left arm swinging free. A little bent
## under it, the knees soft.
const YOKE_AT := Vector3(0.15, 1.5, 0.03) ## (the shoulder's top, the chest's frame)
const YOKE_TURN := -0.42 ## (its front end out to the right)


static func _yoke(rig: LifeRig, k: Dictionary, o: Dictionary, _t: float) -> void:
	var walking := bool(k.walking)
	if walking:
		_walk(k, o)
	var yb := Basis(Vector3.UP, YOKE_TURN) * Basis(Vector3.RIGHT, -0.1)
	_put(rig, "yoke", Transform3D(yb, YOKE_AT), LifeRig.CHEST)
	var front := YOKE_AT + yb * Vector3(0, -0.14 - 0.12, -0.8)
	var back := YOKE_AT + yb * Vector3(0, -0.14 - 0.12, 0.8)
	rig.hung.append([_prop(rig, "pail_a", "pail"), front])
	rig.hung.append([_prop(rig, "pail_b", "pail"), back])
	var ph := _stride(rig, k) if walking else rig.t * 1.3
	rig.swing = Vector2(sin(ph * 0.5) * (0.13 if walking else 0.03), sin(ph * 0.5 + 1.2) * (0.05 if walking else 0.01))
	_hand(rig, 1, YOKE_AT + yb * Vector3(0.0, -0.06, -0.36) + Vector3(0.0, -0.02, 0.0), true, Vector3(0.7, -1.0, 0.2))
	o.pose = {"lean": 0.07, "kn": 0.06, "twist": -0.06}
	rig.roll = -0.05 # (bowed a little under the weight on the right)
	rig.hips = Vector3(0, -0.015 - absf(sin(ph)) * 0.012 if walking else -0.015, 0)


## A single pail (to the fire, from the well) in the right hand, the arm straight with its weight,
## the body leant away from it.
static func _pail_walk(rig: LifeRig, k: Dictionary, o: Dictionary, _t: float) -> void:
	_walk(k, o)
	var ph := _stride(rig, k)
	var at := Vector3(0.3, 0.72, -0.02 - sin(ph * 0.5) * 0.06)
	_hand(rig, 1, at, false, Vector3(0.3, 0.0, 1.0))
	_put(rig, "pail1", Transform3D(Basis(Vector3.RIGHT, sin(ph * 0.5) * 0.15), at + Vector3(0, -0.02, 0)), "", "pail")
	rig.roll = -0.08
	o.pose = {"lean": 0.04}


## The washing basket on the left hip, the left arm round it, on the way to the river or the line.
static func _basket_walk(rig: LifeRig, k: Dictionary, o: Dictionary, _t: float) -> void:
	if bool(k.walking):
		_walk(k, o)
	var ph := _stride(rig, k)
	var at := Vector3(-0.3, 1.0 + absf(sin(ph)) * 0.01, -0.06)
	_put(rig, "basket", Transform3D(Basis(Vector3.BACK, -0.25), at), LifeRig.CHEST)
	_hand(rig, 0, at + Vector3(-0.02, -0.04, -0.2), true, Vector3(-1.0, -0.4, 0.2))
	rig.roll = 0.07 # (the hip out under it)


## Setting a load down (pails off the yoke, the basket): stooped to it, hands low, then up.
static func _set_down(rig: LifeRig, k: Dictionary, o: Dictionary, _t: float) -> void:
	o.clip = "PutDown"
	o.pace = 1.0
	var what := str((k.life as Dictionary).get("what", ""))
	if what == "yoke":
		# the pails standing either side of the feet now
		_put(rig, "pail_a", Transform3D(Basis.IDENTITY, Vector3(0.32, 0.54, -0.35)), "", "pail")
		_put(rig, "pail_b", Transform3D(Basis.IDENTITY, Vector3(-0.32, 0.54, -0.25)), "", "pail")
		_put(rig, "yoke", Transform3D(Basis(Vector3.UP, 1.3), Vector3(0, 0.3, -0.3)), "", "yoke")


# --- snow ----------------------------------------------------------------------------------------

## The broad wooden shovel: driven along the ground into the snow, lifted with a heap on it, swung
## round and thrown off to the right, the body turning with it; the left hand down the haft, the
## right at its top. About every 2.4 s.
const SHOVEL_KEYS := [
	# u, the blade's foot (where it bites), the haft's top (the right hand), twist, lean, knees, loaded
	[0.0, Vector3(0.05, 0.04, -0.98), Vector3(0.2, 0.82, -0.18), 0.05, 0.58, 0.24, 0.0],
	[0.26, Vector3(0.05, 0.05, -1.18), Vector3(0.2, 0.76, -0.4), 0.05, 0.66, 0.28, 1.0],
	[0.44, Vector3(0.18, 0.55, -0.85), Vector3(0.24, 1.0, -0.1), -0.25, 0.36, 0.2, 1.0],
	[0.6, Vector3(0.95, 0.92, -0.28), Vector3(0.28, 1.08, -0.1), -0.75, 0.16, 0.14, 0.0],
	[0.74, Vector3(0.82, 0.62, -0.52), Vector3(0.26, 0.98, -0.14), -0.6, 0.24, 0.16, 0.0],
]


static func _shovel(rig: LifeRig, k: Dictionary, o: Dictionary, t: float) -> void:
	var u := fmod(t / 2.4, 1.0)
	var n := SHOVEL_KEYS.size()
	var a: Array = SHOVEL_KEYS[n - 1]
	var b: Array = SHOVEL_KEYS[0]
	var f := 0.0
	for i in n:
		var u0 := float(SHOVEL_KEYS[i][0])
		var u1 := 1.0 if i == n - 1 else float(SHOVEL_KEYS[i + 1][0])
		if u >= u0 and u < u1:
			a = SHOVEL_KEYS[i]
			b = SHOVEL_KEYS[(i + 1) % n]
			f = smoothstep(0.0, 1.0, (u - u0) / (u1 - u0))
			break
	var foot: Vector3 = (a[1] as Vector3).lerp(b[1], f)
	var top: Vector3 = (a[2] as Vector3).lerp(b[2], f)
	var down := (foot - top).normalized()
	var bs := _along(down, Vector3(0, 1, 0.3))
	var sh := _put(rig, "shovel", Transform3D(bs, top), "", "shovel")
	sh.get_node("load").visible = float(a[6]) > 0.5 and u < 0.58
	_hand(rig, 1, top + down * 0.02, false, Vector3(0.8, -0.6, 0.6))
	_hand(rig, 0, top + down * 0.5, false, Vector3(-0.7, -1.0, 0.1))
	o.pose = {"twist": lerpf(a[3], b[3], f), "lean": lerpf(a[4], b[4], f), "kn": lerpf(a[5], b[5], f),
		"arm_l": -0.6, "arm_r": -0.5, "el": 0.6, "er": 0.6}
	o.snap = 2.0
	rig.hips = Vector3(0.0, -0.02, 0.04 * float(a[6]))
	if rig.prev_u < 0.6 and u >= 0.6:
		_puff(rig, top + down * 1.3)
	rig.prev_u = u


## A puff of snow thrown off the shovel (or kicked off a boot): a few flakes flung out and falling.
static func _puff(rig: LifeRig, at: Vector3) -> void:
	var sk := rig.skel
	if sk == null or not sk.is_inside_tree():
		return
	var cam := sk.get_viewport().get_camera_3d()
	var w := sk.global_transform * at
	if cam == null or cam.global_position.distance_squared_to(w) > 90.0 * 90.0:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.9
	p.explosiveness = 0.9
	p.direction = (sk.global_basis * Vector3(1, 0.6, -0.3)).normalized()
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var q := BoxMesh.new()
	q.size = Vector3(0.07, 0.07, 0.07)
	p.mesh = q
	p.material_override = LifeProps.mat("snow")
	_world(sk).add_child(p)
	p.global_position = w
	p.emitting = true
	p.finished.connect(p.queue_free)


## At the door out of the snow: the boots stamped, left and right, a few times, then the snow
## brushed off the coat with both hands, down the front.
static func _stamp(rig: LifeRig, _k: Dictionary, o: Dictionary, t: float) -> void:
	var u := fmod(t / 2.2, 1.0)
	if u < 0.55:
		var s := fmod(u / 0.55 * 3.0, 1.0)
		var up := sin(clampf(s / 0.7, 0.0, 1.0) * PI) if s < 0.7 else 0.0
		var lift := up * 0.16
		if int(u / 0.55 * 3.0) % 2 == 0:
			rig.foot_lift = Vector2(lift, 0)
		else:
			rig.foot_lift = Vector2(0, lift)
		rig.hips = Vector3(0, -0.03 * up, 0)
		o.pose = {"lean": 0.1, "arm_l": -0.15, "arm_r": -0.15, "el": 0.5, "er": 0.5}
	else:
		var s := fmod((u - 0.55) / 0.45 * 2.0, 1.0)
		var y := lerpf(1.36, 0.92, s)
		_hand(rig, 0, Vector3(-0.1, y, -0.2 - (1.3 - y) * 0.05), true, Vector3(-0.8, -1.0, 0.2))
		_hand(rig, 1, Vector3(0.1, y + 0.05, -0.2 - (1.3 - y) * 0.05), true, Vector3(0.8, -1.0, 0.2))
		o.pose = {"lean": 0.2}
		rig.head_tilt = 0.25


# --- the chain: hand to hand -------------------------------------------------------------------

## A member of a chain (LifeScenes): stood side-on to the line, the source on its left, taking the
## piece from the one before, swinging it across in front and handing it on to the one after, then
## back empty for the next. `k.life`: {chain (the scene's dictionary), i (its place), item}.
## The beat is the chain's, each member PASS_HOLD of a beat behind the one before, so the piece goes
## down the line from hands to hands.
static func _pass(rig: LifeRig, k: Dictionary, o: Dictionary, body: Townsfolk) -> void:
	var life: Dictionary = k.life
	var chain: Dictionary = life.get("chain", {})
	if not bool(chain.get("ready", true)):
		return # (waiting for the rest to take their places)
	var i := int(life.get("i", 0))
	var n := int(chain.get("n", 1))
	var beat := float(k.beat) - float(chain.get("t0", 0.0))
	var u := fposmod(beat / PASS_T - i * PASS_HOLD, 1.0)
	var item := str(chain.get("item", "crate"))
	if item == "mixed":
		item = "crate" if int(floor(beat / PASS_T - i * PASS_HOLD)) % 3 != 1 else "sack"
	var first := i == 0
	var last := i == n - 1
	var throw := last and str(chain.get("end", "")) == "throw"
	var put := last and str(chain.get("end", "")) == "put"
	var low := 0.95 if item != "pail" else 0.8
	var lp := Vector3(-0.44, low, -0.18)
	var fp := Vector3(0.0, low + 0.08, -0.42)
	var rp := Vector3(0.44, low, -0.18)
	if throw:
		rp = Vector3(0.55, 1.35, -0.42) # (swung up and out at the fire)
	elif put:
		rp = Vector3(0.48, 0.42, -0.3) # (down onto the pile)
	if first and str(chain.get("start", "")) == "pick":
		lp = Vector3(-0.42, 0.45, -0.32) # (taken up off the floor of the wagon, the well's lip)
	# one stood higher than the next (up in a wagon): handed down between them, halfway
	var levels: Array = chain.get("levels", [])
	if not levels.is_empty():
		var h := float(levels[i]) if i < levels.size() else 0.0
		var hp := float(levels[i - 1]) if i > 0 and i - 1 < levels.size() else h
		var hn := float(levels[i + 1]) if i + 1 < levels.size() else h
		if not (first and str(chain.get("start", "")) == "pick"):
			lp.y += (hp - h) * 0.5
		if not (throw or put):
			rp.y += (hn - h) * 0.5
		fp.y += ((hp + hn) * 0.5 - h) * 0.5
	var p: Vector3
	var tw := 0.0
	var holding := u < PASS_HOLD
	if u < 0.12:
		p = lp
		tw = 0.55
	elif u < 0.5:
		var s := (u - 0.12) / 0.38
		p = _arc(lp, fp, rp, smoothstep(0.0, 1.0, s))
		tw = lerpf(0.55, -0.55, smoothstep(0.0, 1.0, s))
	elif u < 0.68:
		p = rp
		tw = -0.55
	else:
		var s := (u - 0.68) / 0.32
		p = _arc(rp, fp + Vector3(0, -0.1, 0.08), lp, smoothstep(0.0, 1.0, s))
		tw = lerpf(-0.55, 0.55, smoothstep(0.0, 1.0, s))
	var half := 0.17 if item != "pail" else 0.05
	if item == "pail":
		_hand(rig, 1, p + Vector3(0.04, 0.28, 0.0), false, Vector3(0.5, -1.0, 0.4))
		_hand(rig, 0, p + Vector3(-0.04, 0.26, 0.0) if holding else p + Vector3(-0.3, 0.1, 0.1), false, Vector3(-0.5, -1.0, 0.4))
	else:
		_hand(rig, 0, p + Vector3(-half, 0.0, 0.0), false, Vector3(-0.7, -1.0, 0.3))
		_hand(rig, 1, p + Vector3(half, 0.0, 0.0), false, Vector3(0.7, -1.0, 0.3))
	if holding:
		var it := _prop(rig, "chain_" + item, item if item != "pail" else "pail")
		rig.held = it
		rig.held_off = Vector3(0, 0.08 if item == "pail" else -0.02, 0) if item != "pail" else Vector3(0, 0.36, 0)
		if item == "pail":
			# (held by the bail: hangs under the hands)
			rig.held_off = Vector3(0, 0.3, 0)
	var dip := absf(tw) / 0.55
	o.pose = {"twist": tw, "lean": 0.16 + (0.25 if (put and u > 0.45 and u < 0.75) else 0.0) + (0.2 if first and lp.y < 0.6 and u < 0.15 else 0.0),
		"kn": 0.18 + dip * 0.08, "arm_l": -0.6, "arm_r": -0.6, "el": 0.7, "er": 0.7}
	o.snap = 2.5
	rig.hips = Vector3(clampf(p.x, -0.45, 0.45) * 0.09, -0.02 - (1.0 - dip) * 0.02, 0)
	if throw and rig.prev_u < 0.56 and u >= 0.56:
		_splash(rig, Vector3(1.2, 1.2, -0.6))
	rig.prev_u = u
	var _b := body


## A point along a curve from a through near b to c (a quadratic arc), at s 0..1.
static func _arc(a: Vector3, b: Vector3, c: Vector3, s: float) -> Vector3:
	var ab := a.lerp(b, s)
	var bc := b.lerp(c, s)
	return ab.lerp(bc, s)


## Water flung from a pail at a fire: a short spray.
static func _splash(rig: LifeRig, at: Vector3) -> void:
	var sk := rig.skel
	if sk == null or not sk.is_inside_tree():
		return
	var cam := sk.get_viewport().get_camera_3d()
	var w := sk.global_transform * at
	if cam == null or cam.global_position.distance_squared_to(w) > 100.0 * 100.0:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 24
	p.lifetime = 0.7
	p.explosiveness = 0.85
	p.direction = (sk.global_basis * Vector3(1, 0.5, -0.2)).normalized()
	p.spread = 22.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -9.0, 0)
	var q := BoxMesh.new()
	q.size = Vector3(0.05, 0.05, 0.05)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.8, 0.9, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	p.material_override = m
	_world(sk).add_child(p)
	p.global_position = sk.global_transform * Vector3(0.5, 1.3, -0.4)
	p.emitting = true
	p.finished.connect(p.queue_free)


# --- the train, greetings ----------------------------------------------------------------------

## A wave at the train (or to someone come): the right arm up, the hand swung side to side, now
## and then the cap or the kerchief lifted off with the left... kept to the arm: read from afar.
static func _wave(rig: LifeRig, _k: Dictionary, o: Dictionary, t: float) -> void:
	var s := sin(t * 7.5)
	_hand(rig, 1, Vector3(0.38 + s * 0.12, 1.78, -0.12), true, Vector3(1.0, -0.6, 0.0))
	o.pose = {"lean": -0.05, "twist": 0.05}
	rig.roll = -0.04
	rig.head_tilt = -0.08


## An embrace: close, the arms round the other (the right over the left shoulder, the left under
## the right arm, so two embracing meet), a pat or two on the back.
static func _embrace(rig: LifeRig, k: Dictionary, o: Dictionary, t: float) -> void:
	var d := float((k.life as Dictionary).get("d", 0.64))
	var pat := maxf(sin(t * 9.0), 0.0) * 0.05 * (1.0 if fmod(t, 3.0) > 1.4 else 0.0)
	_hand(rig, 1, Vector3(-0.08, 1.4 + pat, -(d + 0.12)), false, Vector3(1.0, 0.3, -0.2))
	_hand(rig, 0, Vector3(0.1, 1.12, -(d + 0.12)), false, Vector3(-1.0, -0.3, -0.1))
	o.pose = {"lean": 0.1}
	rig.head_yaw = 0.35
	rig.head_tilt = 0.1


## A handshake: right hands met halfway, shaken a few times, held.
static func _handshake(rig: LifeRig, k: Dictionary, o: Dictionary, t: float) -> void:
	var d := float((k.life as Dictionary).get("d", 0.9))
	var shake := sin(t * 13.0) * 0.04 if fmod(t, 4.0) < 1.8 else 0.0
	_hand(rig, 1, Vector3(0.02, 1.0 + shake, -(d * 0.5 - 0.06)), false, Vector3(0.6, -1.0, 0.4))
	o.pose = {"lean": 0.07}
	rig.head_tilt = 0.06


## Arguing: a finger jabbed at the other, the other hand on the hip; then both arms flung out,
## palms up (what can you do with such a man?), the head shaken. Leant in at it.
static func _argue(rig: LifeRig, _k: Dictionary, o: Dictionary, t: float) -> void:
	o.clip = "ual/UalIdleTalking"
	var cyc := fmod(t / 5.0, 1.0)
	if cyc < 0.6:
		var jab := pow(maxf(sin(t * 4.2), 0.0), 3.0)
		_hand(rig, 1, Vector3(0.2, 1.28 + jab * 0.06, -0.28 - jab * 0.3), true, Vector3(0.9, -0.6, 0.3))
		_hips_hands(rig, 1)
		o.pose = {"lean": 0.08 + jab * 0.08}
	else:
		var s := smoothstep(0.6, 0.7, cyc) * (1.0 - smoothstep(0.92, 1.0, cyc))
		_hand(rig, 0, Vector3(-0.42, 1.18, -0.3), true, Vector3(-1.0, -0.5, 0.2), s)
		_hand(rig, 1, Vector3(0.42, 1.18, -0.3), true, Vector3(1.0, -0.5, 0.2), s)
		o.pose = {"lean": -0.04}
		rig.head_yaw = sin(t * 7.0) * 0.3 * s
	o.snap = 1.5


## Hearing the other out in an argument: the arms folded, the head shaken, turned half away.
static func _argue_listen(rig: LifeRig, _k: Dictionary, o: Dictionary, t: float) -> void:
	o.clip = "ual/UalIdleFoldArms"
	rig.head_yaw = sin(t * 5.0) * 0.22 * (1.0 if fmod(t, 4.0) < 1.5 else 0.0)
	o.pose = {"lean": -0.05, "twist": 0.15}


# --- the household ---------------------------------------------------------------------------------

## Stood over the pot on its tripod in the yard, the ladle going round in it; the left hand on the
## hip; now and then a taste off the ladle.
static func _stir(rig: LifeRig, _k: Dictionary, o: Dictionary, t: float) -> void:
	var fire := Vector3(0, 0, -0.72)
	var h := _put(rig, "hearth", Transform3D(Basis.IDENTITY, fire), "", "hearth")
	for i in 3:
		var fl := h.get_node_or_null("flame%d" % i) as Node3D
		if fl:
			fl.scale = Vector3(1.0, 0.8 + 0.35 * sin(t * (9.0 + i * 3.1) + i), 1.0)
	var taste := fmod(t / 11.0, 1.0) > 0.86
	var a := t * 3.2
	var hand: Vector3
	var tip: Vector3
	if taste:
		hand = Vector3(0.05, 1.42, -0.32)
		tip = Vector3(0.0, 1.5, -0.25)
		o.pose = {"lean": 0.0}
	else:
		hand = fire + Vector3(0.1 + cos(a) * 0.07, 0.95, 0.24 + sin(a) * 0.06)
		tip = fire + Vector3(cos(a) * 0.08, 0.55, sin(a) * 0.08)
		o.pose = {"lean": 0.22, "kn": 0.1}
	_put(rig, "ladle", Transform3D(_along(tip - hand, Vector3(0, 0, 1)), hand), "", "ladle")
	_hand(rig, 1, hand, false, Vector3(0.8, -1.0, 0.3))
	_hips_hands(rig, 1)
	rig.head_tilt = 0.25 if not taste else -0.05


## Knelt on the bank at the washboard, the linen scrubbed up and down it with both hands; now and
## then wrung out, held up before the chest.
static func _scrub(rig: LifeRig, _k: Dictionary, o: Dictionary, t: float) -> void:
	o.clip = "ual/UalFixKneeling"
	o.pace = 0.3 # (the kneel; the hands are this)
	o.blend = 0.4
	_put(rig, "board", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.62)), "", "board")
	_put(rig, "wash_basket", Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.55, 0.12, -0.05)), "", "basket")
	var wring := fmod(t / 9.0, 1.0) > 0.78
	var cloth := _prop(rig, "wet", "cloth")
	if wring:
		var tw := sin(t * 6.0) * 0.08
		var l := Vector3(-0.12, 0.85 + tw, -0.35)
		var r := Vector3(0.12, 0.85 - tw, -0.35)
		_hand(rig, 0, l, false, Vector3(-0.8, -1.0, 0.0))
		_hand(rig, 1, r, false, Vector3(0.8, -1.0, 0.0))
		rig.attached.append([cloth, "", Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis(Vector3.UP, t * 3.0).scaled(Vector3(0.35, 1.0, 1.0)), Vector3(-0.2, 0.85, -0.35))])
		o.pose = {"lean": 0.1}
	else:
		var s := sin(t * 6.5)
		var z := -0.6 + s * 0.13
		_hand(rig, 0, Vector3(-0.1, 0.3 + s * 0.04, z), false, Vector3(-0.7, -0.4, 0.6))
		_hand(rig, 1, Vector3(0.1, 0.3 + s * 0.04, z + 0.02), false, Vector3(0.7, -0.4, 0.6))
		rig.attached.append([cloth, "", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 - 0.25), Vector3(0, 0.21, z - 0.12))])
		o.pose = {"lean": 0.08}
		rig.head_tilt = 0.25
	rig.roll = sin(t * 6.5) * 0.03


## At the clothes line (1.8 m up, before it): a piece taken from the basket at the feet, shaken
## out, reached up and pegged on the line, the arms high, the back arched a little; again.
static func _hang(rig: LifeRig, _k: Dictionary, o: Dictionary, t: float) -> void:
	var u := fmod(t / 6.0, 1.0)
	_put(rig, "line_basket", Transform3D(Basis.IDENTITY, Vector3(0.42, 0.11, -0.25)), "", "basket")
	var cloth := _prop(rig, "dry", "cloth_dry")
	var l: Vector3
	var r: Vector3
	if u < 0.28:
		var s := smoothstep(0.0, 0.18, u)
		l = Vector3(0.28, lerpf(1.0, 0.36, s), -0.32)
		r = Vector3(0.48, lerpf(1.0, 0.36, s), -0.3)
		o.pose = {"lean": lerpf(0.0, 0.62, s), "kn": lerpf(0.05, 0.35, s), "twist": -0.35 * s}
	elif u < 0.48:
		var s := smoothstep(0.28, 0.48, u)
		l = Vector3(lerpf(0.28, -0.2, s), lerpf(0.36, 1.2, s), -0.3)
		r = Vector3(lerpf(0.48, 0.2, s), lerpf(0.36, 1.2, s), -0.3)
		o.pose = {"lean": lerpf(0.62, 0.05, s), "kn": lerpf(0.35, 0.05, s), "twist": -0.35 * (1.0 - s)}
	elif u < 0.86:
		var s := smoothstep(0.48, 0.6, u)
		var peg := sin(clampf((u - 0.66) / 0.14, 0.0, 1.0) * PI) * 0.04
		l = Vector3(-0.2, lerpf(1.2, 1.76, s) + peg, -0.46)
		r = Vector3(0.2, lerpf(1.2, 1.76, s) - peg, -0.46)
		o.pose = {"lean": -0.08 * s}
		rig.head_tilt = -0.3 * s
	else:
		var s := smoothstep(0.86, 1.0, u)
		l = Vector3(-0.2, lerpf(1.76, 1.0, s), -0.46)
		r = Vector3(0.2, lerpf(1.76, 1.0, s), -0.46)
	_hand(rig, 0, l, false, Vector3(-0.8, -1.0, 0.2))
	_hand(rig, 1, r, false, Vector3(0.8, -1.0, 0.2))
	if u > 0.12 and u < 0.86:
		var mid := (l + r) * 0.5 + Vector3(0, 0.07, 0)
		var across := (r - l)
		var yaw := atan2(-across.z, across.x)
		rig.attached.append([cloth, "", Transform3D(Basis(Vector3.UP, yaw), mid)])
	o.snap = 1.5


## The doorstep swept: the besom swung across the boards in short strokes, right to left, the
## body turning with it, a step along now and then.
static func _sweep(rig: LifeRig, _k: Dictionary, o: Dictionary, t: float) -> void:
	var u := fmod(t / 1.3, 1.0)
	var s := smoothstep(0.0, 0.55, u) * (1.0 - smoothstep(0.62, 1.0, u))
	var head := Vector3(lerpf(0.45, -0.4, s), 0.03 + (1.0 - s) * 0.04 * smoothstep(0.62, 0.8, u), lerpf(-0.6, -0.72, sin(s * PI)))
	var top := Vector3(lerpf(0.26, 0.05, s), 1.0, lerpf(-0.12, -0.22, s))
	var down := (head - top).normalized()
	_put(rig, "besom", Transform3D(_along(down, Vector3(0, 0, 1)), top), "", "besom")
	_hand(rig, 1, top + down * 0.02, false, Vector3(0.9, -0.6, 0.4))
	_hand(rig, 0, top + down * 0.42, false, Vector3(-0.6, -1.0, 0.2))
	o.pose = {"lean": 0.28, "kn": 0.15, "twist": lerpf(-0.3, 0.3, s), "arm_l": -0.5, "arm_r": -0.4}
	o.snap = 2.0
	rig.hips = Vector3(lerpf(0.03, -0.03, s), -0.01, 0)


# --- the evening on the square ------------------------------------------------------------------

## The round dance (khorovod) round the square's fire, its own part of the beat (LifeScenes moves
## it round the ring and says which part): going round, facing in, hands joined with the ones
## either side (the scene's points), side-stepping; or stopped, hands on the hips, stamping on the
## beat (the women turning once round); `k.life`: {ring, left_hand, right_hand (world points), part}.
static func _dance(rig: LifeRig, k: Dictionary, o: Dictionary, body: Townsfolk) -> void:
	var life: Dictionary = k.life
	var ring: Dictionary = life.get("ring", {})
	var part := str(ring.get("part", "round"))
	var beat := float(k.beat)
	var bu := fmod(beat / BEAT, 1.0)
	var inv := body.skeleton.global_transform.affine_inverse()
	if part == "wait":
		_clap(rig, k, o, 0.0)
		return
	if part == "round":
		var dir := float(ring.get("dir", 1.0))
		o.clip = "WalkLeft" if dir > 0.0 else "WalkRight"
		o.pace = float(ring.get("speed", 0.6)) / Townsfolk.WALK_SPEED * 1.3
		for i in 2:
			var key := "left_hand" if i == 0 else "right_hand"
			if life.has(key) and life[key] is Vector3:
				var pt: Vector3 = inv * (life[key] as Vector3)
				pt.y = 1.08 + sin(beat * PI * 2.0 / (BEAT * 4.0)) * 0.06
				_hand(rig, i, pt, false, Vector3(-0.6 if i == 0 else 0.6, -1.0, 0.6))
		o.pose = {"lean": -0.03, "kn": 0.1}
		rig.hips = Vector3(0, -absf(sin(bu * PI)) * 0.025, 0)
	else:
		# stamp on the beat, left and right; hands on the hips; the women spin once round
		var foot := int(beat / BEAT) % 2
		var up := sin(clampf(bu / 0.45, 0.0, 1.0) * PI) if bu < 0.45 else 0.0
		rig.foot_lift = Vector2(up * 0.15, 0) if foot == 0 else Vector2(0, up * 0.15)
		rig.hips = Vector3((0.03 if foot == 1 else -0.03), -0.035 * up, 0)
		_hips_hands(rig)
		o.pose = {"lean": -0.06, "kn": 0.14}
		rig.head_tilt = -0.1
		if bool(k.get("female", false)) and float(ring.get("spin_u", -1.0)) >= 0.0:
			o.spin = float(ring.spin_u) * TAU
		o.snap = 2.0


## The garmon played: held before the chest, the bellows drawn out and pushed in by the left
## hand, the right on the buttons; the body swaying with it, the right foot keeping the beat.
static func _garmon(rig: LifeRig, k: Dictionary, o: Dictionary, t: float) -> void:
	var beat := float(k.beat)
	var bel := sin(beat * PI / (BEAT * 4.0))
	var rh := Vector3(0.18, 1.1, -0.3)
	var lh := Vector3(-0.2 - (bel * 0.5 + 0.5) * 0.18, 1.1 + bel * 0.03, -0.3)
	_put(rig, "garmon_r", Transform3D(Basis.IDENTITY, rh + Vector3(-0.04, 0, 0)), "", "garmon_r")
	_put(rig, "garmon_l", Transform3D(Basis.IDENTITY, lh + Vector3(0.04, 0, 0)), "", "garmon_l")
	var span := (rh.x - 0.04) - (lh.x + 0.04)
	var mid := Vector3(((rh.x - 0.04) + (lh.x + 0.04)) * 0.5, 1.1 + bel * 0.015, -0.3)
	var bp := _put(rig, "bellows", Transform3D(Basis.IDENTITY.scaled(Vector3(maxf(span - 0.05, 0.02), 1.0, 1.0)), mid), "", "bellows")
	var _b := bp
	_hand(rig, 1, rh + Vector3(0.05, 0.0, 0.02), false, Vector3(0.9, -0.8, 0.3))
	_hand(rig, 0, lh + Vector3(-0.05, 0.0, 0.02), false, Vector3(-0.9, -0.8, 0.3))
	var bu := fmod(beat / BEAT, 1.0)
	if bool(k.get("seat", -1.0) < 0.0):
		rig.foot_lift = Vector2(0, sin(clampf(bu / 0.4, 0.0, 1.0) * PI) * 0.05 if bu < 0.4 else 0.0)
	rig.roll = sin(beat * PI / (BEAT * 2.0)) * 0.05
	rig.head_tilt = 0.15
	rig.head_yaw = sin(beat * PI / (BEAT * 4.0)) * 0.2
	var _t := t
	o.pose = {"lean": 0.06}


## The balalaika: the neck up to the left in the left hand, the right strumming quick across the
## strings at the body.
static func _balalaika(rig: LifeRig, k: Dictionary, o: Dictionary, t: float) -> void:
	var body_at := Vector3(0.06, 1.05, -0.22)
	var neck := Vector3(-0.38, 1.4, -0.32)
	var up := (neck - body_at).normalized()
	_put(rig, "balalaika", Transform3D(_along(-up, Vector3(0, 0, 1)), body_at), "", "balalaika")
	_hand(rig, 0, body_at + up * 0.45 + Vector3(0, 0, 0.03), false, Vector3(-0.8, -1.0, 0.0))
	var strum := sin(t * 18.0) * 0.06
	_hand(rig, 1, body_at + Vector3(0.05, 0.02 + strum, 0.04), false, Vector3(0.9, -0.6, 0.4))
	var beat := float(k.beat)
	rig.roll = sin(beat * PI / (BEAT * 2.0)) * 0.04
	rig.head_tilt = 0.18
	o.pose = {"lean": 0.05}


## Clapping in time to the dance, stood by: the hands meeting before the chest on the beat; a
## little bob at the knees.
static func _clap(rig: LifeRig, k: Dictionary, o: Dictionary, _t: float) -> void:
	var bu := fmod(float(k.beat) / BEAT, 1.0)
	var apart := 0.03 + smoothstep(0.08, 0.5, bu) * (1.0 - smoothstep(0.6, 0.95, bu)) * 0.2
	_hand(rig, 0, Vector3(-apart, 1.24, -0.32), true, Vector3(-0.9, -1.0, 0.0))
	_hand(rig, 1, Vector3(apart, 1.24, -0.32), true, Vector3(0.9, -1.0, 0.0))
	rig.hips = Vector3(0, -absf(sin(bu * PI)) * 0.02, 0)
	o.pose = {"kn": 0.08}


# --- at the graves ---------------------------------------------------------------------------------

## The sign of the cross as the Orthodox make it: the right hand's three fingers to the brow, to
## the belly, to the right shoulder, then the left, and a bow from the waist; three times, then
## stood with the head bowed a while. Knelt (one knee down, the left hand on the other) at a grave
## one prays at, stood at a funeral.
static func _cross(rig: LifeRig, k: Dictionary, o: Dictionary, t: float, knelt: bool) -> void:
	if knelt:
		o.clip = "ual/UalFixKneeling"
		o.pace = 0.3
		o.blend = 0.4
	var cyc := fmod(t, 16.0)
	o.bow = 1.0
	if cyc < 9.0:
		var u := fmod(cyc, 3.0) / 3.0
		var keys := [[0.0, Vector3(0.12, 1.02, -0.18)], [0.12, Vector3(0.02, 1.66, -0.15)], [0.3, Vector3(0.02, 1.66, -0.15)],
			[0.38, Vector3(0.02, 1.12, -0.22)], [0.5, Vector3(0.02, 1.12, -0.22)], [0.58, Vector3(0.16, 1.43, -0.13)],
			[0.66, Vector3(0.16, 1.43, -0.13)], [0.74, Vector3(-0.14, 1.43, -0.13)], [0.82, Vector3(-0.14, 1.43, -0.13)],
			[0.92, Vector3(0.12, 1.02, -0.18)]]
		var p: Vector3 = _keys(keys, u)
		_hand(rig, 1, p, true, Vector3(0.6, -1.0, 0.1))
		var bow := smoothstep(0.82, 0.9, u) * (1.0 - smoothstep(0.95, 1.0, u))
		o.pose = {"lean": bow * (0.5 if not knelt else 0.3)}
		o.snap = 2.0
		o.bow = 0.5
	else:
		o.pose = {"lean": 0.08}
	if knelt:
		_hand(rig, 0, Vector3(-0.12, 0.62, -0.28), false, Vector3(-1.0, -0.2, 0.2))
	var _k := k


# --- the children ----------------------------------------------------------------------------------

## A snowball fight: down to scoop the snow, packed between the hands, up and thrown overarm at
## the other (`k.life.at`, a world point), again. The ball flies (LifeScenes catches where it lands).
static func _snowball(rig: LifeRig, k: Dictionary, o: Dictionary, t: float, body: Townsfolk) -> void:
	var u := fmod(t / 3.0, 1.0)
	if u < 0.42:
		var s := smoothstep(0.0, 0.12, u)
		var pack := sin(t * 12.0) * 0.03 * smoothstep(0.15, 0.25, u)
		_hand(rig, 0, Vector3(-0.06 - pack, lerpf(0.9, 0.35 + smoothstep(0.2, 0.42, u) * 0.45, s), -0.35), false, Vector3(-0.6, -1.0, 0.4))
		_hand(rig, 1, Vector3(0.06 + pack, lerpf(0.9, 0.35 + smoothstep(0.2, 0.42, u) * 0.45, s), -0.35), false, Vector3(0.6, -1.0, 0.4))
		o.pose = {"lean": 0.65 * s * (1.0 - smoothstep(0.25, 0.42, u)), "kn": 0.7 * s * (1.0 - smoothstep(0.25, 0.42, u)) + 0.05}
		if u > 0.15:
			_put(rig, "ball", Transform3D(Basis.IDENTITY, Vector3(0, 0.35 + smoothstep(0.2, 0.42, u) * 0.45, -0.38)), "", "snowball")
	elif u < 0.62:
		var s := smoothstep(0.42, 0.6, u)
		var wind := Vector3(0.32, 1.55, 0.18)
		_hand(rig, 1, Vector3(0.06, 0.8, -0.38).lerp(wind, s), false, Vector3(1.0, -0.2, 0.3))
		_put(rig, "ball", Transform3D(Basis.IDENTITY, Vector3(0.06, 0.8, -0.42).lerp(wind + Vector3(0, 0.05, -0.05), s)), "", "snowball")
		o.pose = {"twist": -0.5 * s, "lean": -0.08 * s}
		rig.hips = Vector3(0, 0, 0.04 * s)
	elif u < 0.7:
		var s := smoothstep(0.62, 0.7, u)
		_hand(rig, 1, Vector3(0.32, 1.55, 0.18).lerp(Vector3(0.12, 1.25, -0.62), s), false, Vector3(1.0, -0.4, 0.2))
		o.pose = {"twist": lerpf(-0.5, 0.35, s), "lean": lerpf(-0.08, 0.25, s)}
		rig.hips = Vector3(0, -0.02, -0.06 * s)
		o.snap = 3.0
		if rig.prev_u < 0.64 and u >= 0.64:
			_throw_ball(rig, body, Vector3(0.2, 1.45, -0.45), (k.life as Dictionary).get("at", Vector3.INF), (k.life as Dictionary).get("who"))
	else:
		o.pose = {"lean": 0.1}
	rig.prev_u = u


## The snowball off from the hand at `from` (skeleton space) in an arc to `to` (world), and gone in
## a puff where it lands.
static func _throw_ball(rig: LifeRig, body: Townsfolk, from: Vector3, to: Variant, who: Variant = null) -> void:
	var sk := rig.skel
	if sk == null or not sk.is_inside_tree() or not (to is Vector3) or to == Vector3.INF:
		return
	var a := sk.global_transform * from
	var b: Vector3 = to
	var ball := LifeProps.make("snowball")
	_world(sk).add_child(ball)
	ball.global_position = a
	var dist := a.distance_to(b)
	var dur := clampf(dist / 9.0, 0.35, 1.2)
	var tw := ball.create_tween()
	tw.tween_method(func(s: float) -> void:
		if is_instance_valid(ball):
			ball.global_position = a.lerp(b, s) + Vector3.UP * sin(s * PI) * dist * 0.18, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		if is_instance_valid(ball):
			_puff_at(ball, ball.global_position)
			# a hit: the other jerks back from it
			if who is Villager and is_instance_valid(who) and (who as Villager)._body and (who as Villager).position.distance_to(b) < 1.5 and randf() < 0.6:
				(who as Villager)._body.flinch("HitReact")
			ball.queue_free())
	var _b := body


static func _puff_at(n: Node3D, w: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 8
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -5.0, 0)
	var q := BoxMesh.new()
	q.size = Vector3(0.05, 0.05, 0.05)
	p.mesh = q
	p.material_override = LifeProps.mat("snow")
	_world(n).add_child(p)
	p.global_position = w
	p.emitting = true
	p.finished.connect(p.queue_free)


## Up the slope with the sled on its rope behind, the rope over the right shoulder in both hands,
## leant into the pull.
static func _sled_pull(rig: LifeRig, k: Dictionary, o: Dictionary, _t: float) -> void:
	_walk(k, o)
	var sled := Vector3(0, 0, 1.5)
	_put(rig, "sled", Transform3D(Basis.IDENTITY, sled), "", "sled")
	var hand := Vector3(0.18, 1.22, 0.05)
	_hand(rig, 1, hand, true, Vector3(0.8, -0.6, -0.4))
	_hand(rig, 0, hand + Vector3(-0.1, -0.12, -0.08), true, Vector3(-0.8, -1.0, 0.0))
	o.pose = {"lean": 0.18}
	var rope := _put(rig, "rope", Transform3D.IDENTITY, "", "rope")
	_rope(rope, hand + Vector3(0, 0, 0), sled + Vector3(0, 0.14, -0.5))


## A rope (a thin stick) from a to b, remade each frame (cheap: a scaled cylinder).
static func _rope(n: Node3D, a: Vector3, b: Vector3) -> void:
	if n.get_child_count() == 0:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.008
		cm.bottom_radius = 0.008
		cm.height = 1.0
		cm.radial_segments = 4
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = LifeProps.mat("twig")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
	var mi2 := n.get_child(0) as MeshInstance3D
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi2.transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), (a + b) * 0.5)
	n.transform = Transform3D.IDENTITY


## Sat on the sled going down: the knees up, the hands on the rope at the front, leant back, a
## whoop in the arms now and then.
static func _sled_ride(rig: LifeRig, _k: Dictionary, o: Dictionary, t: float) -> void:
	o.seat = 0.16
	_put(rig, "sled", Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.18)), "", "sled")
	var whoop := fmod(t, 4.0) < 0.9
	if whoop:
		_hand(rig, 0, Vector3(-0.3, 1.55, -0.1), true, Vector3(-1.0, -0.3, 0.0))
		_hand(rig, 1, Vector3(0.3, 1.55, -0.1), true, Vector3(1.0, -0.3, 0.0))
	else:
		_hand(rig, 0, Vector3(-0.14, 0.42, -0.62), false, Vector3(-0.8, -0.6, 0.3))
		_hand(rig, 1, Vector3(0.14, 0.42, -0.62), false, Vector3(0.8, -0.6, 0.3))
	o.pose = {"lean": -0.12}


## After a hen: running at it with the arms out and down, stooped to grab where it was.
static func _grab(rig: LifeRig, k: Dictionary, o: Dictionary, t: float, running: bool) -> void:
	if running:
		_walk(k, o)
		var s := sin(t * 5.0) * 0.05
		_hand(rig, 0, Vector3(-0.3, 0.95 + s, -0.42), true, Vector3(-0.8, -1.0, 0.2))
		_hand(rig, 1, Vector3(0.3, 0.95 - s, -0.42), true, Vector3(0.8, -1.0, 0.2))
		o.pose = {"lean": 0.25}
	else:
		var u := fmod(t / 1.2, 1.0)
		var s := sin(clampf(u / 0.6, 0.0, 1.0) * PI)
		_hand(rig, 0, Vector3(-0.15, lerpf(0.9, 0.3, s), -0.5), false, Vector3(-0.7, -1.0, 0.4))
		_hand(rig, 1, Vector3(0.15, lerpf(0.9, 0.3, s), -0.5), false, Vector3(0.7, -1.0, 0.4))
		o.pose = {"lean": 0.7 * s, "kn": 0.5 * s + 0.05}
		o.snap = 2.0
