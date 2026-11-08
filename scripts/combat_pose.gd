class_name CombatPose
extends SkeletonModifier3D
## How a townsman (or one of the band) carries himself in a fight, laid over whatever his body's
## clip and TownsfolkPose make of him, last of the skeleton's modifiers. It reads the villager it
## belongs to each frame and decides for itself:
##  - the Mosin worked after each shot (the bolt lifted, drawn back, run home, turned down), and
##    every fifth shot a stripper clip pressed in with the thumb (Raids.shoot asks fired());
##  - down behind sandbags or in a trench between shots, up only to aim and fire; leaning out round
##    a house's corner to shoot and back in against the wall; flat on the ground to hold a post in
##    the open; doubled over running when the shots are close;
##  - struck: jerked the way the shot went; falling: forward, thrown back, crumpled, or spun round
##    (fell()); down and alive, dragging himself toward a door (crawl());
##  - a prisoner walking with his hands on his head; folk with no gun keeping their heads down and
##    running crouched when shots are near, cowering where they stand; a parent with a child held
##    to the chest, the child clinging on;
##  - at the Maxim: the gunner hunched over the grips shaking with it, the loader feeding the belt.
## Clips it doesn't play through the body's AnimationPlayer are sampled here from the same library
## (the crouch, the prone, the crawl...) and blended in by weight, so nothing fights the player.

const RELOAD_EVERY := 5 ## a Mosin's magazine: a clip of five
const BOLT_DELAY := 0.14 ## s after the shot before the hand goes to the bolt (the recoil first)
const BOLT_T := 0.8 ## s the bolt takes, up and back and home again
const RELOAD_T := 3.3 ## s a clip takes: bolt open, the clip from the pouch, thumbed in, bolt home
const FIRE_REACH := 32.0 ## m from a shot within which the folk get their heads down
const FIRE_FRESH := 4.5 ## s a shot is still in the air for that
const CRAWL_SPEED := 0.32 ## m/s, a man dragging himself
const CRAWL_REACH := 16.0 ## m the furthest he gets
const MG_GRIPS := Vector3(0.0, 0.62, 0.05) ## the Maxim's spade grips, in the nest's frame
const MG_FEED := Vector3(-0.22, 0.7, 0.3) ## where the belt goes in (the loader's side)

## A Mosin, held as the rifle clips hold it (the grip at the origin, the barrel along -z): where the
## fist goes to work the bolt and press the clip, and where the stock meets the shoulder.
const HANDLE_DOWN := Vector3(0.075, 0.0, -0.1)
const HANDLE_UP := Vector3(0.03, 0.065, -0.1)
const HANDLE_BACK := Vector3(0.03, 0.065, 0.0)
const CLIP_TOP := Vector3(0.0, 0.11, -0.05)
const BUTT := Vector3(0.0, 0.0, 0.3)

static var _shots: Array = [] ## [where, Time msec]
static var _maps := {} ## clip -> {bone: [rotation track, position track]}
static var _speeds := {} ## clip -> m/s over the ground it covers at its own pace
static var _clip_lib := {} ## clip -> Animation

var v: Villager
var body: Townsfolk
var _sk: Skeleton3D
var _bones := {}

# the sampled clips laid over the body: {clip, t, w, want, rate, mask, by_dist, loop, fade}
var _layers: Array = []
var _stance := "" ## the clip asked for now ("" the body's own)
var _last := Vector3.INF
var _speed := 0.0 ## m/s it's moving over the ground (smoothed)
var _moved := 0.0 ## m this frame
var _clock := 0.0

# the rifle
var _rounds := 0
var _bolt := 99.0 ## s into the bolt's work (from -BOLT_DELAY)
var _reload := 99.0 ## s into a clip's
var _recoil := 0.0
var _since_shot := 99.0
var _prone := 0 ## 0 up, 1 going down, 2 down, 3 getting up
var _prone_t := 0.0
var _prone_w := 0.0
var _up_w := 1.0 ## (in low cover) up over it to shoot

# what's around it, looked at now and then
var _scan_t := 0.0
var _cover := "" ## "low" (sandbags, a trench, a rock), "wall" (a palisade's walkway), "corner", "open", ""
var _corner_side := 0.0 ## (-1 left, 1 right) the way to lean out round it
var _under_fire := false
var _foe_near := false

# the hands, put somewhere by IK: "up", "behind", "head", "cradle", "hug", "mg", "feed"
var _hands := ""
var _hands_w := 0.0
var _lean := 0.0
var _hit := Vector2.ZERO ## (x the side, y forward) the jerk of a shot taken, a damped spring
var _hit_v := Vector2.ZERO
var _spin := 0.0 ## a fall spun round: the turn it ends at
var _spin_t := 99.0
var _mg_t := 99.0 ## s since the Maxim fired


# --- From outside -----------------------------------------------------------------------------------

## `v`'s, made if it hasn't one (null with no rigged body).
static func of(who: Villager) -> CombatPose:
	if who == null or not is_instance_valid(who) or who._body == null or who._body.skeleton == null:
		return null
	if who.has_meta("combat_pose"):
		var c: Variant = who.get_meta("combat_pose")
		if is_instance_valid(c) and (c as CombatPose).body == who._body:
			return c
	var cp := CombatPose.new()
	cp.v = who
	cp.body = who._body
	cp.name = "CombatPose"
	who._body.skeleton.add_child(cp)
	who.set_meta("combat_pose", cp)
	return cp


## Everyone in the fight (and the prisoners) given one: Raids, now and then.
static func ensure(list: Array) -> void:
	for x: Variant in list:
		if is_instance_valid(x) and not (x as Villager).has_meta("combat_pose"):
			of(x)


## A shot fired at `at`: anyone near it ducks.
static func heard_shot(at: Vector3) -> void:
	var now := Time.get_ticks_msec()
	_shots.append([at, now])
	if _shots.size() > 48:
		_shots = _shots.slice(_shots.size() - 48)


static func fire_near(p: Vector3, reach: float) -> bool:
	var now := Time.get_ticks_msec()
	var fresh := FIRE_FRESH * 1000.0 / maxf(Engine.time_scale, 1.0)
	for i in range(_shots.size() - 1, -1, -1):
		var s: Array = _shots[i]
		if now - int(s[1]) > fresh:
			break
		if (s[0] as Vector3).distance_squared_to(p) < reach * reach:
			return true
	return false


## `by` has just fired its rifle: the bolt to work, or every fifth a clip to load. The extra seconds
## before it can fire again (a clip's slower than the bolt).
static func fired(by: Villager) -> float:
	var c := of(by)
	if c == null or not by._rifle:
		return 0.0
	c._recoil = 1.0
	c._since_shot = 0.0
	c._rounds += 1
	if c._rounds >= RELOAD_EVERY:
		c._rounds = 0
		c._reload = -BOLT_DELAY
		c._bolt = 99.0
		return RELOAD_T - 1.6
	c._bolt = -BOLT_DELAY
	return 0.0


## The Maxim at `nest` has fired: its crew shake with it.
static func mg_fired(nest: Building) -> void:
	for w: Villager in nest.workers:
		var c := of(w)
		if c:
			c._mg_t = 0.0


## `who` struck and still on its feet by a shot going `dir` (world): jerked that way, and a flinch
## for the side it came from.
static func struck(who: Villager, dir: Vector3, dmg: float) -> void:
	var c := of(who)
	if c == null:
		return
	var l := who.global_basis.orthonormalized().inverse() * dir
	var push := clampf(dmg / 20.0, 0.6, 1.6)
	# (y: + forward. A shot from in front pushes it back: the way it goes, +z, is back)
	c._hit_v += Vector2(l.x, -l.z).normalized() * 7.0 * push
	if c._prone == 2 or c._stance in ["CrouchIdle", "RifleCrouchIdle"]:
		return # (down already: only the jerk)
	if l.z > 0.4:
		who._body.flinch(["ual/UalHitChest", "RifleHit" if who.armed else "HitReact", "ual/UalHitHead"][randi() % 3])
	elif l.z < -0.4:
		c._hit_v.y += 3.0 # (hit from behind: stumbles forward, no clip for it)
	else:
		who._body.flinch("ual/UalHitChest")


## `who` has just fallen (dead, or down and alive) from a shot going `dir` (world): which way it goes
## down. Shot from behind it pitches forward; from in front it's thrown back or the knees go and it
## crumples; from the side it's spun round as it drops. One of the town down and alive may crawl.
static func fell(who: Villager, dir: Vector3, dmg: float) -> void:
	var c := of(who)
	if c == null or who._body.player == null:
		return
	var l := who.global_basis.orthonormalized().inverse() * dir
	var clip := "Death"
	c._spin = 0.0
	if who.down and who.team == 0 and not who.is_child and randf() < 0.6:
		who.set_meta("crawler", true) # (face down, to drag itself off after)
		who.set_meta("crawl_wait", randf_range(1.6, 3.0))
	elif l.z < -0.35:
		clip = "Death"
	elif l.z > 0.35:
		clip = "ual/UalHitKnockback" if dmg > 22.0 and randf() < 0.6 else "ual/UalDeath"
	else:
		clip = "ual/UalDeath" if randf() < 0.5 else "Death"
		c._spin = signf(l.x if absf(l.x) > 0.01 else 1.0) * randf_range(1.3, 2.4)
	c._spin_t = 0.0 if c._spin != 0.0 else 99.0
	var p := who._body.player
	if not p.has_animation(clip):
		return
	var a := p.get_animation(clip)
	if a.loop_mode != Animation.LOOP_NONE:
		a.loop_mode = Animation.LOOP_NONE
	p.play(clip, 0.08)
	p.speed_scale = randf_range(0.9, 1.15)


## One of the town down and alive dragging itself toward the nearest door or cover (a few metres,
## no more), if it fell so. True while it's at it (Villager._downed).
static func crawl(who: Villager, dt: float) -> bool:
	if not who.has_meta("crawler") or who._body == null:
		return false
	var wait := float(who.get_meta("crawl_wait", 0.0)) - dt
	who.set_meta("crawl_wait", wait)
	if wait > 0.0:
		return false
	var vil = who.village
	if not who.has_meta("crawl_to"):
		var best := Vector3.INF
		var bd := 24.0
		for b: Building in vil.buildings:
			if b.state == "done" and str(b.def.role) in ["house", "store", "barracks", "post", "mg"] and not b.is_burning():
				var at: Vector3 = b.door() if str(b.def.role) in ["house", "store", "barracks"] else b.global_position
				var d := at.distance_to(who.position)
				if d < bd:
					bd = d
					best = at
		if best == Vector3.INF:
			var q: Vector3 = vil.cover_near(who.position, 5.0)
			if q.distance_to(who.position) > 1.0:
				best = q
		if best == Vector3.INF:
			who.remove_meta("crawler")
			return false
		who.set_meta("crawl_to", best)
		who.set_meta("crawl_left", CRAWL_REACH)
	var to: Vector3 = who.get_meta("crawl_to")
	var left := float(who.get_meta("crawl_left"))
	var d := Vector2(to.x - who.position.x, to.z - who.position.z)
	if d.length() < 1.6 or left <= 0.0:
		who.remove_meta("crawler")
		who.remove_meta("crawling")
		return false
	# turned toward it first (while lying still), then on
	var want := atan2(-d.x, -d.y)
	var turn := angle_difference(who.rotation.y, want)
	who.rotation.y = rotate_toward(who.rotation.y, want, dt * 0.9)
	who.set_meta("crawling", true)
	if absf(turn) > 0.35:
		return true
	var step := CRAWL_SPEED * dt * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.004)) # (in heaves)
	who.position += Vector3(d.x, 0, d.y).normalized() * step
	who.position.y = vil.ground_at(who.position)
	who.set_meta("crawl_left", left - step)
	return true


# --- Each frame --------------------------------------------------------------------------------------

func _bone(n: String) -> int:
	if not _bones.has(n):
		_bones[n] = _sk.find_bone(n)
	return _bones[n]


func _gp(n: String) -> Transform3D:
	return _sk.get_bone_global_pose(_bone(n))


func _process_modification_with_delta(delta: float) -> void:
	_sk = get_skeleton()
	if _sk == null or not is_instance_valid(v) or body == null:
		return
	_clock += delta
	var p := v.global_position
	_moved = 0.0 if _last == Vector3.INF else Vector2(p.x - _last.x, p.z - _last.z).length()
	if _moved > 2.0:
		_moved = 0.0 # (put somewhere, not walked)
	_last = p
	_speed = lerpf(_speed, _moved / maxf(delta, 0.0001), 1.0 - exp(-8.0 * delta))
	_since_shot += delta
	_bolt += delta
	_reload += delta
	_mg_t += delta
	_spin_t += delta
	_recoil = move_toward(_recoil, 0.0, delta * 6.0)
	_decide(delta)
	_apply_layers(delta)
	_apply_spin()
	_apply_body(delta)
	_apply_rifle(delta)
	_apply_hands(delta)


## What it should be doing with itself just now.
func _decide(delta: float) -> void:
	var stance := ""
	var mask := "full"
	var by_dist := false
	var hands := ""
	var lean := 0.0
	var prone := false
	if v.dead or v.sleeping or not v.visible:
		_set_stance("", "full", false, 0.15)
		_hands_to("", delta)
		_lean = 0.0
		_prone = 0
		_prone_w = 0.0
		return
	if v.down:
		if v.has_meta("crawling") and not is_instance_valid(v.carried_by):
			stance = "Crawl"
			by_dist = true
			if not v.has_meta("crawler"):
				v.remove_meta("crawling")
		_set_stance(stance, "full", by_dist, 0.5)
		_hands_to("", delta)
		_prone = 0
		_prone_w = 0.0
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = randf_range(0.35, 0.55)
		_scan()
	var moving := _speed > 0.35
	var step := str(v.plan[0].t) if not v.plan.is_empty() else ""
	var mg := v.job == "Makineli tüfek başında" and v.workplace != null and is_instance_valid(v.workplace) and not moving
	if v.has_meta("snatched_by"):
		# a child snatched up: clinging on, the knees drawn up
		hands = "hug"
		stance = "CrouchIdle"
		mask = "legs"
	elif v.has_meta("snatching"):
		hands = "cradle"
	elif v.team == 1 and (v.held_in != null or v.job == "Teslim oluyor" or v.has_meta("led_off")):
		# giving up: the hands up where they can be seen; walked off, on the head
		hands = "up" if not moving and v.job == "Teslim oluyor" else "behind"
	elif mg:
		stance = "CrouchIdle"
		hands = "mg" if v.workplace.workers.find(v) == 0 else "feed"
	elif v._rifle and not v.perched:
		var holding := step in ["hold", "fight"] or (v.team == 1 and v._anim == "aim")
		if moving and (_under_fire or _foe_near):
			stance = "RifleCrouchWalk"
			by_dist = true
		elif holding and not moving:
			match _cover:
				"low":
					# up to aim and fire, down again for the bolt and between shots
					var want_up := (v._anim == "aim" and v._attack_t < 0.8 and _reload > RELOAD_T) or _since_shot < 0.3
					_up_w = move_toward(_up_w, 1.0 if want_up else 0.0, delta * 4.0)
					stance = "" if _up_w > 0.5 else "RifleCrouchIdle"
				"corner":
					var out := v._anim == "aim" and _reload > RELOAD_T and (v._attack_t < 1.0 or _since_shot < 0.4)
					lean = _corner_side * (0.45 if out else -0.08)
				"open":
					prone = v.job in ["Mevzide", "Pusuda"] or (v.team == 1 and v._anim == "aim")
	elif moving and v.job == "Makineli tüfek başında" and _under_fire:
		stance = "CrouchWalk" # (the crew running to the gun, doubled over)
		by_dist = true
	elif not v.armed and v.team == 0 and not v.drafted and (_under_fire or (_foe_near and v.job in ["Saklanıyor", "Kaçıyor"])):
		# no gun: the head down, the hands over it; running doubled over, or cowering where it is
		hands = "head"
		stance = "CrouchWalk" if moving else "CrouchIdle"
		by_dist = moving
	# flat on the ground in the open: down onto it, lying there, up again
	if prone:
		if _prone == 0 or _prone == 3:
			_prone = 1
			_prone_t = 0.0
		stance = "GoProne" if _prone == 1 else "ProneIdle"
		_prone_t += delta
		if _prone == 1 and _prone_t > 1.05:
			_prone = 2
			stance = "ProneIdle"
	elif _prone != 0:
		if _prone != 3:
			_prone = 3
			_prone_t = 0.0
		_prone_t += delta
		if moving or _prone_t > 1.1:
			_prone = 0
		else:
			stance = "GetUpFromProne"
	_prone_w = move_toward(_prone_w, 1.0 if _prone == 2 else 0.0, delta * (3.0 if _prone == 2 else 6.0))
	var fade := 0.3
	if stance in ["GoProne", "GetUpFromProne"]:
		fade = 0.2
	elif stance == "" and _cover == "low":
		fade = 0.22
	_set_stance(stance, mask, by_dist, fade)
	_lean = lerpf(_lean, lean, 1.0 - exp(-7.0 * delta))
	_hands_to(hands, delta)


## The ground about it: what cover it's in, whether shots are close.
func _scan() -> void:
	var vil = v.village
	var p := v.position
	_under_fire = fire_near(p, FIRE_REACH)
	_foe_near = false
	var raids = vil.raids
	if raids and raids.active:
		if v.team == 0:
			_foe_near = raids.nearest_raider(p, 45.0) != null
		else:
			for o: Villager in raids.town_folk():
				if o.armed and not o.dead and not o.down and o.position.distance_squared_to(p) < 2500.0:
					_foe_near = true
					break
	_cover = ""
	if not v._rifle or v.perched:
		return
	if v.in_cover and p.y - vil.nav.height(p.x, p.z) > 0.8:
		_cover = "wall"
		return
	var c: Dictionary = vil.cover_at(p)
	if c.has("post") or c.has("trench"):
		_cover = "low"
		return
	if c.has("wall"):
		_cover = "wall"
		return
	# a rock close in front, or a house's wall beside it
	var side := Vector3.ZERO
	var b_inv := v.global_basis.orthonormalized().inverse()
	for k in 8:
		var dir := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
		var kind: int = vil.nav.shut_kind(p + dir * 1.1)
		if kind == 1:
			_cover = "low"
			return
		if kind == 2 and raids:
			var b: Building = raids._building_at(p + dir * 1.1)
			if b and str(b.def.role) in ["post", "mg"]:
				_cover = "low"
				return
			if b and str(b.def.role) != "obstacle" and b.state == "done":
				side += b_inv * dir
	if side.length() > 0.1:
		_cover = "corner"
		# lean away from the wall; with the wall in front, out the side it's nearer the edge of
		_corner_side = -signf(side.x) if absf(side.x) > 0.25 else (1.0 if v.get_instance_id() % 2 == 0 else -1.0)
		return
	_cover = "open"


# --- The sampled clips ----------------------------------------------------------------------------

func _set_stance(clip: String, mask: String, by_dist: bool, fade: float) -> void:
	if clip == _stance:
		if clip != "" and not _layers.is_empty():
			_layers[-1].mask = mask
		return
	_stance = clip
	for l: Dictionary in _layers:
		l.want = 0.0
		l.fade = fade
	if clip == "":
		return
	var a := _anim(clip)
	if a == null:
		return
	var loop := not clip in ["GoProne", "GetUpFromProne"]
	_layers.append({"clip": clip, "t": 0.0 if not loop else randf() * a.length, "w": 0.0, "want": 1.0, "mask": mask,
		"by_dist": by_dist, "loop": loop, "fade": fade})


func _anim(clip: String) -> Animation:
	if _clip_lib.has(clip):
		return _clip_lib[clip]
	var a: Animation = body.player.get_animation(clip) if body.player.has_animation(clip) else null
	_clip_lib[clip] = a
	return a


## clip's tracks by bone.
func _map(clip: String) -> Dictionary:
	if _maps.has(clip):
		return _maps[clip]
	var out := {}
	var a := _anim(clip)
	if a:
		for i in a.get_track_count():
			var path := a.track_get_path(i)
			if path.get_subname_count() == 0:
				continue
			var b := _sk.find_bone(String(path.get_subname(0)))
			if b < 0:
				continue
			var e: Array = out.get(b, [-1, -1])
			match a.track_get_type(i):
				Animation.TYPE_ROTATION_3D:
					e[0] = i
				Animation.TYPE_POSITION_3D:
					e[1] = i
			out[b] = e
	_maps[clip] = out
	return out


## m/s over the ground `clip` walks at its own pace: the planted foot's speed back under the body.
func _clip_speed(clip: String) -> float:
	if _speeds.has(clip):
		return _speeds[clip]
	var a := _anim(clip)
	var m := _map(clip)
	var sp := 1.0
	if a:
		var chain := ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
		var chain_r := ["Hips", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
		var n := 48
		var feet: Array = []
		for k in n + 1:
			var t := a.length * k / n
			feet.append([_fk(a, m, chain, t), _fk(a, m, chain_r, t)])
		var low := INF
		for f: Array in feet:
			low = minf(low, minf((f[0] as Vector3).y, (f[1] as Vector3).y))
		var total := 0.0
		var count := 0
		for k in n:
			for s in 2:
				var f0: Vector3 = feet[k][s]
				var f1: Vector3 = feet[k + 1][s]
				var other: Vector3 = feet[k][1 - s]
				# (this foot the lower and down on the ground: it's the one carrying the body)
				if f0.y <= other.y and f0.y < low + 0.035 and f1.y < low + 0.035:
					total += absf(f1.z - f0.z)
					count += 1
		if count > 0:
			sp = total / (a.length * count / float(n))
	sp = clampf(sp, 0.3, 6.0)
	_speeds[clip] = sp
	return sp


## Where the last bone of `chain` is at `t` in `a` (skeleton space, from its rest and the clip's turns).
func _fk(a: Animation, m: Dictionary, chain: Array, t: float) -> Vector3:
	var xf := Transform3D.IDENTITY
	for n: String in chain:
		var b := _sk.find_bone(n)
		var rest := _sk.get_bone_rest(b)
		if n == "Hips":
			rest = _sk.get_bone_global_rest(b)
		var e: Array = m.get(b, [-1, -1])
		var q := rest.basis.get_rotation_quaternion() if int(e[0]) < 0 else a.rotation_track_interpolate(int(e[0]), t)
		var o := rest.origin if int(e[1]) < 0 else a.position_track_interpolate(int(e[1]), t)
		xf = xf * Transform3D(Basis(q), o)
	return xf.origin


const LEGS := ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]


func _apply_layers(delta: float) -> void:
	var kept: Array = []
	for l: Dictionary in _layers:
		l.w = move_toward(float(l.w), float(l.want), delta / maxf(float(l.fade), 0.05))
		if float(l.w) > 0.0 or float(l.want) > 0.0:
			kept.append(l)
	_layers = kept
	for l: Dictionary in _layers:
		var a := _anim(str(l.clip))
		if a == null:
			continue
		var adv := delta
		if bool(l.by_dist):
			adv = _moved / (_clip_speed(str(l.clip)) * body.model.scale.z) # (the feet kept where they're put down)
		var t := float(l.t) + adv
		t = fposmod(t, a.length) if bool(l.loop) else minf(t, a.length)
		l.t = t
		var w := smoothstep(0.0, 1.0, float(l.w))
		if w <= 0.001:
			continue
		var m := _map(str(l.clip))
		var mask := str(l.mask)
		for b: int in m:
			var name := _sk.get_bone_name(b)
			if name == "Root":
				continue
			if mask == "legs" and not name in LEGS:
				continue
			var e: Array = m[b]
			if int(e[0]) >= 0:
				var q := a.rotation_track_interpolate(int(e[0]), t)
				_sk.set_bone_pose_rotation(b, _sk.get_bone_pose_rotation(b).slerp(q, w))
			if int(e[1]) >= 0 and mask != "legs":
				var o := a.position_track_interpolate(int(e[1]), t)
				_sk.set_bone_pose_position(b, _sk.get_bone_pose_position(b).lerp(o, w))


# --- Procedural over it ----------------------------------------------------------------------------

## Bone `n` turned by `angle` about `axis` (the body's frame), at its joint.
func _turn(n: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.0005:
		return
	var b := _bone(n)
	if b < 0:
		return
	var g := _sk.get_bone_global_pose(b)
	g.basis = Basis(axis, angle) * g.basis
	_sk.set_bone_global_pose(b, g)


func _apply_spin() -> void:
	if _spin == 0.0 or not v.dead and not v.down:
		return
	var u := smoothstep(0.0, 0.6, _spin_t)
	var b := _bone("Root")
	if b < 0:
		return
	var g := _sk.get_bone_global_pose(b)
	g.basis = Basis(Vector3.UP, _spin * u) * g.basis
	_sk.set_bone_global_pose(b, g)


## The jerk of a shot taken, the recoil, leaning out round a corner, the hunch over the Maxim.
func _apply_body(delta: float) -> void:
	# a damped spring: kicked by a shot, back in half a second
	var acc := -_hit * 90.0 - _hit_v * 13.0
	_hit_v += acc * delta
	_hit += _hit_v * delta
	var x := Vector3.RIGHT
	var z := Vector3.BACK
	if _hit.length() > 0.004 and not v.dead and not v.down:
		_turn("Spine", x, -_hit.y * 0.6)
		_turn("Chest", x, -_hit.y * 0.5)
		_turn("Spine", z, -_hit.x * 0.55)
		_turn("Chest", z, -_hit.x * 0.4)
		_turn("UpperChest", Vector3.UP, _hit.x * 0.4)
		_turn("Head", x, -_hit.y * 0.4)
		_turn("Head", z, -_hit.x * 0.3)
	if _recoil > 0.01:
		var r := _recoil * _recoil
		_turn("UpperChest", x, 0.09 * r * (0.4 if _prone_w > 0.5 else 1.0))
		_turn("Head", x, 0.05 * r)
	if absf(_lean) > 0.005:
		_turn("Spine", z, -_lean * 0.45)
		_turn("Chest", z, -_lean * 0.45)
		_turn("Neck", z, _lean * 0.5)
	if _hands == "mg" and _hands_w > 0.01:
		var j := (sin(_clock * 71.0) * 0.6 + sin(_clock * 43.0) * 0.4) * (1.0 - smoothstep(0.15, 0.35, _mg_t))
		_turn("Spine", x, -0.32 * _hands_w)
		_turn("Chest", x, -0.12 * _hands_w)
		_turn("UpperChest", x, j * 0.03)
		_turn("Head", x, 0.12 * _hands_w + j * 0.02)


## The rifle: worked after a shot, a clip thumbed in, laid along the ground when lying flat.
func _apply_rifle(_delta: float) -> void:
	if not v._rifle or v.dead or v.down:
		return
	var bolt_u := _bolt / BOLT_T if _bolt >= 0.0 and _bolt < BOLT_T else -1.0
	var load_u := _reload / RELOAD_T if _reload >= 0.0 and _reload < RELOAD_T else -1.0
	if bolt_u < 0.0 and load_u < 0.0 and _prone_w <= 0.001:
		return
	var wi := _bone("Weapon")
	var rh := _bone("RightHand")
	var lh := _bone("LeftHand")
	if wi < 0 or rh < 0 or lh < 0:
		return
	var rifle := _sk.get_bone_global_pose(wi)
	var r_wr := _sk.get_bone_global_pose(rh)
	var l_wr := _sk.get_bone_global_pose(lh)
	var inv := rifle.affine_inverse()
	var r_off := inv * r_wr.origin # (the wrist from the grip, in the rifle's frame)
	var l_off := inv * l_wr.origin
	var r_basis := rifle.basis.inverse() * r_wr.basis
	var l_basis := rifle.basis.inverse() * l_wr.basis
	var new_rifle := rifle
	if _prone_w > 0.001:
		# lying flat: the rifle along the ground in front of the face, the butt in the shoulder
		var head := _gp("Head").origin
		var sh := _gp("RightUpperArm").origin
		var fwd := Vector3(0, -0.06, -1.0).normalized()
		var at := Vector3(sh.x * 0.6, head.y - 0.1, head.z - 0.05)
		var pr := Transform3D(Basis.looking_at(fwd, Vector3.UP), at)
		pr.origin -= pr.basis * BUTT * 0.75
		new_rifle = rifle.interpolate_with(pr, smoothstep(0.0, 1.0, _prone_w))
		r_off = r_off.lerp(Vector3(0.0, 0.07, 0.03), _prone_w)
		l_off = l_off.lerp(Vector3(-0.01, -0.02, -0.4), _prone_w)
	var fist := Vector3.ZERO ## where the right fist goes, in the rifle's frame (zero: the grip)
	var off_shoulder := 0.0
	var cant := 0.0
	var look_down := 0.0
	if bolt_u >= 0.0:
		var keys := [[0.0, Vector3.ZERO], [0.17, HANDLE_DOWN], [0.32, HANDLE_UP], [0.5, HANDLE_BACK],
			[0.66, HANDLE_UP], [0.8, HANDLE_DOWN], [1.0, Vector3.ZERO]]
		fist = _path(keys, bolt_u)
		var env := sin(bolt_u * PI)
		cant = 0.32 * env
		off_shoulder = 0.35 * env
		look_down = -0.1 * env # (the cheek off the stock)
	if load_u >= 0.0:
		# brought up in front of the chest, the muzzle high and the action turned up to the right
		# hand, held there by the left on the fore-end while the right works
		var env := smoothstep(0.0, 0.1, load_u) * (1.0 - smoothstep(0.88, 1.0, load_u))
		var chest := _gp("UpperChest")
		var muzzle := Vector3(0.12, 0.8, -0.6).normalized()
		var held := Basis.looking_at(muzzle, Vector3(0.3, 0.6, 0.8).normalized())
		held = Basis(muzzle, 0.55) * held # (canted, the open action toward the right hand)
		var port := Transform3D(held, chest.origin + Vector3(0.1, -0.36, -0.3))
		new_rifle = new_rifle.interpolate_with(port, env)
		var pulse := maxf(sin((load_u - 0.45) / 0.27 * PI * 4.0), 0.0) if load_u > 0.45 and load_u < 0.72 else 0.0
		var press := CLIP_TOP - Vector3(0, 0.07 * pulse, 0)
		var pouch := new_rifle.affine_inverse() * (_gp("Hips") * Vector3(0.17, 0.02, -0.16)) - r_off
		var keys := [[0.0, Vector3.ZERO], [0.05, HANDLE_DOWN], [0.09, HANDLE_UP], [0.14, HANDLE_BACK],
			[0.28, pouch], [0.33, pouch], [0.43, CLIP_TOP], [0.45, CLIP_TOP], [0.72, press],
			[0.78, CLIP_TOP + Vector3(0.1, 0.12, 0.02)], [0.85, HANDLE_UP], [0.9, HANDLE_DOWN], [1.0, Vector3.ZERO]]
		fist = _path(keys, load_u)
		if load_u > 0.45 and load_u < 0.72:
			fist = press
		look_down = 0.35 * env
	if cant != 0.0 or off_shoulder != 0.0:
		# off the shoulder, down to the chest, the muzzle up a little and the action turned up to the
		# right hand (about the butt, so it doesn't swing through the body)
		var pivot := new_rifle * BUTT
		var turn := Basis(new_rifle.basis.z.normalized(), -cant) * Basis(new_rifle.basis.x.normalized(), 0.3 * off_shoulder)
		new_rifle = Transform3D(turn * new_rifle.basis, pivot + turn * (new_rifle.origin - pivot))
		new_rifle.origin += Vector3(0.0, -0.13, -0.06) * off_shoulder
	_turn("Head", Vector3.RIGHT, look_down)
	# the left hand stays on the fore-end; the right goes where the work is
	var l_goal := new_rifle * l_off
	var r_goal := new_rifle * (fist + r_off)
	_ik("LeftUpperArm", "LeftLowerArm", "LeftHand", l_goal, Vector3(-0.6, -1.0, 0.2), 1.0, new_rifle.basis * l_basis)
	_ik("RightUpperArm", "RightLowerArm", "RightHand", r_goal, Vector3(0.9, -0.6, 0.4), 1.0, new_rifle.basis * r_basis)
	_sk.set_bone_global_pose(wi, new_rifle) # (the rifle where it's held, whatever the right hand's at)


## Along `keys` ([[u, point], ...]) at `u`, eased between each.
func _path(keys: Array, u: float) -> Vector3:
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if u <= float(b[0]):
			var k := smoothstep(float(a[0]), float(b[0]), u)
			return (a[1] as Vector3).lerp(b[1], k)
	return keys[-1][1]


func _hands_to(h: String, delta: float) -> void:
	if h != _hands:
		_hands_w = move_toward(_hands_w, 0.0, delta * 5.0)
		if _hands_w <= 0.0:
			_hands = h
	else:
		_hands_w = move_toward(_hands_w, 1.0 if h != "" else 0.0, delta * 3.5)


## The hands put somewhere: up, on the head, over it, round a child, on the Maxim's grips.
func _apply_hands(_delta: float) -> void:
	if _hands == "" or _hands_w <= 0.001:
		return
	var w := smoothstep(0.0, 1.0, _hands_w)
	var head := _gp("Head").origin
	var chest := _gp("UpperChest").origin
	var to_sk := _sk.global_transform.affine_inverse()
	for s in 2:
		var side := -1.0 if s == 0 else 1.0
		var pre := "Left" if s == 0 else "Right"
		var goal := Vector3.ZERO
		var pole := Vector3(side, -0.3, 0.0)
		match _hands:
			"up":
				goal = _gp(pre + "UpperArm").origin + Vector3(side * 0.2, 0.42, -0.06)
				pole = Vector3(side, -0.6, 0.2)
			"behind":
				goal = head + Vector3(side * 0.1, 0.04, 0.1)
				pole = Vector3(side, 0.1, -0.3)
			"head":
				goal = head + Vector3(side * 0.085, 0.08, -0.03)
				pole = Vector3(side * 0.5, -0.4, -1.0)
			"cradle":
				goal = chest + Vector3(side * 0.1, -0.24, -0.3)
				pole = Vector3(side, -1.0, 0.3)
			"hug":
				goal = chest + Vector3(side * 0.12, 0.08, -0.24)
				pole = Vector3(side, -0.5, 0.0)
			"mg", "feed":
				var nest := v.workplace
				if nest == null or not is_instance_valid(nest):
					return
				var j := (1.0 - smoothstep(0.15, 0.35, _mg_t))
				if _hands == "mg":
					var g: Vector3 = nest.global_transform * (MG_GRIPS + Vector3(side * 0.09, 0, 0))
					goal = to_sk * g + Vector3(sin(_clock * 67.0 + s), sin(_clock * 53.0), cos(_clock * 61.0)) * 0.012 * j
				else:
					var feed: Vector3 = nest.global_transform * (MG_FEED + Vector3(0, 0, -0.06 * s))
					goal = to_sk * feed + Vector3(0, 0, sin(_clock * 18.0) * 0.05 * j * (1.0 if s == 0 else -1.0))
				pole = Vector3(side, -1.0, 0.2)
		_ik(pre + "UpperArm", pre + "LowerArm", pre + "Hand", goal, pole, w)


## A two-bone arm (`up`, `lo`, the wrist `hand`) brought to `goal` (skeleton space) by weight `w`,
## the elbow toward `pole`; the hand turned to `keep` if given.
func _ik(up: String, lo: String, hand: String, goal: Vector3, pole: Vector3, w: float, keep := Basis()) -> void:
	var ui := _bone(up)
	var li := _bone(lo)
	var hi := _bone(hand)
	if ui < 0 or li < 0 or hi < 0:
		return
	var sh := _sk.get_bone_global_pose(ui).origin
	var el := _sk.get_bone_global_pose(li).origin
	var wr := _sk.get_bone_global_pose(hi).origin
	goal = wr.lerp(goal, w)
	var l1 := sh.distance_to(el)
	var l2 := el.distance_to(wr)
	var d := goal - sh
	if d.length_squared() < 1e-6:
		return
	var c := clampf(d.length(), absf(l1 - l2) + 0.002, l1 + l2 - 0.002)
	var dn := d.normalized()
	var now_bend := (el - sh) - dn * (el - sh).dot(dn)
	var want_bend := pole - dn * pole.dot(dn)
	if want_bend.length_squared() < 1e-6:
		want_bend = now_bend
	var bend := now_bend.normalized().lerp(want_bend.normalized(), w) if now_bend.length_squared() > 1e-6 else want_bend.normalized()
	if bend.length_squared() < 1e-6:
		return
	bend = bend.normalized()
	var cos_a := clampf((l1 * l1 + c * c - l2 * l2) / (2.0 * l1 * c), -1.0, 1.0)
	var new_el := sh + (dn * cos_a + bend * sqrt(1.0 - cos_a * cos_a)) * l1
	var gu := _sk.get_bone_global_pose(ui)
	gu.basis = Basis(Quaternion((el - sh).normalized(), (new_el - sh).normalized())) * gu.basis
	_sk.set_bone_global_pose(ui, gu)
	el = _sk.get_bone_global_pose(li).origin
	wr = _sk.get_bone_global_pose(hi).origin
	var reach := sh + dn * c
	if (wr - el).length_squared() > 1e-8 and (reach - el).length_squared() > 1e-8:
		var gl := _sk.get_bone_global_pose(li)
		gl.basis = Basis(Quaternion((wr - el).normalized(), (reach - el).normalized())) * gl.basis
		_sk.set_bone_global_pose(li, gl)
	if keep != Basis():
		var gh := _sk.get_bone_global_pose(hi)
		gh.basis = gh.basis.slerp(keep.orthonormalized(), w) if w < 0.999 else keep.orthonormalized()
		_sk.set_bone_global_pose(hi, gh)
